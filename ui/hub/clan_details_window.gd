extends Window
class_name ClanDetailsWindow

var status: Label
var details: Label
var refresh: Button
var leave: Button
var confirmation: ConfirmationDialog
var values := {}
var _pending := false
var _leaving := false
var _deadline := 0

func _ready() -> void:
	title = "Detalles del clan"
	size = Vector2i(520, 460)
	min_size = Vector2i(360, 320)
	transient = true
	exclusive = true
	theme = Theme.new()
	theme.default_font_size = Global.dialogFontSize
	Global.dialog_font_size_changed.connect(func(value: int): theme.default_font_size = value)
	close_requested.connect(RequestClose)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details)
	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	refresh = Button.new()
	refresh.text = "Actualizar"
	refresh.pressed.connect(RequestDetails)
	buttons.add_child(refresh)
	leave = Button.new()
	leave.text = "Abandonar clan"
	leave.disabled = true
	leave.pressed.connect(func(): confirmation.popup_centered())
	buttons.add_child(leave)
	var close := Button.new()
	close.text = "Cerrar"
	close.pressed.connect(RequestClose)
	buttons.add_child(close)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Abandonar clan"
	confirmation.dialog_text = "¿Querés abandonar tu clan?"
	confirmation.confirmed.connect(_LeaveConfirmed)
	add_child(confirmation)

func _process(_delta: float) -> void:
	if _pending and Time.get_ticks_msec() >= _deadline:
		_pending = false
		refresh.disabled = false
		leave.disabled = values.get("name", "").is_empty()
		status.text = "No se confirmó la solicitud. Revisá la consola o actualizá los detalles."

func RequestClose() -> void:
	hide()
	confirmation.hide()

func RequestDetails() -> void:
	if _pending or not GameProtocol.WriteGuildRequestDetails():
		return
	_Wait("Esperando detalles del servidor…")

func _Wait(message: String) -> void:
	_pending = true
	_deadline = Time.get_ticks_msec() + 5000
	refresh.disabled = true
	leave.disabled = true
	status.text = message

func _LeaveConfirmed() -> void:
	if _pending or values.get("name", "").is_empty():
		return
	_leaving = true
	GameProtocol.WriteGuildLeave()
	GameProtocol.WriteGuildRequestDetails()
	_Wait("Esperando el resultado del servidor…")

func ApplyDetails(data: Dictionary) -> void:
	_pending = false
	values = data
	refresh.disabled = false
	leave.disabled = data.name.is_empty()
	if data.name.is_empty():
		status.text = "No pertenecés a ningún clan."
		details.text = ""
	else:
		status.text = "Seguís perteneciendo al clan; revisá la respuesta en consola." if _leaving else "Datos confirmados por el servidor."
		details.text = "Clan: %s\nFundador: %s\nFundación: %s\nLíder: %s\nSitio: %s\nMiembros: %d\nAlineación: %s\nGuerras: %d\nAlianzas: %d\nPuntos: %s\nCódice: %s\n\n%s" % [data.name, data.founder, data.foundation_date, data.leader, data.website, data.members, data.alignment, data.enemies, data.allies, data.antifaction_points, data.codex, data.description]
	_leaving = false
