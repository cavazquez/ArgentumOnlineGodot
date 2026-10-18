extends GridContainer
class_name InventoryContainer
const InventorySlotScene = preload("uid://b8q7jv01joc1r")

@export var allow_reorder := false

signal slotPressed(index:int) 
  
var _inventory:Inventory
var _selectedSlot:int = -1

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
		add_child(inventorySlot)
		
		inventorySlot.index = i
		inventorySlot.pressed.connect(_InventorySlotOnPressed.bind(i)) 
		_OnSlotChanged(i, _inventory.GetSlot(i))
		inventorySlot.SetSelected(i == _selectedSlot)

func GetInventorySlot(index:int) -> InventorySlot:
	for child in get_children():
		if child is InventorySlot && child.index == index:
			return child
	return null

func _OnSlotChanged(index:int, itemStack:ItemStack) -> void:
	var inventorySlot = GetInventorySlot(index) 
	if inventorySlot:
		inventorySlot.SetIcon(itemStack.item.icon)
		inventorySlot.SetQuantity(itemStack.quantity)
		inventorySlot.SetEquipped(itemStack.equipped)
		
func _InventorySlotOnPressed(index:int) -> void:
	if index < 0 or _inventory == null or index >= _inventory.GetSize():
		return
	if GetInventorySlot(_selectedSlot):
		GetInventorySlot(_selectedSlot).SetSelected(false)
	GetInventorySlot(index).SetSelected(true)
	
	_selectedSlot = index
	slotPressed.emit(index) 

func CreateDragData(index: int) -> Variant:
	if not allow_reorder or _inventory == null or index < 0 or index >= _inventory.GetSize():
		return null
	var stack := _inventory.GetSlot(index)
	if stack == null or stack.item == null or stack.quantity < 1 or stack.item.index < 1:
		return null
	return {"kind": "pyao_player_inventory", "inventory": _inventory.get_instance_id(), "source": index}

func CanDropItem(destination: int, data: Variant) -> bool:
	if not allow_reorder or _inventory == null or destination < 0 or destination >= _inventory.GetSize():
		return false
	if not data is Dictionary or data.get("kind") != "pyao_player_inventory" or data.get("inventory") != _inventory.get_instance_id():
		return false
	var source = data.get("source", -1)
	if not source is int or source < 0 or source >= _inventory.GetSize() or source == destination:
		return false
	var stack := _inventory.GetSlot(source)
	return stack != null and stack.item != null and stack.quantity > 0 and stack.item.index > 0

func DropItem(destination: int, data: Variant) -> void:
	if not CanDropItem(destination, data):
		return
	# Sin cambios optimistas: sólo ChangeInventorySlot puede actualizar el modelo.
	GameProtocol.WriteMoveItem(int(data.source) + 1, destination + 1)
