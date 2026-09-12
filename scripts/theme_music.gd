extends AudioStreamPlayer

## Dark, low piano + cello pad. Mixed in code so the project stays small.

const RATE := 22050.0
const BPM := 54.0

var muted := false
var _playback: AudioStreamGeneratorPlayback
var _i := 0
var _piano: Array = []
var _pad_phase: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _pad_freq: Array[float] = [73.42, 110.0, 146.83, 98.0, 55.0]
var _pad_target: Array[float] = [73.42, 110.0, 146.83, 98.0, 55.0]

func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.5
	stream = gen
	volume_db = -8.0
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
	var eighth := int(RATE * 60.0 / BPM / 2.0)
	var avail := mini(_playback.get_frames_available(), 1536)
	for _n in avail:
		var step := int(_i / eighth) % 64
		if _i % eighth == 0:
			_on_step(step)
		_glide_pads()
		var s := _pad_sample() + _piano_sample()
		s = clampf(s * 0.62, -0.85, 0.85)
		_playback.push_frame(Vector2(s * 1.02, s * 0.96))
		_i += 1

func _on_step(step: int) -> void:
	var bar := int(step / 8)
	var beat := step % 8
	# D minor — Bb — G minor — A; kept in the low octave.
	var roots: Array[float] = [38.0, 38.0, 34.0, 34.0, 43.0, 43.0, 33.0, 33.0]
	var thirds: Array[float] = [41.0, 41.0, 38.0, 38.0, 46.0, 46.0, 36.0, 36.0]
	var fifths: Array[float] = [45.0, 45.0, 41.0, 41.0, 50.0, 50.0, 40.0, 40.0]
	var root := roots[bar]
	var third := thirds[bar]
	var fifth := fifths[bar]
	_pad_target[0] = _midi(root)
	_pad_target[1] = _midi(fifth)
	_pad_target[2] = _midi(third)
	_pad_target[3] = _midi(root + 7.0)
	_pad_target[4] = _midi(root - 12.0)
	var arp: Array[float] = [root, fifth, third, root, fifth, third, root - 5.0, fifth]
	if beat == 0 or beat == 4:
		_pluck(arp[beat], 0.22, 3.6)
	elif beat % 2 == 0:
		_pluck(arp[beat], 0.12, 2.8)
	if beat == 0:
		_pluck(root - 12.0, 0.28, 5.0)

func _pluck(midi_note: float, amp: float, life: float) -> void:
	if midi_note > 52.0:
		midi_note -= 12.0
	if _piano.size() > 8:
		_piano.pop_front()
	_piano.append({
		"phase": 0.0,
		"freq": _midi(midi_note),
		"amp": amp,
		"life": life,
		"age": 0.0,
	})

func _glide_pads() -> void:
	for p in 5:
		_pad_freq[p] = lerpf(_pad_freq[p], _pad_target[p], 0.0012)

func _pad_sample() -> float:
	var out := 0.0
	var amps: Array[float] = [0.16, 0.11, 0.07, 0.06, 0.18]
	for p in 5:
		var vib := 1.0 + 0.002 * sin(float(_i) * TAU * (3.1 + float(p) * 0.11) / RATE)
		_pad_phase[p] += TAU * _pad_freq[p] * vib / RATE
		if _pad_phase[p] > TAU:
			_pad_phase[p] -= TAU
		var ph := _pad_phase[p]
		out += amps[p] * sin(ph)
	return out

func _piano_sample() -> float:
	var out := 0.0
	var keep: Array = []
	for voice in _piano:
		var v: Dictionary = voice
		var age := float(v["age"]) + 1.0 / RATE
		var life := float(v["life"])
		if age > life:
			continue
		var env := exp(-age * 1.7) * (1.0 - age / life)
		var freq := float(v["freq"])
		var phase := float(v["phase"]) + TAU * freq / RATE
		if phase > TAU * 8.0:
			phase = fmod(phase, TAU)
		var tone := sin(phase) + 0.18 * sin(2.0 * phase)
		out += float(v["amp"]) * env * tone
		v["phase"] = phase
		v["age"] = age
		keep.append(v)
	_piano = keep
	return out
