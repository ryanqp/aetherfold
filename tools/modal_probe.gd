extends SceneTree

## Which "Choose one —" bullets the reader can't read, by frequency (numbers and mana folded).
## Usage: godot --headless --path . -s res://tools/modal_probe.gd -- [--step=2] [--out=user://modal.txt]

func _initialize() -> void:
	var step := 1
	var out_path := "user://modal.txt"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--step="):
			step = maxi(1, int(s.substr(7)))
		elif s.begins_with("--out="):
			out_path = s.substr(6)
	var f := FileAccess.open("res://data/scryfall/catalog.jsonl", FileAccess.READ)
	var freq := {}
	var idx := 0
	while not f.eof_reached():
		var raw := f.get_line().strip_edges()
		if raw == "":
			continue
		var row: Variant = JSON.parse_string(raw)
		if not (row is Dictionary) or not bool((row as Dictionary).get("commander_legal", false)):
			continue
		var text := OracleIr.normalize(CardDefinition.from_catalog_row(row))
		if not text.contains("•"):
			continue
		idx += 1
		if idx % step != 0:
			continue
		for line in text.split("\n"):
			var l := str(line).strip_edges()
			if not l.begins_with("•"):
				continue
			var rd := OracleIr.new()
			if rd._read_effects(l.substr(1).strip_edges()):
				continue
			var key := RegEx.create_from_string("\\d+").sub(RegEx.create_from_string("\\{[^}]*\\}").sub(l.substr(1).strip_edges(), "{M}", true), "N", true)
			freq[key] = int(freq.get(key, 0)) + 1
	var keys: Array = freq.keys()
	keys.sort_custom(func(a, b) -> bool: return int(freq[a]) > int(freq[b]))
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	for k in keys:
		out.store_line("%d\t%s" % [int(freq[k]), str(k)])
	out.close()
	print("distinct unread bullets: %d" % keys.size())
	quit(0)
