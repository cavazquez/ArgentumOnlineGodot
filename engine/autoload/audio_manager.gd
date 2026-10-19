extends Node

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

func PlayAudio(waveId:int) -> void:
	if !ResourceLoader.exists("res://Assets/Sfx/%d.wav" % waveId):
		push_error("AudioManager: Audio resource not found: %d" % waveId)
		return
		
	var audioStreamPlayer = AudioStreamPlayer.new()
	add_child(audioStreamPlayer)
	
	audioStreamPlayer.stream = load("res://Assets/Sfx/%d.wav" % waveId)
	audioStreamPlayer.bus = "sfx"
	audioStreamPlayer.finished.connect(audioStreamPlayer.queue_free)
	audioStreamPlayer.play()
