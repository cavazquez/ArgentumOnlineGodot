extends GridContainer
class_name InventoryContainer
const InventorySlotScene = preload("uid://b8q7jv01joc1r")

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
