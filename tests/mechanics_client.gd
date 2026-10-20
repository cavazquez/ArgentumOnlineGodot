extends "res://tests/r10_client.gd"

# Instrumentación de observación. Los casts pasan por la UI y la red reales.
var capture_label := ""
var packets: Array = []
var frames: Array = []
var audio_frames: Array = []
var platform_probe: Dictionary = {}
var keyboard_probe: Dictionary = {}
var seen := {}
var server_console_count := 0

func run(owner: Node) -> bool:
	host = owner
	ClientInterface.dataReceived.connect(_packet)
	host.get_tree().process_frame.connect(_observe)
	return await super.run(owner)

func _packet(data: PackedByteArray) -> void:
	if not data.is_empty() and data[0] == 248:
		var stream := StreamPeerBuffer.new()
		stream.data_array = data
		stream.seek(1)
		var state := WorldStatePacket.new(stream)
		if state.valid and state.data.kind == "chat" and state.data.data.channel == "system":
			server_console_count += 1
			if not capture_label.is_empty(): packets.append({"kind": "console", "message": state.data.data.text, "label": capture_label})
		return
	if not data.is_empty() and data[0] == Enums.ServerPacketID.ConsoleMsg:
		server_console_count += 1
	if capture_label.is_empty() or data.is_empty():
		return
	if data[0] in [246, 247]:
		var stream := StreamPeerBuffer.new()
		stream.data_array = data
		stream.seek(1)
		var visual := AOVisualEvent.new(int(data[0]), stream)
		packets.append({"kind":"visual_damage" if data[0] == 246 else "projectile", "event":visual.event_id, "valid":visual.valid, "source":visual.source, "target":visual.target, "actor":visual.actor, "amount":visual.amount, "visual_kind":visual.kind, "map":visual.map_id, "label":capture_label})
	elif data[0] == Enums.ServerPacketID.CreateFX and data.size() == 7:
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
	view.platform_probe = platform_probe.duplicate(true)
	view.fx_packets = packets.duplicate(true)
	view.server_console_count = server_console_count
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
	view.status_text = hub._status_label.text
	view.ping_status = Global.pingStatus
	view.visual_nodes = ScreenController.currentScreen._visuals.get_child_count()
	view.map_cache = ScreenController.currentScreen._gameWorld.GetMapContainer()._cache.snapshot()
	view.tooltip = hub._inventoryContainer.GetInventorySlot(0).tooltip_text
	view.effects_mode = Global.effectsMode
	view.window_size = [host.get_window().size.x, host.get_window().size.y]
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
		view.ministats = {}
		for key in hub._stats_window.ministats_labels:
			view.ministats[key] = hub._stats_window.ministats_labels[key].text
		view.attributes = {}
		for key in hub._stats_window.attribute_labels:
			view.attributes[key] = hub._stats_window.attribute_labels[key].text
		view.attribute_controls = []
		for child in hub._stats_window.attributes_grid.get_children():
			view.attribute_controls.append(child.get_class())
	return view

func execute(command: Dictionary) -> bool:
	if command.op == "native_window":
		var window := host.get_window()
		window.mode = Window.MODE_MINIMIZED if command.action == "minimize" else Window.MODE_WINDOWED
		if command.action == "restore": window.grab_focus()
		await host.get_tree().process_frame
		return true
	if command.op == "platform_probe":
		var original_size := Global.dialogFontSize
		Global.dialogFontSize = 14
		if Global.save_preferences() != OK: return false
		Global.dialogFontSize = 12
		Global.reload_preferences()
		var saved := Global.dialogFontSize == 14
		Global.dialogFontSize = original_size
		if Global.save_preferences() != OK: return false
		var previous := InputBindings.encode(InputMap.action_get_events(&"Attack")[0])
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F8
		if InputBindings.assign(&"Attack", key) != OK: return false
		InputBindings.reload_profile()
		var input_saved: bool = InputBindings.encode(InputMap.action_get_events(&"Attack")[0]).get("physical") == KEY_F8
		if InputBindings.assign(&"Attack", InputBindings.decode(previous)) != OK: return false
		var game := ScreenController.currentScreen as GameScreen
		if game == null: return false
		var keyboard := await keyboard_flows(game)
		var audio := await AudioPlaybackProbe.played(host)
		await RenderingServer.frame_post_draw
		var image := host.get_viewport().get_texture().get_image()
		var rendered := DisplayServer.get_name() != "headless" and image != null and image.get_width() >= 640
		platform_probe = {"rendering": rendered, "audio": audio, "input": input_saved and keyboard, "input_saved": input_saved, "keyboard": keyboard_probe, "preferences": saved, "display_driver": DisplayServer.get_name(), "audio_driver": AudioServer.get_driver_name(), "engine_max_fps": Engine.max_fps, "measured_fps": Engine.get_frames_per_second()}
		return rendered and audio and input_saved and keyboard and saved
	if command.op == "ui_phase":
		var game := ScreenController.currentScreen as GameScreen
		if game == null: return false
		host.get_viewport().gui_release_focus()
		match String(command.action):
			"map":
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_RIGHT
				click.pressed = true
				click.position = game._gameInput.minimap.size / 2
				game._gameInput.minimap.gui_input.emit(click)
			"ping": Global.ping_requested.emit()
			"resize":
				host.get_window().size = Vector2i(command.width, command.height)
				await host.get_tree().process_frame
				await host.get_tree().process_frame
				await host.get_tree().process_frame
				if not verify_layout(game): return false
			"layout":
				if not verify_layout(game): return false
			"options": game._gameInput._on_btn_options_pressed()
			"effects": Global.effectsMode = int(command.value)
			"keyboard_flows":
				if not await keyboard_flows(game): return false
			"keyboard":
				var slot := game._gameInput._inventoryContainer.GetInventorySlot(0)
				slot.grab_focus()
				await host.get_tree().process_frame
				var key := InputEventAction.new()
				key.action = "ui_accept"
				key.pressed = true
				slot._gui_input(key)
			_: return false
		await host.get_tree().process_frame
		return true
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
			await super.execute({"op":"close"})
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

