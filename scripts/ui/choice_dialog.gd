class_name ChoiceDialog
extends Control

## A centered pick screen over the table: a title, an optional subtitle and a list of options, each with a
## name and a line of detail. Used for targets, hideaway, discard, colors, creature types and yes/no
## questions. Emits `picked(value)` for an option and `cancelled` for the optional last button.

signal picked(value)
signal cancelled
## Pointer moved over (or off) an option that stands for a card; `card` is the card dictionary the table can draw.
signal option_hovered(card)
signal option_unhovered

const GOLD := Color(0.96, 0.82, 0.35)
const INK := Color(0.93, 0.91, 0.86)
const MUTED := Color(0.66, 0.66, 0.62)

var signature := ""


## `faces` are ready-made card pictures (Controls) shown across the top, for questions about specific cards.
func show_choices(title: String, sub: String, options: Array, cancel_text: String = "", faces: Array = []) -> void:
	for ch in get_children():
		ch.queue_free()
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
	st.bg_color = Color(0.09, 0.10, 0.11, 0.98)
	st.border_color = GOLD
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(520, 0)
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
	if not faces.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		for f in faces:
			row.add_child(f as Control)
		col.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(60 + options.size() * 58, 420))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for o in options:
		list.add_child(_option_button(o))
	if cancel_text != "":
		var c := Button.new()
		c.text = cancel_text
		c.custom_minimum_size = Vector2(0, 38)
		c.pressed.connect(func() -> void: cancelled.emit())
		col.add_child(c)


func _option_button(o: Dictionary) -> Button:
	var b := Button.new()
	var detail := str(o.get("detail", ""))
	b.text = str(o.get("label", "")) if detail == "" else "%s\n%s" % [str(o.get("label", "")), detail]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 52 if detail != "" else 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := StyleBoxFlat.new()
	var mine := bool(o.get("mine", true))
	n.bg_color = Color(0.17, 0.19, 0.2) if mine else Color(0.24, 0.15, 0.14)
	n.set_corner_radius_all(6)
	n.content_margin_left = 12
	n.content_margin_right = 12
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = n.bg_color.lightened(0.18)
	h.border_color = GOLD
	h.set_border_width_all(2)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_color_override("font_color", INK)
	var card: Variant = o.get("card")
	if card is Dictionary and not (card as Dictionary).is_empty():
		b.mouse_entered.connect(func() -> void: option_hovered.emit(card))
		b.mouse_exited.connect(func() -> void: option_unhovered.emit())
	var v: Variant = o.get("value")
	b.pressed.connect(func() -> void: picked.emit(v))
	return b
