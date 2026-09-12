extends AudioStreamPlayer

## Distant tavern murmur (inaudible talk) plus occasional table-talk shouts.

const RATE := 22050.0
const SHOUT_DIR := "res://audio/shouts"

var muted := false
var _playback: AudioStreamGeneratorPlayback
var _i := 0
var _rng := RandomNumberGenerator.new()
var _brown := 0.0
var _talker_f0: Array[float] = []
var _talker_f1: Array[float] = []
var _talker_f2: Array[float] = []
var _ph0: Array[float] = []
var _ph1: Array[float] = []
var _ph2: Array[float] = []
var _syl: Array[float] = []
var _syl_rate: Array[float] = []
var _talk_amp: Array[float] = []
var _next_shuffle := 0
var _fx: Array = []
var _shout: AudioStreamPlayer
var _shouts: Array = []
var _next_shout_msec := 0

func _ready() -> void:
	_rng.randomize()
	_setup_talkers()
	_next_shuffle = int(RATE * 3.5)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.5
	stream = gen
	volume_db = -11.0
	play()
	_playback = get_stream_playback()
	_shout = AudioStreamPlayer.new()
	_shout.volume_db = -6.0
	_shout.bus = "Master"
	add_child(_shout)
	call_deferred("_load_shouts")
	_arm_shout()

func _setup_talkers() -> void:
	for t in 6:
		var male := t < 4
		_talker_f0.append(_rng.randf_range(100.0, 140.0) if male else _rng.randf_range(170.0, 205.0))
		_talker_f1.append(_rng.randf_range(450.0, 680.0))
		_talker_f2.append(_rng.randf_range(1000.0, 1350.0))
		_ph0.append(_rng.randf() * TAU)
		_ph1.append(_rng.randf() * TAU)
		_ph2.append(_rng.randf() * TAU)
		_syl.append(_rng.randf() * TAU)
		_syl_rate.append(_rng.randf_range(2.6, 4.2))
		_talk_amp.append(_rng.randf_range(0.022, 0.038))

func _load_shouts() -> void:
	_shouts.clear()
	var dir := DirAccess.open(SHOUT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".wav"):
			var stream: AudioStream = load(SHOUT_DIR.path_join(fname))
			if stream:
				_shouts.append(stream)
		fname = dir.get_next()
	dir.list_dir_end()

func _arm_shout() -> void:
	var wait_ms := int(_rng.randf_range(60.0, 600.0) * 1000.0)
	_next_shout_msec = Time.get_ticks_msec() + wait_ms

func play_random_shout() -> String:
	if muted or _shouts.is_empty() or _shout == null:
		return ""
	var stream: AudioStream = _shouts[_rng.randi_range(0, _shouts.size() - 1)]
	_shout.stream = stream
	_shout.pitch_scale = _rng.randf_range(0.92, 1.08)
	_shout.play()
	return str(stream.resource_path)

func _process(_dt: float) -> void:
	if not muted and _shouts.size() > 0 and Time.get_ticks_msec() >= _next_shout_msec:
		play_random_shout()
		_arm_shout()
	if muted or _playback == null:
		return
	_fill()

func set_muted(on: bool) -> void:
	muted = on
	stream_paused = on
	if _shout and on:
		_shout.stop()

func toggle_mute() -> bool:
	set_muted(not muted)
	return muted

func play_card() -> void:
	_fx.append({"kind": "card", "age": 0.0, "life": 0.14, "amp": 0.11})

func play_draw() -> void:
	_spawn_shuffle(0.12, 0.28)

func play_mug() -> void:
	_fx.append({"kind": "card", "age": 0.0, "life": 0.16, "amp": 0.09})

func play_dice() -> void:
	_fx.append({"kind": "dice", "age": 0.0, "life": 0.42, "amp": 0.22})

func _spawn_shuffle(amp: float, life: float) -> void:
	_fx.append({"kind": "shuffle", "age": 0.0, "life": life, "amp": amp})

func _fill() -> void:
	var avail := mini(_playback.get_frames_available(), 1536)
	for _n in avail:
		if _i >= _next_shuffle:
			_spawn_shuffle(0.035 + _rng.randf() * 0.025, 0.5 + _rng.randf() * 0.4)
			_next_shuffle = _i + int(RATE * (6.0 + _rng.randf() * 9.0))
		var s := _murmur_sample() + _room_sample() + _fx_sample()
		s = clampf(s, -0.7, 0.7)
		_playback.push_frame(Vector2(s * 0.9, s * 1.08))
		_i += 1

func _murmur_sample() -> float:
	var out := 0.0
	var n := _talker_f0.size()
	for t in n:
		_ph0[t] += TAU * _talker_f0[t] / RATE
		_ph1[t] += TAU * _talker_f1[t] / RATE
		_syl[t] += TAU * _syl_rate[t] / RATE
		if _ph0[t] > TAU:
			_ph0[t] -= TAU
		if _ph1[t] > TAU:
			_ph1[t] -= TAU
		if _syl[t] > TAU:
			_syl[t] -= TAU
		var gate := sin(_syl[t])
		if gate <= 0.0:
			continue
		var env := gate * gate
		var voiced := sin(_ph0[t])
		out += _talk_amp[t] * env * (0.65 * voiced + 0.35 * sin(_ph1[t]) * voiced)
	return out

func _room_sample() -> float:
	var white := _rng.randf_range(-1.0, 1.0)
	_brown = clampf(_brown * 0.988 + white * 0.012, -1.0, 1.0)
	return _brown * 0.035

func _fx_sample() -> float:
	var out := 0.0
	var keep: Array = []
	for item in _fx:
		var v: Dictionary = item
		var age := float(v["age"]) + 1.0 / RATE
		var life := float(v["life"])
		if age > life:
			continue
		var kind := str(v["kind"])
		var amp := float(v["amp"])
		var white := _rng.randf_range(-1.0, 1.0)
		var env := 1.0
		var tone := 0.0
		if kind == "shuffle":
			env = sin((age / life) * PI)
			tone = _brown * 0.7 + white * 0.25
		elif kind == "card":
			env = exp(-age * 18.0)
			tone = _brown * 0.5 + white * 0.4
		elif kind == "dice":
			var hits := 0.0
			for k in 6:
				var dt := absf(age - float(k) * 0.045)
				if dt < 0.018:
					hits += (1.0 - dt / 0.018) * white
			env = 1.0
			tone = hits * 0.85 + _brown * 0.25
		out += amp * env * tone
		v["age"] = age
		keep.append(v)
	_fx = keep
	return out
