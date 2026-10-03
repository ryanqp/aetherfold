extends RefCounted

## The look of the match's panels and pick screens (coin flip, mulligan, pick lists, menu, game over, audio panel,
## context menus): dark green-black panels with a thin gold rim, charcoal buttons that light up gold, green
## primary actions. Set once as the table's theme, so every control without its own style follows it.

const BG := Color(0.035, 0.065, 0.06, 0.97)
const BG_SOFT := Color(0.07, 0.11, 0.10, 0.97)
const RIM := Color(0.66, 0.54, 0.24)
const RIM_DIM := Color(0.40, 0.33, 0.16)
const GOLD := Color(0.93, 0.78, 0.28)
const INK := Color(0.93, 0.93, 0.90)
const MUTED := Color(0.72, 0.74, 0.70)
const GREEN := Color(0.20, 0.42, 0.18)


static func box(bg: Color, border: Color, width: int = 2, radius: int = 8) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(width)
	st.set_corner_radius_all(radius)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	return st


static func make_theme() -> Theme:
	var t := Theme.new()
	## Panels (pick screens, overlays, popups).
	var panel := box(BG, RIM, 2, 10)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 10
	t.set_stylebox("panel", "PanelContainer", panel)
	## Buttons: charcoal, gold rim on hover, darker when pressed.
	var normal := box(Color(0.11, 0.15, 0.14), RIM_DIM, 1, 6)
	var hover := box(Color(0.16, 0.22, 0.20), GOLD, 2, 6)
	hover.shadow_color = Color(0.93, 0.78, 0.28, 0.25)
	hover.shadow_size = 6
	var pressed := box(Color(0.07, 0.10, 0.09), GOLD, 2, 6)
	var disabled := box(Color(0.08, 0.10, 0.10), Color(0.2, 0.2, 0.18), 1, 6)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 0.97, 0.85))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.48))
	## Labels, check boxes, sliders, text fields, context menus.
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "CheckBox", INK)
	t.set_stylebox("normal", "LineEdit", box(Color(0.05, 0.08, 0.08), RIM_DIM, 1, 5))
	t.set_stylebox("focus", "LineEdit", box(Color(0.05, 0.08, 0.08), GOLD, 1, 5))
	t.set_color("font_color", "LineEdit", INK)
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.16, 0.20, 0.19)
	rail.set_corner_radius_all(3)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	var fill := rail.duplicate() as StyleBoxFlat
	fill.bg_color = GOLD.darkened(0.15)
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var menu := box(BG, RIM, 1, 6)
	t.set_stylebox("panel", "PopupMenu", menu)
	t.set_stylebox("hover", "PopupMenu", box(Color(0.20, 0.27, 0.24), Color(0, 0, 0, 0), 0, 4))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.97, 0.85))
	t.set_color("font_disabled_color", "PopupMenu", Color(0.5, 0.5, 0.48))
	return t


## A green call-to-action button style (the "Draw card" look): use on top of the theme for the main choice.
static func primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(GREEN, Color(0.45, 0.75, 0.40), 1, 6))
	b.add_theme_stylebox_override("hover", box(GREEN.lightened(0.15), GOLD, 2, 6))
	b.add_theme_stylebox_override("pressed", box(GREEN.darkened(0.15), GOLD, 2, 6))
	b.add_theme_color_override("font_color", Color(0.95, 1.0, 0.92))
