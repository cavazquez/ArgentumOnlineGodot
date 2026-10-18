extends Window
class_name PlayerTradePanel

signal finished
var snapshot: Dictionary = {}
var inventory: Inventory
var _pending := false
var _closing := false
var _ended := false
var status: Label
var offers: Array[Label] = []
var available: OptionButton
var slot: SpinBox
var quantity: SpinBox
var gold: SpinBox
var item_button: Button
var gold_button: Button
var accept_button: Button
var confirm_button: Button
var cancel_button: Button

func _ready() -> void:
	title = "Intercambio entre jugadores"
	theme = Theme.new()
	theme.default_font_size = Global.dialogFontSize
	Global.dialog_font_size_changed.connect(func(value: int): theme.default_font_size = value)
	size = Vector2i(640, 440)
	min_size = Vector2i(450, 360)
	transient = true
	exclusive = true
	close_requested.connect(RequestClose)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
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
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(columns)
	for index in range(2):
		var offer := Label.new()
		offer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offer.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		columns.add_child(offer)
		offers.append(offer)
	available = OptionButton.new()
	root.add_child(available)
	available.item_selected.connect(func(index: int): slot.value = available.get_item_id(index))
	var editor := HBoxContainer.new()
	root.add_child(editor)
	slot = _number(editor, "Slot", 1, 30)
	quantity = _number(editor, "Cantidad (0: quitar)", 0, 32767)
	quantity.value = 1
	item_button = _button(editor, "Ofrecer objeto", func(): _send(1, int(slot.value), int(quantity.value)))
	var gold_row := HBoxContainer.new()
	root.add_child(gold_row)
	gold = _number(gold_row, "Oro", 0, 999999999)
	gold_button = _button(gold_row, "Ofrecer oro", func(): _send(2, 0, int(gold.value)))
	var actions := HBoxContainer.new()
	root.add_child(actions)
	accept_button = _button(actions, "Aceptar invitación", func(): _send(0))
	confirm_button = _button(actions, "Confirmar esta revisión", func(): _send(3))
	cancel_button = _button(actions, "Cancelar", RequestClose)
	if inventory != null:
		inventory.slotChanged.connect(_InventoryChanged)
		_RefreshInventoryChoices()
	if not snapshot.is_empty():
		ApplySnapshot(snapshot)

func _number(parent: Node, caption: String, minimum: int, maximum: int) -> SpinBox:
	var column := VBoxContainer.new()
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	column.add_child(label)
	var value := SpinBox.new()
	value.min_value = minimum
	value.max_value = maximum
	value.step = 1
	column.add_child(value)
	return value

func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func ApplySnapshot(value: Dictionary) -> void:
	if not snapshot.is_empty() and (value.id != snapshot.id or value.sequence < snapshot.sequence):
		return
	if _ended:
		return
	snapshot = value
	_pending = false
	if status == null:
		return
	status.text = "Revisión %d · %s
%s" % [value.revision, value.state, value.reason]
	for index in range(2):
		var player: Array = value.players[index]
		var lines := "%s%s
Oro: %d
%s" % [player[1], " (vos)" if player[0] == value.viewer else "", player[2], "Confirmado" if player[3] else "Sin confirmar"]
		for item in player[4]:
			var label := "Objeto #%d" % int(item[1])
			if inventory != null:
				for own_index in range(inventory.GetSize()):
					var own := inventory.GetSlot(own_index)
					if own != null and own.item.index == int(item[1]):
						label = own.item.name
						break
			lines += "
%s × %d (slot %d)" % [label, int(item[2]), int(item[0])]
		offers[index].text = lines
	var active: bool = value.state == "active"
	item_button.disabled = not active
	gold_button.disabled = not active
	accept_button.disabled = false
	accept_button.visible = value.state == "pending" and value.viewer == value.players[1][0]
	var own_index := 0 if value.viewer == value.players[0][0] else 1
	confirm_button.disabled = not active or value.players[own_index][3]
	if value.state in ["completed", "cancelled"]:
		_ended = true
		finished.emit()

func _send(action: int, source: int = 0, amount: int = 0) -> void:
	if _pending or _closing or snapshot.is_empty():
		return
	if GameProtocol.WriteTradeAction(snapshot.id, int(snapshot.revision), action, source, amount):
		_pending = true
		item_button.disabled = true
		gold_button.disabled = true
		confirm_button.disabled = true
		accept_button.disabled = true

func RequestClose() -> void:
	if _closing or snapshot.is_empty():
		return
	_closing = GameProtocol.WriteTradeAction(snapshot.id, int(snapshot.revision), 4)
	if _closing:
		status.text = "Esperando el resultado de la cancelación…"
		cancel_button.disabled = true

func _InventoryChanged(_index: int, _stack: ItemStack) -> void:
	_RefreshInventoryChoices()

func _RefreshInventoryChoices() -> void:
	available.clear()
	available.add_item("Tu inventario · elegí un objeto", 0)
	for index in range(inventory.GetSize()):
		var stack := inventory.GetSlot(index)
		if stack != null and stack.quantity > 0:
			available.add_item("Slot %d · %s × %d%s" % [index + 1, stack.item.name, stack.quantity, " (equipado)" if stack.equipped else ""], index + 1)
