extends Node

var _playbacks: Array[WeakRef] = []
var _active := {}
var _music: AudioStreamPlayer
var _track := 0


func _ready() -> void:
	Global.preferences_changed.connect(_update_music_volume)
	# ClientInterface se registra después de AudioManager entre los autoloads.
	_connect_session_cleanup.call_deferred()

func _connect_session_cleanup() -> void:
	ClientInterface.disconnected.connect(StopAll)

func _exit_tree() -> void:
	StopAll()

func StopAll() -> void:
	_active.clear()
	_music = null
	_track = 0
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
			child.free()

func IsDrained() -> bool:
	_forget_finished_playbacks()
	return get_child_count() == 0 and _playbacks.is_empty()

func _forget_finished_playbacks() -> void:
	for index in range(_playbacks.size() - 1, -1, -1):
		if _playbacks[index].get_ref() == null:
			_playbacks.remove_at(index)

func PlayAudio(waveId:int, prevent_overlap: bool = false) -> void:
	if prevent_overlap and is_instance_valid(_active.get(waveId)) and _active[waveId].playing: return
	if get_child_count() >= 32: return
	_forget_finished_playbacks()
	if !ResourceLoader.exists("res://Assets/Sfx/%d.wav" % waveId):
		push_warning("AudioManager: Audio resource not found: %d" % waveId)
		return
		
	var audioStreamPlayer = AudioStreamPlayer.new()
	add_child(audioStreamPlayer)
	
	audioStreamPlayer.stream = load("res://Assets/Sfx/%d.wav" % waveId)
	audioStreamPlayer.bus = "sfx"
	_active[waveId] = audioStreamPlayer
	audioStreamPlayer.finished.connect(func():
		if _active.get(waveId) == audioStreamPlayer: _active.erase(waveId)
		audioStreamPlayer.queue_free())
	audioStreamPlayer.play()
	var playback: AudioStreamPlayback = audioStreamPlayer.get_stream_playback()
	if playback != null:
		_playbacks.append(weakref(playback))

func PlayMusic(track: int) -> void:
	if track == _track and is_instance_valid(_music) and _music.playing: return
	if is_instance_valid(_music):
		_music.stop()
		_music.queue_free()
	_music = null
	_track = 0
	if track <= 0: return
	var path := "res://Assets/Music/%d.ogg" % track
	if not ResourceLoader.exists(path):
		push_warning("Pista musical no disponible: %d" % track)
		return
	var stream := load(path) as AudioStreamOggVorbis
	if stream == null: return
	stream = stream.duplicate()
	stream.loop = true
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	add_child(_music)
	_track = track
	_update_music_volume()
	_music.play()
	var playback := _music.get_stream_playback()
	if playback != null: _playbacks.append(weakref(playback))

func _update_music_volume() -> void:
	if is_instance_valid(_music):
		_music.volume_db = linear_to_db(Global.musicVolume) if Global.musicVolume > 0 else -80.0
