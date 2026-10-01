extends AudioStreamPlayer

## Tavern ambience: a soft crowd murmur (voices rising and falling, no words), a low fire crackle, a glass
## clink at random (no sooner than 45 seconds, no later than 6 minutes apart) and occasional table-talk shouts.

const RATE := 22050.0
const SHOUT_DIR := "res://audio/shouts"
const CLINK_MIN_SEC := 45.0
const CLINK_MAX_SEC := 360.0
## Vowel-ish formant pairs (F1, F2) the talkers drift between.
const VOWELS := [[730.0, 1090.0], [530.0, 1840.0], [400.0, 2000.0], [570.0, 840.0], [450.0, 1100.0], [650.0, 1500.0]]

var muted := false
var _playback: AudioStreamGeneratorPlayback
var _i := 0
var _rng := RandomNumberGenerator.new()
var _brown := 0.0
var _talkers: Array = []
var _next_clink_msec := 0
var _pop := 0.0
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
	_arm_clink()

func _setup_talkers() -> void:
	_talkers.clear()
	for t in 4:
		var male := t < 3
		var f0 := _rng.randf_range(95.0, 135.0) if male else _rng.randf_range(165.0, 215.0)
		_talkers.append({
			"f0": f0, "phase": 0.0,
			"amp": _rng.randf_range(0.5, 1.0),
			"talking": _rng.randf() < 0.5,
			"switch": int(_rng.randf_range(0.5, 3.0) * RATE),
			"syl": 0.0, "syl_rate": _rng.randf_range(3.0, 5.0),
			"env": 0.0, "wob": _rng.randf() * TAU,
			"y1a": 0.0, "y2a": 0.0, "y1b": 0.0, "y2b": 0.0,
			"ca1": 0.0, "ca2": 0.0, "cb1": 0.0, "cb2": 0.0, "ga": 0.0, "gb": 0.0,
		})
		_new_vowel(_talkers[t])

## Two-pole resonators for the talker's current vowel.
func _new_vowel(t: Dictionary) -> void:
	var v: Array = VOWELS[_rng.randi_range(0, VOWELS.size() - 1)]
	var shift := _rng.randf_range(0.9, 1.12)
	var fa := float(v[0]) * shift
	var fb := float(v[1]) * shift
	var ra := exp(-PI * 90.0 / RATE)
	var rb := exp(-PI * 130.0 / RATE)
	t["ca1"] = 2.0 * ra * cos(TAU * fa / RATE)
	t["ca2"] = -ra * ra
	t["cb1"] = 2.0 * rb * cos(TAU * fb / RATE)
	t["cb2"] = -rb * rb
	t["ga"] = 1.0 - ra
	t["gb"] = (1.0 - rb) * 0.7

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

func _arm_clink() -> void:
	var wait_ms := int(_rng.randf_range(CLINK_MIN_SEC, CLINK_MAX_SEC) * 1000.0)
	_next_clink_msec = Time.get_ticks_msec() + wait_ms


## A glass touching another: a few bright, inharmonic partials that ring out; sometimes twice.
func play_clink() -> void:
	var base := _rng.randf_range(1500.0, 2100.0)
	_fx.append({"kind": "glass", "age": 0.0, "life": 1.3, "amp": 0.16, "f": base})
	if _rng.randf() < 0.4:
		_fx.append({"kind": "glass", "age": -0.11, "life": 1.3, "amp": 0.1, "f": base * _rng.randf_range(1.05, 1.18)})


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
	if Time.get_ticks_msec() >= _next_clink_msec:
		if not muted:
			play_clink()
		_arm_clink()
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


func play_hit() -> void:
	_fx.append({"kind": "hit", "age": 0.0, "life": 0.22, "amp": 0.28})

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
	for item in _talkers:
		var t: Dictionary = item
		t["switch"] = int(t["switch"]) - 1
		if int(t["switch"]) <= 0:
			t["talking"] = not bool(t["talking"])
			t["switch"] = int(_rng.randf_range(0.4, 2.2) * RATE) if bool(t["talking"]) else int(_rng.randf_range(1.0, 5.0) * RATE)
		var goal := 1.0 if bool(t["talking"]) else 0.0
		t["env"] = float(t["env"]) + (goal - float(t["env"])) * 0.0006
		if float(t["env"]) < 0.01:
			continue
		# Syllables: a new vowel each time the beat comes round.
		var syl := float(t["syl"]) + TAU * float(t["syl_rate"]) / RATE
		if syl > TAU:
			syl -= TAU
			_new_vowel(t)
			t["syl_rate"] = _rng.randf_range(3.0, 5.0)
		t["syl"] = syl
		var gate := 0.5 + 0.5 * sin(syl)
		gate = gate * gate
		# A pulse train with a little drift in pitch, then shaped by two resonances.
		t["wob"] = float(t["wob"]) + TAU * 0.7 / RATE
		var f0 := float(t["f0"]) * (1.0 + 0.06 * sin(float(t["wob"])))
		var ph := float(t["phase"]) + f0 / RATE
		if ph > 1.0:
			ph -= 1.0
		t["phase"] = ph
		var src := (ph * 2.0 - 1.0) + 0.25 * _rng.randf_range(-1.0, 1.0)
		var ya := float(t["ga"]) * src + float(t["ca1"]) * float(t["y1a"]) + float(t["ca2"]) * float(t["y2a"])
		t["y2a"] = t["y1a"]
		t["y1a"] = ya
		var yb := float(t["gb"]) * src + float(t["cb1"]) * float(t["y1b"]) + float(t["cb2"]) * float(t["y2b"])
		t["y2b"] = t["y1b"]
		t["y1b"] = yb
		out += (ya + yb) * gate * float(t["env"]) * float(t["amp"]) * 0.5
	return out * 0.55

func _room_sample() -> float:
	var white := _rng.randf_range(-1.0, 1.0)
	_brown = clampf(_brown * 0.988 + white * 0.012, -1.0, 1.0)
	# A low fire: now and then a tiny pop.
	if _pop <= 0.0 and _rng.randf() < 0.00012:
		_pop = _rng.randf_range(0.2, 0.7)
	var crackle := 0.0
	if _pop > 0.0:
		crackle = white * _pop * 0.05
		_pop *= 0.985
		if _pop < 0.01:
			_pop = 0.0
	return _brown * 0.035 + crackle

func _fx_sample() -> float:
	var out := 0.0
	var keep: Array = []
	for item in _fx:
		var v: Dictionary = item
		var age := float(v["age"]) + 1.0 / RATE
		var life := float(v["life"])
		if age > life:
			continue
		if age < 0.0:
			v["age"] = age
			keep.append(v)
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
		elif kind == "hit":
			env = exp(-age * 10.0)
			tone = sin(age * 180.0) * 0.7 + _brown * 0.8
		elif kind == "glass":
			var f := float(v["f"])
			var ringing := 0.0
			var ratios := [1.0, 2.32, 3.7, 4.9]
			var decays := [5.0, 7.5, 11.0, 16.0]
			var gains := [1.0, 0.55, 0.3, 0.15]
			for k in 4:
				ringing += float(gains[k]) * sin(TAU * f * float(ratios[k]) * age) * exp(-age * float(decays[k]))
			env = clampf(age / 0.002, 0.0, 1.0)
			tone = ringing
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
