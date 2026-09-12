class_name CommanderValidator
extends RefCounted

const WORD_NUM := {
	"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
	"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
}


func validate(deck: NormalizedDeck, rows: Dictionary, unresolved: PackedStringArray = PackedStringArray()) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var total := deck.total_cards()
	if total < 100:
		var need := 100 - total
		errors.append("Deck contains %d cards including commander. Add %d card%s." % [total, need, "s" if need != 1 else ""])
	elif total > 100:
		errors.append("Deck contains %d cards. Commander decks must contain exactly 100 cards." % total)
	if deck.commanders.is_empty():
		errors.append("No commander found.")
	var cmd_rows: Array = []
	for e in deck.commanders:
		var n := str(e.get("name", ""))
		var row: Dictionary = rows.get(n, {})
		if row.is_empty():
			errors.append("Commander could not be resolved: %s" % n)
			continue
		cmd_rows.append(row)
		if not _can_be_commander(row) and not _is_background(row):
			errors.append("%s is not a legal commander." % n)
	if cmd_rows.size() > 2:
		errors.append("Too many commanders (%d)." % cmd_rows.size())
	elif cmd_rows.size() == 2 and not _pair_legal(cmd_rows[0], cmd_rows[1]):
		errors.append("These two cards are not a legal commander pair (Partner / Partner With / Background).")
	var allowed_ci: PackedStringArray = PackedStringArray()
	for cr in cmd_rows:
		for c in cr.get("color_identity", []):
			var cs := str(c)
			if not cs in allowed_ci:
				allowed_ci.append(cs)
	var copies := {}
	for e2 in deck.mainboard:
		var n2 := str(e2.get("name", ""))
		var q := int(e2.get("quantity", 1))
		copies[n2] = int(copies.get(n2, 0)) + q
		var row2: Dictionary = rows.get(n2, {})
		if row2.is_empty():
			continue
		if not bool(row2.get("commander_legal", true)):
			errors.append("Not Commander-legal: %s" % n2)
		if not _ci_subset(row2.get("color_identity", []), allowed_ci) and not allowed_ci.is_empty():
			var extra := _ci_outside(row2.get("color_identity", []), allowed_ci)
			errors.append("Illegal card:\n%s\n\nReason:\n%s color identity is outside the commander's color identity." % [n2, extra])
		var maxc := _max_copies(row2)
		if q > maxc:
			errors.append("Illegal duplicate: %s x%d (max %d)." % [n2, q, maxc])
	for u in unresolved:
		warnings.append("Unresolved: %s" % u)
	var commander_ok := deck.commanders.size() >= 1 and deck.commanders.size() <= 2
	var singleton_ok := true
	for k in copies.keys():
		var row3: Dictionary = rows.get(str(k), {})
		if not row3.is_empty() and int(copies[k]) > _max_copies(row3):
			singleton_ok = false
	var identity_ok := true
	for err in errors:
		if str(err).find("color identity") >= 0 or str(err).begins_with("Illegal card:"):
			identity_ok = false
	return {
		ok = errors.is_empty(),
		errors = errors,
		warnings = warnings,
		total = total,
		commander_ok = commander_ok and errors.find("No commander found.") < 0,
		singleton_ok = singleton_ok,
		identity_ok = identity_ok,
		unresolved = unresolved,
		color_identity = allowed_ci,
	}


func _can_be_commander(row: Dictionary) -> bool:
	var tl := str(row.get("type_line", ""))
	var ot := str(row.get("oracle_text", ""))
	if tl.find("Legendary") >= 0 and tl.find("Creature") >= 0:
		return true
	if ot.to_lower().find("can be your commander") >= 0:
		return true
	if tl.find("Legendary") >= 0 and tl.find("Planeswalker") >= 0 and ot.to_lower().find("can be your commander") >= 0:
		return true
	return false


func _is_background(row: Dictionary) -> bool:
	return str(row.get("type_line", "")).find("Background") >= 0


func _has_partner(row: Dictionary) -> bool:
	var kw: Variant = row.get("keywords", [])
	if kw is Array or kw is PackedStringArray:
		for k in kw:
			if str(k).to_lower() == "partner":
				return true
	var ot := str(row.get("oracle_text", "")).to_lower()
	return ot.find("partner") >= 0 and ot.find("partner with") < 0


func _partner_with(row: Dictionary) -> String:
	var ot := str(row.get("oracle_text", ""))
	var re := RegEx.new()
	re.compile("Partner with ([^\\n(]+)")
	var m := re.search(ot)
	if m:
		return m.get_string(1).strip_edges()
	return ""


func _pair_legal(a: Dictionary, b: Dictionary) -> bool:
	if _is_background(a) and _can_be_commander(b):
		return true
	if _is_background(b) and _can_be_commander(a):
		return true
	if _has_partner(a) and _has_partner(b):
		return true
	var aw := _partner_with(a)
	var bw := _partner_with(b)
	if aw != "" and DeckText.normalize_key(aw) == DeckText.normalize_key(str(b.get("name", ""))):
		return true
	if bw != "" and DeckText.normalize_key(bw) == DeckText.normalize_key(str(a.get("name", ""))):
		return true
	return false


func _max_copies(row: Dictionary) -> int:
	var def := CardDefinition.from_catalog_row(row)
	if def.is_basic_land():
		return 99
	var ot := str(row.get("oracle_text", "")).to_lower()
	if ot.find("a deck can have any number of cards named") >= 0:
		return 99
	var re := RegEx.new()
	re.compile("a deck can have up to ([a-z0-9]+) cards named")
	var m := re.search(ot)
	if m:
		var w := m.get_string(1)
		if w.is_valid_int():
			return int(w)
		if WORD_NUM.has(w):
			return int(WORD_NUM[w])
	return 1


func _ci_subset(have: Variant, allowed: PackedStringArray) -> bool:
	if have == null:
		return true
	for c in have:
		if not str(c) in allowed:
			return false
	return true


func _ci_outside(have: Variant, allowed: PackedStringArray) -> String:
	var names := {"W": "White", "U": "Blue", "B": "Black", "R": "Red", "G": "Green"}
	var extra: PackedStringArray = PackedStringArray()
	for c in have:
		if not str(c) in allowed:
			extra.append(str(names.get(str(c), str(c))))
	return " / ".join(extra)
