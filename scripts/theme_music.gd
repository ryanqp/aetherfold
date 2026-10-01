extends AudioStreamPlayer

## Upbeat acoustic instrumental, mixed in code so the project stays small: fingerpicked guitar (plucked
## string model), a warm acoustic bass, a cajon-style kick and rim, a shaker and a whistle-like lead.
## G - D - Em - C - G - D - C - D, 112 BPM, eight bars then round again.

const RATE := 22050.0
const BPM := 112.0

var muted := false
var _playback: AudioStreamGeneratorPlayback
var _i := 0
var _rng := RandomNumberGenerator.new()
var _plucks: Array = []
var _drums: Array = []
var _lead_freq := 0.0
var _lead_phase := 0.0
var _lead_age := 0.0
var _lead_dur := 0.0
var _lead_on := false
var _breath := 0.0

## Guitar voicings per bar (MIDI): low root first, then up the chord.
const CHORDS := [
	[43, 50, 55, 59, 62, 67],  # G
	[50, 57, 62, 66, 69, 74],  # D
	[40, 47, 52, 55, 59, 64],  # Em
	[48, 52, 55, 60, 64, 67],  # C
	[43, 50, 55, 59, 62, 67],  # G
	[50, 57, 62, 66, 69, 74],  # D
	[48, 52, 55, 60, 64, 67],  # C
	[50, 57, 62, 66, 69, 74],  # D
]
const BASS := [43, 38, 40, 36, 43, 38, 36, 38]
## Which chord note each eighth picks.
const PICK := [0, 2, 3, 4, 3, 2, 4, 3]
## Lead melody per bar: [eighth step, MIDI note, length in eighths].
const LEAD := [
	[[0, 74, 2], [3, 71, 1], [4, 74, 3]],
	[[0, 69, 2], [2, 74, 2], [4, 78, 2], [6, 74, 2]],
	[[0, 76, 2], [2, 71, 2], [4, 67, 3]],
	[[0, 72, 2], [2, 76, 2], [4, 79, 4]],
	[[0, 74, 1], [1, 76, 1], [2, 79, 3], [5, 74, 1], [6, 71, 2]],
	[[0, 78, 2], [2, 74, 2], [4, 69, 2], [6, 74, 2]],
	[[0, 76, 2], [2, 72, 2], [4, 67, 2], [6, 72, 2]],
	[[0, 74, 3], [4, 69, 4]],
]


class Pluck extends RefCounted:
	var buf := PackedFloat32Array()
	var pos := 0
	var amp := 0.2
	var decay := 0.997
	var delay := 0
	var age := 0


func _ready() -> void:
	_rng.randomize()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.5
	stream = gen
	volume_db = -9.0
	play()
	_playback = get_stream_playback()


func _process(_dt: float) -> void:
	if muted or _playback == null:
		return
	_fill()


func set_muted(on: bool) -> void:
	muted = on
	stream_paused = on


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted


func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func _fill() -> void:
	var sixteenth := int(RATE * 60.0 / BPM / 4.0)
	var avail := mini(_playback.get_frames_available(), 1536)
	for _n in avail:
		if _i % sixteenth == 0:
			_on_step(int(_i / sixteenth) % 128)
		var guitar := _pluck_sample()
		var lead := _lead_sample()
		var drums := _drum_sample()
		var l := guitar * 1.0 + lead * 0.8 + drums
		var r := guitar * 0.86 + lead * 1.0 + drums
		_playback.push_frame(Vector2(clampf(l * 0.9, -0.9, 0.9), clampf(r * 0.9, -0.9, 0.9)))
		_i += 1


