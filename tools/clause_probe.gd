extends SceneTree

## Reads each line of a text file as an effect sentence and prints which the Oracle reader understands.
## Usage: godot --headless --path . -s res://tools/clause_probe.gd -- --file=<path>

func _initialize() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--file="):
			path = str(a).substr(7)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("no file")
		quit(1)
		return
	var dump := OS.get_cmdline_user_args().has("--dump")
	var ok := 0
	var bad := 0
	while not f.eof_reached():
		var l := f.get_line().strip_edges()
		if l == "":
			continue
		var rd := OracleIr.new()
		if rd._read_effects(l):
			ok += 1
			if dump:
				print("  ", JSON.stringify(rd._effects), " targets=", JSON.stringify(rd._targets))
		else:
			bad += 1
			print("UNREAD: ", l)
	print("read=%d unread=%d" % [ok, bad])
	quit(0)
