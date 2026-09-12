extends Node

## Loads the lean Scryfall Oracle catalog from D: so the Godot project on C: stays small.
const DATA_DIR := "D:/AetherfoldData/scryfall"
const CATALOG_FILE := "catalog.jsonl"
const META_FILE := "meta.json"

signal art_updated(card_id: String)

var loaded := false
var load_error := ""
var card_count := 0
var meta: Dictionary = {}
var cards_by_name: Dictionary = {}
var cards_by_id: Dictionary = {}
var _textures: Dictionary = {}
var _http: HTTPRequest
var _download_queue: Array = []
var _download_busy := false
var _download_dest := ""
var _download_card_id := ""

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_image_downloaded)
	load_catalog()

func data_dir() -> String:
	var override := OS.get_environment("AETHERFOLD_SCRYFALL_DIR").strip_edges()
	if override != "":
		return override.replace("\\", "/")
	return DATA_DIR

func load_catalog() -> bool:
	loaded = false
	load_error = ""
	cards_by_name.clear()
	cards_by_id.clear()
	card_count = 0
	var dir := data_dir()
	var meta_path := dir.path_join(META_FILE)
	var catalog_path := dir.path_join(CATALOG_FILE)
	if not FileAccess.file_exists(catalog_path):
		load_error = "Catalog missing at %s. Run tools/fetch_scryfall.py." % catalog_path
		push_warning(load_error)
		return false
	if FileAccess.file_exists(meta_path):
		var meta_text := FileAccess.get_file_as_string(meta_path)
		var parsed: Variant = JSON.parse_string(meta_text)
		if typeof(parsed) == TYPE_DICTIONARY:
			meta = parsed
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		load_error = "Could not open %s (%s)" % [catalog_path, FileAccess.get_open_error()]
		push_warning(load_error)
		return false
	var loaded_cards: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var card: Variant = JSON.parse_string(line)
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var cid := str(card.get("id", ""))
		if cid != "":
			cards_by_id[cid] = card
		loaded_cards.append(card)
		card_count += 1
	file.close()
	for card in loaded_cards:
		_index_name(str(card.get("name", "")), card, true)
	for card in loaded_cards:
		var faces: Variant = card.get("faces", [])
		if faces is Array:
			for face in faces:
				if _normalize(str(face)) == _normalize(str(card.get("name", ""))):
					continue
				_index_name(str(face), card, false)
	loaded = card_count > 0
	if loaded:
		print("Scryfall catalog loaded: %d cards from %s" % [card_count, catalog_path])
	else:
		load_error = "Catalog at %s was empty." % catalog_path
	return loaded

func _index_name(raw: String, card: Dictionary, allow_replace: bool) -> void:
	var key := _normalize(raw)
	if key == "":
		return
	if not cards_by_name.has(key):
		cards_by_name[key] = card
		return
	if not allow_replace:
		return
	var existing: Dictionary = cards_by_name[key]
	if _name_score(card, key) > _name_score(existing, key):
		cards_by_name[key] = card

func _name_score(card: Dictionary, key: String) -> int:
	var score := 0
	if _normalize(str(card.get("name", ""))) == key:
		score += 10
	var type_line := str(card.get("type_line", ""))
	if type_line.begins_with("Basic Land"):
		score += 8
	if card.get("commander_legal", false):
		score += 5
	if str(card.get("layout", "")) == "normal":
		score += 2
	return score

func _normalize(card_name: String) -> String:
	return card_name.strip_edges().to_lower()

func find_by_name(card_name: String) -> Dictionary:
	var card: Variant = cards_by_name.get(_normalize(card_name), {})
	return card if typeof(card) == TYPE_DICTIONARY else {}

func find_by_id(card_id: String) -> Dictionary:
	var card: Variant = cards_by_id.get(card_id, {})
	return card if typeof(card) == TYPE_DICTIONARY else {}

func status_text() -> String:
	if loaded:
		var updated := str(meta.get("updated_at", "unknown"))
		return "Scryfall: %d cards (oracle %s)" % [card_count, updated.substr(0, 10)]
	return "Scryfall: not loaded — %s" % load_error

func image_dir() -> String:
	return data_dir().path_join("images")

