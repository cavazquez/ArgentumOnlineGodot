extends RefCounted
class_name Inventory

signal slotChanged(index:int, itemStack:ItemStack)

var scope := "inventory"
var _slots:Array[ItemStack]

func _init(size:int) -> void:
	_slots.resize(size)
	for i in size:
		_slots[i] = ItemStack.new(0, false, Item.new())
		
func GetSize() -> int:
	return _slots.size()
	
	
func GetSlot(index:int) -> ItemStack:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index]
	
	
func SetSlot(index:int, itemStack:ItemStack) -> bool:
	if index < 0 or index >= _slots.size():
		return false
	_slots[index] = itemStack
	slotChanged.emit(index, itemStack)
	return true

func SetProtocolSlot(slot: int, item_stack: ItemStack) -> bool:
	# Único punto de conversión de actualizaciones de red 1-based al modelo 0-based.
	return SetSlot(slot - 1, item_stack)
