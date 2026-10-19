extends Control
class_name WorldPresentation

var viewport: SubViewport
var map_id := 0
var waiting := false
var _freeze: TextureRect
var _rain: ColorRect
var _fog: ColorRect
var _audio: AudioStreamPlayer
var _phase := ""
var _weather: Dictionary = {}
var _fade: Tween
var _rain_fade: Tween
var _rain_target := 0.0
var _transition_seconds := 0.2
var _topology: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/world-topology.json"))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rain = _overlay(preload("res://shaders/world_rain.gdshader"))
	_fog = _overlay(preload("res://shaders/world_fog.gdshader"))
	_freeze = TextureRect.new()
	_freeze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_freeze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_freeze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_freeze.stretch_mode = TextureRect.STRETCH_SCALE
	_freeze.hide()
	add_child(_freeze)
	_audio = AudioStreamPlayer.new()
	_audio.bus = "sfx"
	_audio.finished.connect(_audio_finished)
	add_child(_audio)
	Global.preferences_changed.connect(_preferences)
	resized.connect(_resize)
	_resize()
	_preferences()

func _overlay(shader: Shader) -> ColorRect:
	var layer := ColorRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	layer.material = shader_material
	add_child(layer)
	return layer

func _resize() -> void:
	for layer in [_rain, _fog]:
		layer.material.set_shader_parameter("viewport_size", size.max(Vector2.ONE))

func begin(next_map: int) -> void:
	if _fade != null: _fade.kill()
	# Una copia independiente evita que el frame congelado cambie con el viewport.
	if not waiting and map_id > 0 and Global.transitionEffects and viewport != null and DisplayServer.get_name() != "headless":
		var image := viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			_freeze.texture = ImageTexture.create_from_image(image)
			_freeze.modulate.a = 1.0
			_freeze.show()
	_transition_seconds = 0.2
	for edge in _topology.get("edges", []):
		if int(edge.get("from", -1)) == map_id and int(edge.get("to", -1)) == next_map and edge.get("kind", "") in ["cardinal", "diagonal"]:
			_transition_seconds = 0.12
			break
	map_id = next_map
	waiting = true
	_weather.clear()
	_update_weather(true)

func reveal() -> void:
	if not waiting: return
	waiting = false
	if not Global.transitionEffects or not _freeze.visible:
		_clear_freeze()
		return
	_fade = create_tween()
	_fade.tween_property(_freeze, "modulate:a", 0.0, _transition_seconds)
	_fade.tween_callback(_clear_freeze)

func _clear_freeze() -> void:
	_freeze.hide()
	_freeze.texture = null

func apply_weather(value: Dictionary) -> void:
	if int(value.map) != map_id: return
	_weather = value.duplicate(true)
	_update_weather()

func _preferences() -> void:
	_fog.material.set_shader_parameter("intensity", Global.peripheralFog if Global.effectsMode > 0 else 0.0)
	if not Global.transitionEffects:
		if _fade != null: _fade.kill()
		_clear_freeze()
	_update_weather()

func _update_weather(immediate: bool = false) -> void:
	var target := 0.0
	if _weather.get("outdoor", false) and _weather.get("raining", false) and Global.effectsMode > 0:
		target = float(_weather.get("intensity", 0)) / 100.0 * Global.rainIntensity
		if Global.effectsMode == 1: target *= 0.5
	if is_equal_approx(_rain_target, target) and not immediate:
		if target > 0: _audio.volume_db = linear_to_db(target * 0.5)
		return
	var was_raining := _rain_target > 0
	_rain_target = target
	if _rain_fade != null: _rain_fade.kill()
	if immediate:
		_rain.material.set_shader_parameter("intensity", target)
		_audio.stop()
		_audio.stream = null
		_phase = ""
	else:
		_rain_fade = create_tween()
		_rain_fade.tween_method(func(value: float): _rain.material.set_shader_parameter("intensity", value), float(_rain.material.get_shader_parameter("intensity")), target, 0.2)
	if target > 0:
		_audio.volume_db = linear_to_db(target * 0.5)
		if not was_raining or not _audio.playing: _play_rain("start")
	elif was_raining and not immediate and Global.rainIntensity > 0 and Global.effectsMode > 0:
		_play_rain("end")
	else:
		_audio.stop()
		_audio.stream = null
		_phase = ""

func _play_rain(phase: String) -> void:
	_audio.stop()
	_phase = phase
	var suffix: String = {"start": "st", "loop": "", "end": "end"}[phase]
	var path := "res://Assets/Sfx/lluviaout%s.wav" % suffix
	if not ResourceLoader.exists(path):
		if phase == "start": _play_rain("loop")
		return
	var stream := load(path).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if phase == "loop" else AudioStreamWAV.LOOP_DISABLED
	if phase == "loop":
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_audio.stream = stream
	_audio.play()
	AudioManager.TrackPlayback(_audio.get_stream_playback())

func _audio_finished() -> void:
	if _phase == "start" and _rain_target > 0: _play_rain("loop")
	else:
		_phase = ""
		_audio.stream = null

func set_world_offset(offset: Vector2) -> void:
	_rain.material.set_shader_parameter("world_offset", offset)

func reset() -> void:
	if _fade != null: _fade.kill()
	if _rain_fade != null: _rain_fade.kill()
	waiting = false
	map_id = 0
	_clear_freeze()
	_weather.clear()
	_update_weather(true)

func _exit_tree() -> void:
	if Global.preferences_changed.is_connected(_preferences): Global.preferences_changed.disconnect(_preferences)
	if _fade != null: _fade.kill()
	if _rain_fade != null: _rain_fade.kill()
	if is_instance_valid(_audio):
		_audio.stop()
		_audio.stream = null
