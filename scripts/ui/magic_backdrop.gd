
extends Control

## The animated backdrop of the title screen and menu pages: a midnight sky with twinkling stars, a slowly turning
## mana wheel (the five colors of Magic around a pentacle) and motes of mana drifting upward. Drawn in code, so it
## needs no image files and scales to any window.

## The five colors of mana, in wheel order: White, Blue, Black, Red, Green.
const MANA := [
	Color(0.98, 0.95, 0.78),
	Color(0.34, 0.62, 0.97),
	Color(0.62, 0.42, 0.80),
	Color(0.94, 0.32, 0.20),
	Color(0.32, 0.76, 0.40),
]
const GOLD := Color(0.93, 0.78, 0.28)
const STAR_COUNT := 90
const MOTE_COUNT := 36

## 1.0 on the title screen; lower for a quieter wheel behind the menu pages.
var wheel_strength := 1.0
var _t := 0.0
var _stars: Array = []
var _motes: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in STAR_COUNT:
		_stars.append({
			x = rng.randf(), y = rng.randf(), r = rng.randf_range(0.6, 1.9),
			phase = rng.randf() * TAU, speed = rng.randf_range(0.6, 2.2),
		})
	for i in MOTE_COUNT:
		_motes.append({
			x = rng.randf(), y = rng.randf(), r = rng.randf_range(1.5, 4.0),
			speed = rng.randf_range(0.010, 0.032), sway = rng.randf_range(8.0, 36.0),
			phase = rng.randf() * TAU, color = rng.randi() % 5,
		})


var _since_draw := 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not get_window().has_focus():
		return  ## nothing to animate when hidden or when the window is in the background (T-016)
	_t += delta
	_since_draw += delta
	## Full speed on the title screen, 30 frames a second behind the other menu pages.
	if wheel_strength < 1.0 and _since_draw < 1.0 / 30.0:
		return
	_since_draw = 0.0
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	_draw_sky(s)
	_draw_stars(s)
	_draw_wheel(s)
	_draw_motes(s)
	_draw_vignette(s)


func _draw_sky(s: Vector2) -> void:
	var top := Color(0.025, 0.02, 0.09)
	var bottom := Color(0.12, 0.045, 0.17)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	## A soft violet glow behind the wheel.
	var c := Vector2(s.x * 0.5, s.y * 0.47)
	var reach := minf(s.x, s.y) * 0.75
	for i in 14:
		var k := float(i) / 14.0
		draw_circle(c, reach * (1.0 - k), Color(0.40, 0.24, 0.72, 0.022))


func _draw_stars(s: Vector2) -> void:
	for st in _stars:
		var tw := 0.5 + 0.5 * sin(_t * float(st.speed) + float(st.phase))
		var a := 0.20 + 0.75 * tw
		var p := Vector2(float(st.x) * s.x, float(st.y) * s.y)
		draw_circle(p, float(st.r), Color(0.92, 0.92, 1.0, a))
		if float(st.r) > 1.6:
			draw_circle(p, float(st.r) * 2.6, Color(0.7, 0.7, 1.0, a * 0.12))


func _draw_wheel(s: Vector2) -> void:
	var c := Vector2(s.x * 0.5, s.y * 0.47)
	var radius := minf(s.x, s.y) * 0.43
	var k := wheel_strength
	var rot := _t * 0.05
	var ring := Color(GOLD.r, GOLD.g, GOLD.b, 0.34 * k)
	var faint := Color(GOLD.r, GOLD.g, GOLD.b, 0.16 * k)
	draw_arc(c, radius, 0.0, TAU, 128, ring, 2.0, true)
	draw_arc(c, radius * 1.07, 0.0, TAU, 128, faint, 1.0, true)
	draw_arc(c, radius * 0.62, 0.0, TAU, 96, faint, 1.0, true)
	## Tick marks on the outer ring, turning against the star.
	for i in 72:
		var a := -rot * 0.6 + float(i) * TAU / 72.0
		var d := Vector2(cos(a), sin(a))
		var tick := 0.045 if i % 6 == 0 else 0.022
		draw_line(c + d * radius * 1.07, c + d * radius * (1.07 + tick), faint, 1.0, true)
	## Dashed inner rune ring.
	for i in 40:
		var a0 := rot * 1.4 + float(i) * TAU / 40.0
		draw_arc(c, radius * 0.5, a0, a0 + TAU / 40.0 * 0.45, 6, faint, 2.0, true)
	## The pentacle: each color's neighbor-but-one, so every color faces its two enemies.
	var pts: Array = []
	for i in 5:
		var a := rot + float(i) * TAU / 5.0 - PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	for i in 5:
		draw_line(pts[i], pts[(i + 2) % 5], ring, 1.6, true)
		var edge := Color(MANA[i].r, MANA[i].g, MANA[i].b, 0.20 * k)
		draw_line(pts[i], pts[(i + 1) % 5], edge, 1.2, true)
	for i in 5:
		var m: Color = MANA[i]
		var pulse := 0.5 + 0.5 * sin(_t * 1.3 + float(i) * 1.26)
		var p: Vector2 = pts[i]
		var orb := minf(s.x, s.y) * 0.032
		for g in 5:
			draw_circle(p, orb * (3.0 - float(g) * 0.5), Color(m.r, m.g, m.b, (0.035 + 0.02 * pulse) * k))
		draw_circle(p, orb, Color(m.r * 0.55, m.g * 0.55, m.b * 0.55, 0.95 * k))
		draw_circle(p, orb * 0.72, Color(m.r, m.g, m.b, (0.80 + 0.2 * pulse) * k))
		draw_arc(p, orb, 0.0, TAU, 28, Color(GOLD.r, GOLD.g, GOLD.b, 0.8 * k), 1.5, true)


func _draw_motes(s: Vector2) -> void:
	for m in _motes:
		var y := fposmod(float(m.y) - _t * float(m.speed), 1.0)
		var x := float(m.x) * s.x + sin(_t * 0.7 + float(m.phase)) * float(m.sway)
		var col: Color = MANA[int(m.color)]
		var fade := sin(y * PI)
		var p := Vector2(x, y * s.y)
		draw_circle(p, float(m.r) * 3.2, Color(col.r, col.g, col.b, 0.07 * fade))
		draw_circle(p, float(m.r), Color(col.r, col.g, col.b, 0.55 * fade))


func _draw_vignette(s: Vector2) -> void:
	var dark := Color(0.0, 0.0, 0.02, 0.55)
	var clear := Color(0.0, 0.0, 0.02, 0.0)
	var band := s.y * 0.22
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, band), Vector2(0, band)]),
		PackedColorArray([dark, dark, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, s.y - band), Vector2(s.x, s.y - band), s, Vector2(0, s.y)]),
		PackedColorArray([clear, clear, dark, dark]))
