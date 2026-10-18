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
