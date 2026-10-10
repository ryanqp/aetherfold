extends SceneTree

## Builds the game's card catalog (data/scryfall/catalog.jsonl) from Scryfall's "Oracle Cards" bulk file.
## Same job as tools/fetch_scryfall.py, but it needs only Godot, keeps every face's rules (double-faced, split and adventure
## cards), and leaves out cards that are not part of the game (art cards, tokens, emblems, planes, schemes, vanguards).
##
## Usage: godot --headless --path . -s res://tools/build_catalog.gd -- --src=<oracle-cards.jsonl.gz> [--out=res://data/scryfall]
##   --src  the bulk file (default D:/AetherfoldData/scryfall/oracle-cards.jsonl.gz, which fetch_scryfall.py downloads)
##   --out  the folder to write catalog.jsonl and meta.json into (default res://data/scryfall)

const SKIP_LAYOUTS := ["art_series", "token", "double_faced_token", "emblem", "vanguard", "scheme", "planar", "reversible_card"]


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var src := "D:/AetherfoldData/scryfall/oracle-cards.jsonl.gz"
	var out_dir := "res://data/scryfall"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--src="):
			src = s.substr(6)
		elif s.begins_with("--out="):
			out_dir = s.substr(6)
	if not FileAccess.file_exists(src):
		print("BUILD no bulk file at ", src)
		quit(1)
		return
	var packed := FileAccess.get_file_as_bytes(src)
	var raw := packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		print("BUILD could not unzip ", src)
		quit(1)
		return
	var text := raw.get_string_from_utf8()
	raw = PackedByteArray()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out := FileAccess.open(out_dir.path_join("catalog.jsonl"), FileAccess.WRITE)
	if out == null:
		print("BUILD cannot write to ", out_dir)
		quit(1)
		return
	var resolver := ScryfallResolver.new()
	var kept := 0
	var skipped := 0
	var multi := 0
	for line in text.split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if not (parsed is Dictionary):
			continue
		var card: Dictionary = parsed
		if str(card.get("layout", "normal")) in SKIP_LAYOUTS:
			skipped += 1
			continue
		var row: Dictionary = resolver._normalize_api_card(card)
		if (row.get("faces", []) as Array).size() >= 2:
			multi += 1
		out.store_line(JSON.stringify(row))
		kept += 1
	out.close()
	var meta := {
		"source": "scryfall", "bulk_type": "oracle_cards", "built_by": "tools/build_catalog.gd",
		"built_at": Time.get_datetime_string_from_system(true),
		"card_count": kept, "multi_face_cards": multi, "skipped_layouts": SKIP_LAYOUTS,
	}
	var mf := FileAccess.open(out_dir.path_join("meta.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta, "  "))
	mf.close()
	print("BUILD kept=%d multi_face=%d skipped=%d -> %s" % [kept, multi, skipped, out_dir])
	quit(0)
