extends Node

var _failed := false

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	ClientInterface.capabilities.enabled = ClientCapabilities.REQUESTED
	Global.skillPoints = 10
	var window = load("res://ui/hub/skills_window.tscn").instantiate()
	add_child(window)
	var catalog := SendSkills.new()
	catalog._initialize_skills()
	catalog.skills[8].level = 2
	catalog.skills[8].experience = 37
	window.set_skills(catalog.skills)
	await get_tree().process_frame
	_check(window.skills_container.get_child_count() == 22, "Faltan habilidades en la interfaz")
	_check(window.skills_container.get_child(8).get_child(4).value == 37, "La barra no usa el porcentaje de entrenamiento")
	_check(window.skills_container.get_child(20).get_child(4).text == "Manual", "Robustez debe conservar su progresión manual")
	_check(window.skills_container.get_child(13).get_child(5).text == "Fabricar", "Falta acceso a Carpintería")
	window.operation_id = GameProtocol.NewSkillActionId()
	window._on_plus_pressed(8)
	catalog.skills[8].level = 3
	catalog.skills[8].experience = 55
	window.ApplyProgressUpdate(catalog.skills)
	_check(window.skill_values[8] == 3 and window.initial_skill_values[8] == 2, "El entrenamiento borró el punto en borrador")
	var refresh := SkillAllocationState.new()
	refresh.status = 0
	refresh.next_operation_id = GameProtocol.NewSkillActionId()
	refresh.free_points = 15
	refresh.skills = catalog.skills
	window.ApplyAllocationState(refresh)
	_check(window.initial_skill_values[8] == 3 and window.skill_values[8] == 4, "Un snapshot ajeno descartó la asignación pendiente")
	_check(window.current_free_skills == 14 and window.operation_id == refresh.next_operation_id, "El borrador no usa el presupuesto y la identidad actualizados")
	_check(window.skill_percentages[8] == 55, "El borrador oculta el progreso confirmado")
	# Si se perdió un ACK, refrescar no debe proponer gastar el mismo punto otra vez.
	window._pending_id = window.operation_id
	window.operation_id = ""
	window._deadline = 0
	window._process(0.0)
	catalog.skills[8].level = 4
	refresh.skills = catalog.skills
	refresh.free_points = 14
	refresh.next_operation_id = GameProtocol.NewSkillActionId()
	window.ApplyAllocationState(refresh)
	_check(window.skill_values[8] == 4 and not window.has_skill_changes(), "Consultar tras perder un ACK duplica la asignación propuesta")
	var requested := [0]
	window.action_requested.connect(func(skill): requested[0] = skill)
	window._request_action(17)
	_check(requested[0] == 17, "El botón Domar no emite su habilidad")
	window.queue_free()
	var stats = load("res://ui/hub/stats_window.tscn").instantiate()
	add_child(stats)
	stats.popup_centered()
	stats.size = Vector2i(460, 460)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(stats.close_button.get_global_rect().end.y <= stats.size.y, "Estadísticas recorta el botón al redimensionar: size=%s button=%s minimum=%s" % [stats.size, stats.close_button.get_global_rect(), stats.get_node("VBox").get_combined_minimum_size()])
	_check(stats.get_node("VBox/ProgressionExplanation").position.y >= 0, "Estadísticas recorta la explicación de atributos")
	stats.queue_free()
	GameProtocol.Clear()
	var identity := GameProtocol.NewSkillActionId()
	_check(SkillAllocationState.valid_identity(identity), "Identidad de acción inválida")
	_check(GameProtocol.WriteSkillAction("recipes", {"skill": "carpinteria", "page": 0}, identity), "No se serializa la consulta de recetas")
	var bytes := GameProtocol.Flush()
	_check(bytes[0] == 251 and bytes[1] == 1, "Cambió el ID o versión del protocolo de habilidades")
	var reader := StreamPeerBuffer.new()
	reader.data_array = bytes
	reader.seek(2)
	var request: Dictionary = JSON.parse_string(Utils.GetUnicodeString(reader))
	_check(request.id == identity and request.params.page == 0, "La intención enviada no conserva identidad y parámetros")
	var crafting := CraftingWindow.new()
	add_child(crafting)
	crafting.open_skill("carpinteria")
	var pending := crafting._pending_id
	crafting.apply_result({"id": pending, "applied": true, "kind": "recipes", "skill": "carpinteria", "page": 0, "has_next": false, "recipes": [{"id": "carpinteria:480", "item_id": 480, "name": "Flecha", "required": 1, "success_rate": 80, "materials": [{"item_id": 58, "name": "Leña", "quantity": 1}]}]})
	_check(crafting._list.item_count == 1 and not crafting._craft.disabled, "No se puede seleccionar una receta confirmada")
	_check(crafting._details.text.contains("Leña"), "Los materiales no tienen nombres legibles")
	crafting._submit()
	var original_id := crafting._pending_id
	crafting._resend()
	_check(crafting._pending_id == original_id and not original_id.is_empty(), "Reintentar cambió la identidad y podría duplicar la fabricación")
	crafting.apply_result({"id": original_id, "applied": false, "message": "Faltan materiales"})
	_check(crafting._status.text == "Faltan materiales" and crafting._pending_id.is_empty(), "No se muestra el rechazo autoritativo")
	crafting.queue_free()
	var character := Character.new()
	character.renderer = CharacterRenderer.new()
	character._nameLabel = Label.new()
	character.SetCharacterInvisible(true)
	_check(not character.renderer.visible, "SET_INVISIBLE true no oculta")
	character.SetCharacterInvisible(false)
	_check(character.renderer.visible, "SET_INVISIBLE false no revela")
	character.renderer.free()
	character._nameLabel.free()
	character.free()
	var map := MapContainer.new()
	add_child(map)
	map._view = Node2D.new()
	map.add_child(map._view)
	var layer := Node2D.new()
	layer.name = "Layer3"
	map._view.add_child(layer)
	var world := GameWorld.new()
	world._mapContainer = map
	add_child(world)
	var movement_camera := Camera2D.new()
	add_child(movement_camera)
	movement_camera.make_current()
	await get_tree().process_frame
	var npc = GameWorld.CharacterScene.instantiate()
	npc.instanceId = 10001
	npc.position = Vector2(64, 64)
	map.AddCharacter(npc)
	var move_screen := GameScreen.new()
	move_screen._gameWorld = world
	npc.gridPosition = Vector2i(50, 50)
	npc.position = Vector2(1584, 1600)
	var movement := CharacterMove.new()
	movement.charIndex = 10001
	movement.x = 50
	movement.y = 50
	move_screen._HandleCharacterMove(movement)
	_check(npc.gridPosition == Vector2i(50, 50) and not npc.isMoving, "La misma posición remota hace caminar al NPC")
	movement.x = 51
	move_screen._HandleCharacterMove(movement)
	var step_target: Vector2 = npc._targetPosition
	_check(npc.gridPosition == Vector2i(51, 50) and npc.isMoving, "Un paso remoto perdió su animación")
	move_screen._HandleCharacterMove(movement)
	_check(npc.gridPosition == Vector2i(51, 50) and npc._targetPosition == step_target, "Un duplicado durante la animación agrega otro paso")
	movement.x = 55
	movement.y = 53
	move_screen._HandleCharacterMove(movement)
	_check(npc.gridPosition == Vector2i(55, 53) and npc.position == Vector2(1744, 1696) and not npc.isMoving, "La corrección remota no alcanza la posición autoritativa")
	npc._ProcessMovement(1.0)
	_check(npc.position == Vector2(1744, 1696), "Una interpolación vieja sobrescribe la corrección")
	move_screen.free()
	npc.position = Vector2(64, 64)
	world.DeleteCharacter(10001)
	world.PlayCharacterEffect(10001, 15, 1)
	await get_tree().process_frame
	_check(layer.get_child_count() == 1, "El FX letal desaparece junto con el NPC")
	var anchor = layer.get_child(0)
	_check(anchor.position == Vector2(64, 64), "El FX letal perdió la posición del objetivo")
	var final_effect = anchor.get_child(0)
	_check(final_effect.effect_id == 15 and final_effect.is_playing(), "El FX letal no reproduce cuadros reales")
	final_effect.stop_effect()
	await get_tree().process_frame
	_check(layer.get_child_count() == 0, "El FX transitorio deja nodos sin liberar")
	world.queue_free()
	map.queue_free()
	movement_camera.queue_free()
	GameProtocol.Clear()
	await get_tree().process_frame
	# Control positivo del audio: bytes PlayWave -> parser -> handler -> WAV real.
	# No acredita las voces de NPC que faltan en el catálogo del servidor.
	var audio_screen := GameScreen.new()
	for wave in [47, 103, 62]:
		AudioManager.StopAll()
		var wave_reader := StreamPeerBuffer.new()
		wave_reader.data_array = PackedByteArray([wave, 51, 50])
		var packet := PlayWave.new(wave_reader)
		_check(packet.wave == wave and packet.x == 51 and packet.y == 50, "PlayWave perdió la identidad o posición del NPC")
		audio_screen._HandlePlayWave(packet)
		var voice := AudioManager.get_child(0) as AudioStreamPlayer
		_check(voice != null and voice.playing and voice.stream.resource_path == "res://Assets/Sfx/%d.wav" % wave, "El WAV de control del NPC no inició reproducción")
	audio_screen.free()
	AudioManager.StopAll()
	AudioManager.PlayAudio(3)
	var sound := AudioManager.get_child(0) as AudioStreamPlayer
	var stream_ref: WeakRef = weakref(sound.stream)
	var playback_ref: WeakRef = weakref(sound.get_stream_playback())
	_check(sound.playing, "El sonido no inició una reproducción real")
	ClientInterface.disconnected.emit()
	_check(AudioManager.get_child_count() == 0, "La desconexión dejó reproductores activos")
	var deadline := Time.get_ticks_msec() + 1000
	while (stream_ref.get_ref() != null or playback_ref.get_ref() != null) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(stream_ref.get_ref() == null and playback_ref.get_ref() == null, "La desconexión retuvo recursos de audio")
	_check(AudioManager.IsDrained(), "El mixer conserva reproducciones al cerrar")
	print("MECHANICS_SMOKE: ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
