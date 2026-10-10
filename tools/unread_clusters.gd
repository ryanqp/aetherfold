extends SceneTree

## Turns the unread lines of a catalog_coverage.gd report into a work list of the smallest pieces that fail:
## trigger headers ("When X, ..."), activation costs, and single effect sentences, each folded so that numbers, mana,
## colours, card types and the card's own name look alike. Pieces that are read on their own are skipped, so what is left
## is what the reader can't do.
## Usage: godot --headless --path . -s res://tools/unread_clusters.gd -- --in=user://coverage_full.txt [--out=user://clusters.txt]

const COLORS := ["white", "blue", "black", "red", "green", "colorless", "multicolored", "monocolored"]
const TYPES := ["creature", "artifact", "enchantment", "land", "planeswalker", "instant", "sorcery", "battle", "permanent", "spell"]


func _initialize() -> void:
	var in_path := "user://coverage_full.txt"
	var out_path := "user://clusters.txt"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--in="):
			in_path = s.substr(5)
		elif s.begins_with("--out="):
			out_path = s.substr(6)
	var f := FileAccess.open(in_path, FileAccess.READ)
	if f == null:
		print("no report at ", in_path)
		quit(1)
		return
	var heads := {}
	var costs := {}
	var sentences := {}
	var statics := {}
	var examples := {}
	while not f.eof_reached():
		var raw := f.get_line()
		if not raw.begins_with("CARD|"):
			continue
		var parts := raw.split("|")
		if parts.size() < 4:
			continue
		var card_name := parts[1]
		for i in range(3, parts.size()):
			var line := OracleIr.strip_ability_word(parts[i].strip_edges())
			_one(line, card_name, heads, costs, sentences, statics, examples)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	for section in [["TRIGGER HEADERS", heads], ["ACTIVATION COSTS", costs], ["EFFECT SENTENCES", sentences], ["STATIC / OTHER LINES", statics]]:
		var table: Dictionary = section[1]
		var keys: Array = table.keys()
		keys.sort_custom(func(x, y) -> bool: return int(table[x]) > int(table[y]))
		var total := 0
		for k in keys:
			total += int(table[k])
		out.store_line("=== %s (%d distinct, %d in all)" % [section[0], keys.size(), total])
		for k in keys:
			out.store_line("%d\t%s\t[%s]" % [int(table[k]), str(k), str(examples.get(k, ""))])
	out.close()
	print("written ", ProjectSettings.globalize_path(out_path))
	quit(0)


func _fold(s: String) -> String:
	var t := s.to_lower()
	t = RegEx.create_from_string("\\{[^}]*\\}").sub(t, "{M}", true)
	t = RegEx.create_from_string("\\b\\d+\\b").sub(t, "N", true)
	t = RegEx.create_from_string("[+-]N/[+-]N").sub(t, "+N/+N", true)
	for c in COLORS:
		t = RegEx.create_from_string("\\b%s\\b" % c).sub(t, "COLOR", true)
	for ty in TYPES:
		t = RegEx.create_from_string("\\b%ss?\\b" % ty).sub(t, "TYPE", true)
	return t


func _bump(table: Dictionary, examples: Dictionary, key: String, card_name: String) -> void:
	table[key] = int(table.get(key, 0)) + 1
	if not examples.has(key):
		examples[key] = card_name


func _one(line: String, card_name: String, heads: Dictionary, costs: Dictionary, sentences: Dictionary, statics: Dictionary, examples: Dictionary) -> void:
	var low := line.to_lower()
	var rd := OracleIr.new()
	OracleIr.lenient = false
	## Triggered: "When/Whenever/At ..., effect"
	var tm := RegEx.create_from_string("(?i)^(when|whenever|at) (.+?), ((?:if |you may |[a-z~]).+)$").search(line.trim_suffix("."))
	if tm != null and (low.begins_with("when") or low.begins_with("at ")):
		var header := tm.get_string(2)
		var head_ok := not rd._header(header).is_empty()
		if not head_ok and low.begins_with("at the beginning of"):
			head_ok = true  ## step triggers are read in _trigger_line, not _header
		if not head_ok:
			_bump(heads, examples, _fold(tm.get_string(1) + " " + header), card_name)
		_sentences(tm.get_string(3), card_name, sentences, examples)
		return
	## Activated: "cost: effect"
	var colon := line.find(": ")
	var cost_like := colon > 0 and colon < 70 and not low.begins_with("choose") and (line.substr(0, colon).find("{") >= 0 \
		or low.begins_with("sacrifice") or low.begins_with("tap ") or low.begins_with("exile") or low.begins_with("remove") \
		or low.begins_with("discard") or low.begins_with("pay") or RegEx.create_from_string("^[+−-]?\\d+$").search(line.substr(0, colon)) != null)
	if cost_like:
		var cost := line.substr(0, colon)
		var effect := line.substr(colon + 2)
		if rd._costs(cost).is_empty() and cost != "{T}":
			_bump(costs, examples, _fold(cost), card_name)
		_sentences(effect, card_name, sentences, examples)
		return
	## A line that reads as a whole static ability?
	if not rd._static_line(low.trim_suffix(".")).is_empty():
		return
	## Spell-like text: try it sentence by sentence; if every sentence reads alone, the line is a static/other form.
	var before := sentences.size()
	var any_bad := _sentences(line, card_name, sentences, examples)
	if not any_bad:
		_bump(statics, examples, _fold(line), card_name)


## Counts each sentence of `text` that doesn't read on its own. True if any didn't.
func _sentences(text: String, card_name: String, sentences: Dictionary, examples: Dictionary) -> bool:
	var bad := false
	for raw in text.split(". "):
		var s := str(raw).strip_edges().trim_suffix(".").strip_edges()
		if s == "":
			continue
		var rd := OracleIr.new()
		rd._self_it = true
		if rd._read_effects(s):
			continue
		bad = true
		_bump(sentences, examples, _fold(s), card_name)
	return bad
