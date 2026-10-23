extends Window
class_name WorldStateWindow

var topic := ""
var state: Dictionary = {}
var revision := ""
var body: VBoxContainer
var status: Label
var _pending: Dictionary = {}
var _deadline := 0
var _retry: Button
var _refresh: Button
var _confirmation: ConfirmationDialog
var _confirmed_action: Dictionary = {}

func _ready() -> void:
	Utils.ApplyDialogTheme(self)
	size = Vector2i(620, 530)
	min_size = Vector2i(420, 360)
	transient = true
	exclusive = true
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_build()
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Esperando estado del servidor…"
	root.add_child(status)
	var actions := HBoxContainer.new()
	root.add_child(actions)
	_refresh = button(actions, "Actualizar estado", request_state)
	_retry = button(actions, "Reintentar la misma operación", _resend)
	_retry.hide()
	_confirmation = ConfirmationDialog.new()
	add_child(_confirmation)
	Utils.ApplyDialogTheme(_confirmation)
	_confirmation.confirmed.connect(_confirm)
	ClientInterface.world_state.changed.connect(_receive)
	visibility_changed.connect(_visibility)
	hide()

func _build() -> void:
	pass

func _render() -> void:
	pass

func button(parent: Node, caption: String, callback: Callable) -> Button:
	var value := Button.new()
	value.text = caption
	value.pressed.connect(callback)
	parent.add_child(value)
	return value

func label(parent: Node, text: String = "") -> Label:
	var value := Label.new()
	value.text = text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(value)
	return value

func Open() -> void:
	popup_centered()

func _visibility() -> void:
	if topic.is_empty() or not ClientInterface.capabilities.has_feature(ClientCapabilities.WORLD_STATE): return
	if visible:
		if ClientInterface.world_state.states.has(topic):
			_receive(topic, ClientInterface.world_state.states[topic], ClientInterface.world_state.revisions.get(topic, ""))
		GameProtocol.WriteWorldAction("subscribe", {"topic": topic, "enabled": true})
		request_state()
	elif not topic in ["tax", "weather", "lottery"]:
		GameProtocol.WriteWorldAction("subscribe", {"topic": topic, "enabled": false})

func request_state() -> void:
	var params := {"page": int(state.get("page", 0))} if topic == "clan" else {}
	if not GameProtocol.WriteWorldAction(topic + ".read", params):
		status.text = "Esta función requiere el servidor actualizado."

func pending() -> bool:
	return not _pending.is_empty()

func mutate(action: String, params: Dictionary = {}) -> void:
	if pending() or revision.is_empty() or ClientInterface.world_state.epoch.is_empty(): return
	var identity := GameProtocol.NewSkillActionId()
	_pending = {"id": identity, "action": action, "params": params.duplicate(true), "revision": revision, "epoch": ClientInterface.world_state.epoch}
	_resend()
	_render()

func confirm_action(action: String, params: Dictionary, explanation: String) -> void:
	if pending() or revision.is_empty(): return
	_confirmed_action = {"action": action, "params": params, "revision": revision}
	_confirmation.dialog_text = explanation
	_confirmation.popup_centered()

func _confirm() -> void:
	if _confirmed_action.get("revision", "") != revision:
		status.text = "El estado cambió; volvé a seleccionar la acción."
		return
	mutate(_confirmed_action.action, _confirmed_action.params)
	_confirmed_action.clear()

func _resend() -> void:
	if _pending.is_empty(): return
	if _pending.epoch != ClientInterface.world_state.epoch:
		_pending.clear()
		status.text = "La conexión cambió; consultá el estado."
		return
	if GameProtocol.WriteWorldAction(_pending.action, _pending.params, _pending.revision, _pending.id):
		_deadline = Time.get_ticks_msec() + 5000
		_retry.hide()
		status.text = "Esperando confirmación del servidor…"
	else:
		_pending.clear()
		_deadline = 0
		status.text = "No se pudo enviar. Revisá la conexión y los caracteres ingresados antes de intentarlo otra vez."
		_retry.hide()
		_render()

func _receive(kind: String, data: Dictionary, value: String) -> void:
	if kind == "reset":
		_pending.clear()
		state.clear()
		revision = ""
		_confirmation.hide()
		_retry.hide()
		status.text = "Desconectado."
		_render()
	elif kind == "result" and data.get("id", "") == _pending.get("id", "missing"):
		status.text = data.get("message", "Respuesta recibida.")
		if data.get("uncertain", false):
			_retry.show()
		else:
			_pending.clear()
			_retry.hide()
		_deadline = 0
		_render()
	elif kind == topic:
		if revision != value: _confirmation.hide()
		state = data.duplicate(true)
		revision = value
		if _pending.is_empty() and status.text == "Esperando estado del servidor…": status.text = "Estado confirmado."
		_render()

func _process(_delta: float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		_deadline = 0
		_retry.show()
		status.text = "La respuesta está pendiente. Podés consultar el estado o reintentar la misma operación."
