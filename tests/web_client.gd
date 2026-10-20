extends Node

# Sólo se activa con el parámetro explícito de aceptación. Las credenciales de
# prueba llegan en memoria desde Playwright; nunca se escriben ni se imprimen.
var context: Dictionary

func report(value: Dictionary) -> void:
	JavaScriptBridge.eval("window.PYAO_PROOF = " + JSON.stringify(value), true)

func wait_for(predicate: Callable, label: String) -> bool:
	var until := Time.get_ticks_msec() + 30000
	while not predicate.call():
		if Time.get_ticks_msec() > until:
			report({"passed": false, "error": label})
			return false
		await get_tree().process_frame
	return true

func preferences() -> bool:
	Global.dialogFontSize = 14
	if Global.save_preferences() != OK: return false
	var config := ConfigFile.new()
	WebPreferences.load_config(config, "user://options.cfg")
	config.set_value("future", "unknown_option", "preserved")
	WebPreferences.save_config(config, "user://options.cfg")
	if Global.save_preferences() != OK: return false
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F8
	if InputBindings.assign(&"Attack", key) != OK: return false
	if SavedCredentials.save_username(context.username) != OK: return false
	WebPreferences.select_endpoint("wss://other-server.example.invalid:7668")
	var separated := Global.dialogFontSize == 12 and SavedCredentials.load_username().is_empty()
	WebPreferences.select_endpoint(context.endpoint)
	return separated and persisted()

func persisted() -> bool:
	var config := ConfigFile.new()
	var loaded := WebPreferences.load_config(config, "user://options.cfg")
	return loaded == OK and Global.dialogFontSize == 14 and SavedCredentials.load_username() == context.username and InputBindings.encode(InputMap.action_get_events(&"Attack")[0]).get("physical") == KEY_F8 and config.get_value("future", "unknown_option") == "preserved"

func _ready() -> void:
	await get_tree().process_frame
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.PYAO_TEST_CONTEXT || {})", true)
	var parsed: Variant = JSON.parse_string(str(raw))
	if not parsed is Dictionary or not parsed.get("endpoint", "").begins_with("wss://"):
		report({"passed": false, "error": "Contexto de prueba inválido"})
		return
	context = parsed
	WebPreferences.select_endpoint(context.endpoint)
	if context.get("mode") == "persistence":
		report({"passed": persisted(), "preferences": persisted(), "reloaded": true})
		return
	if context.get("mode") == "storage_blocked":
		Global.dialogFontSize = 14
		var saved := Global.save_preferences() == OK
		Global.reload_preferences()
		report({"passed": saved and Global.dialogFontSize == 14 and not WebPreferences.last_error.is_empty(), "session_fallback": saved, "visible_warning": not WebPreferences.last_error.is_empty()})
		return
	JavaScriptBridge.eval("window.PYAO_AUDIO_READY = true", true)
	if not await wait_for(func(): return JavaScriptBridge.eval("window.PYAO_AUDIO_CLICKED === true", true), "Gesto real para iniciar audio web"): return
	var login := ScreenController.currentScreen
	login.get_node("%Ip").text = context.endpoint
	login.get_node("%CaPath").text = ""
	login._loginPanel.get_node("%Reg").pressed.emit()
	var login_id: int = login.get_instance_id()
	if not await wait_for(func(): return ScreenController.currentScreen.get_instance_id() != login_id, "Alta por WSS"): return
	await get_tree().process_frame
	var creation := ScreenController.currentScreen
	creation._usernameLineEdit.text = context.username
	creation._passwordLineEdit.text = context.password
	creation._confirmPasswordLineEdit.text = context.password
	creation._emailLineEdit.text = "browser@example.invalid"
	creation._classOptionButton.select(0)
	creation._raceOptionButton.select(0)
	creation._genderOptionButton.select(0)
	creation._homeOptionButton.select(0)
	# Simular un cuadro lento durante el primer mapa: JS recibe toda la ráfaga
	# de login aunque Godot todavía no pueda drenar WebSocketPeer.
	ClientInterface.set_process(false)
	creation._submitButton.pressed.emit()
	await get_tree().create_timer(2.0).timeout
	ClientInterface.set_process(true)
	context.erase("password")
	JavaScriptBridge.eval("delete window.PYAO_TEST_CONTEXT.password", true)
	if not await wait_for(func(): return ScreenController.currentScreen is GameScreen, "Login por WSS"): return
	var game := ScreenController.currentScreen as GameScreen
	if not await wait_for(func(): return game._gameContext.player_map > 0 and game._gameWorld.GetCharacter(game._mainCharacterInstanceId) != null and game._gameContext.playerInventory.GetSlot(0).quantity > 0, "Mapa e inventario web"):
		var quantities: Array[int] = []
		for index in game._gameContext.playerInventory.GetSize(): quantities.append(game._gameContext.playerInventory.GetSlot(index).quantity)
		report({"passed": false, "error": "Mapa e inventario web", "map": game._gameContext.player_map, "actor_id": game._mainCharacterInstanceId, "actor_present": game._gameWorld.GetCharacter(game._mainCharacterInstanceId) != null, "quantities": quantities})
		return
	var actor = game._gameWorld.GetCharacter(game._mainCharacterInstanceId)
	var before: Vector2i = actor.gridPosition
	for action in ["ui_right", "ui_down", "ui_left", "ui_up"]:
		Input.action_press(action)
		await get_tree().create_timer(0.2).timeout
		Input.action_release(action)
		await get_tree().create_timer(0.15).timeout
		if actor.gridPosition != before: break
	var movement: bool = actor.gridPosition != before
	var saved := preferences()
	var audio := await AudioPlaybackProbe.played(self)
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image().get_width() >= 640
	var secure := ClientInterface._websocket != null and ClientInterface.IsConnected()
	report({"passed": secure and saved and movement and audio and rendered, "login": secure, "preferences": saved, "input": movement, "audio": audio, "audio_driver": AudioServer.get_driver_name(), "user_activation": JavaScriptBridge.eval("navigator.userActivation.hasBeenActive", true), "rendering": rendered, "wss": secure, "map": game._gameContext.player_map, "slots": game._gameInput._inventoryContainer.get_child_count(), "profile": ClientInterface.local_character_key(context.username)})
