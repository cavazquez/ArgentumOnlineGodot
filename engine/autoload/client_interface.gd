extends Node

signal connected
signal disconnected
signal connection_failed(message: String)
signal serialization_failed(message: String)
signal capabilities_changed
signal dataReceived(data: PackedByteArray)

enum State { DISCONNECTED, CONNECTING, TLS_HANDSHAKING, CONNECTED }

const MAX_READS_PER_FRAME := 256
const MAX_RECEIVED_BYTES_PER_FRAME := 65536

var _socket: StreamPeerTCP = StreamPeerTCP.new()
var _tls: StreamPeerTLS
var _transport: StreamPeer
var _state := State.DISCONNECTED
var _use_tls := true
var _hostname := ""
var _port := 0
var _deadline_msec := 0
var capabilities := ClientCapabilities.new()
var world_state := WorldStateContext.new()
var _logged := false
var _framer := AOPacketFramer.new()
var _generation := 0
var _trusted_ca: X509Certificate
var _websocket: WebSocketPeer
var _websocket_url := ""
var _closing_websockets: Array[Dictionary] = []

func _ready() -> void:
	set_process(false)

func _reset() -> void:
	_generation += 1
	_framer.clear()
	capabilities.clear()
	world_state.clear()
	Global.character_local.open_profile("")
	_logged = false
	set_process(false)
	if _websocket != null:
		_websocket.close()
		_closing_websockets.append({"peer": _websocket, "deadline": Time.get_ticks_msec() + 5000})
	_websocket = null
	_websocket_url = ""
	set_process(not _closing_websockets.is_empty())
	if _tls != null:
		_tls.disconnect_from_stream()
	_socket.disconnect_from_host()
	_socket = StreamPeerTCP.new()
	_tls = null
	_transport = null
	_state = State.DISCONNECTED
	_trusted_ca = null
	GameProtocol.Clear()

func ConnectToHost(host: String, port: int, use_tls: bool = true, trusted_ca: X509Certificate = null, timeout_seconds: float = 10.0) -> Error:
	if host.strip_edges().begins_with("wss://"):
		return ConnectToWebSocket(host.strip_edges(), trusted_ca, timeout_seconds)
	if OS.has_feature("web"):
		if not use_tls:
			_fail("El navegador requiere un endpoint WSS seguro")
			return ERR_INVALID_PARAMETER
		return ConnectToWebSocket("wss://%s:%d" % [host.strip_edges(), port], null, timeout_seconds)
	_reset()
	if host.strip_edges().is_empty() or port < 1 or port > 65535 or timeout_seconds <= 0:
		_fail("Dirección, puerto o plazo de conexión inválido")
		return ERR_INVALID_PARAMETER
	_hostname = host.strip_edges()
	_port = port
	_use_tls = use_tls
	_trusted_ca = trusted_ca
	_deadline_msec = Time.get_ticks_msec() + int(timeout_seconds * 1000)
	_state = State.CONNECTING
	var result := _socket.connect_to_host(_hostname, port)
	if result != OK:
		_fail("No se pudo conectar con el servidor")
		return result
	set_process(true)
	return OK

func DisconnectFromHost() -> void:
	var was_active := _state != State.DISCONNECTED
	_reset()
	if was_active:
		disconnected.emit()

func IsConnected() -> bool:
	return _state == State.CONNECTED

func _fail(message: String) -> void:
	_reset()
	disconnected.emit()
	connection_failed.emit(message)

func Send(data: PackedByteArray) -> Error:
	# No se encolan credenciales antes de validar completamente el handshake.
	if not IsConnected() or (_transport == null and _websocket == null):
		return ERR_UNAVAILABLE
	if data.is_empty():
		return OK
	if _websocket != null:
		var result := _websocket.send(data, WebSocketPeer.WRITE_MODE_BINARY)
		if result != OK: _fail("No se pudo enviar al servidor WSS")
		return result
	var result := _transport.put_data(data)
	if result != OK:
		_fail("No se pudo enviar al servidor")
	return result

func _mark_connected() -> void:
	_state = State.CONNECTED
	connected.emit()

func _process(_delta: float) -> void:
	for index in range(_closing_websockets.size() - 1, -1, -1):
		var closing: WebSocketPeer = _closing_websockets[index].peer
		closing.poll()
		if closing.get_ready_state() == WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec() >= int(_closing_websockets[index].deadline):
			if closing.get_ready_state() != WebSocketPeer.STATE_CLOSED: closing.close(-1)
			_closing_websockets.remove_at(index)
	if _state == State.DISCONNECTED:
		set_process(not _closing_websockets.is_empty())
		return
	if capabilities.expire():
		capabilities_changed.emit()
	if _state != State.CONNECTED and Time.get_ticks_msec() >= _deadline_msec:
		_fail("Se agotó el tiempo de conexión o verificación TLS")
		return
	if _websocket != null:
		_ProcessWebSocket()
		return
	_socket.poll()
	var tcp_status := _socket.get_status()
	if tcp_status == StreamPeerTCP.STATUS_ERROR or tcp_status == StreamPeerTCP.STATUS_NONE:
		_fail("La conexión con el servidor se cerró")
		return
	if tcp_status != StreamPeerTCP.STATUS_CONNECTED:
		return
	if _state == State.CONNECTING:
		if _use_tls:
			_tls = StreamPeerTLS.new()
			_state = State.TLS_HANDSHAKING
			# client verifica cadena, vigencia y hostname; nunca client_unsafe.
			if _tls.connect_to_stream(_socket, _hostname, TLSOptions.client(_trusted_ca)) != OK:
				_fail("No se pudo iniciar la verificación TLS")
				return
			_transport = _tls
		else:
			_transport = _socket
			_mark_connected()
	if _tls != null:
		_tls.poll()
		var tls_status := _tls.get_status()
		if tls_status == StreamPeerTLS.STATUS_HANDSHAKING:
			return
		if tls_status != StreamPeerTLS.STATUS_CONNECTED:
			_fail("No se pudo verificar el certificado TLS o el nombre del servidor")
			return
		if _state == State.TLS_HANDSHAKING:
			_mark_connected()
	# Un listener de connected puede cerrar o cambiar de pantalla.
	if _state != State.CONNECTED or _transport == null:
		return
	_ReadAvailableData()

