extends Node

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error("ECONOMY_UI_SMOKE: " + message)

func _ready() -> void:
	_run.call_deferred()

func _frame(sequence: int, revision: int, wallet: int) -> Dictionary:
	return {"epoch": "a".repeat(32), "sequence": sequence, "kind": "tax", "id": "", "revision": str(revision), "data": {"wallet": wallet, "bank": 200, "money_revision": revision, "rate_bps": 100, "enabled": true, "scope": "wallet_and_bank", "last_day": 20000, "from_day": 19999, "last_charge": 3, "total_paid": 3, "receipt": "synthetic", "next_cutoff": 1728086400}}

func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func _run() -> void:
	await get_tree().process_frame
	var equipment_scene := preload("res://screens/game_screen.tscn").instantiate()
	var equipment_hub: HubController = equipment_scene.get_node("HubController")
	for row in [[Enums.eOBJType.eOBJType_otESCUDO, "LblShield"], [Enums.eOBJType.eOBJType_otCASCO, "LblHelmet"], [Enums.eOBJType.eOBJType_otArmadura, "LblArmor"], [Enums.eOBJType.eOBJType_otWeapon, "LblWeapon"]]:
		var item := Item.new()
		item.type = row[0]
		item.minHit = 3
		item.maxHit = 7
		item.minDef = 3
		item.maxDef = 7
		var stack := ItemStack.new(1, true, item)
		equipment_hub.update_equipment_label(0, stack)
		check(equipment_hub.get_node("%" + row[1]).text == "3/7", "No muestra el rango del equipo en el primer slot")
		stack.equipped = false
		equipment_hub.update_equipment_label(0, stack)
		check(equipment_hub.get_node("%" + row[1]).text == "0/0", "Desequipar el primer slot deja stats de otro tipo")
	var original_cursor := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	for cycle in range(32):
		var scaled: Texture2D = equipment_scene._scale_cursor(original_cursor, 0.5)
		check(scaled != null and scaled.get_size() == Vector2(4, 4), "Repetir login reduce el cursor compartido")
		check(original_cursor.get_image().get_size() == Vector2i(8, 8), "Escalar modifica la imagen original")
	var tiny := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	check(equipment_scene._scale_cursor(tiny, 0.1).get_size() == Vector2(1, 1), "Un cursor pequeño genera una imagen de cero píxeles")
	equipment_scene.free()
	var context := WorldStateContext.new()
	check(context.accept(_frame(1, 2, 300)), "Rechaza el saldo inicial")
	check(not context.accept(_frame(2, 1, 100)) and context.states.tax.wallet == 300, "Una lectura vieja pisa un movimiento nuevo")
	var foreign := _frame(3, 3, 900)
	foreign.epoch = "b".repeat(32)
	check(not context.accept(foreign), "Acepta una generación ajena")
	context.clear()
	check(context.accept(foreign), "Reconectar no libera la generación anterior")
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/fixtures.json"))
	for fixture in fixtures:
		if fixture.name != "world_party_unicode": continue
		var reader := StreamPeerBuffer.new()
		reader.data_array = String(fixture.hex).hex_decode().slice(1)
		var packet := WorldStatePacket.new(reader)
		check(packet.valid and packet.data.data.members[0].name == "Peña", "Frame compartido pierde acentos o tipos")
	var reader := StreamPeerBuffer.new()
	var malformed := _frame(1, 1, 100)
	malformed.data.money_revision = 1.5
	var text := JSON.stringify(malformed).to_ascii_buffer()
	reader.put_u8(1)
	reader.put_u16(text.size())
	reader.put_data(text)
	reader.seek(0)
	check(not WorldStatePacket.new(reader).valid, "Acepta revisiones fraccionales")
	var trade_panel := PlayerTradePanel.new()
	var animated_icon := false
	for graphic in GameAssets.GrhDataList.size():
		var data: GrhData = GameAssets.GrhDataList[graphic]
		if data == null or data.frameCount <= 1 or data.frames.size() < 2 or data.frames[1] <= 0: continue
		var icon := trade_panel._icon({"graphic": graphic}) as AtlasTexture
		check(icon != null and icon.atlas != null and icon.region == GameAssets.GrhDataList[data.frames[1]].region, "El intercambio usa el índice cero reservado de una animación")
		animated_icon = true
		break
	check(animated_icon, "No se validó ningún gráfico animado del catálogo propio")
	trade_panel.free()
	ClientInterface.capabilities.begin()
	check(ClientInterface.capabilities.accept(PackedByteArray([250, 1, 191, 3, 0, 0])), "No negocia las extensiones nuevas")
	ClientInterface.world_state.clear()
	ClientInterface.world_state.accept(_frame(1, 1, 100))
	var social := SocialWindow.new("party")
	add_child(social)
	var party := {"user": 1, "party_id": 7, "leader": 1, "permissions": ["leave", "invite", "kick", "leader"], "members": [{"id": 1, "name": "Alice", "level": 20, "online": true, "hp": 100, "max_hp": 100, "map": 1}, {"id": 2, "name": "Bob", "level": 10, "online": true, "hp": 50, "max_hp": 100, "map": 1}], "invitations": []}
	social._receive("party", party, "r1")
	social._selected_member = 2
	social._refresh_buttons()
	check(not social._member_actions.kick.disabled, "El líder no puede administrar")
	GameProtocol.Clear()
	social.request_state()
	check(social.pending() and social._member_actions.kick.disabled, "La caché habilita acciones antes de recibir la consulta actual")
	social._receive("tax", {"wallet": 300}, "other")
	check(social.pending(), "Una respuesta ajena termina la consulta de grupo")
	social._receive("party", party, "r1")
	check(social.pending(), "Una respuesta de otra consulta libera datos guardados")
	social._read_deadline = Time.get_ticks_msec() - 1
	social._process(0)
	check(social.pending() and social._member_actions.kick.disabled, "El timeout habilita acciones con estado viejo")
	GameProtocol.Clear()
	social.mutate("party.kick", {"username": "Bob"})
	check(GameProtocol.Flush().is_empty(), "Se ejecuta una mutación durante la lectura pendiente")
	ClientInterface.world_state.response_ids["party"] = social._read_id
	social._receive("party", party, "r1")
	check(not social.pending(), "La respuesta fresca no libera la ventana")
	social._selected_member = 2
	social._refresh_buttons()
	check(not social._member_actions.kick.disabled, "La respuesta fresca no restaura las acciones permitidas")
	social._pending = {"id": "confirmed"}
	social._receive("result", {"id": "confirmed", "applied": true, "message": "Confirmado"}, "")
	check(social.pending() and social._member_actions.kick.disabled, "El resultado habilita acciones antes del estado confirmado")
	ClientInterface.world_state.response_ids["party"] = ""
	social._receive("party", party, "r1")
	check(not social.pending(), "El estado posterior a la mutación deja la ventana bloqueada")
	social.confirm_action("party.kick", {"username": "Bob"}, "Expulsar")
	party.permissions = ["leave"]
	party.leader = 2
	social._receive("party", party, "r2")
	GameProtocol.Clear()
	social._confirm()
	check(GameProtocol.Flush().is_empty() and social._member_actions.kick.disabled, "Una confirmación vieja ejecuta permisos revocados")
	social.mutate("party.invite", {"username": "名字"})
	check(not social.pending() and GameProtocol.Flush().is_empty(), "Un texto rechazado localmente deja una operación bloqueada")
	social.queue_free()
	var finder := ExpansionWindow.new("finder")
	add_child(finder)
	ClientInterface.capabilities.enabled |= ClientCapabilities.EXPANSION
	finder._receive("finder", {"rows": [], "requests": [], "leader": true}, "r1")
	finder.request_state()
	check(finder.pending(), "El buscador no espera su lectura fresca")
	finder._receive("reset", {}, "")
	check(not finder.pending() and finder.state.is_empty(), "Desconectar conserva una lectura pendiente")
	finder.queue_free()
	var line := LineEdit.new()
	add_child(line)
	var helper := ChatInputHelper.new()
	helper.install(line)
	helper.record("hola")
	helper.record("/PASSWORD no-guardar-esto")
	line.text = "borrador"
	helper._input(_key(KEY_UP))
	check(line.text == "hola", "Arriba no recupera el mensaje")
	helper._input(_key(KEY_DOWN))
	check(line.text == "borrador" and helper.history.size() == 1, "Pierde el borrador o guarda secretos")
	helper._state_changed("commands", {"commands": [{"text": "/PARTY", "syntax": "/PARTY nombre"}]}, "r")
	line.text = "/pa Bob"
	helper._changed(line.text)
	GameProtocol.Clear()
	helper._input(_key(KEY_TAB))
	check(line.text == "/PARTY Bob" and GameProtocol.Flush().is_empty(), "Completar envía un comando o borra argumentos")
	helper.clear()
	check(helper.history.is_empty(), "Reconectar conserva el historial")
	line.queue_free()
	var local := CharacterLocalState.new()
	local.open_profile("1".repeat(64))
	local.visit(1)
	local.visit(32000)
	local.open_profile("2".repeat(64))
	check(local.visited.is_empty(), "Se mezclan personajes o servidores")
	local.open_profile("1".repeat(64))
	check(local.visited.has(1) and not local.visited.has(32000), "Pierde la visita o admite IDs desconocidos")
	var file := FileAccess.open("user://characters/%s.json" % "3".repeat(64), FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	local.open_profile("3".repeat(64))
	check(local.visited.is_empty(), "Archivo corrupto bloquea el perfil")
	var character: Character = preload("res://engine/character/character.tscn").instantiate()
	add_child(character)
	Global.animateDialogs = true
	character.Say("¡Caña y pingüino!", Color.GREEN)
	check(character._dialog_revealing, "No anima los acentos")
	Global.animateDialogs = false
	check(not character._dialog_revealing and character._dialogLabel.text == "¡Caña y pingüino!", "Desactivar pierde el texto")
	character.ClearDialog()
	check(character._dialogLabel.text.is_empty() and character._dialogClearTimer.is_stopped(), "Limpiar deja un timer vivo")
	character.FadeIn()
	character.SetCharacterInvisible(true)
	check(not character.renderer.visible, "El fade revela a un personaje invisible")
	character.queue_free()
	var host := Control.new()
	host.size = Vector2(920, 520)
	add_child(host)
	var presentation := WorldPresentation.new()
	host.add_child(presentation)
	presentation.begin(1)
	Global.rainIntensity = 1
	presentation.apply_weather({"map": 1, "outdoor": true, "raining": true, "intensity": 80})
	var audio := presentation._audio
	presentation.apply_weather({"map": 1, "outdoor": true, "raining": true, "intensity": 80})
	check(audio == presentation._audio and audio.playing, "Repetir lluvia crea voces o invierte el estado")
	presentation.begin(42)
	presentation.apply_weather({"map": 1, "outdoor": true, "raining": true, "intensity": 80})
	check(not audio.playing and presentation._rain_target == 0.0, "Queda lluvia del mapa anterior")
	presentation.apply_weather({"map": 42, "outdoor": false, "raining": false, "intensity": 0})
	Global.peripheralFog = 0.4
	host.size = Vector2(640, 480)
	await get_tree().process_frame
	check(presentation.size == host.size and presentation.mouse_filter == Control.MOUSE_FILTER_IGNORE, "El resize o la niebla altera la geometría del viewport")
	presentation.reset()
	check(not presentation.waiting and not audio.playing, "Desconectar deja efectos pendientes")
	host.queue_free()
	var crafting := CraftingWindow.new()
	add_child(crafting)
	crafting.open_skill("carpinteria")
	var identity := crafting._pending_id
	crafting.invalidate_context()
	crafting.apply_result({"id": identity, "applied": true, "kind": "recipes", "page": 0, "recipes": [{"id": "synthetic", "name": "Banco", "required": 1, "materials": [], "success_rate": 100}], "has_next": false})
	check(crafting._craft.disabled and not crafting.visible, "Una respuesta tardía reactiva fabricar lejos de la estación")
	crafting.queue_free()
	GameProtocol.Clear()
	ClientInterface.world_state.clear()
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 2000
	while not AudioManager.IsDrained() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(AudioManager.IsDrained(), "El mixer retiene la lluvia después de cerrar")
	print("ECONOMY_UI_SMOKE: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
