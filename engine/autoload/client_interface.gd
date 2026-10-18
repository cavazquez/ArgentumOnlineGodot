extends Node

signal connected
signal disconnected
signal connection_failed(message: String)
signal serialization_failed(message: String)
signal capabilities_changed
signal dataReceived(data: PackedByteArray)

enum State { DISCONNECTED, CONNECTING, TLS_HANDSHAKING, CONNECTED }

var _socket: StreamPeerTCP = StreamPeerTCP.new()
var _tls: StreamPeerTLS
var _transport: StreamPeer
var _state := State.DISCONNECTED
var _use_tls := true
var _hostname := ""
var _deadline_msec := 0
var capabilities := ClientCapabilities.new()
var _logged := false
var _framer := AOPacketFramer.new()
var _generation := 0
var _trusted_ca: X509Certificate

func _ready() -> void:
	set_process(false)

func _reset() -> void:
	_generation += 1
	_framer.clear()
	capabilities.clear()
	_logged = false
	set_process(false)
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
	_reset()
	if host.strip_edges().is_empty() or port < 1 or port > 65535 or timeout_seconds <= 0:
		_fail("Dirección, puerto o plazo de conexión inválido")
		return ERR_INVALID_PARAMETER
	_hostname = host.strip_edges()
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
	if not IsConnected() or _transport == null:
		return ERR_UNAVAILABLE
	if data.is_empty():
		return OK
	var result := _transport.put_data(data)
	if result != OK:
		_fail("No se pudo enviar al servidor")
	return result

func _mark_connected() -> void:
	_state = State.CONNECTED
	connected.emit()

func _process(_delta: float) -> void:
	if capabilities.expire():
		capabilities_changed.emit()
	if _state != State.CONNECTED and Time.get_ticks_msec() >= _deadline_msec:
		_fail("Se agotó el tiempo de conexión o verificación TLS")
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
	var available := _transport.get_available_bytes()
	if available > 0:
		var response := _transport.get_partial_data(mini(available, 65536))
		if response[0] != OK:
			_fail("No se pudieron recibir datos del servidor")
			return
		_AcceptIncomingData(response[1])

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
