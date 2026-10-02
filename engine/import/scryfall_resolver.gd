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
	## A double-faced or split card is listed under its full name ("A // B") or just its front face.
	for nm in [card_name, _front_face(card_name)]:
		if cat != null and cat.has_method("find_by_name"):
			var row: Variant = cat.find_by_name(str(nm))
			if row is Dictionary and not (row as Dictionary).is_empty():
				return _normalize_row(row)
		var cached := _read_cache(str(nm))
		if not cached.is_empty():
			return cached
	return {}


## "Fell the Profane // Fell Mire" -> "Fell the Profane"; other names are returned as they are.
static func _front_face(card_name: String) -> String:
	var i := card_name.find(" // ")
	return card_name.substr(0, i).strip_edges() if i > 0 else card_name


func _fetch_collection(names: Array) -> Dictionary:
	var out := {}
	var i := 0
	while i < names.size():
		var chunk: Array = []
		var slice := mini(BATCH, names.size() - i)
		for j in slice:
			chunk.append({name = _front_face(str(names[i + j]))})
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
	var front_key := DeckText.normalize_key(_front_face(resolved_name))
	for n in asked:
		if DeckText.normalize_key(_front_face(str(n))) == front_key:
			return str(n)
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
			art_crop = str(iu.get("art_crop", "")),
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
					art_crop = str(fiu.get("art_crop", "")),
				}
	var legal := true
	var legs: Variant = card.get("legalities", {})
	if legs is Dictionary:
		legal = str((legs as Dictionary).get("commander", "legal")) == "legal"
	## Every face with its own rules (transform, MDFC, split, adventure): the engine plays the other face too.
	var faces_out: Array = []
	if card.get("card_faces") is Array:
		for f in card.get("card_faces"):
			if f is Dictionary:
				var fd: Dictionary = f
				faces_out.append({name = str(fd.get("name", "")), mana_cost = str(fd.get("mana_cost", "")), type_line = str(fd.get("type_line", "")),
					oracle_text = str(fd.get("oracle_text", "")), power = str(fd.get("power", "")), toughness = str(fd.get("toughness", "")),
					loyalty = str(fd.get("loyalty", "")), colors = fd.get("colors", card.get("colors", []))})
	var out_row := {
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
	return with_front_face(out_row, card)


## A double-faced, split or adventure card has no top-level Oracle text, cost or P/T on Scryfall: the
## engine plays its front (main) face, so those characteristics come from the first face (CR 709.3, 712.8a).
static func with_front_face(row: Dictionary, card: Dictionary) -> Dictionary:
	var faces: Variant = card.get("card_faces", [])
	if not (faces is Array) or (faces as Array).is_empty() or not ((faces as Array)[0] is Dictionary):
		return row
	var f: Dictionary = (faces as Array)[0]
	if str(row.get("oracle_text", "")) == "":
		row["oracle_text"] = str(f.get("oracle_text", ""))
	if str(row.get("mana_cost", "")) == "":
		row["mana_cost"] = str(f.get("mana_cost", ""))
	if str(row.get("type_line", "")).contains(" // "):
		row["type_line"] = str(f.get("type_line", row.get("type_line", "")))
	for k in ["power", "toughness", "loyalty"]:
		if str(row.get(k, "")) == "":
			row[k] = str(f.get(k, ""))
	return row


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
