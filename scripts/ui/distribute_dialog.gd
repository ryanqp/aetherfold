class_name DistributeDialog
extends Control

## A pick screen for dividing a number of points among several things: combat damage among blockers (and the player, with
## trample), or "3 damage divided as you choose among up to three targets". Each row has - / + buttons; "Lethal" fills in
## the damage that kills a creature. The split can be confirmed once every point is placed (and no more targets are used
## than allowed). Emits `confirmed({id: amount})`, or `automatic` to let the game split it.

signal confirmed(split: Dictionary)
signal automatic

const GOLD := Color(0.96, 0.82, 0.35)
const INK := Color(0.93, 0.91, 0.86)
const MUTED := Color(0.66, 0.66, 0.62)
const BAD := Color(0.95, 0.45, 0.35)

var signature := ""
var _total := 0
var _max_targets := 0
var _amounts: Dictionary = {}  ## id -> amount
var _count_labels: Dictionary = {}
var _left_label: Label
var _confirm: Button
var _options: Array = []


## `options`: [{value: id, label, detail, lethal, player}]. `start` is the split shown at first ({id: amount}).
func show_split(title: String, sub: String, total: int, options: Array, max_targets: int, start: Dictionary, auto_text: String = "Split it for me") -> void:
	for ch in get_children():
		ch.queue_free()
	_total = total
	_max_targets = max_targets
	_options = options
	_amounts.clear()
	_count_labels.clear()
	for o in options:
		_amounts[int((o as Dictionary).value)] = 0
	for k in start.keys():
		if _amounts.has(int(str(k))):
			_amounts[int(str(k))] = int(start[k])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.035, 0.065, 0.06, 0.97)
	st.border_color = GOLD
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var t := Label.new()
	t.text = title
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", GOLD)
	col.add_child(t)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_color_override("font_color", MUTED)
		col.add_child(s)
	_left_label = Label.new()
	_left_label.add_theme_font_size_override("font_size", 18)
	col.add_child(_left_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(40 + options.size() * 56, 380))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for o in options:
		list.add_child(_row(o as Dictionary))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var auto_btn := Button.new()
	auto_btn.text = auto_text
	auto_btn.custom_minimum_size = Vector2(0, 40)
	auto_btn.pressed.connect(func() -> void: automatic.emit())
	buttons.add_child(auto_btn)
	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.custom_minimum_size = Vector2(0, 40)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)
	col.add_child(buttons)
	_refresh()


func _row(o: Dictionary) -> Control:
	var id := int(o.value)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := Label.new()
	nm.text = str(o.get("label", ""))
	nm.add_theme_color_override("font_color", INK)
	names.add_child(nm)
	var detail := str(o.get("detail", ""))
	if detail != "":
		var d := Label.new()
		d.text = detail
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", MUTED)
		names.add_child(d)
	box.add_child(names)
	var lethal := int(o.get("lethal", 0))
	if lethal > 0:
		var lb := Button.new()
		lb.text = "Lethal (%d)" % lethal
		lb.tooltip_text = "Put exactly enough here to kill it"
		lb.pressed.connect(func() -> void: _set_amount(id, lethal))
		box.add_child(lb)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(38, 34)
	minus.pressed.connect(func() -> void: _set_amount(id, int(_amounts[id]) - 1))
	box.add_child(minus)
	var count := Label.new()
	count.custom_minimum_size = Vector2(34, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 20)
	_count_labels[id] = count
	box.add_child(count)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(38, 34)
	plus.pressed.connect(func() -> void: _set_amount(id, int(_amounts[id]) + 1))
	box.add_child(plus)
	return box


func _placed() -> int:
	var n := 0
	for k in _amounts.keys():
		n += int(_amounts[k])
	return n


func _targets_used() -> int:
	var n := 0
	for k in _amounts.keys():
		if int(_amounts[k]) > 0:
			n += 1
	return n


func _set_amount(id: int, value: int) -> void:
	var room := _total - (_placed() - int(_amounts[id]))
	_amounts[id] = clampi(value, 0, maxi(0, room))
	_refresh()


func _refresh() -> void:
	for k in _count_labels.keys():
		(_count_labels[k] as Label).text = str(int(_amounts[k]))
	var left := _total - _placed()
	var too_many := _max_targets > 0 and _targets_used() > _max_targets
	if too_many:
		_left_label.text = "Left to place: %d — at most %d targets" % [left, _max_targets]
		_left_label.add_theme_color_override("font_color", BAD)
	else:
		_left_label.text = "Left to place: %d of %d" % [left, _total]
		_left_label.add_theme_color_override("font_color", GOLD if left > 0 else INK)
	_confirm.disabled = left != 0 or too_many


func _on_confirm() -> void:
	var out := {}
	for k in _amounts.keys():
		if int(_amounts[k]) > 0:
			out[int(k)] = int(_amounts[k])
	confirmed.emit(out)
