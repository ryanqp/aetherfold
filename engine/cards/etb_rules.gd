class_name EtbRules
extends RefCounted

## Lands (and other permanents) that "enter tapped unless ...", read from Oracle text. The zone
## manager asks `tapped_on_entry` as the permanent enters, so it is never untapped by mistake (CR 614.1c).
##
## Rule kinds:
##   REVEAL        "As ~ enters, you may reveal a Mountain or Forest card from your hand. If you don't, ~ enters tapped."
##   CONTROL       "~ enters tapped unless you control a Plains or an Island."
##   MAX_OTHER     "... unless you control two or fewer other lands."
##   MIN_OTHER     "... unless you control two or more other lands."
##   MIN_BASIC     "~ enters tapped unless you control two or more basic lands."
##   PAY_LIFE      "As ~ enters, you may pay 2 life. If you don't, it enters tapped."
## There is no prompt yet: revealing is free so it always happens when it can; paying life happens
## while you are at PAY_LIFE_FLOOR life or more.

const PAY_LIFE_FLOOR := 8

const NUMBERS := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7}


static func parse(def: CardDefinition) -> Dictionary:
	if def == null or def.oracle_text == "":
		return {}
	var text := OracleIr.normalize(def).to_lower().replace("\n", " ")
	var m := _m("as ~ enters(?: the battlefield)?, you may reveal an? (.+?) cards? from your hand\\. if you don't, (?:~|it) enters(?: the battlefield)? tapped", text)
	if m != null:
		return {"kind": "REVEAL", "types": _types(m.get_string(1))}
	m = _m("as ~ enters(?: the battlefield)?, you may pay (\\d+) life\\. if you don't, (?:~|it) enters(?: the battlefield)? tapped", text)
	if m != null:
		return {"kind": "PAY_LIFE", "n": int(m.get_string(1))}
	m = _m("~ enters(?: the battlefield)? tapped unless you control (\\w+) or more basic lands", text)
	if m != null and NUMBERS.has(m.get_string(1)):
		return {"kind": "MIN_BASIC", "n": int(NUMBERS[m.get_string(1)])}
	m = _m("~ enters(?: the battlefield)? tapped unless you control (\\w+) or (fewer|more) other lands", text)
	if m != null and NUMBERS.has(m.get_string(1)):
		return {"kind": "MAX_OTHER" if m.get_string(2) == "fewer" else "MIN_OTHER", "n": int(NUMBERS[m.get_string(1)])}
	m = _m("~ enters(?: the battlefield)? tapped unless you control an? (.+?)(?:\\.|$)", text)
	if m != null:
		return {"kind": "CONTROL", "types": _types(m.get_string(1))}
	return {}


## Whether `def` enters tapped for `controller`, given the board as it is just before it arrives.
## `hand` and `battlefield` are arrays of GameObject; `life` is the controller's life.
static func tapped_on_entry(rule: Dictionary, hand: Array, battlefield: Array, life: int) -> bool:
	match str(rule.get("kind", "")):
		"REVEAL":
			return not _any_has(hand, rule.get("types", []))
		"CONTROL":
			return not _any_has(battlefield, rule.get("types", []))
		"MAX_OTHER":
			return _count_lands(battlefield) > int(rule.get("n", 0))
		"MIN_OTHER":
			return _count_lands(battlefield) < int(rule.get("n", 0))
		"MIN_BASIC":
			return _count_basic_lands(battlefield) < int(rule.get("n", 0))
		"PAY_LIFE":
			return life < PAY_LIFE_FLOOR
	return false


static func _count_basic_lands(objs: Array) -> int:
	var n := 0
	for o in objs:
		var obj := o as GameObject
		if obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).is_basic_land():
			n += 1
	return n


static func _any_has(objs: Array, types: Array) -> bool:
	for o in objs:
		var obj := o as GameObject
		if obj == null or not (obj.definition is CardDefinition):
			continue
		var tl := (obj.definition as CardDefinition).type_line
		for t in types:
			if tl.contains(str(t)):
				return true
	return false


static func _count_lands(objs: Array) -> int:
	var n := 0
	for o in objs:
		var obj := o as GameObject
		if obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).is_land():
			n += 1
	return n


## "mountain or forest" / "plains or an island" / "basic land" -> ["Mountain", "Forest"] ...
static func _types(list_text: String) -> Array:
	var out: Array = []
	for part in list_text.replace(", or ", ",").replace(" or ", ",").split(","):
		var w := str(part).strip_edges()
		for article in ["an ", "a "]:
			if w.begins_with(article):
				w = w.substr(article.length())
		if w == "basic land":
			out.append("Basic")
		elif w != "":
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return out


static func _m(pattern: String, s: String) -> RegExMatch:
	return RegEx.create_from_string("(?i)" + pattern).search(s)
