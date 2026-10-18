extends Node

enum State {
	None,
	Login,
	NewPj
}

@export var _loginPanel:LoginPanel

var _state:State

func _ready() -> void:
	DisplayServer.window_set_title("PyAO Client " + str(ProjectSettings.get_setting("application/config/version", "unknown")))
	ClientInterface.connected.connect(_OnConnected)
	ClientInterface.disconnected.connect(_OnDisconnected)
	ClientInterface.dataReceived.connect(_OnDataReceived)
	ClientInterface.connection_failed.connect(_OnConnectionFailed)
	var preferences := ConnectionPreferences.load_preferences()
	%Ip.text = preferences.host
	%Port.value = preferences.port
	%UseTLS.button_pressed = preferences.tls
	%CaPath.text = preferences.ca_path
	%CancelConnection.pressed.connect(ClientInterface.DisconnectFromHost)
	
	_loginPanel.error.connect(func(message): 
		Utils.ShowAlertDialog("Login", message, self)) 
	
func _OnConnected() -> void:
	if _state == State.NewPj:
		_DetachNetwork()
		var screen = load("uid://bp35uafwebjdb").instantiate()
		ScreenController.SwitchScreen(screen)
	elif _state == State.Login:
		GameProtocol.WriteLoginExistingCharacter(_loginPanel.GetUsername(), _loginPanel.GetPassword())
		_Flush()
	
func _OnDisconnected() -> void:
	_SetEndpointControls(true)
	_state = State.None
	_loginPanel.EnableAuthControls()
	
func _OnConnectionFailed(message: String) -> void:
	_OnDisconnected()
	Utils.ShowAlertDialog("Conexión", message, self)

func _SetEndpointControls(enabled: bool) -> void:
	%Ip.editable = enabled
	%Port.editable = enabled
	%UseTLS.disabled = not enabled
	%CaPath.editable = enabled
	%CancelConnection.visible = not enabled

func _GetEnpoint() -> Dictionary:
	return {
		"host": %Ip.text,
		"port": int(%Port.value),
		"tls": %UseTLS.button_pressed,
		"ca_path": %CaPath.text.strip_edges()
	}

func _OnDataReceived(data:PackedByteArray) -> void:
	var stream = StreamPeerBuffer.new()
	stream.data_array = data
	
	while stream.get_position() < stream.get_size():
		var packetId = stream.get_u8()
		match packetId:
			Enums.ServerPacketID.ErrorMsg:
				_HandleErrorMsg(Utils.GetUnicodeString(stream))
			Enums.ServerPacketID.Logged:
				_HandleLogged(data)
				return

func _HandleErrorMsg(message:String) -> void:
	Utils.ShowAlertDialog("Server", message, self)
	ClientInterface.DisconnectFromHost()

func _HandleLogged(data:PackedByteArray) -> void:
	_DetachNetwork()
	var screen = load("uid://b2dyxo3826bub").instantiate() as GameScreen
	screen.networkMessages.append(data)
	
	ScreenController.SwitchScreen(screen)
		
func _OnLoginPanelSubmit() -> void:
	_ConnectToHost(State.Login)
		
func _OnLoginPanelRegister() -> void:
	_ConnectToHost(State.NewPj)
		
func _ConnectToHost(state: State) -> void:
	var endpoint = _GetEnpoint()
	var ca: X509Certificate
	if endpoint.tls and not endpoint.ca_path.is_empty():
		ca = X509Certificate.new()
		if ca.load(endpoint.ca_path) != OK:
			_OnConnectionFailed("No se pudo cargar el certificado de la CA elegida")
			return
	if ConnectionPreferences.save_preferences(endpoint) != OK:
		_OnConnectionFailed("No se pudo guardar la configuración de conexión")
		return
	_state = state
	_loginPanel.DisableAuthControls()
	_SetEndpointControls(false)
	ClientInterface.ConnectToHost(endpoint.host, endpoint.port, endpoint.tls, ca)

func _Flush() -> void:
	ClientInterface.Send(GameProtocol.Flush());

func _DetachNetwork() -> void:
	for pair in [[ClientInterface.connected, _OnConnected], [ClientInterface.disconnected, _OnDisconnected], [ClientInterface.dataReceived, _OnDataReceived], [ClientInterface.connection_failed, _OnConnectionFailed]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