func verify_layout(game: GameScreen) -> bool:
	var hub: HubController = game._gameInput
	hub._responsive.layout()
	var viewport := host.get_viewport().get_visible_rect().grow(1)
	for record in hub._responsive.records:
		var control: Control = record.node
		if not control.is_visible_in_tree() or not control.size.x > 0 or not control.size.y > 0: continue
		if not viewport.encloses(control.get_global_rect()):
			push_error("HUD fuera de pantalla: %s %s en %s" % [control.name, control.get_global_rect(), viewport])
			return false
	print("HUD_LAYOUT: PASS %s" % viewport.size)
	return true

func focus_native_window(window: Window) -> bool:
	if OS.get_name() != "Windows": return true
	window.grab_focus()
	var deadline := Time.get_ticks_msec() + 2000
	while not window.has_focus() and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	return window.has_focus()

func keyboard_flows(game: GameScreen) -> bool:
	keyboard_probe = {}
	keyboard_probe.main_focused = await focus_native_window(host.get_window())
	if not keyboard_probe.main_focused: return false
	var hub: HubController = game._gameInput
	var actor = game._gameWorld.GetCharacter(game._mainCharacterInstanceId)
	var before: Vector2i = actor.gridPosition
	var slot := hub._inventoryContainer.GetInventorySlot(0)
	slot.grab_focus()
	Input.action_press("ui_right")
	await host.get_tree().create_timer(0.2).timeout
	Input.action_release("ui_right")
	keyboard_probe.inventory = actor.gridPosition == before and hub.IsWorldInputBlocked()
	if not keyboard_probe.inventory: return false
	for action in ["options", "stats", "skills"]:
		var window: Window
		match action:
			"options":
				hub._on_btn_options_pressed()
				window = hub._options_window
			"stats":
				hub._on_btn_stadistics_pressed()
				window = hub._stats_window
			"skills":
				hub._on_btn_skills_pressed()
				window = hub._skills_window
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		keyboard_probe[action + "_focused"] = await focus_native_window(window)
		if not keyboard_probe[action + "_focused"]: return false
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		window.push_input(tab)
		await host.get_tree().process_frame
		keyboard_probe[action] = window.gui_get_focus_owner() != null and hub.IsWorldInputBlocked()
		if not keyboard_probe[action]: return false
		window.close_requested.emit()
		await host.get_tree().process_frame
	var controls := ControlsWindow.new()
	hub.add_child(controls)
	controls.popup_centered()
	await host.get_tree().process_frame
	keyboard_probe.controls_focused = await focus_native_window(controls)
	if not keyboard_probe.controls_focused: return false
	var original := InputBindings.encode(InputMap.action_get_events(&"Attack")[0])
	controls._action = &"Attack"
	InputBindings.capturing = true
	Input.action_press("ui_right")
	await host.get_tree().create_timer(0.2).timeout
	Input.action_release("ui_right")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	controls.push_input(escape)
	await host.get_tree().process_frame
	keyboard_probe.capture_cancelled = not InputBindings.capturing and actor.gridPosition == before
	keyboard_probe.binding_preserved = InputBindings.encode(InputMap.action_get_events(&"Attack")[0]) == original
	if not keyboard_probe.capture_cancelled or not keyboard_probe.binding_preserved: return false
	controls.close_requested.emit()
	await host.get_tree().process_frame
	host.get_viewport().gui_release_focus()
	print("KEYBOARD_FLOWS: PASS inventory/options/stats/skills/capture")
	return true
