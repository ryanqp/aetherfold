class_name ManaPool
extends RefCounted

var w: int = 0
var u: int = 0
var b: int = 0
var r: int = 0
var g: int = 0
var colorless: int = 0


func empty() -> void:
	w = 0
	u = 0
	b = 0
	r = 0
	g = 0
	colorless = 0


func is_empty() -> bool:
	return total() == 0


func total() -> int:
	return w + u + b + r + g + colorless


func add_cost(produced: ManaCost) -> void:
	if produced == null:
		return
	w += produced.w
	u += produced.u
	b += produced.b
	r += produced.r
	g += produced.g
	colorless += produced.colorless + produced.generic


func can_pay(cost: ManaCost) -> bool:
	if cost == null:
		return true
	if w < cost.w or u < cost.u or b < cost.b or r < cost.r or g < cost.g:
		return false
	if colorless < cost.colorless:
		return false
	var leftover := (w - cost.w) + (u - cost.u) + (b - cost.b) + (r - cost.r) + (g - cost.g) + (colorless - cost.colorless)
	return leftover >= cost.generic


## Colors of mana spent since the last reset_spent() (sunburst, CR 702.44) and how much was spent (increment).
var spent_colors: Dictionary = {}
var spent_total: int = 0


func reset_spent() -> void:
	spent_colors = {}
	spent_total = 0


func pay(cost: ManaCost) -> bool:
	if not can_pay(cost):
		return false
	var before := {"W": w, "U": u, "B": b, "R": r, "G": g, "C": colorless}
	spent_total += cost.cmc()
	_note_spent(before)
	w -= cost.w
	u -= cost.u
	b -= cost.b
	r -= cost.r
	g -= cost.g
	colorless -= cost.colorless
	var remain := cost.generic
	remain = _take_generic(remain, "colorless")
	remain = _take_generic(remain, "w")
	remain = _take_generic(remain, "u")
	remain = _take_generic(remain, "b")
	remain = _take_generic(remain, "r")
	remain = _take_generic(remain, "g")
	var after := {"W": w, "U": u, "B": b, "R": r, "G": g}
	for k in after.keys():
		if int(after[k]) < int(_spent_before[k]):
			spent_colors[k] = true
	return remain == 0


var _spent_before: Dictionary = {}


func _note_spent(before: Dictionary) -> void:
	_spent_before = before


func _take_generic(remain: int, channel: String) -> int:
	if remain <= 0:
		return 0
	var have := 0
	match channel:
		"w":
			have = w
		"u":
			have = u
		"b":
			have = b
		"r":
			have = r
		"g":
			have = g
		"colorless":
			have = colorless
	var use := mini(have, remain)
	match channel:
		"w":
			w -= use
		"u":
			u -= use
		"b":
			b -= use
		"r":
			r -= use
		"g":
			g -= use
		"colorless":
			colorless -= use
	return remain - use
