extends Node

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _ready() -> void:
	var contract = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/contract.json"))
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/fixtures.json"))
	var by_name := {}
	check(contract.inventory_slots == 30, "El contrato debe conservar 30 slots")
	for fixture in fixtures:
		var bytes: PackedByteArray = fixture.hex.hex_decode()
		by_name[fixture.name] = bytes
		var reader := StreamPeerBuffer.new()
		reader.data_array = bytes
		var id := reader.get_u8()
		var packet = contract.directions[fixture.direction][str(id)]
		var fields: Array = packet.fields.duplicate()
		if packet.has("variants"): fields.append_array(packet.variants[str(bytes[1])])
		for field in fields:
			var value
			match field.type:
				"u8": value = reader.get_u8()
				"i16": value = reader.get_16()
				"i32": value = reader.get_32()
				"u32": value = reader.get_u32()
				"f32": value = reader.get_float()
				"str16":
					var length := reader.get_u16()
					value = reader.get_data(length)[1].get_string_from_ascii()
			if fixture.values.has(field.name):
				check(value == fixture.values[field.name], fixture.name + ": campo " + field.name)
		check(reader.get_available_bytes() == 0, fixture.name + ": bytes sobrantes")
	_verify_framing(fixtures)
	var mini_reader := StreamPeerBuffer.new()
	mini_reader.data_array = by_name.mini_stats
	mini_reader.seek(1)
	var mini := MiniStats.new(mini_reader)
	check(mini.Muertes == 9 and mini.NpcsMatados == 70000 and mini.PenaCarcel == 2, "MiniStats debe separar muertes, bajas y días sin truncar")
	GameProtocol.Clear()
	GameProtocol.WriteLoginExistingCharacter("Peña", "cláve1")
	check(GameProtocol.Flush() == by_name.login_latin1, "Writer de login difiere de la fixture")
	GameProtocol.WriteLoginNewChar("Peña", "cláve1", "test@example.invalid", 1, 1, 1, 1, 1)
	check(GameProtocol.Flush() == by_name.create_latin1, "Writer de alta difiere de la fixture")
	GameProtocol.WriteWalk(1)
	check(GameProtocol.Flush() == by_name.walk, "Writer WALK difiere de la fixture")
	GameProtocol.WriteDoubleClick(50, 51)
	check(GameProtocol.Flush() == by_name.double_click, "Writer DOUBLE_CLICK difiere de la fixture")
	for slot in [25, 26, 30]:
		var reader := StreamPeerBuffer.new()
		reader.data_array = by_name["inventory_" + str(slot)]
		reader.get_u8()
		var update := ChangeInventorySlot.new(reader)
		check(update.slot == slot and update.name == "Poción", "Reader inventario incompatible")
		check(reader.get_available_bytes() == 0, "Reader inventario dejó bytes pendientes")
	_verify_skills(by_name)
	_verify_text_policy()
	_verify_capabilities()
	_verify_drag()
	_verify_inventory()
	_verify_password_change(by_name)
	_verify_allocation(by_name)
	_verify_clan_details(by_name)
	_verify_minimap()
	_verify_chat_text()
	_verify_targeting(by_name)
	_verify_spellbook_order()
	_verify_trade()
	_verify_ui()
	_verify_screen_handoff()
	_verify_receive_reconnection()
	print("PROTOCOL_SMOKE: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)

func _verify_framing(fixtures: Array) -> void:
	for fixture in fixtures:
		if fixture.direction != "server":
			continue
		var bytes: PackedByteArray = fixture.hex.hex_decode()
		for split in range(1, bytes.size()):
			var framer := AOPacketFramer.new()
			check(framer.feed(bytes.slice(0, split)).is_empty(), "Entrega anticipada " + fixture.name)
			var suffix := bytes.slice(split)
			suffix.append(88)
			var packets := framer.feed(suffix)
			check(packets.size() == 2 and packets[0] == bytes and packets[1] == PackedByteArray([88]), "Frontera inválida " + fixture.name)
		var bytewise := AOPacketFramer.new()
		var count := 0
		for value in bytes:
			count += bytewise.feed(PackedByteArray([value])).size()
		check(count == 1 and bytewise.pending_size() == 0, "Reensamblado byte a byte " + fixture.name)
	for invalid in [PackedByteArray([249]), PackedByteArray([24, 255, 255]), PackedByteArray([104, 255])]:
		var framer := AOPacketFramer.new()
		check(framer.feed(invalid).is_empty() and not framer.error.is_empty(), "Se aceptó ID, longitud o subtipo inválido")
	var large := PackedByteArray()
	large.resize(10000)
	large.fill(88)
	check(AOPacketFramer.new().feed(large).size() == 10000, "Una lectura grande de PONG válidos fue rechazada")
	var partial := AOPacketFramer.new()
	partial.feed(PackedByteArray([0]))
	partial.clear()
	check(partial.pending_size() == 0 and partial.feed(PackedByteArray([88])).size() == 1, "Reconexión conserva bytes viejos")

func _verify_screen_handoff() -> void:
	ClientInterface._reset()
	var login = load("res://screens/login_screen.tscn").instantiate()
	ScreenController.SwitchScreen(login)
	ClientInterface._AcceptIncomingData(PackedByteArray([0, 1, 21, 1]))
	var game = ScreenController.currentScreen
	check(game is GameScreen, "Logged=0 no cambió a juego")
	check(game.networkMessages.size() == 1, "Logged se perdió o se duplicó")
	check(ClientInterface._framer.pending_size() == 2, "Se perdió el ChangeMap parcial en la transición")
	ClientInterface._AcceptIncomingData(PackedByteArray([0, 0, 0, 88]))
	check(ScreenController.currentScreen == game and game.networkMessages.size() == 3, "El login anterior recibió paquetes después del cambio")
	game._OnDisconnected()
	check(not game.is_processing() and game.networkMessages.is_empty(), "La pantalla desconectada sigue procesando mensajes")
	ScreenController.currentScreen.free()
	game.free()
	ScreenController.currentScreen = null
	ClientInterface._reset()

func _verify_receive_reconnection() -> void:
	ClientInterface._reset()
	var old_stream := StreamPeerBuffer.new()
	old_stream.data_array = PackedByteArray([88, 88])
	var new_stream := StreamPeerBuffer.new()
	new_stream.data_array = PackedByteArray([88])
	var seen := [0]
	var reconnect := func(_packet):
		seen[0] += 1
		ClientInterface._reset()
		ClientInterface._transport = new_stream
		ClientInterface._state = ClientInterface.State.CONNECTED
	ClientInterface._transport = old_stream
	ClientInterface._state = ClientInterface.State.CONNECTED
	ClientInterface.dataReceived.connect(reconnect)
	ClientInterface._ReadAvailableData()
	check(seen[0] == 1 and new_stream.get_position() == 0, "La recepción anterior consumió datos de una conexión nueva")
	ClientInterface.dataReceived.disconnect(reconnect)
	ClientInterface._reset()

func _verify_inventory() -> void:
	var inventory := Inventory.new(Consts.MaxInventorySlots)
	var grid = load("res://ui/hub/inventory_container.tscn").instantiate()
	add_child(grid)
	grid.SetInventory(inventory)
	check(grid.get_child_count() == 30, "La grilla trunca los slots 26–30")
	for slot in [1, 25, 26, 30]:
		var item := Item.new()
		item.name = "Objeto " + str(slot)
		var stack := ItemStack.new(slot, true, item)
		check(inventory.SetProtocolSlot(slot, stack), "Se rechazó slot válido")
		grid._InventorySlotOnPressed(slot - 1)
		check(grid.GetSelectedSlot() == slot - 1 and grid.GetInventorySlot(slot - 1) != null, "Slot alto no seleccionable")
		check(inventory.GetSlot(slot - 1).quantity == slot and inventory.GetSlot(slot - 1).equipped, "Se perdió cantidad/equipado")
	var last := inventory.GetSlot(29)
	check(not inventory.SetProtocolSlot(0, ItemStack.new()) and not inventory.SetProtocolSlot(31, ItemStack.new()), "Se aceptó slot inválido")
	check(inventory.GetSlot(29) == last and inventory.GetSlot(-1) == null and inventory.GetSlot(30) == null, "Índice inválido alteró otro item")
	grid.SetInventory(inventory)
	check(grid.get_child_count() == 30 and grid.GetSelectedSlot() == 29, "El refresco duplica slots o pierde selección")
	GameProtocol.WriteUseItem(30)
	check(GameProtocol.Flush() == PackedByteArray([30, 30]), "No se puede usar slot 30")
	GameProtocol.WriteEquipItem(30)
	check(GameProtocol.Flush() == PackedByteArray([36, 30]), "No se puede equipar slot 30")
	grid.free()

func _verify_text_policy() -> void:
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/credentials.json"))
	var panel = load("res://ui/login_panel.tscn").instantiate()
	add_child(panel)
	var visibility: Button = panel.get_node("%ShowPasswordButton")
	var password: LineEdit = panel.get_node("%Password")
	check(password.secret and visibility.text.is_empty() and visibility.icon != null, "Login no oculta la clave o depende de un glifo del sistema")
	var show_icon: Texture2D = visibility.icon
	visibility.button_pressed = true
	check(not password.secret and visibility.icon != show_icon and visibility.tooltip_text == "Ocultar contraseña", "Mostrar clave no actualiza el campo y su icono")
	check(visibility.icon.get_width() > 0 and visibility.icon.get_height() > 0, "El icono de ocultar no se importó")
	visibility.button_pressed = false
	check(password.secret and visibility.icon == show_icon and visibility.tooltip_text == "Mostrar contraseña", "Ocultar clave no restablece el campo y su icono")
	var counts := {"submit": 0, "error": 0, "serialization": 0}
	panel.submit.connect(func(): counts.submit += 1)
	panel.error.connect(func(_message): counts.error += 1)
	var rejected := func(_message): counts.serialization += 1
	ClientInterface.serialization_failed.connect(rejected)
	for vector in cases:
		check(CredentialPolicy.validate(vector.username, vector.password).is_empty() == vector.accepted, "Política: " + vector.name)
		GameProtocol.Clear()
		GameProtocol.WriteWalk(1)
		GameProtocol.WriteLoginExistingCharacter(vector.username, vector.password)
		var data := GameProtocol.Flush()
		if vector.accepted:
			var reader := StreamPeerBuffer.new()
			reader.data_array = data
			check(reader.get_u8() == 6 and reader.get_u8() == 1 and reader.get_u8() == 0, "Se perdió el comando anterior")
			check(Utils.GetUnicodeString(reader) == vector.username and Utils.GetUnicodeString(reader) == vector.password, "Se normalizó una credencial aceptada")
		else:
			check(data == PackedByteArray([6, 1]), "Credencial rechazada dejó bytes o borró un comando")
		panel.get_node("%Username").text = vector.username
		panel.get_node("%Password").text = vector.password
		var before := int(counts.submit)
		panel._OnButtonLoginPressed()
		check(counts.submit - before == (1 if vector.accepted else 0), "El formulario no respeta la política compartida")
	GameProtocol.Clear()
	GameProtocol.WriteWalk(1)
	GameProtocol.WriteTalk("texto🙂")
	GameProtocol.WriteWalk(2)
	check(GameProtocol.Flush() == PackedByteArray([6, 1, 6, 2]), "Chat inválido contaminó comandos anteriores/siguientes")
	GameProtocol.WriteTalk("¡Hola, señor! áéíóú")
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/fixtures.json"))
	for fixture in fixtures:
		if fixture.name == "talk_latin1":
			check(GameProtocol.Flush() == fixture.hex.hex_decode(), "Acentos de chat difieren de la fixture")
	GameProtocol.WritePartyJoin("Ana")
	check(GameProtocol.Flush() == PackedByteArray([93, 3, 0, 65, 110, 97]), "Party no envía el nickname compartido")
	for nickname in ["", "a".repeat(21), "Ana🙂"]:
		GameProtocol.WritePartyJoin(nickname)
		check(GameProtocol.IsEmpty(), "Nickname inválido produjo un paquete parcial")
	check(counts.serialization > 0, "Los errores locales no se comunican a la UI")
	ClientInterface.serialization_failed.disconnect(rejected)
	panel.free()

func _verify_capabilities() -> void:
	# Cargar mapa/libro/inventario puede superar 10 s en un equipo lento.
	var slow := ClientCapabilities.new()
	slow.begin()
	slow._deadline_msec -= 12000
	check(slow.accept(PackedByteArray([250, 1, 143, 0, 0, 0])), "ACK tras 12 s perdió las acciones negociadas")
	var legacy := ClientCapabilities.new()
	var extended := ClientCapabilities.new()
	check(legacy.enabled == 0, "Se habilitaron funciones sin negociar")
	var request := extended.begin()
	check(request == PackedByteArray([250, 1, 191, 7, 0, 0]), "Solicitud de capacidades fuera del contrato")
	check(extended.accept(PackedByteArray([250, 1, 1, 0, 0, 0])), "Respuesta válida rechazada")
	check(extended.has_feature(ClientCapabilities.SKILLS_CATALOG) and legacy.enabled == 0, "Se mezclaron capacidades entre conexiones")
	extended.clear()
	check(extended.enabled == 0, "Reconexión conserva capacidades")
	extended.begin()
	extended._deadline_msec -= 31000
	check(not extended.accept(PackedByteArray([250, 1, 255, 0, 0, 0])) and extended.enabled == 0, "Respuesta tardía elevó funciones")
	for response in [PackedByteArray([250, 2, 1, 0, 0, 0]), PackedByteArray([250, 1, 0, 0, 16, 0]), PackedByteArray([250, 1, 255, 255, 255, 255])]:
		extended.begin()
		check(not extended.accept(response) and extended.enabled == 0, "Respuesta inválida elevó funciones")
	for id in [28, 69, 72, 93, 41, 43, 129]:
		check(legacy.can_send(id), "Se bloqueó una función propia soportada: " + str(id))
	for id in [29, 31, 32, 38, 39, 46, 107, 124]:
		check(not legacy.can_send(id), "Una función sin backend está habilitada: " + str(id))
	GameProtocol.Clear()
	GameProtocol.write_invisible()
	GameProtocol.WriteTrainList()
	GameProtocol.WriteChangePassword("secret", "secret2")
	GameProtocol.WriteModifySkills([1])
	check(GameProtocol.IsEmpty(), "Writer sin backend produjo bytes")
	GameProtocol.WriteWarpChar("YO", 1, 50, 50)
	check(GameProtocol.Flush() == PackedByteArray([122, 11, 2, 0, 89, 79, 1, 0, 50, 50]), "Se bloqueó el subcomando GM propio soportado")
	var password_window = load("res://ui/hub/password_change_window.tscn").instantiate()
	add_child(password_window)
	password_window.current_password_input.text = "secret"
	password_window.new_password_input.text = "secret2"
	password_window.confirm_password_input.text = "secret2"
	password_window._validate_fields()
	check(password_window.accept_button.disabled and not password_window.error_label.text.is_empty(), "Cambio de contraseña no explica la indisponibilidad")
	password_window._on_accept_pressed()
	check(GameProtocol.IsEmpty(), "La ventana envió un cambio no soportado")
	password_window.free()
	var previous_points = Global.skillPoints
	Global.skillPoints = 5
	var skills_window = load("res://ui/hub/skills_window.tscn").instantiate()
	add_child(skills_window)
	var skills: Array = []
	for index in 20:
		skills.append({"level": 0})
	skills_window.set_skills(skills)
	skills_window._on_plus_pressed(0)
	skills_window._on_accept_pressed()
	check(skills_window.skill_values[0] == 0 and Global.skillPoints == 5, "La ventana aplicó puntos sin backend")
	check(skills_window.accept_button.disabled and GameProtocol.IsEmpty(), "La ventana de skills permite una asignación sin backend")
	skills_window.free()
	Global.skillPoints = previous_points

func _verify_skills(fixtures: Dictionary) -> void:
	for key in ["skills_legacy", "skills_catalog_v1"]:
		var reader := StreamPeerBuffer.new()
		reader.data_array = fixtures[key]
		reader.get_u8()
		var update: SendSkills = SkillCatalogPacket.new(reader) if key == "skills_catalog_v1" else SendSkills.new(reader)
		check(update.valid and update.skills.size() == 22 and reader.get_available_bytes() == 0, "Reader de skills no consume exactamente la fixture")
		check(update.skills[20].level == 5 and update.skills[21].level == 3, "Se perdieron robustez/agilidad propias de pyao")
		if key == "skills_catalog_v1":
			check(update.free_points == 4 and update.skills[8].level == 2 and update.skills[8].experience == 75, "Se confundió XP acumulada con nivel/porcentaje")
		var combined: PackedByteArray = fixtures[key].duplicate()
		combined.append_array(fixtures.change_map)
		for split in range(1, combined.size()):
			var framer := AOPacketFramer.new()
			var packets := framer.feed(combined.slice(0, split))
			packets.append_array(framer.feed(combined.slice(split)))
			check(packets.size() == 2 and packets[0] == fixtures[key] and packets[1] == fixtures.change_map, "Skills consumió bytes de ChangeMap")
	var invalid: PackedByteArray = fixtures.skills_catalog_v1.duplicate()
	invalid[4] = 22  # ID repetido/fuera del orden canónico.
	var reader := StreamPeerBuffer.new()
	reader.data_array = invalid
	reader.get_u8()
	check(not SkillCatalogPacket.new(reader).valid, "Catálogo con IDs corruptos fue aceptado")
	ClientInterface._reset()
	var counts := {"failure": 0, "data": 0}
	var failed := func(_message): counts.failure += 1
	var received := func(_packet): counts.data += 1
	ClientInterface.connection_failed.connect(failed)
	ClientInterface.dataReceived.connect(received)
	ClientInterface._AcceptIncomingData(fixtures.skills_catalog_v1)
	check(counts.failure == 1 and counts.data == 0, "Extensión no negociada fue entregada")
	ClientInterface.capabilities.begin()
	ClientInterface.capabilities.accept(PackedByteArray([250, 1, 1, 0, 0, 0]))
	ClientInterface._AcceptIncomingData(fixtures.skills_catalog_v1)
	check(counts.data == 1, "Se rechazó el catálogo solicitado y negociado")
	ClientInterface.connection_failed.disconnect(failed)
	ClientInterface.dataReceived.disconnect(received)
	ClientInterface._reset()

func _verify_drag() -> void:
	GameProtocol.Clear()
	var inventory := Inventory.new(30)
	var item := Item.new()
	item.index = 42
	inventory.SetProtocolSlot(1, ItemStack.new(3, false, item))
	var original := inventory.GetSlot(0)
	var grid = load("res://ui/hub/inventory_container.tscn").instantiate()
	add_child(grid)
	grid.allow_reorder = true
	grid.SetInventory(inventory)
	var data = grid.CreateDragData(0)
	check(data != null and GameProtocol.IsEmpty(), "Empezar/cancelar un drag envió bytes")
	check(grid.CreateDragData(29) == null, "Se inició drag de un slot vacío")
	for destination in [-1, 0, 30]:
		grid.DropItem(destination, data)
		check(GameProtocol.IsEmpty(), "Soltar inválido/mismo slot envió bytes")
	grid.GetInventorySlot(29)._drop_data(Vector2.ZERO, data)
	check(GameProtocol.Flush() == PackedByteArray([129, 1, 30]), "MOVE_ITEM incluye un move_type o índices incorrectos")
	check(inventory.GetSlot(0) == original and inventory.GetSlot(29).quantity == 0, "Drag mutó inventario antes de confirmar el servidor")
	var merchant = load("res://ui/hub/inventory_container.tscn").instantiate()
	add_child(merchant)
	merchant.SetInventory(Inventory.new(20))
	check(merchant.CreateDragData(0) == null and not merchant.CanDropItem(1, data), "Se habilitó reordenar stock o banco")
	merchant.allow_reorder = true
	check(not merchant.CanDropItem(1, data), "Drag cruzó inventarios distintos")
	var selected := {"count": 0}
	merchant.slotPressed.connect(func(_index): selected.count += 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	merchant.GetInventorySlot(0)._gui_input(click)
	check(selected.count == 1 and merchant.GetSelectedSlot() == 0 and GameProtocol.IsEmpty(), "Se perdió la selección propia de comerciantes/banco")
	grid.free()
	merchant.free()

func _verify_ui() -> void:
	ClientInterface.capabilities.clear()
	GameProtocol.Clear()
	var game = load("res://screens/game_screen.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	var hub: HubController = game._gameInput
	var drag_item := Item.new()
	drag_item.index = 38
	game._gameContext.playerInventory.SetSlot(29, ItemStack.new(5, false, drag_item))
	var cell := hub._inventoryContainer.GetInventorySlot(29)
	var inventory_click := InputEventMouseButton.new()
	inventory_click.button_index = MOUSE_BUTTON_LEFT
	inventory_click.position = cell.size / 2
	inventory_click.pressed = true
	cell._gui_input(inventory_click)
	check(GameProtocol.IsEmpty(), "Presionar para iniciar un drag usa el objeto")
	game._gameContext.tick_intervals.timers[TickIntervals.ActionTimers.USE_ITEM_WITH_DOUBLE_CLICK].elapsed_time = -1000
	inventory_click.pressed = false
	cell._gui_input(inventory_click)
	check(GameProtocol.Flush() == PackedByteArray([30, 30]), "Un clic completo perdió el uso habitual")
	var gold_reader := StreamPeerBuffer.new()
	gold_reader.put_32(9930)
	gold_reader.seek(0)
	game._HandleUpdateGold(UpdateGold.new(gold_reader))
	check(game._gameContext.player_gold == 9930, "UpdateGold deja el contexto con un saldo viejo")
	hub._consoleInputLineEdit.show()
	hub._consoleInputLineEdit.text = "no atacar"
	check(hub.IsWorldInputBlocked(), "El chat deja pasar movimiento")
	game._gameContext.usingSkill = 1
	hub.RouteEscape()
	check(game._gameContext.usingSkill == 0 and hub._consoleInputLineEdit.visible, "Escape debe cancelar sólo la captura")
	hub.RouteEscape()
	check(not hub._consoleInputLineEdit.visible and hub._consoleInputLineEdit.text.is_empty(), "Escape no cerró el chat")
	hub.RouteEscape()
	check(hub._options_window.visible and hub.IsWorldInputBlocked(), "Escape no abrió el menú o deja pasar acciones")
	hub.RouteEscape()
	check(not hub._options_window.visible, "Escape no cerró el modal superior")
	hub.OpenMerchant()
	var merchant: MerchantPanel = hub._currentPanel
	check(merchant is Window and hub.IsWorldInputBlocked(), "Comercio no bloquea el mundo")
	check(merchant._actionButton.disabled, "Comercio permite operar sin selección")
	merchant._merchantInventoryContainer._InventorySlotOnPressed(0)
	check(merchant._actionButton.disabled, "Slot vacío permite comprar")
	var item := Item.new()
	item.index = 1
	item.name = "Objeto impar"
	item.salePrice = 11
	game._gameContext.playerInventory.SetSlot(29, ItemStack.new(5, false, item))
	game._gameContext.merchantInventory.SetSlot(0, ItemStack.new(5, false, item))
	merchant._merchantInventoryContainer._InventorySlotOnPressed(0)
	merchant._quantitySpinBox.value = 3
	check(merchant._Quote() == 33 and merchant._actionButton.text == "Comprar", "Cotización de compra incorrecta")
	merchant._playerInventoryContainer._InventorySlotOnPressed(29)
	check(merchant._merchantInventoryContainer.GetSelectedSlot() == -1 and merchant._Quote() == 15, "Venta impar o selección exclusiva incorrecta")
	game._gameContext.playerInventory.SetSlot(29, ItemStack.new(5, true, item))
	merchant._Submit()
	check(merchant._actionButton.disabled and GameProtocol.Flush().is_empty(), "Vender permite equipo activo")
	game._gameContext.playerInventory.SetSlot(29, ItemStack.new(5, false, item))
	merchant._Submit()
	merchant._Submit()
	check(GameProtocol.Flush() == PackedByteArray([42, 30, 3, 0]), "Venta debe generar una petición y conservar slot 30")
	check(game._gameContext.playerInventory.GetSlot(29).quantity == 5, "Venta alteró inventario antes de confirmación")
	game._gameContext.playerInventory.SetSlot(29, ItemStack.new(2, false, item))
	check(merchant._actionButton.disabled, "Cantidad obsoleta no deshabilita la acción")
	merchant.SetPlayerInventory(game._gameContext.playerInventory)
	check(merchant._playerInventoryContainer.get_child_count() == 30, "Reconectar inventario duplica nodos")
	merchant.size = Vector2i(420, 340)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	merchant.push_input(escape)
	check(hub._currentPanel == null, "Escape del viewport nativo no llegó al router")
	merchant.RequestClose()
	check(GameProtocol.Flush() == PackedByteArray([17]), "Cerrar comercio duplica CommerceEnd")
	check(not game._gameContext.trading, "Cerrar comercio deja bloqueado el mundo")
	hub.OpenBank()
	var bank: BankPanel = hub._currentPanel
	var dagger := Item.new()
	dagger.index = 15
	dagger.name = "Daga"
	dagger.type = Enums.eOBJType.eOBJType_otWeapon
	dagger.minHit = 1
	dagger.maxHit = 2
	game._gameContext.playerInventory.SetSlot(29, ItemStack.new(1, false, dagger))
	bank._playerInventoryContainer._InventorySlotOnPressed(29)
	check(bank._infoLabel.text == "Daga" and bank._statLabel.text == "1/2", "El banco altera el nombre o daño del arma")
	check(bank._statRow.visible and bank._statIcon.texture == BankPanel.DAMAGE_ICON, "El banco no muestra la espada incluida")
	check(bank._statRow.tooltip_text == "Daño: 1/2", "La espada no describe el daño")
	_check_bank_glyphs(bank._infoLabel)
	_check_bank_glyphs(bank._statLabel)
	var armour := Item.new()
	armour.index = 1073
	armour.name = "Armadura de Aprendiz"
	armour.type = Enums.eOBJType.eOBJType_otArmadura
	armour.minDef = 2
	armour.maxDef = 7
	bank._bankInventory.SetSlot(0, ItemStack.new(1, false, armour))
	bank._bankInventoryContainer._InventorySlotOnPressed(0)
	check(bank._infoLabel.text == "Armadura de Aprendiz" and bank._statLabel.text == "2/7", "El banco invierte el rango de defensa")
	check(bank._statRow.visible and bank._statIcon.texture == BankPanel.DEFENCE_ICON, "El banco no cambia la espada por el escudo incluido")
	check(bank._statRow.tooltip_text == "Defensa: 2/7", "El escudo no describe la defensa")
	_check_bank_glyphs(bank._infoLabel)
	_check_bank_glyphs(bank._statLabel)
	game._gameContext.playerInventory.SetSlot(29, ItemStack.new(1, false, item))
	bank._playerInventoryContainer._InventorySlotOnPressed(29)
	check(bank._infoLabel.text == "Objeto impar" and not bank._statRow.visible, "Un objeto común conserva estadísticas anteriores")
	bank._bankInventoryContainer._InventorySlotOnPressed(1)
	check(bank._infoLabel.text == "Seleccioná un objeto", "Un slot vacío conserva estadísticas anteriores")
	check(not bank._statRow.visible and bank._statIcon.texture == null and bank._statLabel.text.is_empty(), "Un slot vacío conserva el icono anterior")
	_check_bank_glyphs(bank._infoLabel)
	hub.RouteEscape()
	bank.RequestClose()
	check(GameProtocol.Flush() == PackedByteArray([21]), "Cerrar banco duplica BankEnd")
	var bank_reader := StreamPeerBuffer.new()
	BankInit.new(bank_reader)
	check(bank_reader.get_position() == 0, "BANK_INIT consume saldo inexistente")
	game.free()
	GameProtocol.Clear()

func _check_bank_glyphs(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	for character in label.text:
		if character != "\n":
			check(font.has_char(character.unicode_at(0)), "La fuente incluida no dibuja el detalle del banco: " + character)

func _trade_packet(value: Dictionary) -> TradeSnapshot:
	var stream := StreamPeerBuffer.new()
	stream.put_u8(1)
	Utils.PutUnicodeString(stream, JSON.stringify(value))
	stream.seek(0)
	return TradeSnapshot.new(stream)

func _verify_trade() -> void:
	ClientInterface.capabilities.clear()
	ClientInterface.capabilities.begin()
	check(ClientInterface.capabilities.accept(PackedByteArray([250, 1, 129, 0, 0, 0])), "No habilita trade negociado")
	GameProtocol.Clear()
	var value := {"id": "a".repeat(32), "revision": 1, "sequence": 1, "state": "active", "viewer": 1, "players": [[1, "Alice", 0, false, [[30, 101, 2]]], [2, "Bob", 10, false, []]], "reason": ""}
	check(_trade_packet(value).valid, "Snapshot válido de trade rechazado")
	for field in ["revision", "viewer"]:
		var invalid := value.duplicate(true)
		invalid[field] = 1.5
		check(not _trade_packet(invalid).valid, "Trade acepta entero fraccional")
	var invalid := value.duplicate(true)
	invalid.players[0][4].append([30, 202, 1])
	check(not _trade_packet(invalid).valid, "Trade acepta slot repetido")
	var panel := PlayerTradePanel.new()
	var inventory := Inventory.new(30)
	var item := Item.new()
	item.index = 101
	item.name = "Poción"
	inventory.SetProtocolSlot(30, ItemStack.new(5, false, item))
	panel.inventory = inventory
	add_child(panel)
	panel.ApplySnapshot(value)
	check(panel.offer_items[0].get_item_text(0).contains("Poción") and panel.offers[0].text.contains("Alice") and panel.offers[1].text.contains("Bob"), "No representa ambos participantes")
	panel.slot.value = 30
	panel.quantity.value = 2
	panel.item_button.pressed.emit()
	panel.item_button.pressed.emit()
	var output := GameProtocol.Flush()
	check(output.size() == 46 and output[0] == 252 and output[41] == 30, "Editar envía duplicados o slot incorrecto")
	check(inventory.GetSlot(29).quantity == 5 and panel.snapshot.players[0][4][0][2] == 2, "Trade modificó stacks antes del servidor")
	value.sequence = 2
	value.revision = 2
	value.players[0][3] = true
	panel.ApplySnapshot(value.duplicate(true))
	check(panel.confirm_button.disabled and panel.offers[0].text.contains("Confirmado"), "Confirmación propia no se ve")
	value.sequence = 3
	value.revision = 3
	value.players[0][3] = false
	panel.ApplySnapshot(value.duplicate(true))
	check(not panel.confirm_button.disabled and panel.offers[0].text.contains("Sin confirmar"), "Editar no borra confirmación visual")
	panel.RequestClose()
	panel.RequestClose()
	output = GameProtocol.Flush()
	check(output.size() == 46 and output[40] == 4 and not panel.is_queued_for_deletion(), "Cancelar se duplica o cierra antes del resultado")
	var ended := {"count": 0}
	panel.finished.connect(func(): ended.count += 1)
	value.sequence = 4
	value.state = "cancelled"
	value.reason = "Desconectado"
	panel.ApplySnapshot(value)
	check(ended.count == 1 and inventory.GetSlot(29).quantity == 5, "Cancelación no conserva inventario")
	panel.free()
	ClientInterface.capabilities.clear()

func _verify_spellbook_order() -> void:
	GameProtocol.Clear()
	var panel = load("res://ui/hub/spell_list_panel.tscn").instantiate()
	add_child(panel)
	panel._on_btn_move_down_pressed()
	panel._on_btn_move_up_pressed()
	check(GameProtocol.IsEmpty(), "Libro sin selección emite movimientos")
	panel._item_list.select(0)
	panel._on_btn_move_down_pressed()
	check(GameProtocol.IsEmpty(), "Slot de hechizo vacío se mueve")
	panel.set_slot_text(0, "Curar", 1)
	panel.set_slot_text(1, "Fuego", 2)
	panel._on_btn_move_up_pressed()
	check(GameProtocol.IsEmpty(), "Mover arriba del primer slot emite paquete")
	panel._on_btn_move_down_pressed()
	panel._on_btn_move_down_pressed()
	var bytes := GameProtocol.Flush()
	check(bytes == PackedByteArray([45, 0, 1]), "Bajar debe enviar upwards=0 con el slot original una sola vez")
	check(panel.get_selected_slot() == 0 and panel._item_list.get_item_text(0) == "Curar", "MOVE_SPELL cambió nombres/selección antes del ack")
	panel.set_slot_text(0, "Fuego", 2)
	panel.set_slot_text(1, "Curar", 1)
	check(panel.get_selected_slot() == 1 and panel._pending_move.is_empty(), "Selección no sigue al hechizo confirmado")
	panel._on_btn_move_up_pressed()
	bytes = GameProtocol.Flush()
	check(bytes == PackedByteArray([45, 1, 2]), "Subir debe enviar upwards=1 con el slot original")
	panel.set_slot_text(0, "Curar", 1)
	panel.set_slot_text(1, "Fuego", 2)
	check(panel.get_selected_slot() == 0 and panel._pending_move.is_empty(), "Selección no sigue el movimiento hacia arriba confirmado")
	panel._item_list.select(1)
	panel._on_btn_move_down_pressed()
	GameProtocol.Clear()
	panel._deadline = 0
	panel._process(0)
	check(panel._pending_move.is_empty() and panel.get_selected_slot() == 1, "Rechazo/timeout modifica selección")
	panel._item_list.select(Consts.MaxUserHechizos - 1)
	panel.set_slot_text(Consts.MaxUserHechizos - 1, "Final", 3)
	panel._on_btn_move_down_pressed()
	check(GameProtocol.IsEmpty(), "Mover después del último slot emite paquete")
	panel._ResetPending()
	panel.free()

func _verify_chat_text() -> void:
	var game = load("res://screens/game_screen.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	var hub: HubController = game._gameInput
	hub._consoleRichTextLabel.clear()
	var untrusted := "[color=red]Peña[/color]\n[url={\"type\":\"screenshot\",\"path\":\"https://example.invalid\"}]abrir[/url]"
	hub.ShowConsoleMessage(untrusted, FontData.new(Color.RED, true))
	check(hub._consoleRichTextLabel.get_parsed_text().contains(untrusted), "La consola interpretó BBCode de red")
	for invalid in ["https://example.invalid", '{"type":"screenshot","path":"/tmp/evil.png"}', "pyao-screenshot:inventado", {}]:
		check(hub._ResolveScreenshot(invalid).is_empty(), "Metadato remoto puede abrir una ruta")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screenshots"))
	var path := "user://screenshots/protocol-smoke.png"
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLUE)
	check(image.save_png(path) == OK, "No se pudo crear captura local de prueba")
	var absolute := ProjectSettings.globalize_path(path)
	var token := hub._ShowSavedScreenshot(absolute)
	check(not token.is_empty() and hub._ResolveScreenshot(token) == absolute, "La captura creada no conserva su enlace interno")
	DirAccess.remove_absolute(absolute)
	check(hub._ResolveScreenshot(token).is_empty(), "Se abre un enlace a captura ya inexistente")
	game.free()

func _verify_minimap() -> void:
	var minimap := Minimap.new()
	add_child(minimap)
	minimap.size = Vector2(200, 100)
	minimap.load_thumbnail(1)
	check(minimap.texture != null and minimap.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Miniatura propia ausente o filtrada")
	for tile in [Vector2i(1, 1), Vector2i(100, 1), Vector2i(1, 100), Vector2i(100, 100), Vector2i(50, 50)]:
		var point := minimap.TileToPoint(tile)
		check(minimap.PointToTile(point) == tile, "Conversión minimapa no conserva tile " + str(tile))
	check(minimap.TileToPoint(Vector2i(1, 1)).is_equal_approx(Vector2(50.5, 0.5)), "Miniatura centrada usa recorte ajeno")
	check(minimap.PointToTile(Vector2(20, 20)) == Vector2i.ZERO, "Margen del minimapa produce coordenadas")
	minimap.size = Vector2(300, 200)
	check(minimap.TileToPoint(Vector2i(1, 1)).is_equal_approx(Vector2(51, 1)), "Resize no recalcula posición")
	minimap.load_thumbnail(99999)
	check(minimap.texture == null, "Miniatura ausente conserva imagen anterior")
	minimap.load_thumbnail(1)
	check(not minimap._InstallThumbnail(PackedByteArray([66, 77])) and minimap.texture == null, "Miniatura corrupta no activa fallback")
	minimap.free()
	GameProtocol.Clear()
	var game = load("res://screens/game_screen.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	game._gameContext.player_map = 1
	game._gameInput._on_minimap_click(Vector2(50, 50))
	game._gameInput._on_minimap_click(Vector2(-1, 200))
	check(GameProtocol.IsEmpty(), "Clic normal en minimapa emite un comando GM")
	game.free()

func _verify_clan_details(fixtures: Dictionary) -> void:
	for name in ["clan_empty", "clan_accents_zero"]:
		var zero := StreamPeerBuffer.new()
		zero.data_array = fixtures[name]
		zero.get_u8()
		var decoded := ClanDetailsPacket.new(zero)
		check(decoded.valid and decoded.values.members == 0, "Clan vacío/acentuado no consume la fixture")
	var stream := StreamPeerBuffer.new()
	stream.data_array = fixtures.clan_large_counts
	check(stream.get_u8() == 80, "Fixture de clan tiene otro ID")
	var packet := ClanDetailsPacket.new(stream)
	check(packet.valid and packet.values.members == 32768, "Detalles de clan no consumen contadores int32")
	var window := ClanDetailsWindow.new()
	add_child(window)
	window.ApplyDetails(packet.values)
	check(window.details.text.contains("32768") and window.details.text.contains(packet.values.description), "Ventana pierde datos de clan")
	GameProtocol.Clear()
	window.RequestDetails()
	window.RequestDetails()
	check(GameProtocol.Flush() == PackedByteArray([69]), "Petición de detalles duplicada o con ID ajeno")
	window.ApplyDetails(packet.values)
	window.leave.pressed.emit()
	check(GameProtocol.IsEmpty(), "Abandonar no pidió confirmación")
	window.confirmation.confirmed.emit()
	window.confirmation.confirmed.emit()
	check(GameProtocol.Flush() == PackedByteArray([72, 69]), "Abandono no usa 72 seguido de consulta autoritativa")
	window.ApplyDetails(packet.values)
	check(not window.leave.disabled and window.status.text.contains("Seguís"), "Rechazo de abandono se representa como éxito")
	var empty := packet.values.duplicate(true)
	empty.name = ""
	empty.members = 0
	window.ApplyDetails(empty)
	check(window.leave.disabled and window.details.text.is_empty(), "Clan vacío conserva detalle anterior")
	window.free()

func _allocation_packet(bytes: PackedByteArray) -> SkillAllocationState:
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	stream.get_u8()
	return SkillAllocationState.new(stream)

func _verify_allocation(fixtures: Dictionary) -> void:
	ClientInterface.capabilities.clear()
	ClientInterface.capabilities.begin()
	check(ClientInterface.capabilities.accept(PackedByteArray([250, 1, 133, 0, 0, 0])), "No habilita asignación de habilidades")
	var initial := _allocation_packet(fixtures.allocation_state)
	check(initial.valid and initial.free_points == 8 and initial.skills[0].level == 12 and initial.skills[0].experience == 77, "Estado de asignación mezcla nivel y XP")
	var window = load("res://ui/hub/skills_window.tscn").instantiate()
	add_child(window)
	window.ApplyAllocationState(initial)
	GameProtocol.Clear()
	window._on_plus_pressed(1)
	check(window.current_free_skills == 7 and window.skill_values[1] == 1, "Robar no admite asignación manual")
	window._on_minus_pressed(1)
	check(window.current_free_skills == 8, "Deshacer Robar no devuelve el punto del borrador")
	window._on_plus_pressed(0)
	check(window.current_free_skills == 7 and Global.skillPoints == 8, "Borrador cambia presupuesto global")
	window._on_accept_pressed()
	window._on_accept_pressed()
	check(GameProtocol.Flush() == fixtures.allocation_request, "Asignación duplicada, sin IDs o con valores absolutos")
	check(Global.skillPoints == 8 and not window._pending_id.is_empty(), "Guardar confirma antes del ack")
	window.ApplyAllocationState(initial)
	check(not window._pending_id.is_empty() and Global.skillPoints == 8, "Consulta vieja liberó un guardado pendiente")
	var accepted := _allocation_packet(fixtures.allocation_accepted)
	window.ApplyAllocationState(accepted)
	check(window._pending_id.is_empty() and Global.skillPoints == 7 and window.initial_skill_values[0] == 13, "Ack no actualiza niveles y presupuesto")
	window._on_plus_pressed(0)
	window._on_accept_pressed()
	GameProtocol.Clear()
	window.ApplyAllocationState(_allocation_packet(fixtures.allocation_rejected))
	check(window.skill_values[0] == 13 and Global.skillPoints == 7 and window._status.text.contains("insuficientes"), "Rechazo conserva cambios locales como guardados")
	window._on_plus_pressed(0)
	window._on_cancel_pressed()
	check(window.skill_values[0] == 13 and Global.skillPoints == 7, "Cancelar modifica datos confirmados")
	window._on_plus_pressed(0)
	window._on_accept_pressed()
	GameProtocol.Clear()
	window._deadline = 0
	window._process(0)
	check(GameProtocol.Flush() == PackedByteArray([15]) and window.operation_id.is_empty(), "Timeout permite otro gasto sin consultar estado")
	window.free()
	ClientInterface.capabilities.clear()

func _password_reply(bytes: PackedByteArray) -> PasswordChangeReply:
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	stream.get_u8()
	return PasswordChangeReply.new(stream)

func _password_fields(window, current: String = "cláve1", new_password: String = "nueva42") -> void:
	window.current_password_input.text = current
	window.new_password_input.text = new_password
	window.confirm_password_input.text = new_password
	window._validate_fields()

func _verify_password_change(fixtures: Dictionary) -> void:
	ClientInterface.capabilities.clear()
	ClientInterface.capabilities.begin()
	check(ClientInterface.capabilities.accept(PackedByteArray([250, 1, 143, 0, 0, 0])), "No habilita cambio de contraseña")
	var window = load("res://ui/hub/password_change_window.tscn").instantiate()
	add_child(window)
	var inputs := [window.current_password_input, window.new_password_input, window.confirm_password_input]
	var toggles := [window.current_password_toggle, window.new_password_toggle, window.confirm_password_toggle]
	for index in range(3):
		var toggle: Button = toggles[index]
		check(toggle.text.is_empty() and toggle.icon != null and toggle.icon.get_width() > 0, "Cambio de clave depende de un glifo del sistema")
		var show_icon: Texture2D = toggle.icon
		toggle.pressed.emit()
		check(not inputs[index].secret and toggle.icon != show_icon and toggle.tooltip_text == "Ocultar contraseña", "El botón no revela su campo y cambia de icono")
		for other in range(3):
			check(inputs[other].secret == (other != index), "Un botón de visibilidad altera otro campo")
		toggle.pressed.emit()
		check(inputs[index].secret and toggle.icon == show_icon, "El botón no vuelve a ocultar la clave")
	GameProtocol.Clear()
	window.show_window()
	window.show_window()
	check(GameProtocol.Flush() == fixtures.password_challenge, "La apertura duplica la solicitud o manda claves")
	window.ApplyReply(_password_reply(fixtures.password_ready))
	_password_fields(window, "corta")
	check(window.accept_button.disabled, "Clave corta habilita cambio")
	_password_fields(window)
	window.confirm_password_input.text = "diferente"
	window._validate_fields()
	check(window.accept_button.disabled, "Confirmación distinta habilita cambio")
	window.confirm_password_input.text = "nueva42"
	window._validate_fields()
	window._on_accept_pressed()
	window._on_accept_pressed()
	check(GameProtocol.Flush() == fixtures.password_change_request, "Cambio de clave duplicado o con codec distinto")
	check(window.current_password_input.text.is_empty() and window.new_password_input.text.is_empty() and window.confirm_password_input.text.is_empty(), "Guardar retiene las contraseñas en el formulario")
	check(not window._pending_id.is_empty() and not window.error_label.text.contains("actualizada"), "El formulario anuncia éxito sin ack")
	window._deadline = 0
	window._process(0)
	check(GameProtocol.Flush() == fixtures.password_change_query, "Timeout vuelve a mandar claves o cambia el ID")
	window.ApplyReply(_password_reply(fixtures.password_changed))
	check(window._pending_id.is_empty() and window.error_label.text == "Contraseña actualizada.", "El éxito real no se confirma")
	_password_fields(window)
	window._on_accept_pressed()
	GameProtocol.Clear()
	window.ApplyReply(_password_reply(fixtures.password_rejected))
	check(window._pending_id.is_empty() and window.error_label.text.contains("incorrecta") and window.current_password_input.text.is_empty(), "Rechazo no limpia campos o afirma éxito")
	_password_fields(window)
	window._on_accept_pressed()
	GameProtocol.Clear()
	window.ApplyReply(_password_reply(fixtures.password_unknown))
	check(window._pending_id.is_empty() and window.error_label.text.contains("No hay resultado confirmado") and window.current_password_input.text.is_empty(), "Un resultado incierto se presenta como éxito")
	_password_fields(window)
	window.current_password_toggle.pressed.emit()
	window.RequestClose()
	check(window.current_password_input.secret and window.current_password_input.text.is_empty() and window.new_password_input.text.is_empty() and not window.visible, "Cerrar conserva una clave o su modo visible")
	for toggle in toggles:
		check(toggle.icon == window.SHOW_PASSWORD_ICON and toggle.tooltip_text == "Mostrar contraseña", "Cerrar conserva el icono de una clave visible")
	window._Disconnected()
	check(window.operation_id.is_empty() and window._pending_id.is_empty() and window.accept_button.disabled, "Desconexión conserva autorización de cambio")
	window.free()
	ClientInterface.capabilities.clear()

func _verify_targeting(fixtures: Dictionary) -> void:
	ClientInterface.capabilities.enabled = ClientCapabilities.TARGETED_CAST
	var game = load("res://screens/game_screen.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	var hub: HubController = game._gameInput
	game._gameContext.player_stats.hp = 100
	GameProtocol.Clear()
	hub.spell_list_panel.set_slot_text(0, "Dardo", 2)
	hub.spell_list_panel._item_list.select(0)
	hub.spell_list_panel._on_btn_cast_pressed()
	check(hub._target_spell_slot == 1 and GameProtocol.IsEmpty(), "Elegir magia lanzó un cast antes del clic")
	hub.RouteEscape()
	check(hub._target_spell_slot == 0 and Input.get_current_cursor_shape() == Input.CURSOR_ARROW, "Escape no canceló magia")
	hub.BeginSpellTarget(1)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_RIGHT
	hub._input(click)
	check(hub._target_spell_slot == 0, "Clic derecho no canceló magia")
	hub.BeginSpellTarget(1)
	check(hub.TargetTile(Vector2(-1, 2)) == Vector2i.ZERO, "Target fuera del mundo se aceptó")
	hub._consoleInputLineEdit.show()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(64, 64)
	hub._HandleMouseInput(click)
	check(GameProtocol.IsEmpty() and hub._target_spell_slot == 1, "Modal permite castear")
	hub._consoleInputLineEdit.hide()
	GameProtocol.Clear()
	check(GameProtocol.WriteCastTarget(1, Vector2i(55, 50)), "Cast válido no se serializa")
	check(GameProtocol.Flush() == fixtures.cast_target, "Writer targeting difiere del contrato")
	check(not GameProtocol.WriteCastTarget(0, Vector2i.ONE) and not GameProtocol.WriteCastTarget(1, Vector2i(101, 50)), "Cast con slot/coordenadas inválidas se envía")
	var hp_reader := StreamPeerBuffer.new()
	hp_reader.data_array = PackedByteArray([0, 0])
	game._HandleUpdateHP(UpdateHP.new(hp_reader))
	check(hub._target_spell_slot == 0, "Muerte no canceló magia")
	game._gameContext.player_stats.hp = 100
	hub.BeginSpellTarget(1)
	hub._restore_default_cursor()
	check(hub._target_spell_slot == 0, "Desconexión/mapa no limpian targeting")
	ClientInterface.capabilities.clear()
	check(not GameProtocol.WriteCastTarget(1, Vector2i.ONE), "Legacy recibió extensión de magia")
	game.free()
