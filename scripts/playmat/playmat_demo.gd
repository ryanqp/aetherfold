extends Control
## Test bench for the Super Playmat. Open scenes/playmat_demo.tscn and press F6.
##
##   ← / →   cycle YOUR identity (bottom)        ↑ / ↓   cycle OPPONENT (top)
##   R       random duel                         Space   damage pulse on you
##   Q       cycle quality (Low/Med/High)        P       pause animation
##   S       toggle split board / single mat

@onready var opponent: SuperPlaymat = $Playmats/OpponentMat
@onready var player: SuperPlaymat = $Playmats/PlayerMat
@onready var hud: Label = $HUD

var _ids := ManaPalette.all_identities()
var _p := 0
var _o := 0


func _ready() -> void:
	_p = maxi(_ids.find(player.identity), 0)
	_o = maxi(_ids.find(opponent.identity), 0)
	_update_hud()


func _process(_delta: float) -> void:
	# FPS in the HUD so you can judge cost per quality level.
	hud.text = hud.text.get_slice("\n[", 0) + "\n[%d FPS]" % Engine.get_frames_per_second()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_RIGHT: _step_player(1)
		KEY_LEFT: _step_player(-1)
		KEY_UP: _step_opponent(1)
		KEY_DOWN: _step_opponent(-1)
		KEY_R:
			_p = randi() % _ids.size()
			_o = randi() % _ids.size()
			player.identity = _ids[_p]
			opponent.identity = _ids[_o]
		KEY_SPACE:
			player.pulse(Color(1.0, 0.2, 0.15), 1.0, 0.8)
		KEY_Q:
			var qv := (player.quality + 1) % 3
			player.quality = qv
			opponent.quality = qv
		KEY_P:
			player.paused = not player.paused
			opponent.paused = player.paused
		KEY_S:
			opponent.visible = not opponent.visible
			player.seam_glow = 0.6 if opponent.visible else 0.0
	_update_hud()


func _step_player(dir: int) -> void:
	_p = wrapi(_p + dir, 0, _ids.size())
	player.identity = _ids[_p]


func _step_opponent(dir: int) -> void:
	_o = wrapi(_o + dir, 0, _ids.size())
	opponent.identity = _ids[_o]


func _update_hud() -> void:
	var q: String = ["Low", "Medium", "High"][player.quality]
	hud.text = "OPPONENT  %s · %s (%s)\nYOU       %s · %s (%s)\nQuality %s%s   ←→ you  ↑↓ opponent  R random  Space pulse  Q quality  P pause  S split\n[" % [
		ManaPalette.get_group(opponent.identity), opponent.get_display_name(), opponent.identity,
		ManaPalette.get_group(player.identity), player.get_display_name(), player.identity,
		q, "  (paused)" if player.paused else "",
	]
