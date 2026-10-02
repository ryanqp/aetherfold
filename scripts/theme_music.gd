extends AudioStreamPlayer

## Music for the whole app (an autoload named "Music"): a recorded fantasy-tavern piece (lute, whistle,
## fiddle, hand drum, strings), 2:17, looping. It starts in the main menu and keeps playing at the table.
## Rendered by tools/make_music.py, so playing it costs almost nothing (no live synthesis).
## The volume (0..1, default 0.7) is saved in user://audio.cfg.

const TRACK := "res://audio/music/tavern_theme.ogg"
const CONFIG := "user://audio.cfg"
const DEFAULT_VOLUME := 0.7
## 0.7 sounds like the old fixed -7 dB level.
const BASE_DB := -4.0

var muted := false
var volume := DEFAULT_VOLUME


func _ready() -> void:
	volume = _load_volume()
	var saved := ConfigFile.new()
	if saved.load(CONFIG) == OK:
		muted = bool(saved.get_value("audio", "muted", false))
	_apply_volume()
	var track: AudioStream = null
	if ResourceLoader.exists(TRACK):
		track = load(TRACK) as AudioStream
	if track == null:
		## Not imported yet (the editor imports new files when it regains focus): read the file directly.
		track = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(TRACK))
	if track == null:
		push_warning("Aetherfold: music file missing: %s (run tools/make_music.py)" % TRACK)
		return
	if track is AudioStreamOggVorbis:
		(track as AudioStreamOggVorbis).loop = true
	stream = track
	play()
	stream_paused = muted


func set_volume(v: float, save: bool = true) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	if save:
		_save()


## Volume and mute are remembered between launches (T-011).
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(CONFIG)


func _apply_volume() -> void:
	volume_db = -80.0 if volume <= 0.001 else BASE_DB + linear_to_db(volume)


func _load_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) == OK:
		return clampf(float(cfg.get_value("audio", "volume", DEFAULT_VOLUME)), 0.0, 1.0)
	return DEFAULT_VOLUME


func set_muted(on: bool) -> void:
	muted = on
	stream_paused = on
	_save()


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted
