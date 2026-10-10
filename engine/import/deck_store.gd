class_name DeckStore
extends RefCounted

const DIR := "user://imported_decks"

## Where this store keeps its decks. Tests pass their own folder (see DeckStore.scratch) so they never touch the player's decks.
var dir: String = DIR
## Why the last save / rename / delete failed ("" when it worked).
var last_error: String = ""


func _init(p_dir: String = DIR) -> void:
	dir = p_dir


## A store in its own throw-away folder under user://test_decks, for tests. Call wipe() when done.
static func scratch(label: String) -> DeckStore:
	return DeckStore.new("user://test_decks/%s-%d" % [label, Time.get_ticks_usec()])


## Removes this store's whole folder (only ever used on scratch stores).
func wipe() -> void:
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if not d.current_is_dir():
				DirAccess.remove_absolute(dir.path_join(f))
			f = d.get_next()
		d.list_dir_end()
	DirAccess.remove_absolute(dir)


func list_decks() -> Array:
	_ensure_dir()
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".json"):
			var path := dir.path_join(f)
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				var rec: Dictionary = parsed
				rec["_path"] = path
				out.append(rec)
		f = d.get_next()
	d.list_dir_end()
	return out


## Deck files that exist but can't be read (a save cut short, a hand-edited file). Listed so they can be shown and removed
## instead of vanishing from the deck lists.
func list_damaged() -> Array:
	_ensure_dir()
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".json"):
			var path := dir.path_join(f)
			if not (JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary):
				out.append(path)
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


## Finds an imported record by its stable source key (e.g. "edhrec:krenko-mob-boss").
func find_by_source_key(key: String) -> Dictionary:
	if key.strip_edges() == "":
		return {}
	for rec in list_decks():
		if str(rec.get("source_key", "")) == key:
			return rec
	return {}


## Saves a complete deck record as it is (the bundled precons); `replace_path` overwrites that file.
## Returns the path, or "" when it could not be written (see last_error).
func save_record(rec: Dictionary, replace_path: String = "") -> String:
	_ensure_dir()
	var out := rec.duplicate(true)
	out.erase("_path")
	if not out.has("id"):
		out["id"] = str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec())
	out["importedAt"] = Time.get_datetime_string_from_system(true, true)
	var path := replace_path
	if path == "":
		path = dir.path_join("%s-%s.json" % [_slug(str(out.get("name", "deck"))), str(out.id)])
	return path if _atomic_write(path, JSON.stringify(out, "\t")) else ""


## `meta` keys are merged into the record (is_imported, source, source_url, source_commander, ...).
func save(deck: NormalizedDeck, rows: Dictionary, validation: Dictionary, replace_path: String = "", meta: Dictionary = {}) -> String:
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
	for k in meta.keys():
		rec[k] = meta[k]
	var path := replace_path
	if path == "":
		var slug := _slug(deck.name)
		path = dir.path_join("%s-%s.json" % [slug, str(rec.id)])
	return path if _atomic_write(path, JSON.stringify(rec, "\t")) else ""


func rename(path: String, new_name: String) -> bool:
	var rec: Dictionary = load_path(path)
	if rec.is_empty():
		last_error = "That deck could not be read."
		return false
	var nm := DeckText.sanitize_name(new_name)
	if nm == "":
		last_error = "A deck needs a name."
		return false
	rec["name"] = nm
	return _atomic_write(path, JSON.stringify(rec, "\t"))


## A copy of a saved deck under a new name ("... (copy)"). The copy is an ordinary deck of your own: it forgets where the
## original came from, so it is never mistaken for (or overwritten as) a bundled precon or an imported-from-URL deck.
## Returns the new path, or "" (see last_error).
func duplicate(path: String) -> String:
	var rec: Dictionary = load_path(path)
	if rec.is_empty():
		last_error = "That deck could not be read."
		return ""
	rec["name"] = "%s (copy)" % str(rec.get("name", "Deck"))
	for k in ["id", "source_key", "precon_id", "precon_version", "precon_order", "precon_set", "sourceUrl"]:
		rec.erase(k)
	rec["source"] = "copy"
	return save_record(rec)


## The deck as a plain list that any site or this game's Import window reads back: a Commander block, then the 99.
static func export_text(rec: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Commander")
	for e in rec.get("commander", []):
		lines.append("%d %s" % [int((e as Dictionary).get("quantity", 1)), str((e as Dictionary).get("name", ""))])
	lines.append("")
	lines.append("Deck")
	for e2 in rec.get("mainboard", []):
		lines.append("%d %s" % [int((e2 as Dictionary).get("quantity", 1)), str((e2 as Dictionary).get("name", ""))])
	return "\n".join(lines) + "\n"


func delete_path(path: String) -> bool:
	if path.strip_edges() == "" or not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Writes `text` to a temporary file next to `path`, then renames it into place, so a crash or a full disk in the middle of a
## save leaves the old file as it was instead of half a deck. Sets last_error and returns false when anything fails.
func _atomic_write(path: String, text: String) -> bool:
	last_error = ""
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "Could not write %s (error %d)." % [path.get_file(), FileAccess.get_open_error()]
		return false
	f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(tmp)
		last_error = "Could not finish writing %s (error %d)." % [path.get_file(), write_err]
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_err := DirAccess.rename_absolute(tmp, path)
	if rename_err != OK:
		DirAccess.remove_absolute(tmp)
		last_error = "Could not save %s (error %d)." % [path.get_file(), rename_err]
		return false
	return true


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
			layout = str(row.get("layout", "normal")),
			faces = row.get("faces", []),
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
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
