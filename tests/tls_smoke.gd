extends Node

const CANARY = "SYNTHETIC_TLS_CANARY_3"
var failed := false
var connections := 0
var failures := 0
var closes := 0
var received := PackedByteArray()
var expected := PackedByteArray()
var login_screen: Node

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var scenario := OS.get_environment("PYAO_TLS_CASE")
	var port := int(OS.get_environment("PYAO_TLS_PORT"))
	var ca := X509Certificate.new()
	check(ca.load(OS.get_environment("PYAO_TLS_CA")) == OK, "No se cargó CA sintética")
	ClientInterface.connected.connect(func():
		connections += 1
		GameProtocol.WriteLoginExistingCharacter("CuentaPrueba", CANARY)
		GameProtocol.WriteLoginNewChar("CuentaPrueba", CANARY, "test@example.invalid", 1, 1, 1, 1, 1)
		var outgoing := GameProtocol.Flush()
		expected = PackedByteArray([88])
		check(ClientInterface.Send(outgoing) == OK, "No se pudo enviar por el transporte validado")
	)
	ClientInterface.disconnected.connect(func(): closes += 1)
	ClientInterface.connection_failed.connect(func(_message): failures += 1)
	ClientInterface.dataReceived.connect(func(data): received.append_array(data))
	check(ClientInterface.Send(CANARY.to_ascii_buffer()) == ERR_UNAVAILABLE, "Se enviaron datos sin conexión")
	var before := Time.get_ticks_msec()
	if scenario == "ui":
		login_screen = load("res://screens/login_screen.tscn").instantiate()
		add_child(login_screen)
		login_screen.get_node("%Ip").text = "127.0.0.1"
		login_screen.get_node("%Port").value = port
		login_screen.get_node("%UseTLS").button_pressed = true
		login_screen.get_node("%CaPath").text = OS.get_environment("PYAO_TLS_CA")
		login_screen._ConnectToHost(login_screen.State.Login)
		check(login_screen._loginPanel.get_node("%Submit").disabled, "No se deshabilitó el formulario durante TLS")
	elif scenario == "immediate":
		check(ClientInterface.ConnectToHost("127.0.0.1", 0, true, ca) != OK, "Puerto inválido aceptado")
	else:
		ClientInterface.ConnectToHost("127.0.0.1", port, scenario != "tcp", null if scenario == "untrusted" else ca)
		check(ClientInterface._deadline_msec >= before + 10000, "El deadline por defecto no es de 10 segundos")
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		if scenario in ["stall", "ui"] and ClientInterface._state == ClientInterface.State.TLS_HANDSHAKING:
			# Reloj controlado: vencer el plazo sin esperar diez segundos reales.
			ClientInterface._deadline_msec = Time.get_ticks_msec() - 1
		if scenario == "cancel" and ClientInterface._state == ClientInterface.State.TLS_HANDSHAKING:
			ClientInterface.DisconnectFromHost()
			break
		if failures > 0 or (not expected.is_empty() and received.size() >= expected.size()):
			break
	if scenario in ["valid", "tcp"]:
		check(connections == 1 and failures == 0, "No se completó la conexión esperada")
		check(not received.is_empty() and received.count(88) == received.size(), "Los mensajes de login/alta no atravesaron el transporte")
		# Un plazo anterior no se aplica a una conexión ya completada.
		ClientInterface._deadline_msec = 0
		await get_tree().process_frame
		check(ClientInterface.IsConnected(), "Un deadline tardío desconectó la sesión")
	elif scenario == "cancel":
		check(connections == 0 and failures == 0 and closes == 1, "La cancelación no terminó una sola vez")
	else:
		check(connections == 0 and failures == 1 and closes == 1, "Se aceptó un certificado inválido o se duplicó el resultado")
		check(not ClientInterface.is_processing(), "Quedó un poll activo después de fallar")
	if scenario == "ui":
		check(not login_screen._loginPanel.get_node("%Submit").disabled, "No se restauró el formulario al fallar TLS")
		check(login_screen.get_node("%Ip").editable, "No se restauró la edición del endpoint")
		login_screen.queue_free()
		await get_tree().process_frame
	ClientInterface.DisconnectFromHost()
	check(ClientInterface.Send(CANARY.to_ascii_buffer()) == ERR_UNAVAILABLE, "Se reutilizó un transporte cerrado")
	# Un segundo intento empieza con socket, handshake y buffers nuevos.
	connections = 0
	failures = 0
	received.clear()
	expected.clear()
	ClientInterface.ConnectToHost("127.0.0.1", int(OS.get_environment("PYAO_TLS_RETRY_PORT")), true, ca)
	end = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end and (expected.is_empty() or received.size() < expected.size()) and failures == 0:
		await get_tree().process_frame
	check(connections == 1 and failures == 0 and not received.is_empty() and received.count(88) == received.size(), "El segundo intento no se recuperó")
	ClientInterface.DisconnectFromHost()
	var preferences := {"host": "127.0.0.1", "port": port, "tls": false, "ca_path": ""}
	check(ConnectionPreferences.save_preferences(preferences) == OK, "No se guardó selección explícita de TCP")
	check(ConnectionPreferences.load_preferences().tls == false, "No se conservó la selección de transporte")
	print("TLS_SMOKE: ", scenario, " ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
