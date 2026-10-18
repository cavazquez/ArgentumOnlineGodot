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
	print("PROTOCOL_SMOKE: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
