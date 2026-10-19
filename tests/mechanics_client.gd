extends "res://tests/r10_client.gd"

# Instrumentación de observación. Los casts pasan por la UI y la red reales.
var capture_label := ""
var packets: Array = []
var frames: Array = []
var audio_frames: Array = []
var seen := {}

func run(owner: Node) -> bool:
	host = owner
	ClientInterface.dataReceived.connect(_packet)
	host.get_tree().process_frame.connect(_observe)
	return await super.run(owner)

func _packet(data: PackedByteArray) -> void:
	if capture_label.is_empty() or data.is_empty():
		return
	if data[0] == Enums.ServerPacketID.CreateFX and data.size() == 7:
		packets.append({"kind": "fx", "char_index": data.decode_s16(1), "fx": data.decode_s16(3), "loops": data.decode_s16(5), "label": capture_label})
	elif data[0] == Enums.ServerPacketID.PlayWave:
		packets.append({"kind": "sound", "bytes": Array(data), "label": capture_label})
	elif data[0] == Enums.ServerPacketID.ConsoleMsg:
		var reader := StreamPeerBuffer.new()
		reader.data_array = data
		reader.seek(1)
		var message := ConsoleMessage.new(reader)
		packets.append({"kind": "console", "message": message.message, "label": capture_label})

func _observe() -> void:
	if capture_label.is_empty() or not ScreenController.currentScreen is GameScreen:
		return
	var game = ScreenController.currentScreen
	for player in AudioManager.get_children():
		if player is AudioStreamPlayer and player.playing and player.stream != null:
			var audio_key := "audio:%s:%d" % [capture_label, player.get_instance_id()]
			if not seen.has(audio_key):
				seen[audio_key] = true
				audio_frames.append({"resource": player.stream.resource_path, "playing": true, "position": player.get_playback_position()})
	for actor in game._gameWorld.GetMapContainer()._characterCollection:
		var effect = actor.effect
		if effect.effect_id <= 0:
			continue
		var key := "%s:%d:%d:%d" % [capture_label, actor.instanceId, effect.effect_id, effect.frame]
		if seen.has(key):
			continue
		seen[key] = true
		frames.append({"label": capture_label, "char_index": actor.instanceId, "fx": effect.effect_id, "frame": effect.frame, "visible": effect.visible, "playing": effect.is_playing(), "resource": effect.sprite_frames.resource_path})

func snapshot() -> Dictionary:
	var view := super.snapshot()
	view.fx_packets = packets.duplicate(true)
	view.fx_frames = frames.duplicate(true)
	view.audio_playback = audio_frames.duplicate(true)
	if not view.in_game:
		return view
	var hub = ScreenController.currentScreen._gameInput
	var context = ScreenController.currentScreen._gameContext
	view.statuses = {"paralyzed": context.userParalizado, "dumb": context.userEstupido, "blind": context.userCiego}
	view.actor_visibility = {}
	for actor in ScreenController.currentScreen._gameWorld.GetMapContainer()._characterCollection:
		view.actor_visibility[str(actor.instanceId)] = {"renderer_visible": actor.renderer.visible, "visible_in_tree": actor.renderer.is_visible_in_tree(), "name_visible": actor._nameLabel.visible, "internal_invisible": actor.GetCharacterInvisible()}
	view.sailing = context.userNavegando
	view.craft = {}
	if is_instance_valid(hub._crafting_window):
		var craft = hub._crafting_window
		view.craft = {"visible":craft.visible, "ready":craft._pending_id.is_empty(), "status":craft._status.text, "recipes":craft.recipes, "page":craft.page}
	view.skill_rows = []
	if is_instance_valid(hub._skills_window):
		var window = hub._skills_window
		for index in window.skills_container.get_child_count():
			var row = window.skills_container.get_child(index)
			view.skill_rows.append({"id": index + 1, "name": row.get_child(0).text, "level": row.get_child(2).text, "plus_disabled": row.get_child(3).disabled, "plus_visible": row.get_child(3).visible, "progress":row.get_child(4).value if row.get_child(4) is ProgressBar else -1, "manual":row.get_child(4).text if row.get_child(4) is Label else ""})
		view.skill_status = window._status.text
	if is_instance_valid(hub._stats_window):
		view.attributes = {}
		for key in hub._stats_window.attribute_labels:
			view.attributes[key] = hub._stats_window.attribute_labels[key].text
		view.attribute_controls = []
		for child in hub._stats_window.attributes_grid.get_children():
			view.attribute_controls.append(child.get_class())
	return view

