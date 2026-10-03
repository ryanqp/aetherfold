@tool
class_name SuperPlaymat
extends ColorRect
## Procedural MTG playmat. Attach to any ColorRect (no material needed).
##
##   $PlayerMat.identity = "WG"               # cross-fades with a radial wave
##   $PlayerMat.set_identity("Grixis", false) # instant, no transition
##   $PlayerMat.pulse(Color.RED)              # flash for damage / triggers
##
## Each SuperPlaymat gets its own material copy, so two players can run two
## different identities side by side from the same shader.

signal identity_changed(identity: String, display_name: String)
signal transition_finished(identity: String)

const PLAYMAT_SHADER := preload("super_playmat.gdshader")
const TIME_WRAP := 36000.0 # seconds; keeps float precision healthy in long sessions

## Any identity format: "WU", "uw", "{W}{U}", "Azorius", "white blue", "colorless".
@export var identity: String = "WUBRG":
	get:
		return _identity
	set(value):
		set_identity(value)

@export_range(0.0, 4.0, 0.05, "suffix:s") var transition_duration: float = 1.4
@export_range(0.0, 4.0, 0.05) var animation_speed: float = 1.0
## Freezes the animation (e.g. low-power mode, menus over the board).
@export var paused: bool = false

@export_group("Look")
@export_enum("Low:0", "Medium:1", "High:2") var quality: int = 2:
	set(v):
		quality = v
		_set_param("quality", v)
## Rotate 180° — use on the opponent's half so effects face their side.
@export var flip: bool = false:
	set(v):
		flip = v
		_set_param("flip", v)
## Glow along this mat's top edge (the center line in a split board).
@export_range(0.0, 1.0, 0.01) var seam_glow: float = 0.0:
	set(v):
		seam_glow = v
		_set_param("seam_glow", v)
@export_range(0.0, 1.0, 0.01) var sigil_amount: float = 0.35:
	set(v):
		sigil_amount = v
		_set_param("sigil_amount", v)
@export_range(0.5, 6.0, 0.05) var pattern_scale: float = 2.2:
	set(v):
		pattern_scale = v
		_set_param("pattern_scale", v)
@export_range(0.2, 2.0, 0.01) var brightness: float = 1.0:
	set(v):
		brightness = v
		_set_param("brightness", v)

var _identity := "WUBRG"
var _mat: ShaderMaterial
var _time := 0.0
var _speed := 1.0 # the identity's own tempo (Red is fast, Black is slow); tweened
var _tween: Tween
var _pulse_tween: Tween
var _pending_palette := PackedColorArray()
var _pending_accent := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE # never steal clicks from cards
	_setup_material()
	_push_static_params()
	_apply_identity(_identity, false)
	resized.connect(_on_resized)
	_on_resized()


func _process(delta: float) -> void:
	if _mat == null or paused:
		return
	_time = fmod(_time + delta * animation_speed * _speed, TIME_WRAP)
	_mat.set_shader_parameter("anim_time", _time)


## Change identity. animate=false snaps instantly (use when loading a game).
func set_identity(value: String, animate: bool = true) -> void:
	var key := ManaPalette.normalize(value)
	var changed := key != _identity
	_identity = key
	if _mat == null or not is_node_ready() or not changed:
		return # _ready() applies it
	_apply_identity(key, animate and not Engine.is_editor_hint())
	identity_changed.emit(key, ManaPalette.get_display_name(key))


func get_display_name() -> String:
	return ManaPalette.get_display_name(_identity)


## Brief full-mat flash — life loss, a big trigger, your turn starting.
func pulse(color: Color = Color(1.0, 0.25, 0.2), strength: float = 1.0, duration: float = 0.7) -> void:
	if _mat == null:
		return
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_mat.set_shader_parameter("pulse_color", color)
	_pulse_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_mat, "shader_parameter/pulse_amount", 0.0, duration) \
		.from(clampf(strength, 0.0, 1.0))


# ------------------------------------------------------------ internals ----

func _setup_material() -> void:
	var sm := material as ShaderMaterial
	if sm and sm.shader == PLAYMAT_SHADER:
		if not Engine.is_editor_hint():
			material = sm.duplicate() # independent uniforms per playmat
	else:
		sm = ShaderMaterial.new()
		sm.shader = PLAYMAT_SHADER
		material = sm
	_mat = material as ShaderMaterial


func _push_static_params() -> void:
	_set_param("quality", quality)
	_set_param("flip", flip)
	_set_param("seam_glow", seam_glow)
	_set_param("sigil_amount", sigil_amount)
	_set_param("pattern_scale", pattern_scale)
	_set_param("brightness", brightness)
	_set_param("pulse_amount", 0.0)
	_set_param("anim_time", _time)


func _apply_identity(key: String, animate: bool) -> void:
	var pal := ManaPalette.build_palette(key)
	var accent := ManaPalette.build_accent(key)
	var style := ManaPalette.build_style(key)

	if _tween and _tween.is_valid():
		_tween.kill()
		_commit_pending() # snap a half-finished transition to its target first

	if not animate or transition_duration <= 0.0:
		_mat.set_shader_parameter("palette_a", pal)
		_mat.set_shader_parameter("accent_a", accent)
		_mat.set_shader_parameter("palette_b", pal)
		_mat.set_shader_parameter("accent_b", accent)
		_mat.set_shader_parameter("transition", 0.0)
		for k in ManaPalette.LAYER_KEYS:
			_mat.set_shader_parameter(k, style[k])
		_speed = style["speed"]
		_pending_palette = PackedColorArray()
		return

	_pending_palette = pal
	_pending_accent = accent
	_mat.set_shader_parameter("palette_b", pal)
	_mat.set_shader_parameter("accent_b", accent)
	_mat.set_shader_parameter("transition", 0.0)

	_tween = create_tween().set_parallel(true) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_mat, "shader_parameter/transition", 1.0, transition_duration)
	for k in ManaPalette.LAYER_KEYS:
		_tween.tween_property(_mat, "shader_parameter/" + k, style[k], transition_duration)
	_tween.tween_property(self, "_speed", style["speed"], transition_duration)
	_tween.chain().tween_callback(_on_transition_done.bind(key))


func _commit_pending() -> void:
	if _pending_palette.is_empty():
		return
	_mat.set_shader_parameter("palette_a", _pending_palette)
	_mat.set_shader_parameter("accent_a", _pending_accent)
	_mat.set_shader_parameter("transition", 0.0)
	_pending_palette = PackedColorArray()


func _on_transition_done(key: String) -> void:
	_commit_pending()
	_tween = null
	transition_finished.emit(key)


func _on_resized() -> void:
	_set_param("rect_size", size)


func _set_param(param: String, value: Variant) -> void:
	if _mat:
		_mat.set_shader_parameter(param, value)
