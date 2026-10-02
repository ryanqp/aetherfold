class_name PreconDecks
extends RefCounted
## The eight starter decks that come with the game besides the two built-in ones (Krenko and Talrand):
## official Commander precon decklists, the first eight on Moxfield's "Commander Precons" page
## (https://moxfield.com/decks/public?q=eyJmb3JtYXQiOiJjb21tYW5kZXJQcmVjb25zIn0%3D).
##
## Each list ships with the game in res://data/precons/*.json, card rows included (name, cost, type line,
## Oracle text, P/T, loyalty, Scryfall image links), so the decks work with no network and no local
## Scryfall catalog. On start-up `install()` copies any that are missing into user://imported_decks, where
## the Vs. AI lists and the gallery read them like any other saved deck, and removes the decks the
## starter list used to have (the eight most-liked Moxfield decks).

const SOURCE := "moxfield_commander_precons"
const DATA_DIR := "res://data/precons"
const WANT := 8
## Sources of starter decks this replaced; saved copies of them are deleted by install().
const RETIRED_SOURCES := ["moxfield_top_likes", "edhrec_scryfall_top_100"]

var store: DeckStore = DeckStore.new()
var data_dir: String = DATA_DIR


## The bundled precon records, in the order Moxfield lists them.
func bundled() -> Array:
	var out: Array = []
	var dir := DirAccess.open(data_dir)
	if dir == null:
		return out
	var names: Array = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join(str(n))))
		if parsed is Dictionary and str((parsed as Dictionary).get("source", "")) == SOURCE:
			out.append(parsed)
	return out


## Every Scryfall row in the bundled decks (one per card name), for tools and tests.
static func all_rows() -> Array:
	var seen := {}
	var out: Array = []
	for rec in PreconDecks.new().bundled():
		var cards: Dictionary = (rec as Dictionary).get("cards", {})
		for k in cards.keys():
			if not seen.has(str(k)):
				seen[str(k)] = true
				out.append(cards[k])
	return out


## How many precons are saved on this computer.
func saved_count() -> int:
	var n := 0
	for rec in store.list_decks():
		if str(rec.get("source", "")) == SOURCE:
			n += 1
	return n


## Deletes saved copies of the retired starter decks, then saves each bundled precon that isn't saved yet (or
## whose bundled version is newer). Returns {installed, kept, removed}.
func install() -> Dictionary:
	var out := {installed = 0, kept = 0, removed = 0}
	for rec in store.list_decks():
		var src := str(rec.get("source", ""))
		if src in RETIRED_SOURCES:
			var art := str(rec.get("commander_image", ""))
			if store.delete_path(str(rec.get("_path", ""))):
				out.removed += 1
			if art != "" and FileAccess.file_exists(art) and not _art_shared(art):
				DirAccess.remove_absolute(art)
	for b in bundled():
		var rec2: Dictionary = b
		var key := str(rec2.get("source_key", ""))
		var have: Dictionary = store.find_by_source_key(key)
		if not have.is_empty() and int(have.get("precon_version", 0)) >= int(rec2.get("precon_version", 0)):
			out.kept += 1
			continue
		var path := str(have.get("_path", "")) if not have.is_empty() else ""
		if store.save_record(rec2, path) != "":
			out.installed += 1
	return out


## The commander picture may be the same file another saved deck uses (same commander).
func _art_shared(art: String) -> bool:
	for rec in store.list_decks():
		if str(rec.get("commander_image", "")) == art:
			return true
	return false
