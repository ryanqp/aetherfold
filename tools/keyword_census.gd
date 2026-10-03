extends SceneTree

## Every keyword the Scryfall catalog lists (commander-legal cards), with how many cards use it and what KeywordDb
## does with it. Usage: godot --headless --path . -s res://tools/keyword_census.gd -- [--catalog=<jsonl>] [--out=user://keywords.txt]

func _initialize() -> void:
	var catalog := "res://data/scryfall/catalog.jsonl"
	var out_path := "user://keywords.txt"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--catalog="):
			catalog = s.substr(10)
		elif s.begins_with("--out="):
			out_path = s.substr(6)
	var f := FileAccess.open(catalog, FileAccess.READ)
	if f == null:
		quit(1)
		return
	var counts := {}
	var example := {}
	while not f.eof_reached():
		var raw := f.get_line().strip_edges()
		if raw == "":
			continue
		var row: Variant = JSON.parse_string(raw)
		if not (row is Dictionary) or not bool((row as Dictionary).get("commander_legal", false)):
			continue
		for k in (row as Dictionary).get("keywords", []):
			var key := str(k).to_lower()
			counts[key] = int(counts.get(key, 0)) + 1
			if not example.has(key):
				example[key] = str((row as Dictionary).get("name", ""))
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b) -> bool: return int(counts[a]) > int(counts[b]))
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	for k in keys:
		var info: Dictionary = KeywordDb.lookup(str(k))
		var status := str(info.get("status", "UNKNOWN")) if not info.is_empty() else "UNKNOWN"
		out.store_line("%s\t%d\t%s\t%s" % [status, counts[k], k, example[k]])
	out.close()
	print("keywords=%d -> %s" % [keys.size(), ProjectSettings.globalize_path(out_path)])
	quit(0)