func execute(command: Dictionary) -> bool:
	if command.op == "capture_reset":
		capture_label = command.label
		packets.clear()
		frames.clear()
		audio_frames.clear()
		seen.clear()
		return true
	if command.op == "screenshot":
		await RenderingServer.frame_post_draw
		return host.get_viewport().get_texture().get_image().save_png(command.path) == OK
	if command.op == "resources":
		var results: Array = []
		for raw_id in command.ids:
			var id := int(raw_id)
			var path := "res://Resources/Fxs/fx_%d.tres" % id
			var result := {"id": id, "exists": ResourceLoader.exists(path)}
			if result.exists:
				var anchor := Node2D.new()
				host.add_child(anchor)
				anchor.position = Vector2(400, 300)
				var effect := CharacterEffect.new()
				anchor.add_child(effect)
				effect.play_effect(id, 0)
				var first := effect.frame
				await host.get_tree().create_timer(0.25).timeout
				result.frame_count = effect.sprite_frames.get_frame_count("default")
				result.first_frame = first
				result.later_frame = effect.frame
				result.frame_advanced = effect.frame != first
				result.visible = effect.visible
				result.playing = effect.is_playing()
				await RenderingServer.frame_post_draw
				host.get_viewport().get_texture().get_image().save_png(command.folder.path_join("resource-fx-%d.png" % id))
				effect.stop_effect()
				anchor.queue_free()
			results.append(result)
		var file := FileAccess.open(command.folder.path_join("fx-resources.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(results))
		return true
	if not ScreenController.currentScreen is GameScreen:
		return await super.execute(command)
	var hub = ScreenController.currentScreen._gameInput
	match command.op:
		"ability":
			if not is_instance_valid(hub._skills_window) or not hub._skills_window.visible:
				hub._on_btn_skills_pressed()
				if not await host.wait_for(func(): return is_instance_valid(hub._skills_window) and hub._skills_window.visible, "ventana de habilidades"):
					return false
			if not await host.wait_for(func(): return hub._skills_window.skills_container.get_child_count() == 22 and not hub._skills_window.operation_id.is_empty(), "catálogo confirmado antes de usar habilidad"):
				return false
			var id := int(command.skill)
			if id == 88:
				hub._skills_window.skills_container.get_child(12).get_child(6).pressed.emit()
			else:
				hub._skills_window.skills_container.get_child(id - 1).get_child(5).pressed.emit()
		"face":
			GameProtocol.WriteChangeHeading(int(command.heading))
		"craft_submit":
			var craft = hub._crafting_window
			var index := -1
			for i in craft.recipes.size():
				if craft.recipes[i].id == command.recipe:
					index = i
			if index < 0 or not craft._pending_id.is_empty():
				return false
			craft._list.select(index)
			craft._select_recipe(index)
			craft._quantity.value = int(command.quantity)
			craft._craft.pressed.emit()
		"close_mechanics":
			if is_instance_valid(hub._crafting_window): hub._crafting_window.hide()
			if is_instance_valid(hub._skills_window): hub._skills_window.hide()
			if is_instance_valid(hub._stats_window): hub._stats_window.hide()
		"stats_open":
			hub._on_btn_stadistics_pressed()
		"allocate_batch":
			for id in command.ids:
				var row = hub._skills_window.skills_container.get_child(int(id) - 1)
				row.get_child(3).pressed.emit()
			hub._skills_window.accept_button.pressed.emit()
		"cast_probe":
			var cast := command.duplicate()
			cast.op = "cast"
			if not await super.execute(cast):
				return false
			# El aviso local de elegir objetivo no confirma el cast. Esperar la
			# publicación del servidor y conservar cuadros posteriores al ACK.
			var deadline := Time.get_ticks_msec() + 8000
			while not packets.any(func(p): return p.kind == "console") and Time.get_ticks_msec() < deadline:
				await host.get_tree().process_frame
			await host.get_tree().create_timer(2.0).timeout
			await RenderingServer.frame_post_draw
			host.get_viewport().get_texture().get_image().save_png(command.path)
		_:
			return await super.execute(command)
	await host.get_tree().process_frame
	return true
