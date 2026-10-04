extends SceneTree

## Which cards of a saved deck still have lines the Oracle reader does not understand?
## Usage: godot --headless --path . -s res://tools/deck_audit.gd -- <deck.json> [--catalog=<jsonl>]
## Prints every card with an unread line (these show up as "Not coded yet" in the match History).


func _initialize() -> void:
	var deck_path := ""
	var catalog := "res://data/scryfall/catalog.jsonl"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--catalog="):
			catalog = s.substr(10)
		else:
			deck_path = s
	var deck: Variant = JSON.parse_string(FileAccess.get_file_as_string(deck_path))
	if not (deck is Dictionary):
		print("cannot read deck ", deck_path)
		quit(1)
		return
	var names := {}
	for n in ((deck as Dictionary).get("cards", {}) as Dictionary).keys():
		names[str(n).to_lower()] = str(n)
	var mem := CatalogSource.Memory.new()
	var f := FileAccess.open(catalog, FileAccess.READ)
	while not f.eof_reached():
		var raw := f.get_line().strip_edges()
		if raw == "":
			continue
		var row: Variant = JSON.parse_string(raw)
		if row is Dictionary and names.has(str((row as Dictionary).get("name", "")).to_lower()):
			mem.add(row)
	var db := CardDatabase.new()
	db.setup(mem)
	var bad := 0
	var total := 0
	for key in names.keys():
		var d := db.definition_for(str(names[key]))
		if d == null:
			continue
		total += 1
		var lines: Array = []
		for st in db.line_status(d):
			if not bool((st as Dictionary).read):
				lines.append(str((st as Dictionary).line))
		if lines.is_empty():
			continue
		bad += 1
		print("CARD ", d.name)
		for l in lines:
			print("   - ", l)
	print("DECK ", str((deck as Dictionary).get("name", "")), ": ", total - bad, " of ", total, " cards fully read")
	quit(0)
