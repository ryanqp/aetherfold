class_name ManaCost
extends Resource

var generic: int = 0
var w: int = 0
var u: int = 0
var b: int = 0
var r: int = 0
var g: int = 0
var colorless: int = 0
## Produced mana only: one entry per mana whose color is picked when it is made. Each entry lists the
## allowed colors ("W","U","B","R","G"), or ["CI"] for "a color in your commander's color identity".
var choices: Array = []


static func parse(s: String) -> ManaCost:
	var c := ManaCost.new()
	if s.is_empty():
		return c
	var re := RegEx.new()
	re.compile("\\{([^}]+)\\}")
	for m in re.search_all(s):
		var tok := m.get_string(1)
		if tok == "CI":
			c.choices.append(["CI"])
		elif tok.contains("|"):
			c.choices.append(Array(tok.split("|")))
		elif tok.is_valid_int():
			c.generic += int(tok)
		else:
			match tok:
				"W":
					c.w += 1
				"U":
					c.u += 1
				"B":
					c.b += 1
				"R":
					c.r += 1
				"G":
					c.g += 1
				"C":
					c.colorless += 1
				_:
					pass
	return c


func cmc() -> int:
	return generic + w + u + b + r + g + colorless + choices.size()


func is_zero() -> bool:
	return cmc() == 0


func absorb(other: ManaCost) -> void:
	if other == null:
		return
	generic += other.generic
	w += other.w
	u += other.u
	b += other.b
	r += other.r
	g += other.g
	colorless += other.colorless
	choices.append_array(other.choices)


func to_text() -> String:
	var s := ""
	if generic > 0:
		s += "{%d}" % generic
	for _i in w:
		s += "{W}"
	for _i in u:
		s += "{U}"
	for _i in b:
		s += "{B}"
	for _i in r:
		s += "{R}"
	for _i in g:
		s += "{G}"
	for _i in colorless:
		s += "{C}"
	return s


func duplicate_cost() -> ManaCost:
	var c := ManaCost.new()
	c.generic = generic
	c.w = w
	c.u = u
	c.b = b
	c.r = r
	c.g = g
	c.colorless = colorless
	c.choices = choices.duplicate(true)
	return c