func scryfall_id_of(card: Dictionary) -> String:
	var cid := str(card.get("scryfall_id", "")).strip_edges()
	if cid != "" and cards_by_id.has(cid):
		return cid
	if cid != "" and cid.length() > 8 and not cid.is_valid_int():
		return cid
	var found := find_by_name(str(card.get("name", "")))
	return str(found.get("id", ""))

func texture_for(card: Dictionary, kind: String = "small") -> Texture2D:
	var cid := scryfall_id_of(card)
	if cid == "":
		return null
	var path := image_dir().path_join("%s_%s.jpg" % [cid, kind])
	if _textures.has(path):
		return _textures[path]
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			var tex := ImageTexture.create_from_image(img)
			_textures[path] = tex
			return tex
	_queue_image(card, kind, path)
	if kind != "small":
		return texture_for(card, "small")
	return null

func _queue_image(card: Dictionary, kind: String, dest: String) -> void:
	var images: Variant = card.get("images", {})
	if typeof(images) != TYPE_DICTIONARY:
		var found := find_by_id(scryfall_id_of(card))
		images = found.get("images", {})
	if typeof(images) != TYPE_DICTIONARY:
		return
	var url := str(images.get(kind, images.get("normal", "")))
	if url == "":
		return
	for item in _download_queue:
		if str(item.get("dest", "")) == dest:
			return
	_download_queue.append({"url": url, "dest": dest, "card_id": scryfall_id_of(card)})
	_pump_downloads()

func _pump_downloads() -> void:
	if _download_busy or _download_queue.is_empty() or _http == null:
		return
	var job: Dictionary = _download_queue.pop_front()
	_download_busy = true
	_download_dest = str(job["dest"])
	_download_card_id = str(job["card_id"])
	DirAccess.make_dir_recursive_absolute(image_dir())
	if _http.request(str(job["url"]), PackedStringArray(["User-Agent: Aetherfold/1.0", "Accept: image/*"])) != OK:
		_download_busy = false
		_pump_downloads()

func _on_image_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var dest := _download_dest
	var cid := _download_card_id
	_download_busy = false
	_download_dest = ""
	_download_card_id = ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 0:
		var file := FileAccess.open(dest, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
		var img := Image.new()
		if img.load_jpg_from_buffer(body) == OK or img.load(dest) == OK:
			_textures[dest] = ImageTexture.create_from_image(img)
		art_updated.emit(cid)
	_pump_downloads()


func pick_commander_rows(identity: Array, exclude_names: Dictionary, count: int, seed: int) -> Array:
	var creatures: Array = []
	var rest: Array = []
	var seen_oracle := {}
	for card in cards_by_name.values():
		if not (card is Dictionary):
			continue
		var row: Dictionary = card
		if not bool(row.get("commander_legal", false)):
			continue
		var nm := str(row.get("name", "")).strip_edges()
		if nm == "" or exclude_names.has(nm):
			continue
		var oid := str(row.get("oracle_id", nm))
		if seen_oracle.has(oid):
			continue
		var layout := str(row.get("layout", "normal"))
		if layout != "normal" and layout != "transform" and layout != "modal_dfc" and layout != "adventure" and layout != "split":
			continue
		var type_line := str(row.get("type_line", ""))
		if type_line.begins_with("Basic Land"):
			continue
		if (
			type_line.contains("Token")
			or type_line.contains("Emblem")
			or type_line.contains("Scheme")
			or type_line.contains("Plane ")
			or type_line.contains("Conspiracy")
			or type_line.contains("Dungeon")
			or type_line.contains("Stickers")
		):
			continue
		if not _ci_subset(row.get("color_identity", []), identity):
			continue
		seen_oracle[oid] = true
		if type_line.contains("Creature"):
			creatures.append(row)
		else:
			rest.append(row)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_fisher_yates(creatures, rng)
	_fisher_yates(rest, rng)
	var out: Array = []
	for row2 in creatures:
		if out.size() >= count:
			break
		out.append(row2)
	for row3 in rest:
		if out.size() >= count:
			break
		out.append(row3)
	return out


func _ci_subset(have: Variant, allowed: Array) -> bool:
	if have == null:
		return true
	if not (have is Array) and not (have is PackedStringArray):
		return true
	for c in have:
		var ok := false
		for a in allowed:
			if str(c) == str(a):
				ok = true
				break
		if not ok:
			return false
	return true


func _fisher_yates(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
