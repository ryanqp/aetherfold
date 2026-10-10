extends Control
## Gallery of all 32 Living Battlefield scenes. Open scenes/battlefield_demo.tscn and press F6.
##
##   Click a scene      view it full screen          Esc / G   back to the gallery
##   ← / →              previous / next identity (morphs)
##   Space              damage pulse                 O         orientation (normal / mirrored / rotated)
##   L                  liveliness 0.5 / 1 / 1.5     P         pause

const LB := preload("res://scripts/playmat/living_battlefield.gd")
const COLS := 6

var _ids := ManaPalette.all_identities()
var _grid: GridContainer
var _big: LivingBattlefield
var _hud: Label
var _index := 0
var _tiles: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	margin.add_child(_grid)

	for i in _ids.size():
		var tile: LivingBattlefield = LB.new()
		tile.size_flags_horizontal = SIZE_EXPAND_FILL
		tile.size_flags_vertical = SIZE_EXPAND_FILL
		tile.identity = _ids[i]
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		_grid.add_child(tile)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP # (the script sets IGNORE in _ready)
		tile.gui_input.connect(_on_tile_input.bind(i))
		var lab := Label.new()
		lab.text = "%s  ·  %s" % [ManaPalette.get_display_name(_ids[i]), BattlefieldScenes.scene_note(_ids[i])]
		lab.position = Vector2(8, 4)
		lab.add_theme_font_size_override("font_size", 13)
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 5)
		tile.add_child(lab)
		_tiles.append(tile)

	_big = LB.new()
	_big.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_big.visible = false
	_big.paused = true
	add_child(_big)

	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 6)
	add_child(_hud)
	_update_hud()


func _process(_d: float) -> void:
	_update_hud()


func show_full(i: int, animate: bool = false) -> void:
	_index = wrapi(i, 0, _ids.size())
	_big.set_identity(_ids[_index], animate)
	_big.visible = true
	_big.paused = false
	_grid.get_parent().visible = false
	for t in _tiles:
		t.paused = true


func show_gallery() -> void:
	_big.visible = false
	_big.paused = true
	_grid.get_parent().visible = true
	for t in _tiles:
		t.paused = false


func _on_tile_input(event: InputEvent, i: int) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		show_full(i)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE, KEY_G:
			show_gallery()
		KEY_RIGHT:
			show_full(_index + 1, _big.visible)
		KEY_LEFT:
			show_full(_index - 1, _big.visible)
		KEY_SPACE:
			_big.pulse(Color(1.0, 0.2, 0.15))
		KEY_O:
			_big.orient = (_big.orient + 1) % 3
		KEY_P:
			_big.paused = not _big.paused
		KEY_L:
			_big.liveliness = 0.5 if _big.liveliness > 1.2 else _big.liveliness + 0.5


func _update_hud() -> void:
	if _big.visible:
		_hud.text = "%s · %s   (%s)\n←→ next scene   Space pulse   O orientation   L liveliness %.1f   P pause   Esc gallery   [%d FPS]" % [
			ManaPalette.get_display_name(_ids[_index]), _letters(_ids[_index]), BattlefieldScenes.scene_note(_ids[_index]),
			_big.liveliness, Engine.get_frames_per_second()]
	else:
		_hud.text = ""


static func _letters(key: String) -> String:
	if key == "C":
		return "Colorless"
	var names := {"W": "White", "U": "Blue", "B": "Black", "R": "Red", "G": "Green"}
	var parts := PackedStringArray()
	for ch in key:
		parts.append(names[ch])
	return " + ".join(parts)
