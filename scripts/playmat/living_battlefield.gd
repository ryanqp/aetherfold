@tool
class_name LivingBattlefield
extends ColorRect
## Animated painted playmat: the painting for a color identity, brought to life
## (water ripples, lava glow, swaying leaves, drifting clouds, fog, embers, snow…).
## Attach to any ColorRect (no material needed).
##
##   $Mat.identity = "UBR"                 # dissolves into the Grixis painting
##   $Mat.set_identity("Selesnya", false)  # instant
##   $Mat.pulse(Color.RED)                 # flash for damage / triggers
##
## Paintings: <art_dir>/<Colors>.jpg, e.g. "White-Blue.jpg" (see BattlefieldScenes.file_for).
## Effects per identity: battlefield_scenes.gd. Effect areas are detected from the painting (art_masks.gd).

signal identity_changed(identity: String, display_name: String)
signal transition_finished(identity: String)

const SHADER := preload("living_battlefield.gdshader")
const TIME_WRAP := 36000.0

## Any identity format: "WU", "uw", "{W}{U}", "Azorius", "white blue", "colorless".
@export var identity: String = "WUBRG":
	get:
		return _identity
	set(value):
		set_identity(value)

## Folder with the 32 paintings. Swap in another set (same file names) to change the art.
@export_dir var art_dir: String = "res://assets/playmats":
	set(v):
		art_dir = v
		if is_node_ready():
			_apply_identity(_identity, false)
@export_range(0.0, 5.0, 0.05, "suffix:s") var transition_duration: float = 1.8
@export_range(0.0, 4.0, 0.05) var animation_speed: float = 1.0
@export var paused: bool = false

@export_group("Framing")
## 0 = stretch the whole painting to fit, 1 = cover (crop the edges, no distortion).
@export_range(0.0, 1.0, 0.01) var fit: float = 1.0:
	set(v):
		fit = v
		_set_param("fit", v)
## Part of the painting kept in view when cropping (0..1 each).
@export var focus: Vector2 = Vector2(0.5, 0.5):
	set(v):
		focus = v
		_set_param("focus", v)
## 0 = as painted, 1 = mirrored, 2 = rotated 180° (the rival's side of a top-down mat).
@export_enum("Normal:0", "Mirrored:1", "Rotated 180:2") var orient: int = 0:
	set(v):
		orient = v
		_set_param("orient", v)
## Slow camera breathing (zoom/pan). 0 = still.
@export_range(0.0, 1.0, 0.01) var drift: float = 0.35:
	set(v):
		drift = v
		_set_param("drift", v)
@export_range(0.2, 2.0, 0.01) var brightness: float = 1.0:
	set(v):
		brightness = v
		_set_param("brightness", v)
## Scales every effect (0 = the still painting, 1 = as designed, 1.5 = livelier).
@export_range(0.0, 1.5, 0.01) var liveliness: float = 1.0:
	set(v):
		liveliness = v
		if is_node_ready() and not _cur.is_empty():
			_push(_cur)

const SCALED := ["water_amount", "hot_amount", "heat_haze", "foliage_amount", "sky_amount", "cloud_shadow",
	"fog_amount", "rays_amount", "lightning", "breath", "p1_amount", "p2_amount"]

var _identity := "WUBRG"
var _mat: ShaderMaterial
var _time := 0.0
var _cur := {}
var _from := {}
var _to := {}
var _tween: Tween
var _pulse_tween: Tween
var _art := {}   # file -> Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := material as ShaderMaterial
	if sm and sm.shader == SHADER:
		if not Engine.is_editor_hint():
			material = sm.duplicate()
	else:
		sm = ShaderMaterial.new()
		sm.shader = SHADER
		material = sm
	_mat = material as ShaderMaterial
	for p in ["fit", "focus", "orient", "drift", "brightness"]:
		_set_param(p, get(p))
	_set_param("pulse_amount", 0.0)
	_set_param("dissolve", 0.0)
	_apply_identity(_identity, false)
	resized.connect(_on_resized)
	_on_resized()


func _process(delta: float) -> void:
	if _mat == null or paused:
		return
	_time = fmod(_time + delta * animation_speed, TIME_WRAP)
	_mat.set_shader_parameter("anim_time", _time)


## Change identity. animate=false snaps (use when a game loads).
func set_identity(value: String, animate: bool = true) -> void:
	var key := ManaPalette.normalize(value)
	var changed := key != _identity
	_identity = key
	if _mat == null or not is_node_ready() or not changed:
		return
	_apply_identity(key, animate and not Engine.is_editor_hint())
	identity_changed.emit(key, ManaPalette.get_display_name(key))


func get_display_name() -> String:
	return ManaPalette.get_display_name(_identity)


## Brief flash over the whole mat — life loss, a big trigger, your turn starting.
func pulse(color: Color = Color(1.0, 0.25, 0.2), strength: float = 1.0, duration: float = 0.7) -> void:
	if _mat == null:
		return
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_mat.set_shader_parameter("pulse_color", color)
	_pulse_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_mat, "shader_parameter/pulse_amount", 0.0, duration).from(clampf(strength, 0.0, 1.0))


## The painting for an identity (cached). Uses the imported resource, or reads the file directly.
func art_for(identity_key: String) -> Texture2D:
	var file := BattlefieldScenes.file_for(identity_key)
	var path := "%s/%s" % [art_dir, file]
	if _art.has(path):
		return _art[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_art[path] = tex
	return tex


# ------------------------------------------------------------ internals ----

func _apply_identity(key: String, animate: bool) -> void:
	var tex := art_for(key)
	var mask: Texture2D = ArtMasks.for_texture(tex, "%s/%s" % [art_dir, BattlefieldScenes.file_for(key)])
	var aspect := 1.5
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var target := BattlefieldScenes.build(key)

	if _tween and _tween.is_valid():
		# Interrupted mid-dissolve: finish the old one instantly, then start fresh.
		_tween.kill()
		_commit_b()

	if not animate or _cur.is_empty() or transition_duration <= 0.0:
		_set_param("art_a", tex)
		_set_param("mask_a", mask)
		_set_param("aspect_a", aspect)
		_set_param("dissolve", 0.0)
		_cur = target
		_push(_cur)
		return

	_set_param("art_b", tex)
	_set_param("mask_b", mask)
	_set_param("aspect_b", aspect)
	_set_param("dissolve_color", target["dissolve_color"])
	_from = _cur.duplicate()
	_to = target
	_tween = create_tween()
	_tween.tween_method(_blend, 0.0, 1.0, transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_on_transition_done.bind(key))


func _blend(w: float) -> void:
	for k in _to:
		_cur[k] = lerp(_from[k], _to[k], w)
	_push(_cur)
	_set_param("dissolve", w)


func _push(values: Dictionary) -> void:
	for k in values:
		var v = values[k]
		if k in SCALED:
			v = float(v) * liveliness
		_set_param(k, v)


func _commit_b() -> void:
	for p in ["art", "mask", "aspect"]:
		_set_param(p + "_a", _mat.get_shader_parameter(p + "_b"))
	_set_param("dissolve", 0.0)
	if not _to.is_empty():
		_cur = _to.duplicate()
		_push(_cur)


func _on_transition_done(key: String) -> void:
	_commit_b()
	_tween = null
	transition_finished.emit(key)


func _on_resized() -> void:
	_set_param("rect_size", size)


func _set_param(param: String, value: Variant) -> void:
	if _mat:
		_mat.set_shader_parameter(param, value)
