extends SceneTree

## Prints the Oracle lines the engine does not read yet for every card in a JSON list of Scryfall rows.
## Usage: godot --headless --path . -s res://tools/coverage_report.gd -- --cards=<path to json array>
##        (with no --cards, the bundled precon decks are checked: res://data/precons/*.json)

func _initialize() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--cards="):
			path = str(arg).substr(8)
	var rows: Array = []
	if path != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			rows = parsed
	else:
		push_error("pass --cards=")
	var mem := CatalogSource.Memory.new()
	for r in rows:
		mem.add(r)
	var db := CardDatabase.new()
	db.setup(mem)
	var n_bad := 0
	var seen := {}
	for r in rows:
		var nm := str((r as Dictionary).get("name", ""))
		if seen.has(nm):
			continue
		seen[nm] = true
		var def := db.definition_for(nm)
		if def == null:
			print("MISSING ROW: ", nm)
			continue
		var unread: Array = db.unread_lines(def)
		var spell_unread := (def.is_instant() or def.is_sorcery()) and def.spell_ability() == null and def.abilities.is_empty()
		if unread.is_empty() and not spell_unread:
			continue
		n_bad += 1
		print("== ", nm, " [", def.type_line, "]")
		if spell_unread:
			print("   SPELL NOT READ: ", OracleIr.normalize(def).replace("\n", " / "))
		for l in unread:
			print("   - ", l)
	print("cards with unread text: %d of %d" % [n_bad, seen.size()])
	quit(0)
