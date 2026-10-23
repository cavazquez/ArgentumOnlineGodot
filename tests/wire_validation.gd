extends Node

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("WIRE_VALIDATION: " + message)

func convert_arg(value: Variant) -> Variant:
	if value is Dictionary and value.has("vector2i"): return Vector2i(int(value.vector2i[0]), int(value.vector2i[1]))
	if value is Array:
		var result := []
		for element in value: result.append(convert_arg(element))
		return result
	if typeof(value) == TYPE_FLOAT: return int(value)
	return value

func _ready() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/contract.json"))
	check(contract.capabilities.response_timeout_client_seconds == ClientCapabilities.NEGOTIATION_TIMEOUT_SECONDS, "Plazo de negociación desactualizado")
	check(contract.capabilities.mask_bits.expansion == ClientCapabilities.EXPANSION, "Bit EXPANSION ausente")
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/fixtures.json"))
	var protocol := GameProtocol.new()
	var writers := 0
	var receivers := 0
	ClientInterface.capabilities.enabled = ClientCapabilities.REQUESTED
	ClientInterface.world_state.epoch = "a".repeat(32)
	for fixture in fixtures:
		var bytes: PackedByteArray = fixture.hex.hex_decode()
		var framer := AOPacketFramer.new(fixture.direction)
		check(framer.feed(bytes).size() == 1 and framer.error.is_empty() and framer.pending_size() == 0, fixture.name + " inválida")
		if fixture.has("godot"):
			var actual: PackedByteArray
			GameProtocol.Clear()
			if fixture.godot.capabilities:
				actual = ClientCapabilities.new().begin()
			else:
				protocol.callv(fixture.godot.method, convert_arg(fixture.godot.args))
				actual = GameProtocol.Flush()
			check(actual == bytes, "Writer difiere: " + fixture.name)
			writers += 1
		if fixture.direction == "server" and bytes[0] == 67:
			var creation = load("res://screens/character_creation_screen.tscn").instantiate()
			add_child(creation)
			creation._OnDataReceivedd(bytes)
			check(creation._attributeContainer.get_child(0).text.contains(str(int(bytes[1]))), "La pantalla de alta no leyó los atributos")
			creation.free()
			receivers += 1
		elif fixture.direction == "server" and bytes[0] != 250:
			var decoder := AOMessageDispatcher.new()
			var errors := []
			decoder.protocol_error.connect(func(message: String): errors.append(message))
			decoder.dispatch(bytes)
			check(errors.is_empty(), "Receptor " + fixture.name + ": " + str(errors))
			receivers += 1
	GameProtocol.Clear()
	GameProtocol.WriteWalk(0)
	check(GameProtocol.Flush().is_empty(), "Envió dirección inválida")
	GameProtocol.WriteWalk(257)
	check(GameProtocol.Flush().is_empty(), "Truncó una dirección inválida antes de validarla")
	GameProtocol.WriteBankDepositItem(31, 1)
	check(GameProtocol.Flush().is_empty(), "Envió slot inválido")
	for bad in [PackedByteArray([7, 1, 0, 0]), PackedByteArray([85]), PackedByteArray([99]), PackedByteArray([9, 0, 0])]:
		var decoder := AOMessageDispatcher.new()
		var errors := []
		decoder.protocol_error.connect(func(message: String): errors.append(message))
		decoder.dispatch(bad)
		check(not errors.is_empty(), "Aceptó ruta retirada o bytes sobrantes")
	protocol.free()
	ClientInterface.capabilities.clear()
	ClientInterface.world_state.clear()
	print("WIRE_VALIDATION: writers=", writers, " receivers=", receivers, " failures=", failures)
	get_tree().quit(1 if failures else 0)
