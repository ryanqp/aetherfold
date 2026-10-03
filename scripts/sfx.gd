extends Node

## Sound effects (an autoload named "Sfx"):
##   - the tavern ambience loops quietly behind the match (not in the menus: `set_match_active`);
##   - a cork pops at random times (never sooner than 25 seconds, never later than 3 minutes after the last one) and
##     the glasses clink 4 seconds after each cork;
##   - a click sound for the menus (the title screen and its pages, not the table);
##   - a coin-flip sound for the opening coin toss.
## One volume (user://audio.cfg, "sfx_volume") scales all of it. Music has its own volume in theme_music.gd.
##
## Glasses: put a recording at res://audio/sfx/glasses.ogg (or .wav / .mp3) and it is used for the toast; until then a
## synthesized clink plays.

const TAVERN := "res://audio/sfx/tavern.ogg"
const CORK := "res://audio/sfx/cork.ogg"
const SELECT := "res://audio/sfx/selection.ogg"
const GLASSES_FILES := ["res://audio/sfx/glasses.ogg", "res://audio/sfx/glasses.wav", "res://audio/sfx/glasses.mp3"]
const CONFIG := "user://audio.cfg"
const DEFAULT_VOLUME := 0.7

const CORK_MIN := 25.0
const CORK_MAX := 180.0
const CLINK_DELAY := 4.0

## How loud each sound is next to the others (dB at full slider).
const TAVERN_DB := -4.0
const CORK_DB := 0.0
const GLASSES_DB := -3.0
const SELECT_DB := -2.0
const COIN_DB := -2.0

var volume := DEFAULT_VOLUME
## Master volume for the whole game (every bus), 0..1.
var master := 1.0

var _tavern: AudioStreamPlayer
var _cork: AudioStreamPlayer
var _glasses: AudioStreamPlayer
var _select: AudioStreamPlayer
var _coin: AudioStreamPlayer
var _cork_timer: Timer
var _clink_timer: Timer
var _glasses_stream: AudioStream = null


func _ready() -> void:
	volume = _load_volume()
	master = _load_master()
	_apply_master()
	_tavern = _player(TAVERN_DB)
	_cork = _player(CORK_DB)
	_glasses = _player(GLASSES_DB)
	_select = _player(SELECT_DB)
	_cork.stream = _load_stream(CORK)
	_select.stream = _load_stream(SELECT)
	_apply_volume()
	## Tests and tools run headless: stay silent and don't start timers.
	if DisplayServer.get_name() == "headless":
		return
	_cork_timer = Timer.new()
	_cork_timer.one_shot = true
	_cork_timer.timeout.connect(_on_cork_due)
	add_child(_cork_timer)
	_clink_timer = Timer.new()
	_clink_timer.one_shot = true
	_clink_timer.timeout.connect(_on_clink_due)
	add_child(_clink_timer)


func _player(base_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.set_meta("base_db", base_db)
	add_child(p)
	return p


## Imported resource first; a file that the editor has not imported yet is read directly where Godot can.
func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res := load(path) as AudioStream
		if res != null:
			return res
	var abs_path := ProjectSettings.globalize_path(path)
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(abs_path)
	if path.ends_with(".mp3") and FileAccess.file_exists(abs_path):
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(abs_path)
		return mp3
	if path.ends_with(".wav") and ClassDB.class_has_method("AudioStreamWAV", "load_from_file"):
		return AudioStreamWAV.new().call("load_from_file", abs_path) as AudioStream
	push_warning("Aetherfold: sound not found or not imported yet: %s" % path)
	return null


# --- Tavern -------------------------------------------------------------------------------------------------

func _start_tavern() -> void:
	var s := _load_stream(TAVERN)
	if s == null:
		return
	## Loop it for good: the stream's own loop where it has one, otherwise start again when it ends.
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * float(w.mix_rate))
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	_tavern.stream = s
	if not _tavern.finished.is_connected(_tavern.play):
		_tavern.finished.connect(_tavern.play)
	_tavern.play()


# --- Cork and glasses ---------------------------------------------------------------------------------------

func _schedule_cork() -> void:
	_cork_timer.start(randf_range(CORK_MIN, CORK_MAX))


func _on_cork_due() -> void:
	if _cork.stream != null:
		_cork.play()
	_clink_timer.start(CLINK_DELAY)
	_schedule_cork()


func _on_clink_due() -> void:
	if _glasses_stream == null:
		_glasses_stream = _find_glasses()
	_glasses.stream = _glasses_stream
	_glasses.play()


## A recording dropped into audio/sfx/ wins; otherwise the clink is made in code.
func _find_glasses() -> AudioStream:
	for path in GLASSES_FILES:
		if ResourceLoader.exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path)):
			var s := _load_stream(path)
			if s != null:
				return s
	return _make_toast()


## Three bright glass "tings" close together, each a few inharmonic partials that fade quickly, like glasses touching.
func _make_toast() -> AudioStreamWAV:
	var rate := 44100
	var length := 1.9
	var n := int(rate * length)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	## [start time, base frequency, loudness]
	var tings := [[0.00, 2790.0, 1.0], [0.16, 3330.0, 0.75], [0.46, 2480.0, 0.55]]
	var partials := [[1.0, 1.0, 5.5], [2.76, 0.55, 8.0], [5.40, 0.32, 11.0], [8.93, 0.18, 15.0]]
	for ting in tings:
		var start := int(float(ting[0]) * rate)
		var f := float(ting[1])
		var amp := float(ting[2])
		for i in range(start, n):
			var t := float(i - start) / rate
			var v := 0.0
			for p in partials:
				v += float(p[1]) * exp(-t * float(p[2])) * sin(TAU * f * float(p[0]) * t)
			## A tiny click at the moment of contact.
			if t < 0.004:
				v += (rng.randf() * 2.0 - 1.0) * (1.0 - t / 0.004) * 0.6
			samples[i] += v * amp * 0.28
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	return w


