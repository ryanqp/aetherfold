extends SceneTree

## How much of the whole Scryfall catalog the Oracle reader understands, line by line.
## Usage: godot --headless --path . -s res://tools/catalog_coverage.gd -- [--step=4] [--out=user://coverage.txt] [--catalog=<jsonl>]
##   --step=N   read every Nth commander-legal card (default 1 = all, about 30,000 cards)
## Writes CARD|name|type|unread line|... for every card with an unread line, then a frequency table of the unread
## lines (numbers and mana symbols folded together) and the totals. Work down the frequency table.

func _initialize() -> void:
	var step := 1
	var out_path := "user://coverage.txt"
	var catalog := "res://data/scryfall/catalog.jsonl"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--step="):
			step = maxi(1, int(s.substr(7)))
		elif s.begins_with("--out="):
			out_path = s.substr(6)
		elif s.begins_with("--catalog="):
			catalog = s.substr(10)
	var f := FileAccess.open(catalog, FileAccess.READ)
	if f == null:
		push_error("no catalog at %s" % catalog)
		quit(1)
		return
	var db := CardDatabase.new()
	var mem := CatalogSource.Memory.new()
	db.setup(mem)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	var freq := {}
	var pieces := {}
	var piece_example := {}
	var cards := 0
	var clean := 0
	var lines_total := 0
	var lines_unread := 0
	var idx := 0
	var skip_layouts := ["token", "emblem", "art_series", "double_faced_token", "vanguard", "scheme", "planar"]
	while not f.eof_reached():
		var raw := f.get_line().strip_edges()
		if raw == "":
			continue
		var row: Variant = JSON.parse_string(raw)
		if not (row is Dictionary):
			continue
		var r: Dictionary = row
		if not bool(r.get("commander_legal", false)) or str(r.get("layout", "normal")) in skip_layouts:
			continue
		idx += 1
		if idx % step != 0:
			continue
		mem.add(r)
		var def := db.definition_for(str(r.get("name", "")))
		if def == null:
			continue
		cards += 1
		var bad: Array = []
		for st in db.line_status(def):
			lines_total += 1
			if not bool((st as Dictionary).read):
				lines_unread += 1
				bad.append(str((st as Dictionary).line))
		if bad.is_empty():
			clean += 1
			continue
		out.store_line("CARD|%s|%s|%s" % [def.name, def.type_line, "|".join(PackedStringArray(bad))])
		for l in bad:
			var key := RegEx.create_from_string("\\d+").sub(RegEx.create_from_string("\\{[^}]*\\}").sub(str(l), "{M}", true), "N", true)
			freq[key] = int(freq.get(key, 0)) + 1
			## Which piece of the line stops it: a trigger header, a cost, or one sentence (read in its place, not alone).
			var piece := _failing_piece(def, str(l))
			var pkey := _fold(piece)
			pieces[pkey] = int(pieces.get(pkey, 0)) + 1
			if not piece_example.has(pkey):
				piece_example[pkey] = def.name
	var keys: Array = freq.keys()
	keys.sort_custom(func(a, b) -> bool: return int(freq[a]) > int(freq[b]))
	out.store_line("--- FREQUENCY")
	for k in keys:
		out.store_line("%d\t%s" % [int(freq[k]), str(k)])
	var pkeys: Array = pieces.keys()
	pkeys.sort_custom(func(a, b) -> bool: return int(pieces[a]) > int(pieces[b]))
	out.store_line("--- PIECES (what stops each unread line: H header, C cost, S sentence, L the line's shape, M modal)")
	for pk in pkeys:
		out.store_line("%d	%s	[%s]" % [int(pieces[pk]), str(pk), str(piece_example[pk])])
	out.store_line("TOTAL cards=%d clean=%d (%.1f%%) lines=%d unread=%d" % [cards, clean, 100.0 * clean / maxf(1.0, cards), lines_total, lines_unread])
	out.close()
	print("cards=%d clean=%d (%.1f%%) lines=%d unread=%d -> %s" % [cards, clean, 100.0 * clean / maxf(1.0, cards), lines_total, lines_unread, ProjectSettings.globalize_path(out_path)])
	quit(0)


const _COLORS := ["white", "blue", "black", "red", "green", "colorless"]
const _TYPES := ["creature", "artifact", "enchantment", "land", "planeswalker", "instant", "sorcery", "battle", "permanent", "spell"]


func _fold(s: String) -> String:
	var t := s.to_lower()
	t = RegEx.create_from_string("\\{[^}]*\\}").sub(t, "{M}", true)
	t = RegEx.create_from_string("\\b\\d+\\b").sub(t, "N", true)
	for c in _COLORS:
		t = RegEx.create_from_string("\\b%s\\b" % c).sub(t, "COLOR", true)
	for ty in _TYPES:
		t = RegEx.create_from_string("\\b%ss?\\b" % ty).sub(t, "TYPE", true)
	return t


func _failing_piece(def: CardDefinition, line: String) -> String:
	var clean := OracleIr.strip_ability_word(line).trim_suffix(".")
	if clean.ends_with("—") or clean.to_lower().begins_with("choose "):
		## A modal line: the first bullet that doesn't read is what stops it.
		var after := false
		for raw in OracleIr.normalize(def).split("\n"):
			var bl := str(raw).strip_edges()
			if OracleIr.strip_ability_word(bl).trim_suffix(".") == clean:
				after = true
				continue
			if after and bl.begins_with("•"):
				var bullet := bl.substr(1).strip_edges().trim_suffix(".")
				var brd := OracleIr.new()
				OracleIr.diag = []
				OracleIr.diag_on = true
				var ok := brd._read_effects(bullet)
				OracleIr.diag_on = false
				if not ok:
					return str(OracleIr.diag[0]) if not OracleIr.diag.is_empty() else "B:" + bullet
			elif after:
				break
		return "M:" + clean
	OracleIr.diag = []
	OracleIr.diag_on = true
	if def.is_instant() or def.is_sorcery():
		OracleIr.new()._read_effects(clean)
	else:
		OracleIr._read_whole_or_by_sentence(def, clean)
	OracleIr.diag_on = false
	if OracleIr.diag.is_empty():
		return "L:" + clean
	return str(OracleIr.diag[0])
