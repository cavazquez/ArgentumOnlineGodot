extends RefCounted

# El controlador sólo opera pantallas, formularios y acciones del cliente real.
# Las expectativas persistidas se comprueban independientemente en el runner.
var host: Node
var last_chat_tick := 0

func run(owner: Node) -> bool:
	host = owner
	var root := OS.get_environment("PYAO_TEST_CONTROL")
	var sequence := 1
	while true:
		var request := root.path_join("%04d.request.json" % sequence)
		while not FileAccess.file_exists(request):
			await host.get_tree().create_timer(0.05).timeout
		var command: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(request))
		var ok := await execute(command)
		var response := {"ok": ok, "sequence": sequence, "operation": command.op, "view": snapshot()}
		var response_path := root.path_join("%04d.response.json" % sequence)
		var file := FileAccess.open(response_path + ".pending", FileAccess.WRITE)
		file.store_string(JSON.stringify(response))
		file.close()
		if DirAccess.rename_absolute(response_path + ".pending", response_path) != OK:
			push_error("R10: no se pudo confirmar el recibo completo")
			host.get_tree().quit(1)
			return false
		print("R10_CLIENT: ", sequence, " ", command.op, " ", "PASS" if ok else "FAIL")
		if not ok:
			host.get_tree().quit(1)
			return false
		if command.op == "soak":
			return true
		sequence += 1
	return false

func snapshot() -> Dictionary:
	var screen = ScreenController.currentScreen
	if not screen is GameScreen:
		return {"in_game": false}
	var context: GameContext = screen._gameContext
	var hub: HubController = screen._gameInput
	var items := {}
	for index in range(30):
		var stack := context.playerInventory.GetSlot(index)
		if stack.quantity > 0:
			items[str(index + 1)] = [stack.item.index, stack.quantity, stack.equipped]
	var character = screen._gameWorld.GetCharacter(screen._mainCharacterInstanceId)
	var result := {"in_game": true, "name": hub.get_node("%LblName").text, "map": context.player_map, "gold": context.player_gold,
		"hp": context.player_stats.hp, "mana": context.player_stats.mana,
		"level": context.player_level, "experience": context.player_experience,
		"items": items, "console": hub._consoleRichTextLabel.get_parsed_text(),
		"spells": Array(hub.spell_list_panel._spell_ids), "target": hub._target_spell_slot,
		"x": character.gridPosition.x, "y": character.gridPosition.y,
		"appearance": [character.renderer.body, character.renderer.head],
		"panel": "", "characters": screen._gameWorld.get_child_count(),
		"capabilities": ClientInterface.capabilities.enabled, "trading": context.trading,
		"using_skill": context.usingSkill, "world_characters": {},
		"modals": hub._VisibleModals().map(func(w): return w.name)}
	for visible_character in screen._gameWorld.GetMapContainer()._characterCollection:
		result.world_characters[str(visible_character.instanceId)] = [visible_character.gridPosition.x,
			visible_character.gridPosition.y, visible_character.renderer.body, visible_character.renderer.head]
	if is_instance_valid(hub._currentPanel):
		var panel = hub._currentPanel
		if panel is PlayerTradePanel:
			result.panel = "trade"
			result.trade = panel.snapshot
		elif panel is MerchantPanel:
			result.panel = "merchant"
		elif panel is BankPanel:
			result.panel = "bank"
			result.bank_items = {}
			for index in panel._bankInventory.GetSize():
				var stack: ItemStack = panel._bankInventory.GetSlot(index)
				if stack.quantity > 0:
					result.bank_items[str(index + 1)] = [stack.item.index, stack.quantity]
			result.bank_info = {"name": panel._infoLabel.text, "range": panel._statLabel.text,
				"icon": panel._statIcon.texture.resource_path if panel._statRow.visible else "",
				"description": panel._statRow.tooltip_text}
		else:
			result.panel = str(panel)
	if is_instance_valid(hub._clan_details_window) and hub._clan_details_window.visible:
		result.clan_details = hub._clan_details_window.details.text
	result.world_states = ClientInterface.world_state.states.duplicate(true)
	for topic in hub._world_windows:
		var window: WorldStateWindow = hub._world_windows[topic]
		if is_instance_valid(window) and window.visible:
			result["world_window"] = topic
			result["world_window_state"] = window.state.duplicate(true)
			result["world_pending"] = window.pending()
			result["world_status"] = window.status.text
			if window is SocialWindow and topic == "clan": result.clan_details = window._summary.text
	if is_instance_valid(hub._currentPanel) and hub._currentPanel is PlayerTradePanel:
		result["trade_metadata_ready"] = hub._currentPanel._metadata_ready()
		result["trade_confirm_disabled"] = hub._currentPanel.confirm_button.disabled
	if is_instance_valid(hub._skills_window):
		result.skills = {"ready": not hub._skills_window.operation_id.is_empty(),
			"points": hub._skills_window.current_free_skills, "values": hub._skills_window.skill_values}
	return result

