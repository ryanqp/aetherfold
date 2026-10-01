extends AudioStreamPlayer

## Table music: a recorded fantasy-tavern piece (lute, whistle, fiddle, hand drum, strings), 2:17, looping.
## It is rendered by tools/make_music.py, so playing it costs almost nothing (no live synthesis).

const TRACK := "res://audio/music/tavern_theme.ogg"

var muted := false


func _ready() -> void:
	volume_db = -7.0
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


func set_muted(on: bool) -> void:
	muted = on
	stream_paused = on


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted
