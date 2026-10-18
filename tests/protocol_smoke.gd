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
		for field in packet.fields:
			var value
			match field.type:
				"u8": value = reader.get_u8()
				"i16": value = reader.get_16()
				"i32": value = reader.get_32()
				"f32": value = reader.get_float()
				"str16":
					var length := reader.get_u16()
					value = reader.get_data(length)[1].get_string_from_ascii()
			if fixture.values.has(field.name):
				check(value == fixture.values[field.name], fixture.name + ": campo " + field.name)
		check(reader.get_available_bytes() == 0, fixture.name + ": bytes sobrantes")
	_verify_framing(fixtures)
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
	_verify_clan_details(by_name)
	_verify_minimap()
	_verify_chat_text()
	_verify_spellbook_order()
	_verify_trade()
	_verify_ui()
	_verify_screen_handoff()
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
	for invalid in [PackedByteArray([255]), PackedByteArray([24, 255, 255]), PackedByteArray([104, 255])]:
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
	game.set_process(false)
	game.free()
	ScreenController.currentScreen = null
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
	var legacy := ClientCapabilities.new()
	var extended := ClientCapabilities.new()
	check(legacy.enabled == 0, "Se habilitaron funciones sin negociar")
	var request := extended.begin()
	check(request == PackedByteArray([250, 1, 129, 0, 0, 0]), "Solicitud de capacidades fuera del contrato")
	check(extended.accept(PackedByteArray([250, 1, 1, 0, 0, 0])), "Respuesta válida rechazada")
	check(extended.has_feature(ClientCapabilities.SKILLS_CATALOG) and legacy.enabled == 0, "Se mezclaron capacidades entre conexiones")
	extended.clear()
	check(extended.enabled == 0, "Reconexión conserva capacidades")
	extended.begin()
	extended._deadline_msec = 0
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
	var bank := hub._currentPanel
	hub.RouteEscape()
	bank.RequestClose()
	check(GameProtocol.Flush() == PackedByteArray([21]), "Cerrar banco duplica BankEnd")
	var bank_reader := StreamPeerBuffer.new()
	BankInit.new(bank_reader)
	check(bank_reader.get_position() == 0, "BANK_INIT consume saldo inexistente")
	game.free()
	GameProtocol.Clear()

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
	check(panel.offers[0].text.contains("Poción") and panel.offers[1].text.contains("Bob"), "No representa ambos participantes")
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
	check(bytes.size() == 3 and bytes[1] == 1 and bytes[2] == 1, "MOVE_SPELL duplicado o con slot nuevo")
	check(panel.get_selected_slot() == 0 and panel._item_list.get_item_text(0) == "Curar", "MOVE_SPELL cambió nombres/selección antes del ack")
	panel.set_slot_text(0, "Fuego", 2)
	panel.set_slot_text(1, "Curar", 1)
	check(panel.get_selected_slot() == 1 and panel._pending_move.is_empty(), "Selección no sigue al hechizo confirmado")
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
