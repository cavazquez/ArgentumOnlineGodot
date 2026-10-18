extends Node

# Este driver usa pantallas, señales, Input e inventario reales. No simula la red.
var failed := false
var moved := false
var peer_chat_seen := false

func wait_for(predicate: Callable, label: String, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			failed = true
			push_error("INTEGRATION_WORLD: plazo agotado: " + label)
			get_tree().quit(1)
			return false
		await get_tree().process_frame
	return true

func _ready() -> void:
	print("R10_NATIVE: ", OS.has_feature("r10_acceptance"))
	ClientInterface.capabilities_changed.connect(func():
		print("R10_CAPABILITIES: tick=", Time.get_ticks_msec(), " enabled=", ClientInterface.capabilities.enabled))
	var password := OS.get_environment("PYAO_TEST_PASSWORD")
	if password.is_empty():
		push_error("El harness requiere una credencial efímera por entorno")
		get_tree().quit(1)
		return
	var login = load("res://screens/login_screen.tscn").instantiate()
	ScreenController.SwitchScreen(login)
	await get_tree().process_frame
	login.get_node("%Ip").text = "127.0.0.1"
	login.get_node("%Port").value = int(OS.get_environment("PYAO_TEST_PORT"))
	login.get_node("%UseTLS").button_pressed = true
	login.get_node("%CaPath").text = OS.get_environment("PYAO_TEST_CA")
	login._loginPanel.get_node("%Reg").pressed.emit()
	var login_id: int = login.get_instance_id()
	if not await wait_for(func(): return ScreenController.currentScreen.get_instance_id() != login_id, "pantalla de alta"):
		return
	await get_tree().process_frame
	var creation = ScreenController.currentScreen
	creation._usernameLineEdit.text = OS.get_environment("PYAO_TEST_USERNAME")
	creation._passwordLineEdit.text = password
	creation._confirmPasswordLineEdit.text = password
	creation._emailLineEdit.text = "fixture@example.invalid"
	creation._classOptionButton.select(0)
	creation._raceOptionButton.select(0)
	creation._genderOptionButton.select(0)
	creation._homeOptionButton.select(0)
	creation._submitButton.pressed.emit()
	password = ""
	if not await wait_for(func(): return ScreenController.currentScreen is GameScreen, "alta y login"):
		return
	var game = ScreenController.currentScreen as GameScreen
	if not await wait_for(func(): return game._gameContext.player_map > 0 and game._gameWorld.GetCharacter(game._mainCharacterInstanceId) != null and game._gameContext.playerInventory.GetSlot(0).quantity > 0, "mapa, personaje e inventario"):
		return
	var hub: HubController = game._gameInput
	var inventory: InventoryContainer = hub._inventoryContainer
	if inventory.get_child_count() != 30:
		push_error("INTEGRATION_WORLD: inventario incompleto")
		get_tree().quit(1)
		return
	var item_id: int = game._gameContext.playerInventory.GetSlot(0).item.index
	inventory.GetInventorySlot(0).pressed.emit()
	inventory.DropItem(29, inventory.CreateDragData(0))
	if not await wait_for(func(): return game._gameContext.playerInventory.GetSlot(29).item.index == item_id, "ACK de inventario en slot 30"):
		return
	print("INTEGRATION_WORLD: READY map=", game._gameContext.player_map, " slots=30 tls=true")
	if not OS.get_environment("PYAO_TEST_CONTROL").is_empty():
		var scenario = load("res://tests/r10_client.gd").new()
		if not await scenario.run(self):
			return
		game = ScreenController.currentScreen as GameScreen
		hub = game._gameInput
	if DisplayServer.get_name() != "headless" and not OS.get_environment("PYAO_TEST_SCREENSHOT").is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("PYAO_TEST_SCREENSHOT"))
	var duration := maxi(10, int(OS.get_environment("PYAO_TEST_DURATION")))
	var hunger_before := [hub.hunger_stat_bar.value, hub.thirst_stat_bar.value]
	var started := Time.get_ticks_msec()
	var until := started + duration * 1000
	var actions := ["ui_right", "ui_down", "ui_left", "ui_up"]
	var sequence := 0
	while Time.get_ticks_msec() < until:
		if not ClientInterface.IsConnected() or not is_instance_valid(game) or game._gameContext.player_stats.hp <= 0:
			push_error("INTEGRATION_WORLD: sesión o personaje perdido")
			get_tree().quit(1)
			return
		var character = game._gameWorld.GetCharacter(game._mainCharacterInstanceId)
		var before: Vector2i = character.gridPosition
		Input.action_press(actions[sequence % actions.size()])
		await get_tree().create_timer(0.35).timeout
		Input.action_release(actions[sequence % actions.size()])
		await get_tree().create_timer(0.35).timeout
		moved = moved or character.gridPosition != before
		hub._consoleInputLineEdit.show()
		hub._consoleInputLineEdit.grab_focus()
		hub._consoleInputLineEdit.text = "pyao-integration-" + OS.get_environment("PYAO_TEST_INDEX")
		hub._consoleInputLineEdit.text_submitted.emit(hub._consoleInputLineEdit.text)
		await get_tree().create_timer(1.0).timeout
		peer_chat_seen = peer_chat_seen or hub._consoleRichTextLabel.get_parsed_text().contains("pyao-integration-" + OS.get_environment("PYAO_TEST_PEER"))
		sequence += 1
		print("INTEGRATION_WORLD: HEARTBEAT seconds=", (Time.get_ticks_msec() - started) / 1000, " movement=", moved, " peer_chat=", peer_chat_seen)
		await get_tree().create_timer(minf(18.0, maxf(0.0, float(until - Time.get_ticks_msec()) / 1000.0))).timeout
	if not moved or not peer_chat_seen:
		push_error("INTEGRATION_WORLD: falta movimiento o chat entre pares")
		get_tree().quit(1)
		return
	var expected_slots: Dictionary = {}
	for slot in range(30):
		var stack: ItemStack = game._gameContext.playerInventory.GetSlot(slot)
		if stack.quantity > 0:
			expected_slots[slot] = [stack.item.index, stack.quantity, stack.equipped]
	var expected_spells: Array = Array(hub.spell_list_panel._spell_ids).duplicate()
	var hunger_after := [hub.hunger_stat_bar.value, hub.thirst_stat_bar.value]
	if duration >= 1800 and (hunger_after[0] >= hunger_before[0] or hunger_after[1] >= hunger_before[1]):
		push_error("INTEGRATION_WORLD: hambre/sed configuradas no progresaron en 30 minutos")
		get_tree().quit(1)
		return
	ClientInterface.DisconnectFromHost()
	if not await wait_for(func(): return not ScreenController.currentScreen is GameScreen, "desconexión"):
		return
	await get_tree().process_frame
	login = ScreenController.currentScreen
	login._loginPanel.get_node("%Username").text = OS.get_environment("PYAO_TEST_USERNAME")
	login._loginPanel.get_node("%Password").text = OS.get_environment("PYAO_TEST_PASSWORD")
	# El runner confirma en Redis que terminó la limpieza de esta conexión.
	print("INTEGRATION_WORLD: RECONNECT_WAIT")
	if not await wait_for(func(): return FileAccess.file_exists(OS.get_environment("PYAO_TEST_RELEASED")), "liberación de sesión anterior"):
		return
	login._loginPanel.submit.emit()
	if not await wait_for(func(): return ScreenController.currentScreen is GameScreen, "segundo login"):
		return
	game = ScreenController.currentScreen as GameScreen
	if not await wait_for(func():
		for slot in range(30):
			var stack: ItemStack = game._gameContext.playerInventory.GetSlot(slot)
			var actual: Array = [stack.item.index, stack.quantity, stack.equipped] if stack.quantity > 0 else []
			if actual != expected_slots.get(slot, []):
				return false
		if Array(game._gameInput.spell_list_panel._spell_ids) != expected_spells:
			return false
		if ClientInterface.capabilities.enabled != ClientCapabilities.REQUESTED:
			return false
		return not game._gameInput._consoleRichTextLabel.get_parsed_text().is_empty() and game._gameInput.minimap.texture != null,
		"objetos, cantidades, equipo, libro ordenado, consola y minimapa tras reconectar"):
		return
	print("INTEGRATION_WORLD: RECONNECT_STATE ", JSON.stringify({"inventory": expected_slots,
		"spells": expected_spells, "hunger_before": hunger_before, "hunger_after": hunger_after,
		"capabilities": ClientInterface.capabilities.enabled,
		"exact_inventory_and_spell_order": true}))
	ClientInterface.DisconnectFromHost()
	print("INTEGRATION_WORLD: PASS seconds=", (Time.get_ticks_msec() - started) / 1000)
	get_tree().quit(0)
