extends Window
class_name MerchantPanel

signal finished

var _merchantInventoryContainer: InventoryContainer
var _playerInventoryContainer: InventoryContainer
var _infoLabel: Label
var _quantitySpinBox: SpinBox
var _actionButton: Button
var _merchantInventory: Inventory
var _playerInventory: Inventory
var _source := ""
var _slot := -1
var _selected_item := 0
var _closing := false
var _pending := false

func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = Global.dialogFontSize
	Global.dialog_font_size_changed.connect(func(value: int): theme.default_font_size = value)
	exclusive = true
	transient = true
	close_requested.connect(RequestClose)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	_merchantInventoryContainer = _AddInventory(columns, "Mercader")
	_playerInventoryContainer = _AddInventory(columns, "Tu inventario")
	_infoLabel = Label.new()
	_infoLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_infoLabel)
	_quantitySpinBox = SpinBox.new()
	_quantitySpinBox.min_value = 1
	_quantitySpinBox.max_value = 10000
	_quantitySpinBox.value_changed.connect(func(_value): _Refresh())
	layout.add_child(_quantitySpinBox)
	_actionButton = Button.new()
	_actionButton.pressed.connect(_Submit)
	layout.add_child(_actionButton)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(RequestClose)
	layout.add_child(close_button)
	_merchantInventoryContainer.slotPressed.connect(_Select.bind("buy"))
	_playerInventoryContainer.slotPressed.connect(_Select.bind("sell"))
	_Refresh()

func _AddInventory(parent: Container, label_text: String) -> InventoryContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label := Label.new()
	label.text = label_text
	column.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var grid: InventoryContainer = load("res://ui/hub/inventory_container.tscn").instantiate()
	grid.columns = 5
	scroll.add_child(grid)
	return grid

func SetMerchantInventory(inventory: Inventory) -> void:
	if _merchantInventory != null and _merchantInventory.slotChanged.is_connected(_InventoryChanged):
		_merchantInventory.slotChanged.disconnect(_InventoryChanged)
	_merchantInventory = inventory
	_merchantInventoryContainer.SetInventory(inventory)
	_StyleSlots(_merchantInventoryContainer)
	inventory.slotChanged.connect(_InventoryChanged)
	_ResetSelection()

func SetPlayerInventory(inventory: Inventory) -> void:
	if _playerInventory != null and _playerInventory.slotChanged.is_connected(_InventoryChanged):
		_playerInventory.slotChanged.disconnect(_InventoryChanged)
	_playerInventory = inventory
	_playerInventoryContainer.SetInventory(inventory)
	_StyleSlots(_playerInventoryContainer)
	inventory.slotChanged.connect(_InventoryChanged)
	_ResetSelection()

func _ResetSelection() -> void:
	_source = ""
	_slot = -1
	_merchantInventoryContainer.ClearSelection()
	_playerInventoryContainer.ClearSelection()
	_Refresh()

func _Select(index: int, source: String) -> void:
	_source = source
	_slot = index
	_pending = false
	var other := _playerInventoryContainer if source == "buy" else _merchantInventoryContainer
	other.ClearSelection()
	var stack := _GetStack()
	_selected_item = stack.item.index if stack != null and stack.item != null else 0
	_Refresh()

func _GetStack() -> ItemStack:
	var inventory := _merchantInventory if _source == "buy" else _playerInventory
	return inventory.GetSlot(_slot) if inventory != null else null

func _InventoryChanged(_index: int, _stack: ItemStack) -> void:
	_pending = false
	_Refresh()

func _Quote() -> int:
	var stack := _GetStack()
	if stack == null or stack.item == null:
		return 0
	var unit := stack.item.salePrice if _source == "buy" else floori(stack.item.salePrice / 2.0)
	return unit * int(_quantitySpinBox.value)

func _ValidSelection() -> bool:
	var stack := _GetStack()
	var quantity := int(_quantitySpinBox.value)
	return not _closing and not _pending and _source in ["buy", "sell"] and stack != null and stack.item != null and stack.item.index > 0 and stack.item.index == _selected_item and quantity > 0 and quantity <= stack.quantity and _Quote() > 0

func _Refresh() -> void:
	if _actionButton == null:
		return
	_actionButton.text = "Comprar" if _source == "buy" else ("Vender" if _source == "sell" else "Seleccioná un objeto")
	_actionButton.disabled = not _ValidSelection()
	var stack := _GetStack()
	_infoLabel.text = "%s · Total: %d oro" % [stack.item.name, _Quote()] if stack != null and stack.item != null and stack.item.index > 0 else "Seleccioná un objeto del mercader o de tu inventario."

func _Submit() -> void:
	if not _ValidSelection():
		return
	if _source == "buy":
		GameProtocol.WriteCommerceBuy(_slot + 1, int(_quantitySpinBox.value))
	else:
		GameProtocol.WriteCommerceSell(_slot + 1, int(_quantitySpinBox.value))
	_pending = true
	_Refresh()

func RequestClose() -> void:
	if _closing:
		return
	_closing = true
	GameProtocol.WriteCommerceEnd()
	hide()
	finished.emit()

func _StyleSlots(grid: InventoryContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08)
	style.border_color = Color(0.3, 0.3, 0.3)
	style.set_border_width_all(1)
	for cell in grid.get_children():
		if cell is InventorySlot:
			cell.add_theme_stylebox_override("panel", style)
