extends RefCounted
class_name AudioPlaybackProbe

# Verifica el avance o fin real del sonido. Un único muestreo a los 50 ms
# puede perder un sonido corto cuando el runner tarda en devolver el cuadro.
static func played(owner: Node, wave: int = 17) -> bool:
	AudioManager.PlayAudio(wave)
	var player := AudioManager._active.get(wave) as AudioStreamPlayer
	if player == null or player.stream == null or player.stream.get_length() <= 0:
		return false
	var completed := [false]
	player.finished.connect(func(): completed[0] = true, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if completed[0]: return true
		if is_instance_valid(player) and player.playing and player.get_playback_position() > 0:
			return true
		await owner.get_tree().process_frame
	return false
