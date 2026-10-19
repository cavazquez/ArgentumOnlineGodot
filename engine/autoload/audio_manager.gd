extends Node

var _playbacks: Array[WeakRef] = []

func _ready() -> void:
	# ClientInterface se registra después de AudioManager entre los autoloads.
	_connect_session_cleanup.call_deferred()

func _connect_session_cleanup() -> void:
	ClientInterface.disconnected.connect(StopAll)

func _exit_tree() -> void:
	StopAll()

func StopAll() -> void:
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

func PlayAudio(waveId:int) -> void:
	_forget_finished_playbacks()
	if !ResourceLoader.exists("res://Assets/Sfx/%d.wav" % waveId):
		push_error("AudioManager: Audio resource not found: %d" % waveId)
		return
		
	var audioStreamPlayer = AudioStreamPlayer.new()
	add_child(audioStreamPlayer)
	
	audioStreamPlayer.stream = load("res://Assets/Sfx/%d.wav" % waveId)
	audioStreamPlayer.bus = "sfx"
	audioStreamPlayer.finished.connect(audioStreamPlayer.queue_free)
	audioStreamPlayer.play()
	var playback: AudioStreamPlayback = audioStreamPlayer.get_stream_playback()
	if playback != null:
		_playbacks.append(weakref(playback))
