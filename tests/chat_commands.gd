extends Node

# Uses the actual console parser and packet writers, without a network connection.
class ProbeHub extends HubController:
	var observed: Array[String] = []
	func ShowConsoleMessage(message: String, _font: FontData = null) -> void:
		observed.append(message)

	func show_password_change_window() -> void:
		observed.append("password_form")

	func show_guild_foundation_window() -> void:
		observed.append("foundation_form")

	func OpenClanDetails() -> void:
		observed.append("clan_form")

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Global.log_outgoing_packets = false
	ClientInterface.capabilities.enabled = ClientCapabilities.REQUESTED
	var hub := ProbeHub.new()
	var context := GameContext.new()
	context.player_stats.hp = 100
	context.player_stats.max_hp = 100
	context.player_stats.max_mana = 100
	context.player_stats.mana = 25
	var examples := {
		"/DEPOSITAR": " 100", "/RETIRAR": " 50", "/PMSG": " Mensaje privado",
		"/ECHARPARTY": " Jugador", "/PARTYLIDER": " Invitado",
	}
	var rows: Array = []
	for name in ChatCommandCatalog.definitions:
		var definition: Dictionary = ChatCommandCatalog.definitions[name]
		var text: String = name + examples.get(name, " Argumentos de prueba" if definition.transport == "text" else "")
		hub.observed.clear()
		context.pingTime = 0
		GameProtocol.Clear()
		check(ConsoleCommandProcessor.process(text, hub, context), "Sin ruta: " + name)
		var bytes := GameProtocol.Flush()
		if definition.transport == "text" and name != "/PING":
			check(not bytes.is_empty() and bytes[0] == Enums.ClientPacketID.Talk, "Transporte de texto incorrecto: " + name)
			if not bytes.is_empty():
				var reader := StreamPeerBuffer.new()
				reader.data_array = bytes
				reader.get_u8()
				var length := reader.get_u16()
				check(reader.get_data(length)[1].get_string_from_ascii() == text, "Se modificaron argumentos: " + name)
		elif definition.transport == "form":
			check(bytes.is_empty() and not hub.observed.is_empty(), "Formulario sin abrir: " + name)
		else:
			check(not bytes.is_empty(), "Paquete nativo vacío: " + name)
		rows.append({"command": name, "transport": definition.transport, "packet_id": bytes[0] if not bytes.is_empty() else -1, "observed": hub.observed.duplicate()})
	check(rows.size() == 194, "Catálogo incompleto")
	for text in ["/", "/COMERCIARX private", "/METRICS_EXTRA", "/desconocido secret"]:
		hub.observed.clear()
		GameProtocol.Clear()
		check(ConsoleCommandProcessor.process(text, hub, context), "La barra desconocida puede caer en chat público")
		check(GameProtocol.Flush().is_empty(), "Comando desconocido enviado al mapa")
		check(not hub.observed.is_empty() and "desconocido" in hub.observed[0].to_lower(), "Falta rechazo privado")
	var line := LineEdit.new()
	var history := ChatInputHelper.new()
	history.install(line)
	history.record("/APASS\tJugador@Offline")
	history.record("/CONTRASEÑA")
	check(history.history.is_empty(), "Comando sensible guardado en historial")
	history.record("Mensaje normal")
	check(history.history.size() == 1, "Historial normal dejó de funcionar")
	history.dispose()
	line.free()
	# Respuestas largas deben conservar encabezados y un límite de memoria real.
	var screen: GameScreen = load("res://screens/game_screen.tscn").instantiate()
	var console_hub: HubController = screen.get_node("HubController")
	console_hub._console_blocked = true
	console_hub.ShowConsoleMessage("INFO-HEADER")
	for number in range(20):
		console_hub.ShowConsoleMessage("Detalle %d" % number)
	check("INFO-HEADER" in console_hub._consoleRichTextLabel.get_parsed_text(), "La respuesta perdió el encabezado antes de poder leerlo")
	for number in range(console_hub._console_max_lines + 1):
		console_hub.ShowConsoleMessage("Historial %d" % number)
	check(console_hub._consoleRichTextLabel.get_paragraph_count() <= console_hub._console_max_lines, "El historial de consola crece sin límite")
	check("INFO-HEADER" not in console_hub._consoleRichTextLabel.get_parsed_text(), "No se descartó el mensaje más antiguo")
	check(("Historial %d" % console_hub._console_max_lines) in console_hub._consoleRichTextLabel.get_parsed_text(), "El recorte eliminó el mensaje más reciente")
	screen.free()
	# The CLI test verifies this literal never appears in the captured debug log.
	Global.log_outgoing_packets = true
	GameProtocol.WriteTalk("/APASS\tnever-log-secret")
	GameProtocol.Flush()
	Global.log_outgoing_packets = false
	var report_path := OS.get_environment("PYAO_CHAT_REPORT")
	if not report_path.is_empty():
		var output := FileAccess.open(report_path, FileAccess.WRITE)
		check(output != null, "No se pudo escribir el informe de prueba")
		if output:
			output.store_string(JSON.stringify({"engine": Engine.get_version_info(), "network_connected": false, "passed": not failed, "rows": rows}, "  "))
			output.close()
	hub.free()
	print("CHAT_COMMANDS: ", "FAIL" if failed else "PASS", " (194 commands)")
	get_tree().quit(1 if failed else 0)
