class_name ScryfallResolver
extends RefCounted

const COLLECTION_URL := "https://api.scryfall.com/cards/collection"
const BATCH := 75


func resolve(deck: NormalizedDeck, allow_network: bool = true) -> Dictionary:
	var unresolved: PackedStringArray = PackedStringArray()
	var rows := {}
	var pending: Array = []
	for n in deck.unique_names():
		var row: Dictionary = _from_catalog(n)
		if row.is_empty():
			pending.append(n)
		else:
			rows[n] = row
			deck.stamp_entry(n, row)
	if allow_network and not pending.is_empty():
		var fetched: Dictionary = _fetch_collection(pending)
		for n2 in pending:
			if fetched.has(n2):
				var fr: Dictionary = fetched[n2]
				rows[n2] = fr
				deck.stamp_entry(n2, fr)
				_cache_row(fr)
			else:
				unresolved.append(n2)
	else:
		for n3 in pending:
			unresolved.append(n3)
	return {rows = rows, unresolved = unresolved, deck = deck}


func _from_catalog(card_name: String) -> Dictionary:
	var cat := _catalog()
	if cat != null and cat.has_method("find_by_name"):
		var row: Variant = cat.find_by_name(card_name)
		if row is Dictionary and not (row as Dictionary).is_empty():
			return _normalize_row(row)
	var cached := _read_cache(card_name)
	if not cached.is_empty():
		return cached
	return {}


func _fetch_collection(names: Array) -> Dictionary:
	var out := {}
	var i := 0
	while i < names.size():
		var chunk: Array = []
		var slice := mini(BATCH, names.size() - i)
		for j in slice:
			chunk.append({name = str(names[i + j])})
		var body := JSON.stringify({identifiers = chunk})
		var resp: Dictionary = DeckHttp.post_sync(COLLECTION_URL, body, 25000)
		if not bool(resp.get("ok", false)):
			i += slice
			OS.delay_msec(550)
			continue
		var parsed: Variant = JSON.parse_string(str(resp.get("text", "")))
		if parsed is Dictionary:
			var data: Variant = (parsed as Dictionary).get("data", [])
			if data is Array:
				for card in data:
					if card is Dictionary:
						var row := _normalize_api_card(card)
						var nm := str(row.get("name", ""))
						if nm != "":
							out[nm] = row
							var asked := _match_asked(nm, names)
							if asked != nm:
								out[asked] = row
		i += slice
		OS.delay_msec(550)
	return out


func _match_asked(resolved_name: String, asked: Array) -> String:
	var key := DeckText.normalize_key(resolved_name)
	for n in asked:
		if DeckText.normalize_key(str(n)) == key:
			return str(n)
		if DeckText.normalize_key(str(n)).begins_with(key):
			return str(n)
	return resolved_name


func _normalize_api_card(card: Dictionary) -> Dictionary:
	var images := {}
	var iu: Variant = card.get("image_uris", {})
	if iu is Dictionary:
		images = {
			small = str(iu.get("small", "")),
			normal = str(iu.get("normal", "")),
			large = str(iu.get("large", "")),
		}
	elif card.get("card_faces") is Array:
		var faces: Array = card.get("card_faces")
		if not faces.is_empty() and faces[0] is Dictionary:
			var fiu: Variant = (faces[0] as Dictionary).get("image_uris", {})
			if fiu is Dictionary:
				images = {
					small = str(fiu.get("small", "")),
					normal = str(fiu.get("normal", "")),
					large = str(fiu.get("large", "")),
				}
	var legal := true
	var legs: Variant = card.get("legalities", {})
	if legs is Dictionary:
		legal = str((legs as Dictionary).get("commander", "legal")) == "legal"
	var faces_out: Array = []
	if card.get("card_faces") is Array:
		for f in card.get("card_faces"):
			if f is Dictionary:
				faces_out.append(str((f as Dictionary).get("name", "")))
	return {
		id = str(card.get("id", "")),
		oracle_id = str(card.get("oracle_id", "")),
		name = str(card.get("name", "")),
		mana_cost = str(card.get("mana_cost", "")),
		cmc = card.get("cmc", 0),
		type_line = str(card.get("type_line", "")),
		oracle_text = str(card.get("oracle_text", "")),
		colors = card.get("colors", []),
		color_identity = card.get("color_identity", []),
		keywords = card.get("keywords", []),
		power = str(card.get("power", "")),
		toughness = str(card.get("toughness", "")),
		loyalty = str(card.get("loyalty", "")),
		layout = str(card.get("layout", "normal")),
		set = str(card.get("set", "")),
		collector_number = str(card.get("collector_number", "")),
		rarity = str(card.get("rarity", "")),
		commander_legal = legal,
		faces = faces_out,
		images = images,
	}


func _normalize_row(row: Dictionary) -> Dictionary:
	var out := row.duplicate(true)
	if not out.has("commander_legal"):
		out["commander_legal"] = true
	if not out.has("images"):
		out["images"] = {}
	return out


func _cache_path() -> String:
	return "user://scryfall_card_cache.json"


func _read_cache(card_name: String) -> Dictionary:
	var path := _cache_path()
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return {}
	var key := DeckText.normalize_key(card_name)
	var hit: Variant = (parsed as Dictionary).get(key, {})
	return hit if hit is Dictionary else {}


func _cache_row(row: Dictionary) -> void:
	var path := _cache_path()
	var store := {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			store = parsed
	var key := DeckText.normalize_key(str(row.get("name", "")))
	if key != "":
		store[key] = row
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(store))
		f.close()


func _catalog() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/ScryfallCatalog")
	return null