func click_tile(hub: HubController, tile: Vector2i, double_click := false) -> void:
	var world := (Vector2(tile) - Vector2(0.5, 0.5)) * 32.0
	var point := hub._camera.get_canvas_transform() * world
	if hub._target_spell_slot != 0:
		var container := hub.get_node("MainViewportContainer") as SubViewportContainer
		var viewport := hub.get_node("MainViewportContainer/Viewport") as SubViewport
		point *= container.size / Vector2(viewport.size)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	event.position = point
	hub._HandleMouseInput(event)

func execute(command: Dictionary) -> bool:
	if command.op == "create":
		var login = ScreenController.currentScreen
		var original := login.get_instance_id()
		login._loginPanel.get_node("%Reg").pressed.emit()
		if not await host.wait_for(func(): return ScreenController.currentScreen.get_instance_id() != original, "R10 alta de ciudad"):
			return false
		await host.get_tree().process_frame
		var creation = ScreenController.currentScreen
		creation._usernameLineEdit.text = command.name
		creation._passwordLineEdit.text = OS.get_environment("PYAO_TEST_PASSWORD")
		creation._confirmPasswordLineEdit.text = OS.get_environment("PYAO_TEST_PASSWORD")
		creation._emailLineEdit.text = "fixture@example.invalid"
		creation._classOptionButton.select(int(command.job) - 1)
		creation._raceOptionButton.select(int(command.race) - 1)
		creation._genderOptionButton.select(int(command.gender))
		creation._homeOptionButton.select(int(command.home) - 1)
		creation._submitButton.pressed.emit()
		if not await host.wait_for(func(): return ScreenController.currentScreen is GameScreen, "R10 clase/raza/ciudad"):
			return false
		return await host.wait_for(func():
			var g = ScreenController.currentScreen
			return g._gameWorld.GetCharacter(g._mainCharacterInstanceId) != null and ClientInterface.capabilities.has_feature(ClientCapabilities.TARGETED_CAST),
			"R10 recursos de ciudad")
	if command.op == "logout":
		ClientInterface.DisconnectFromHost()
		return await host.wait_for(func(): return not ScreenController.currentScreen is GameScreen, "R10 logout")
	if command.op == "login":
		var login_started := Time.get_ticks_msec()
		var login = ScreenController.currentScreen
		login._loginPanel.get_node("%Username").text = OS.get_environment("PYAO_TEST_USERNAME")
		login._loginPanel.get_node("%Password").text = OS.get_environment("PYAO_TEST_PASSWORD")
		login._loginPanel.get_node("%Submit").pressed.emit()
		if not await host.wait_for(func(): return ScreenController.currentScreen is GameScreen, "R10 login"):
			return false
		print("R10_CAPABILITIES_LOGIN: tick=", Time.get_ticks_msec(), " deadline=", ClientInterface.capabilities._deadline_msec)
		var accepted: bool = await host.wait_for(func():
			var g = ScreenController.currentScreen
			if not g is GameScreen:
				return false
			return g._gameWorld.GetCharacter(g._mainCharacterInstanceId) != null and g._gameContext.player_stats.max_hp > 0 and ClientInterface.capabilities.has_feature(ClientCapabilities.TARGETED_CAST) and g._gameInput.get_node("%LblName").text == OS.get_environment("PYAO_TEST_USERNAME"),
			"R10 personaje y estadísticas")
		if accepted:
			print("R10_LOGIN_PERFORMANCE: ms=", Time.get_ticks_msec() - login_started)
		return accepted
	if not ScreenController.currentScreen is GameScreen:
		return false
	var game = ScreenController.currentScreen
	var hub: HubController = game._gameInput
	var inventory: InventoryContainer = hub._inventoryContainer
	match command.op:
		"capture":
			var capture := OS.get_environment("PYAO_TEST_SCREENSHOT")
			var label: String = command.get("label", "ui")
			if label.length() > 40 or not label.replace("-", "").is_valid_identifier(): return false
			if not capture.is_empty() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				if host.get_viewport().get_texture().get_image().save_png(capture.get_basename() + "-" + label + ".png") != OK: return false
		"world_open":
			hub.OpenWorldTopic(command.topic)
		"world_action":
			var window: WorldStateWindow = hub._world_windows.get(command.topic)
			if not is_instance_valid(window) or not window.visible: return false
			if window is SocialWindow:
				var button: Button
				match command.action:
					"create":
						window._name.text = command.get("name", "")
						window._description.text = "Ensayo aislado"
						button = window._create
					"invite":
						window._target.text = command.username
						button = window._invite
					"accept": button = window._accept
					"reject": button = window._reject
					"leave": button = window._leave
					_:
						window._selected_member = int(command.user)
						window._refresh_buttons()
						button = window._member_actions.get(command.action)
				if button == null or button.disabled: return false
				button.pressed.emit()
				if window._confirmation.visible: window._confirmation.confirmed.emit()
			else: return false
		"snapshot", "soak":
			pass
		"chat":
			while Time.get_ticks_msec() < last_chat_tick + 1000:
				await host.get_tree().process_frame
			last_chat_tick = Time.get_ticks_msec()
			hub._consoleInputLineEdit.show()
			hub._consoleInputLineEdit.grab_focus()
			hub._consoleInputLineEdit.text = command.text
			hub._consoleInputLineEdit.text_submitted.emit(command.text)
		"close":
			if is_instance_valid(hub._currentPanel):
				hub._currentPanel.RequestClose()
			elif is_instance_valid(hub._clan_details_window):
				hub._clan_details_window.close_requested.emit()
			for window in hub.get_children():
				if window is Window and window.visible and not window.is_queued_for_deletion():
					window.close_requested.emit()
		"move":
			host.get_viewport().gui_release_focus()
			Input.action_press(command.action)
			await host.get_tree().create_timer(command.get("seconds", 0.15)).timeout
			Input.action_release(command.action)
		"step":
			var step_started := Time.get_ticks_msec()
			print("NAV_BEGIN: tick=", step_started)
			Global.log_outgoing_packets = true
			host.get_viewport().gui_release_focus()
			var actor = game._gameWorld.GetCharacter(game._mainCharacterInstanceId)
			while actor.isMoving: await host.get_tree().process_frame
			var previous: Vector2i = actor.gridPosition
			var previous_map: int = game._gameContext.player_map
			var deadline := Time.get_ticks_msec() + 2000
			Input.action_press(command.action)
			while is_instance_valid(actor) and actor.gridPosition == previous and game._gameContext.player_map == previous_map and Time.get_ticks_msec() < deadline:
				await host.get_tree().process_frame
			Input.action_release(command.action)
			if is_instance_valid(actor) and actor.gridPosition == previous and game._gameContext.player_map == previous_map: return false
			while is_instance_valid(actor) and actor.isMoving: await host.get_tree().process_frame
			print("NAV_STEP: elapsed_ms=", Time.get_ticks_msec() - step_started)
			# La animación y el reloj del servidor no comparten fase de frame.
			await host.get_tree().create_timer(0.25).timeout
			Global.log_outgoing_packets = false
		"equip", "use", "drop":
			# Respetar el intervalo del mismo gesto que usa el inventario real.
			var timer = game._gameContext.tick_intervals.timers[TickIntervals.ActionTimers.USE_ITEM_WITH_DOUBLE_CLICK]
			while Time.get_ticks_msec() <= timer.get_tick():
				await host.get_tree().process_frame
			inventory._InventorySlotOnPressed(int(command.slot) - 1)
			if command.op == "equip":
				hub._equip_object()
			elif command.op == "use":
				var cell := inventory.GetInventorySlot(int(command.slot) - 1)
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = cell.size / 2
				click.pressed = true
				cell._gui_input(click)
				click.pressed = false
				cell._gui_input(click)
			else:
				hub._drop_object()
				for window in game.get_children():
					if window is Window and window.get_script() != null and window.get_script().resource_path.ends_with("/drop_panel.gd"):
						window.drop(int(command.amount))
		"pickup":
			hub._pickup_object()
		"drag":
			inventory.DropItem(int(command.destination)-1, inventory.CreateDragData(int(command.source)-1))
		"click":
			click_tile(hub, Vector2i(command.x, command.y), command.get("double", false))
		"bank_select":
			if not hub._currentPanel is BankPanel:
				return false
			var panel: BankPanel = hub._currentPanel
			var container := panel._bankInventoryContainer if command.vault else panel._playerInventoryContainer
			container._InventorySlotOnPressed(int(command.slot) - 1)
			var capture := OS.get_environment("PYAO_TEST_SCREENSHOT")
			if command.get("capture", false) and not capture.is_empty() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				if host.get_viewport().get_texture().get_image().save_png(capture.get_basename() + "-bank.png") != OK:
					return false
		"bank_item", "bank_gold":
			if not hub._currentPanel is BankPanel:
				return false
			var panel: BankPanel = hub._currentPanel
			if command.op == "bank_gold":
				panel._quantityGoldSpinBox.value = command.amount
				if command.deposit:
					panel._on_btn_deposit_gold_pressed()
				else:
					panel._on_btn_extract_gold_pressed()
			else:
				panel._quantitySpinBox.value = command.amount
				if command.deposit:
					panel._playerInventoryContainer._InventorySlotOnPressed(int(command.slot) - 1)
					panel._on_btn_deposit_pressed()
				else:
					panel._bankInventoryContainer._InventorySlotOnPressed(int(command.slot) - 1)
					panel._on_btn_extract_pressed()
		"merchant":
			if not hub._currentPanel is MerchantPanel:
				return false
			var panel: MerchantPanel = hub._currentPanel
			panel._Select(int(command.slot) - 1, "buy" if command.buy else "sell")
			panel._quantitySpinBox.value = command.amount
			panel._actionButton.pressed.emit()
		"trade":
			if not hub._currentPanel is PlayerTradePanel:
				return false
			var panel: PlayerTradePanel = hub._currentPanel
			match command.action:
				"accept": panel.accept_button.pressed.emit()
				"gold":
					panel.gold.value = command.amount
					panel.gold_button.pressed.emit()
				"item":
					panel.slot.value = command.slot
					panel.quantity.value = command.amount
					panel.item_button.pressed.emit()
				"confirm": panel.confirm_button.pressed.emit()
				"cancel": panel.cancel_button.pressed.emit()
		"attack":
			host.get_viewport().gui_release_focus()
			var intervals: TickIntervals = game._gameContext.tick_intervals
			var deadline := 0
			for key in [TickIntervals.ActionTimers.ATTACK, TickIntervals.ActionTimers.ATTACK_WITH_BOW, TickIntervals.ActionTimers.SPELL_ATTACK]:
				deadline = maxi(deadline, intervals.timers[key].get_tick())
			while Time.get_ticks_msec() <= deadline:
				await host.get_tree().process_frame
			hub._attack()
		"cast", "cancel_cast":
			host.get_viewport().gui_release_focus()
			var intervals: TickIntervals = game._gameContext.tick_intervals
			var deadline := 0
			for key in [TickIntervals.ActionTimers.SPELL, TickIntervals.ActionTimers.ATTACK_WITH_BOW, TickIntervals.ActionTimers.ATTACK_SPELL]:
				deadline = maxi(deadline, intervals.timers[key].get_tick())
			while Time.get_ticks_msec() <= deadline:
				await host.get_tree().process_frame
			hub.spell_list_panel._item_list.select(int(command.slot) - 1)
			hub.spell_list_panel._on_btn_cast_pressed()
			if command.op == "cancel_cast":
				var escape := InputEventKey.new()
				escape.keycode = KEY_ESCAPE
				escape.pressed = true
				hub._input(escape)
			else:
				click_tile(hub, Vector2i(command.x, command.y))
		"work":
			host.get_viewport().gui_release_focus()
			if game._gameContext.usingSkill != int(command.skill):
				return false
			var timer = game._gameContext.tick_intervals.timers[TickIntervals.ActionTimers.WORK]
			while Time.get_ticks_msec() <= timer.get_tick():
				await host.get_tree().process_frame
			click_tile(hub, Vector2i(command.x, command.y))
		"move_spell":
			hub.spell_list_panel._item_list.select(int(command.slot) - 1)
			hub.spell_list_panel._on_btn_move_down_pressed()
		"skills_open":
			hub._btnSkills.pressed.emit()
		"skills_allocate":
			if not is_instance_valid(hub._skills_window):
				return false
			for i in range(int(command.amount)):
				hub._skills_window._on_plus_pressed(int(command.skill)-1)
			hub._skills_window.accept_button.pressed.emit()
		_:
			return false
	await host.get_tree().process_frame
	return true
