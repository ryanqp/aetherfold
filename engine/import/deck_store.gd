class_name DeckStore
extends RefCounted

const DIR := "user://imported_decks"


func list_decks() -> Array:
	_ensure_dir()
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".json"):
			var path := DIR.path_join(f)
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				var rec: Dictionary = parsed
				rec["_path"] = path
				out.append(rec)
		f = d.get_next()
	d.list_dir_end()
	return out


func find_by_source_url(url: String) -> Dictionary:
	if url.strip_edges() == "":
		return {}
	for rec in list_decks():
		if str(rec.get("sourceUrl", "")) == url:
			return rec
	return {}


func save(deck: NormalizedDeck, rows: Dictionary, validation: Dictionary, replace_path: String = "") -> String:
	_ensure_dir()
	var rec := {
		id = str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec()),
		name = deck.name,
		source = deck.source,
		sourceUrl = deck.source_url,
		importedAt = Time.get_datetime_string_from_system(true, true),
		commander = deck.commanders.duplicate(true),
		mainboard = deck.mainboard.duplicate(true),
		cards = _compact_rows(rows),
		validation = {
			ok = bool(validation.get("ok", false)),
			errors = PackedStringArray(validation.get("errors", PackedStringArray())),
			warnings = PackedStringArray(validation.get("warnings", PackedStringArray())),
			total = int(validation.get("total", deck.total_cards())),
		},
	}
	var path := replace_path
	if path == "":
		var slug := _slug(deck.name)
		path = DIR.path_join("%s-%s.json" % [slug, str(rec.id)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(rec, "\t"))
	f.close()
	return path


func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _compact_rows(rows: Dictionary) -> Dictionary:
	var out := {}
	for k in rows.keys():
		var row: Dictionary = rows[k]
		out[str(k)] = {
			id = str(row.get("id", "")),
			oracle_id = str(row.get("oracle_id", "")),
			name = str(row.get("name", "")),
			mana_cost = str(row.get("mana_cost", "")),
			cmc = row.get("cmc", 0),
			type_line = str(row.get("type_line", "")),
			oracle_text = str(row.get("oracle_text", "")),
			colors = row.get("colors", []),
			color_identity = row.get("color_identity", []),
			keywords = row.get("keywords", []),
			power = str(row.get("power", "")),
			toughness = str(row.get("toughness", "")),
			loyalty = str(row.get("loyalty", "")),
			commander_legal = bool(row.get("commander_legal", true)),
			images = row.get("images", {}),
		}
	return out


func _slug(n: String) -> String:
	var s := n.to_lower()
	var out := ""
	for ch in s:
		var o := ch.unicode_at(0)
		if (o >= 97 and o <= 122) or (o >= 48 and o <= 57):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "-"
	if out == "":
		out = "deck"
	return out.substr(0, 40)


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
