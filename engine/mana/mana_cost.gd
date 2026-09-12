class_name ManaCost
extends Resource

var generic: int = 0
var w: int = 0
var u: int = 0
var b: int = 0
var r: int = 0
var g: int = 0
var colorless: int = 0


static func parse(s: String) -> ManaCost:
	var c := ManaCost.new()
	if s.is_empty():
		return c
	var re := RegEx.new()
	re.compile("\\{([^}]+)\\}")
	for m in re.search_all(s):
		var tok := m.get_string(1)
		if tok.is_valid_int():
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
	return generic + w + u + b + r + g + colorless


func is_zero() -> bool:
	return cmc() == 0


func duplicate_cost() -> ManaCost:
	var c := ManaCost.new()
	c.generic = generic
	c.w = w
	c.u = u
	c.b = b
	c.r = r
	c.g = g
	c.colorless = colorless
	return c
