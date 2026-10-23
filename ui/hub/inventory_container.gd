extends GridContainer
class_name InventoryContainer
const InventorySlotScene = preload("uid://b8q7jv01joc1r")

@export var allow_reorder := false
@export var hide_equipped := false
var reorder_handler: Callable

signal slotPressed(index:int) 
signal slotActivated(index:int)
  
var _inventory:Inventory
var _selectedSlot:int = -1

func _ready() -> void:
	ClientInterface.world_state.changed.connect(_OnConditionState)

func _OnConditionState(kind: String, data: Dictionary, _revision: String) -> void:
	if kind != "items" or _inventory == null or data.scope != _inventory.scope: return
	for row in data.rows:
		var index := int(row[0]) - 1
		var stack := _inventory.GetSlot(index)
		if stack == null: continue
		stack.instance_state = row[1].duplicate(true) if not row[1].is_empty() and stack.item != null and int(row[1].item) == stack.item.index else {}
		_OnSlotChanged(index, stack)

func GetSelectedSlot() -> int:
	return _selectedSlot

func GetInventory() -> Inventory:
	return _inventory

func SetInventory(inventory:Inventory) -> void:
	if _inventory != null and _inventory.slotChanged.is_connected(_OnSlotChanged):
		_inventory.slotChanged.disconnect(_OnSlotChanged)
	for child in get_children():
		if child is InventorySlot:
			child.free()
	_inventory = inventory
	if _selectedSlot >= inventory.GetSize():
		_selectedSlot = -1
	_inventory.slotChanged.connect(_OnSlotChanged)

	for i in _inventory.GetSize():
		var inventorySlot = InventorySlotScene.instantiate() as InventorySlot
		inventorySlot.name = "Slot%d" % i
		add_child(inventorySlot)
		
		inventorySlot.index = i
		inventorySlot.pressed.connect(_InventorySlotOnPressed.bind(i)) 
		inventorySlot.activated.connect(_InventorySlotOnActivated.bind(i))
		_OnSlotChanged(i, _inventory.GetSlot(i))
		inventorySlot.SetSelected(i == _selectedSlot)
	_UpdateFocusNeighbors()

func IsSlotDisplayed(index: int) -> bool:
	if _inventory == null or index < 0 or index >= _inventory.GetSize(): return false
	var stack := _inventory.GetSlot(index)
	return not (hide_equipped and stack != null and stack.quantity > 0 and stack.equipped and stack.item != null and stack.item.IsEquippable())

func _UpdateFocusNeighbors() -> void:
	# GridContainer compacta las celdas visibles; sus índices de protocolo no cambian.
	var cells: Array[InventorySlot] = []
	for child in get_children():
		if child is InventorySlot and child.visible: cells.append(child)
	for position in cells.size():
		var cell := cells[position]
		for info in [["focus_neighbor_left", position - 1], ["focus_neighbor_right", position + 1], ["focus_neighbor_top", position - columns], ["focus_neighbor_bottom", position + columns]]:
			var neighbor: int = info[1]
			cell.set(info[0], cell.get_path_to(cells[neighbor] if neighbor >= 0 and neighbor < cells.size() else cell))
		cell.focus_next = cell.get_path_to(cells[position + 1]) if position + 1 < cells.size() else NodePath()
		cell.focus_previous = cell.get_path_to(cells[position - 1]) if position > 0 else NodePath()

func GetInventorySlot(index:int) -> InventorySlot:
	for child in get_children():
		if child is InventorySlot && child.index == index:
			return child
	return null

func _OnSlotChanged(index:int, itemStack:ItemStack) -> void:
	var inventorySlot = GetInventorySlot(index) 
	if inventorySlot:
		inventorySlot.SetDescription(itemStack)
		inventorySlot.SetIcon(itemStack.item.icon if itemStack != null and itemStack.item != null else null)
		inventorySlot.SetQuantity(itemStack.quantity)
		inventorySlot.SetEquipped(itemStack.equipped)
		var displayed := IsSlotDisplayed(index)
		if not displayed and _selectedSlot == index: ClearSelection()
		if inventorySlot.visible != displayed:
			inventorySlot.visible = displayed
			_UpdateFocusNeighbors()
		
func _InventorySlotOnPressed(index:int) -> void:
	if not IsSlotDisplayed(index):
		return
	if GetInventorySlot(_selectedSlot):
		GetInventorySlot(_selectedSlot).SetSelected(false)
	GetInventorySlot(index).SetSelected(true)
	
	_selectedSlot = index
	slotPressed.emit(index) 

func _InventorySlotOnActivated(index: int) -> void:
	if IsSlotDisplayed(index): slotActivated.emit(index)

func CreateDragData(index: int) -> Variant:
	if not allow_reorder or not IsSlotDisplayed(index):
		return null
	var stack := _inventory.GetSlot(index)
	if stack == null or stack.item == null or stack.quantity < 1 or stack.item.index < 1:
		return null
	return {"kind": "pyao_player_inventory", "inventory": _inventory.get_instance_id(), "source": index}

func CanDropItem(destination: int, data: Variant) -> bool:
	if not allow_reorder or not IsSlotDisplayed(destination):
		return false
	if not data is Dictionary or data.get("kind") != "pyao_player_inventory" or data.get("inventory") != _inventory.get_instance_id():
		return false
	var source = data.get("source", -1)
	if not source is int or not IsSlotDisplayed(source) or source == destination:
		return false
	var stack := _inventory.GetSlot(source)
	return stack != null and stack.item != null and stack.quantity > 0 and stack.item.index > 0

func DropItem(destination: int, data: Variant) -> void:
	if not CanDropItem(destination, data):
		return
	# Sin cambios optimistas: sólo ChangeInventorySlot puede actualizar el modelo.
	if reorder_handler.is_valid():
		reorder_handler.call(int(data.source) + 1, destination + 1)
	else:
		GameProtocol.WriteMoveItem(int(data.source) + 1, destination + 1)

func ClearSelection() -> void:
	var selected := GetInventorySlot(_selectedSlot)
	if selected != null:
		selected.SetSelected(false)
	_selectedSlot = -1
