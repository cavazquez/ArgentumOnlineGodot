extends TextureRect
class_name BankPanel

signal finished
var _closing := false

const DAMAGE_ICON: Texture2D = preload("res://Assets/UI/damage.svg")
const DEFENCE_ICON: Texture2D = preload("res://Assets/UI/defence.svg")

@export var _bankInventoryContainer:InventoryContainer
@export var _playerInventoryContainer:InventoryContainer
@export var _infoLabel:Label 
@export var _quantitySpinBox:SpinBox

@onready var _lbl_gold: Label = $LblGold
@onready var _statRow: HBoxContainer = $Info/Stats
@onready var _statIcon: TextureRect = $Info/Stats/Icon
@onready var _statLabel: Label = $Info/Stats/Range

@export var _goldLabel:Label
@export var _quantityGoldSpinBox:SpinBox

var _bankInventory:Inventory
var _playerInventory:Inventory

func _ready() -> void:
	_bankInventoryContainer.slotPressed.connect(func(index:int):
		_UpdateInfo(_bankInventory.GetSlot(index).item if _bankInventory != null else null))
		
	_playerInventoryContainer.slotPressed.connect(func(index:int):
		_UpdateInfo(_playerInventory.GetSlot(index).item if _playerInventory != null else null))


func SetBankInventory(inventory:Inventory) -> void:
	_bankInventoryContainer.SetInventory(inventory)
	_bankInventory = inventory
	
	
func SetPlayerInventory(inventory:Inventory) -> void:
	_playerInventoryContainer.SetInventory(inventory)
	_playerInventory = inventory


func SetBankGold(gold:int) -> void:
	_lbl_gold.text = str(gold)
  

func _UpdateInfo(item:Item) -> void:
	_statRow.hide()
	_statIcon.texture = null
	_statLabel.text = ""
	_statRow.tooltip_text = ""
	if item == null or item.index < 1:
		_infoLabel.text = "Seleccioná un objeto"
		return
	_infoLabel.text = item.name
	if item.IsWeapon():
		_SetStat(DAMAGE_ICON, "%d/%d" % [item.minHit, item.maxHit], "Daño")
	elif item.IsArmour():
		_SetStat(DEFENCE_ICON, "%d/%d" % [item.minDef, item.maxDef], "Defensa")

func _SetStat(icon: Texture2D, value: String, description: String) -> void:
	_statIcon.texture = icon
	_statLabel.text = value
	_statRow.tooltip_text = "%s: %s" % [description, value]
	_statRow.show()

func _GetQuantity() -> int:
	return int(_quantitySpinBox.value)

func _GetGoldQuantity() -> int:
	return int(_quantityGoldSpinBox.value)


func RequestClose() -> void:
	if _closing:
		return
	_closing = true
	GameProtocol.WriteBankEnd()
	hide()
	finished.emit()

func _on_btn_close_pressed() -> void:
	RequestClose()
 

func _on_btn_extract_gold_pressed() -> void:
	GameProtocol.WriteBankExtractGold(_GetGoldQuantity())


func _on_btn_deposit_gold_pressed() -> void:
	GameProtocol.WriteBankDepositGold(_GetGoldQuantity())


func _on_btn_extract_pressed() -> void:
	if _bankInventoryContainer.GetSelectedSlot() == -1: return
	GameProtocol.WriteBankExtractItem(_bankInventoryContainer.GetSelectedSlot() + 1, _GetQuantity());


func _on_btn_deposit_pressed() -> void:
	if _playerInventoryContainer.GetSelectedSlot() == -1: return
	GameProtocol.WriteBankDepositItem(_playerInventoryContainer.GetSelectedSlot() + 1, _GetQuantity());
