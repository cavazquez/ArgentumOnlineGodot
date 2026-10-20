extends Window

const SHOW_PASSWORD_ICON: Texture2D = preload("res://Assets/UI/password-show.svg")
const HIDE_PASSWORD_ICON: Texture2D = preload("res://Assets/UI/password-hide.svg")

@onready var current_password_input: LineEdit = $VBoxContainer/FormContainer/CurrentPasswordInput
@onready var new_password_input: LineEdit = $VBoxContainer/FormContainer/NewPasswordInput
@onready var confirm_password_input: LineEdit = $VBoxContainer/FormContainer/ConfirmPasswordInput
@onready var accept_button: Button = $VBoxContainer/ButtonsContainer/AcceptButton
@onready var cancel_button: Button = $VBoxContainer/ButtonsContainer/CancelButton
@onready var current_password_toggle: Button = $VBoxContainer/FormContainer/CurrentPasswordToggle
@onready var new_password_toggle: Button = $VBoxContainer/FormContainer/NewPasswordToggle
@onready var confirm_password_toggle: Button = $VBoxContainer/FormContainer/ConfirmPasswordToggle
@onready var error_label: Label = $VBoxContainer/ErrorLabel
var hub_controller: HubController
var operation_id := ""
var _pending_id := ""
var _challenge_pending := false
var _deadline := 0

func _ready() -> void:
	title = "Cambiar contraseña"
	accept_button.pressed.connect(_on_accept_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(RequestClose)
	for field in [current_password_input, new_password_input, confirm_password_input]:
		field.secret = true
		field.max_length = CredentialPolicy.MAX_PASSWORD
		field.text_changed.connect(_validate_fields)
	current_password_toggle.pressed.connect(_toggle_password.bind(current_password_input, current_password_toggle))
	new_password_toggle.pressed.connect(_toggle_password.bind(new_password_input, new_password_toggle))
	confirm_password_toggle.pressed.connect(_toggle_password.bind(confirm_password_input, confirm_password_toggle))
	ClientInterface.disconnected.connect(_Disconnected)
	_validate_fields()

func _clear_fields() -> void:
	for field in [current_password_input, new_password_input, confirm_password_input]:
		field.text = ""
		field.secret = true
	for button in [current_password_toggle, new_password_toggle, confirm_password_toggle]:
		button.icon = SHOW_PASSWORD_ICON
		button.tooltip_text = "Mostrar contraseña"

func _toggle_password(field: LineEdit, button: Button) -> void:
	field.secret = not field.secret
	button.icon = SHOW_PASSWORD_ICON if field.secret else HIDE_PASSWORD_ICON
	button.tooltip_text = "Mostrar contraseña" if field.secret else "Ocultar contraseña"

func _validate_fields(_text: String = "") -> void:
	if not ClientInterface.capabilities.can_send(Enums.ClientPacketID.ChangePassword) and error_label.text.is_empty():
		error_label.text = "El servidor no ofrece cambio de contraseña."
	var ready := ClientInterface.capabilities.can_send(Enums.ClientPacketID.ChangePassword) and not operation_id.is_empty() and _pending_id.is_empty() and not _challenge_pending
	for field in [current_password_input, new_password_input, confirm_password_input]:
		field.editable = ready
	accept_button.disabled = not ready or not CredentialPolicy.validate("usr", current_password_input.text).is_empty() or not CredentialPolicy.validate("usr", new_password_input.text).is_empty() or new_password_input.text != confirm_password_input.text

func show_window(controller: HubController = null) -> void:
	hub_controller = controller
	_clear_fields()
	popup_centered()
	if not ClientInterface.capabilities.can_send(Enums.ClientPacketID.ChangePassword):
		error_label.text = "El servidor no ofrece cambio de contraseña."
		_validate_fields()
		return
	if not _pending_id.is_empty():
		_QueryPending()
	elif _challenge_pending and Time.get_ticks_msec() < _deadline:
		_validate_fields()
		return
	else:
		operation_id = ""
		_challenge_pending = GameProtocol.WritePasswordRequest("", "", "")
		_deadline = Time.get_ticks_msec() + 5000
		error_label.text = "Preparando una solicitud segura…"
	_validate_fields()

func _on_accept_pressed() -> void:
	if accept_button.disabled or not _pending_id.is_empty():
		return
	if GameProtocol.WritePasswordRequest(operation_id, current_password_input.text, new_password_input.text):
		_pending_id = operation_id
		operation_id = ""
		_clear_fields()
		_deadline = Time.get_ticks_msec() + 5000
		error_label.text = "Esperando confirmación del servidor…"
		_validate_fields()

func ApplyReply(reply: PasswordChangeReply) -> void:
	if not _pending_id.is_empty():
		if reply.operation_id != _pending_id:
			return
		if reply.status == 0:
			error_label.text = "Resultado aún no confirmado; consultando…"
			_deadline = Time.get_ticks_msec() + 5000
			return
	elif not reply.operation_id.is_empty():
		return
	_pending_id = ""
	_challenge_pending = false
	operation_id = reply.next_operation_id
	_clear_fields()
	error_label.text = reply.message if not reply.message.is_empty() else "Ingresá la contraseña actual y la nueva."
	error_label.add_theme_color_override("font_color", Color.LIGHT_GREEN if reply.status == 1 else (Color.ORANGE if reply.status == 3 else Color.WHITE))
	_validate_fields()

func _QueryPending() -> void:
	if not _pending_id.is_empty():
		GameProtocol.WritePasswordRequest(_pending_id, "", "")
		_deadline = Time.get_ticks_msec() + 5000
		error_label.text = "Sin confirmación; consultando la operación original…"

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() < _deadline:
		return
	if not _pending_id.is_empty():
		_QueryPending()
	elif _challenge_pending:
		_challenge_pending = false
		error_label.text = "El servidor no respondió. Cerrá y volvé a abrir para reintentar."
		_validate_fields()

func RequestClose() -> void:
	_clear_fields()
	_validate_fields()
	hide()

func _on_cancel_pressed() -> void:
	RequestClose()

func _Disconnected() -> void:
	operation_id = ""
	_pending_id = ""
	_challenge_pending = false
	_clear_fields()
	error_label.text = "Conexión cerrada; no se confirmó ningún resultado local."
	_validate_fields()
