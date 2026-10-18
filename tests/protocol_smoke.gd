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
	_verify_text_policy()
	_verify_capabilities()
	_verify_inventory()
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
	check(request == PackedByteArray([250, 1, 255, 0, 0, 0]), "Solicitud de capacidades fuera del contrato")
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
	GameProtocol.WriteTrainList()
	GameProtocol.WriteChangePassword("secret", "secret2")
	GameProtocol.WriteModifySkills([1])
	check(GameProtocol.IsEmpty(), "Writer sin backend produjo bytes")
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