func _ReadAvailableData() -> void:
	# TLS puede exponer un solo registro por poll. Leer uno por cuadro convierte
	# los mensajes pequeños del login en segundos de espera, aunque ya llegaron.
	var generation := _generation
	var remaining := MAX_RECEIVED_BYTES_PER_FRAME
	for _read in MAX_READS_PER_FRAME:
		if generation != _generation or _state != State.CONNECTED or _transport == null:
			return
		if _tls != null:
			_tls.poll()
			if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
				_fail("La conexión TLS con el servidor se cerró")
				return
		var available := _transport.get_available_bytes()
		if available <= 0:
			return
		var response := _transport.get_partial_data(mini(available, remaining))
		if response[0] != OK:
			_fail("No se pudieron recibir datos del servidor")
			return
		var data: PackedByteArray = response[1]
		if data.is_empty():
			return
		remaining -= data.size()
		_AcceptIncomingData(data)
		if remaining <= 0:
			return

func _AcceptIncomingData(data: PackedByteArray) -> void:
	var generation := _generation
	var packets := _framer.feed(data)
	if not _framer.error.is_empty():
		_fail("Protocolo inválido: " + _framer.error)
		return
	for packet in packets:
		if packet[0] == ClientCapabilities.PACKET_ID:
			capabilities.accept(packet)
			capabilities_changed.emit()
			continue
		var required := _framer.required_capability(packet[0])
		if required != 0 and not capabilities.has_feature(required):
			_fail("El servidor envió una extensión no negociada")
			return
		dataReceived.emit(packet)
		# Una devolución puede desconectar o comenzar otro intento.
		if generation != _generation:
			return
		if packet[0] == 0 and not _logged:
			_logged = true
			# Opt-in exclusivamente después de Logged; nunca antecede al login pyao.
			if IsConnected():
				Send(capabilities.begin())


func local_character_key(character: String) -> String:
	if not _logged or _hostname.is_empty() or _port < 1 or character.is_empty(): return ""
	if _websocket != null:
		return ("%s|%s" % [_websocket_url, character]).sha256_text()
	return ("%s|%s|%d|%s" % ["tls" if _use_tls else "tcp", _hostname.to_lower(), _port, character]).sha256_text()

func ConnectToWebSocket(url: String, trusted_ca: X509Certificate = null, timeout_seconds: float = 10.0, origin: String = "") -> Error:
	_reset()
	var format := RegEx.new()
	format.compile("^wss://(\\[[0-9a-fA-F:]+\\]|[a-zA-Z0-9.-]+)(?::([0-9]{1,5}))?(/[^?#\\s]*)?$")
	var match_url := format.search(url)
	if match_url == null or timeout_seconds <= 0:
		_fail("La dirección web debe ser WSS, sin usuario, contraseña ni parámetros")
		return ERR_INVALID_PARAMETER
	_hostname = match_url.get_string(1).trim_prefix("[").trim_suffix("]")
	_port = int(match_url.get_string(2)) if not match_url.get_string(2).is_empty() else 443
	if not 1 <= _port or _port > 65535:
		_fail("Puerto WSS inválido")
		return ERR_INVALID_PARAMETER
	_websocket_url = url
	_use_tls = true
	_websocket = WebSocketPeer.new()
	_websocket.inbound_buffer_size = 131072
	_websocket.outbound_buffer_size = 131072
	_websocket.max_queued_packets = 256
	if not OS.has_feature("web"):
		_websocket.handshake_headers = PackedStringArray(["Origin: " + (origin if not origin.is_empty() else "https://" + url.get_slice("/", 2))])
	var options := TLSOptions.client(trusted_ca) if not OS.has_feature("web") else null
	var result := _websocket.connect_to_url(url, options)
	if result != OK:
		_fail("No se pudo iniciar la conexión WSS")
		return result
	if OS.has_feature("web"):
		WebPreferences.select_endpoint(url)
	_deadline_msec = Time.get_ticks_msec() + int(timeout_seconds * 1000)
	_state = State.CONNECTING
	set_process(true)
	return OK

func _ProcessWebSocket() -> void:
	var generation := _generation
	_websocket.poll()
	var state := _websocket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING: return
	if state == WebSocketPeer.STATE_CLOSED:
		_fail("La conexión WSS se cerró o no se pudo verificar su certificado")
		return
	if state != WebSocketPeer.STATE_OPEN: return
	if _state == State.CONNECTING: _mark_connected()
	if generation != _generation or _websocket == null: return
	var remaining := MAX_RECEIVED_BYTES_PER_FRAME
	for _read in MAX_READS_PER_FRAME:
		if generation != _generation or _websocket == null or _websocket.get_available_packet_count() == 0: return
		var data := _websocket.get_packet()
		if _websocket.was_string_packet() or data.size() > 65536:
			_fail("Protocolo WSS inválido: sólo se aceptan mensajes AO binarios acotados")
			return
		remaining -= data.size()
		_AcceptIncomingData(data)
		if remaining <= 0: return