func _on_step(step: int) -> void:
	var bar := int(step / 16)
	var s16 := step % 16
	var eighth := int(s16 / 2)
	# Guitar and bass on eighths.
	if s16 % 2 == 0:
		var chord: Array = CHORDS[bar]
		if s16 == 0 and bar % 4 == 0:
			# A short strum to open each four bars.
			for k in 6:
				_add_pluck(float(chord[k]), 0.2 - 0.012 * float(k), 0.9985, k * 330)
		else:
			var amp := 0.2 if eighth % 2 == 0 else 0.15
			_add_pluck(float(chord[PICK[eighth]]), amp, 0.9975, 0)
		if eighth == 0 or eighth == 4:
			_add_pluck(float(BASS[bar]), 0.34, 0.9988, 0)
		# Lead notes.
		for note in LEAD[bar]:
			if int(note[0]) == eighth:
				_start_lead(float(note[1]), float(note[2]) * 60.0 / BPM / 2.0)
	# Percussion: soft kick on 1 and 3, rim on 2 and 4, shaker on sixteenths with an offbeat lift.
	if s16 == 0 or s16 == 8:
		_drums.append({"kind": "kick", "age": 0.0, "life": 0.22, "amp": 0.34})
	if s16 == 4 or s16 == 12:
		_drums.append({"kind": "rim", "age": 0.0, "life": 0.12, "amp": 0.16})
	_drums.append({"kind": "shaker", "age": 0.0, "life": 0.06, "amp": 0.07 if s16 % 4 == 2 else 0.035})


func _add_pluck(midi_note: float, amp: float, decay: float, delay: int) -> void:
	if _plucks.size() > 18:
		_plucks.pop_front()
	var p := Pluck.new()
	var n := maxi(2, int(RATE / _midi(midi_note)))
	p.buf.resize(n)
	var prev := 0.0
	for k in n:
		prev = prev * 0.45 + _rng.randf_range(-1.0, 1.0) * 0.55
		p.buf[k] = prev
	p.amp = amp
	p.decay = decay
	p.delay = delay
	_plucks.append(p)


func _pluck_sample() -> float:
	var out := 0.0
	var keep: Array = []
	for item in _plucks:
		var p: Pluck = item
		p.age += 1
		if p.age > int(RATE * 4.0):
			continue
		keep.append(p)
		if p.delay > 0:
			p.delay -= 1
			continue
		var n := p.buf.size()
		var j := p.pos + 1
		if j >= n:
			j = 0
		var y := p.buf[p.pos]
		p.buf[p.pos] = (y + p.buf[j]) * 0.5 * p.decay
		p.pos = j
		out += y * p.amp
	_plucks = keep
	return out


func _start_lead(midi_note: float, dur: float) -> void:
	_lead_freq = _midi(midi_note)
	_lead_age = 0.0
	_lead_dur = dur
	_lead_on = true


func _lead_sample() -> float:
	if not _lead_on:
		return 0.0
	_lead_age += 1.0 / RATE
	if _lead_age > _lead_dur + 0.35:
		_lead_on = false
		return 0.0
	var vib := 1.0 + 0.006 * sin(_lead_age * TAU * 5.2) * clampf(_lead_age / 0.25, 0.0, 1.0)
	_lead_phase += TAU * _lead_freq * vib / RATE
	if _lead_phase > TAU * 64.0:
		_lead_phase = fmod(_lead_phase, TAU)
	_breath = _breath * 0.9 + _rng.randf_range(-1.0, 1.0) * 0.1
	var env := clampf(_lead_age / 0.05, 0.0, 1.0)
	if _lead_age > _lead_dur:
		env *= exp(-(_lead_age - _lead_dur) * 12.0)
	var tone := sin(_lead_phase) + 0.22 * sin(2.0 * _lead_phase) + 0.35 * _breath
	return 0.13 * env * tone


func _drum_sample() -> float:
	var out := 0.0
	var keep: Array = []
	for item in _drums:
		var d: Dictionary = item
		var age := float(d["age"]) + 1.0 / RATE
		var life := float(d["life"])
		if age > life:
			continue
		var amp := float(d["amp"])
		var noise := _rng.randf_range(-1.0, 1.0)
		var tone := 0.0
		match str(d["kind"]):
			"kick":
				var f := 52.0 + 70.0 * exp(-age * 38.0)
				d["ph"] = float(d.get("ph", 0.0)) + TAU * f / RATE
				tone = sin(float(d["ph"])) * exp(-age * 16.0)
			"rim":
				tone = (0.6 * sin(age * TAU * 420.0) + 0.5 * noise) * exp(-age * 48.0)
			"shaker":
				tone = noise * sin((age / life) * PI)
		out += amp * tone
		d["age"] = age
		keep.append(d)
	_drums = keep
	return out
