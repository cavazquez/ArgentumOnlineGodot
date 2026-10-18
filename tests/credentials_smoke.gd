extends Node

var failed := false
const CANARY = "SYNTHETIC_CANARY_431"

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _ready() -> void:
	SavedCredentials.clear_credentials()
	var legacy := FileAccess.open(SavedCredentials.LEGACY_FILE, FileAccess.WRITE)
	legacy.store_string("CuentaPrueba\n" + CANARY)
	legacy.close()
	check(SavedCredentials.load_username() == "CuentaPrueba", "No se migró el usuario legado")
	check(not FileAccess.file_exists(SavedCredentials.LEGACY_FILE), "Se conserva el archivo con contraseña")
	var preferences := FileAccess.get_file_as_string(SavedCredentials.PREFERENCES_FILE)
	check(not preferences.contains(CANARY), "Se guardó la contraseña en preferencias")
	check(SavedCredentials.load_username() == "CuentaPrueba", "La migración no es idempotente")
	var panel = load("res://ui/login_panel.tscn").instantiate()
	add_child(panel)
	check(panel.GetUsername() == "CuentaPrueba", "No se recordó el usuario")
	check(panel.GetPassword().is_empty(), "Se restauró una contraseña")
	check(panel.get_node("%RememberUsername").text == "Recordar usuario", "Texto de preferencia incorrecto")
	Global.log_outgoing_packets = true
	GameProtocol.Clear()
	GameProtocol.WriteLoginExistingCharacter("CuentaPrueba", CANARY)
	var login := GameProtocol.Flush()
	var wire := StreamPeerBuffer.new()
	wire.data_array = login
	wire.get_u8()
	var username_length := wire.get_u16()
	wire.get_data(username_length)
	var password_length := wire.get_u16()
	check(wire.get_data(password_length)[1].get_string_from_ascii() == CANARY, "Se alteró la contraseña enviada por red")
	check(login.size() > CANARY.length(), "El saneamiento de logs alteró el paquete de login")
	GameProtocol.WriteLoginNewChar("CuentaPrueba", CANARY, "synthetic@example.invalid", 1, 1, 1, 1, 1)
	GameProtocol.Flush()
	GameProtocol.WriteChangePassword(CANARY, CANARY + "NEW")
	GameProtocol.Flush()
	# El transporte tampoco recibe una instrucción para imprimir bytes salientes.
	ClientInterface.Send(login)
	Global.log_outgoing_packets = false
	GameProtocol.WriteLoginExistingCharacter("CuentaPrueba", CANARY)
	ClientInterface.Send(GameProtocol.Flush())
	GameProtocol.WriteLoginNewChar("CuentaPrueba", CANARY, "synthetic@example.invalid", 1, 1, 1, 1, 1)
	GameProtocol.Flush()
	SavedCredentials.clear_credentials()
	check(SavedCredentials.load_username().is_empty(), "No se borró la preferencia")
	check(not FileAccess.file_exists(SavedCredentials.PREFERENCES_FILE), "Persiste el nombre tras borrarlo")
	panel.queue_free()
	print("CREDENTIALS_SMOKE: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