# --- Menu clicks and volume ---------------------------------------------------------------------------------

## The click for menu buttons. The table never calls this.
func play_select() -> void:
	if _select != null and _select.stream != null:
		_select.play()


func set_volume(v: float, save: bool = true) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	if save:
		var cfg := ConfigFile.new()
		cfg.load(CONFIG)  ## keep the music settings that live in the same file
		cfg.set_value("audio", "sfx_volume", volume)
		cfg.save(CONFIG)


func _apply_volume() -> void:
	for p in [_tavern, _cork, _glasses, _select, _coin]:
		if p == null:
			continue
		var base: float = p.get_meta("base_db", 0.0)
		p.volume_db = -80.0 if volume <= 0.001 else base + linear_to_db(volume)


func _load_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) == OK:
		return clampf(float(cfg.get_value("audio", "sfx_volume", DEFAULT_VOLUME)), 0.0, 1.0)
	return DEFAULT_VOLUME


# --- Ambience only while a match is on -----------------------------------------------------------------------

## The table calls this with true when a match starts and false when it ends: the tavern, cork and glasses only play
## in a match, never in the menus.
func set_match_active(on: bool) -> void:
	if DisplayServer.get_name() == "headless" or _cork_timer == null:
		return
	if on:
		if not _tavern.playing:
			_start_tavern()
		if _cork_timer.is_stopped():
			_schedule_cork()
	else:
		_tavern.stop()
		_cork.stop()
		_glasses.stop()
		_cork_timer.stop()
		_clink_timer.stop()


# --- Coin flip -----------------------------------------------------------------------------------------------

var _coin_stream: AudioStream = null


## The sound of the opening coin toss. A recording at audio/sfx/coin_flip.ogg (or .wav) wins over the built-in one.
func play_coin_flip() -> void:
	if _coin_stream == null:
		for path in ["res://audio/sfx/coin_flip.ogg", "res://audio/sfx/coin_flip.wav"]:
			if ResourceLoader.exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path)):
				_coin_stream = _load_stream(path)
				break
		if _coin_stream == null:
			_coin_stream = _make_coin_flip()
	if _coin == null:
		_coin = _player(COIN_DB)
		_apply_volume()
	_coin.stream = _coin_stream
	_coin.play()


## A coin spinning in the air: bright rings that come faster as it spins and then slow with the table's flip
## animation, a few bounces on the table, then it rings out. Matches the roughly 3 second spin on screen.
func _make_coin_flip() -> AudioStreamWAV:
	var rate := 44100
	var length := 4.2
	var n := int(rate * length)
	var samples := PackedFloat32Array()
	samples.resize(n)
	## Spin rings: one per face change of the on-screen flip (14 of them, getting further apart).
	var times: Array = []
	var t0 := 0.0
	var gap := 0.06
	for i in 14:
		times.append(t0)
		t0 += gap
		gap += 0.025
	for k in times.size():
		_add_ring(samples, rate, float(times[k]), 3100.0 + 90.0 * (k % 3), 0.34, 26.0)
	## Landing: three bounces closing in, then the long ring-down with a slight beat.
	var land: float = float(times[times.size() - 1]) + 0.12
	for bounce in [[0.0, 2300.0, 0.7], [0.16, 2500.0, 0.5], [0.27, 2600.0, 0.38], [0.34, 2650.0, 0.3]]:
		_add_ring(samples, rate, land + float(bounce[0]), float(bounce[1]), float(bounce[2]), 14.0)
	_add_ring(samples, rate, land + 0.4, 2640.0, 0.42, 2.6)
	_add_ring(samples, rate, land + 0.4, 2668.0, 0.34, 2.9)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	return w


## Adds a metal "ting" (a few partials that fade) into the sample buffer starting at `start` seconds.
func _add_ring(samples: PackedFloat32Array, rate: int, start: float, freq: float, amp: float, decay: float) -> void:
	var first := int(start * rate)
	var count := mini(samples.size() - first, int(rate * (7.0 / decay)) + 200)
	for i in count:
		var t := float(i) / rate
		var v := sin(TAU * freq * t) + 0.5 * sin(TAU * freq * 2.41 * t) * exp(-t * decay * 0.6) + 0.25 * sin(TAU * freq * 3.83 * t) * exp(-t * decay * 0.9)
		samples[first + i] += v * amp * 0.5 * exp(-t * decay)


# --- Master volume --------------------------------------------------------------------------------------------

func set_master(v: float, save: bool = true) -> void:
	master = clampf(v, 0.0, 1.0)
	_apply_master()
	if save:
		var cfg := ConfigFile.new()
		cfg.load(CONFIG)
		cfg.set_value("audio", "master_volume", master)
		cfg.save(CONFIG)


func _apply_master() -> void:
	AudioServer.set_bus_volume_db(0, -80.0 if master <= 0.001 else linear_to_db(master))


func _load_master() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) == OK:
		return clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	return 1.0
