extends TextureRect
class_name BankPanel

signal finished
var _closing := false
var _bank_state := {}
var _revision := ""
var _pending := {}
var _deadline := 0
var _status: Label
var _retry: Button

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
	_status = Label.new()
	_status.position = Vector2(32, 416)
	_status.size = Vector2(390, 28)
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Arrastrá un objeto para reordenar la bóveda."
	add_child(_status)
	_retry = Button.new()
	_retry.text = "Reintentar"
	_retry.position = Vector2(310, 468)
	_retry.add_theme_font_size_override("font_size", 12)
	_retry.pressed.connect(_Resend)
	_retry.hide()
	add_child(_retry)
	_bankInventoryContainer.reorder_handler = RequestMove
	ClientInterface.world_state.changed.connect(_OnWorldState)
	GameProtocol.WriteWorldAction("bank.read", {})
	GameProtocol.WriteWorldAction("subscribe", {"topic": "bank", "enabled": true})
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
	elif item.type == 18 and item.maxDef > 0:
		_SetStat(DEFENCE_ICON, "%d/%d" % [item.minDef, item.maxDef], "Resistencia mágica")
	elif item.type == 18 and item.maxHit > 0:
		_SetStat(DAMAGE_ICON, "%d/%d" % [item.minHit, item.maxHit], "Daño sin arma")
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
	GameProtocol.WriteWorldAction("subscribe", {"topic": "bank", "enabled": false})
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

func RequestMove(source: int, destination: int) -> void:
	if not _pending.is_empty() or _closing or not _bank_state.get("access", false) or _revision.is_empty(): return
	_pending = {"id": GameProtocol.NewSkillActionId(), "epoch": ClientInterface.world_state.epoch, "revision": _revision, "params": {"source": source, "destination": destination, "banker": _bank_state.banker}}
	_Resend()
	_SetBusy()

func _Resend() -> void:
	if _pending.is_empty() or _closing: return
	if _pending.epoch != ClientInterface.world_state.epoch:
		_status.text = "La conexión cambió. Volvé a abrir el banco."
		return
	if GameProtocol.WriteWorldAction("bank.move", _pending.params, _pending.revision, _pending.id):
		_deadline = Time.get_ticks_msec() + 5000
		_retry.hide()
		_status.text = "Esperando confirmación del movimiento…"
	else:
		_status.text = "No se pudo enviar el movimiento."
		_retry.show()

func _SetBusy() -> void:
	var busy := not _pending.is_empty()
	_bankInventoryContainer.allow_reorder = not busy and _bank_state.get("access", false)
	for button_name in ["BtnExtract", "BtnDeposit", "BtnExtractGold", "BtnDepositGold"]:
		get_node(button_name).disabled = busy or not _bank_state.get("access", false)

func _OnWorldState(kind: String, data: Dictionary, revision: String) -> void:
	if _closing: return
	if kind == "bank":
		_bank_state = data.duplicate(true)
		_revision = revision
		if not data.access: _status.text = "Acercate al banquero y volvé a abrir el banco."
		_SetBusy()
	elif kind == "result" and data.get("id", "") == _pending.get("id", "missing"):
		_status.text = data.get("message", "Respuesta recibida.")
		if data.get("uncertain", false): _retry.show()
		else:
			_pending.clear()
			_retry.hide()
		_deadline = 0
		_SetBusy()
	elif kind == "reset":
		_pending.clear()
		_bank_state.clear()
		_SetBusy()
		_status.text = "Desconectado."

func _process(_delta: float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		_deadline = 0
		_retry.show()
		_status.text = "Respuesta pendiente. Reintentá la misma operación."
