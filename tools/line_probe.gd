extends SceneTree

## Reads each line of a text file as a permanent's Oracle line (triggers, activated abilities, statics) and prints which the
## reader understands. Usage: godot --headless --path . -s res://tools/line_probe.gd -- --file=<path> [--dump]

func _initialize() -> void:
	var path := ""
	var dump := false
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--file="):
			path = str(a).substr(7)
		elif str(a) == "--dump":
			dump = true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("no file")
		quit(1)
		return
	var ok := 0
	var bad := 0
	while not f.eof_reached():
		var l := f.get_line().strip_edges()
		if l == "":
			continue
		var d := CardDefinition.new()
		d.name = "Probe"
		d.type_line = "Creature — Probe"
		d.oracle_text = l
		var res: Array = OracleIr.translate_permanent(d)
		if res.is_empty():
			res = OracleIr._read_whole_or_by_sentence(d, l.trim_suffix("."))
		if res.is_empty():
			bad += 1
			print("UNREAD: ", l)
		else:
			ok += 1
			if dump:
				print("  ", JSON.stringify(res))
	print("read=%d unread=%d" % [ok, bad])
	quit(0)
