extends Node

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("STORAGE_UI: " + message)

func _ready() -> void:
	var editor := ClanProfileEditor.new()
	add_child(editor)
	var state := {"clan_id": 7, "permissions": ["profile"], "profile": {"description": "Original", "news": "Noticias", "website": "", "version": 0}}
	editor.Apply(state, false)
	check(editor.description.text == "Original" and not editor.save.disabled, "No cargó la ficha editable")
	editor.description.text = "Mi borrador"
	editor.description.text_changed.emit(editor.description.text)
	state.profile.description = "Otro cambio"
	state.profile.version = 1
	editor.Apply(state, false)
	check(editor.description.text == "Mi borrador" and editor.save.disabled and editor.rebase.visible, "Perdió el borrador ante un conflicto")
	editor.Confirmed({"applied": false})
	check(editor.description.text == "Mi borrador", "Un rechazo borró el texto")
	editor.rebase.pressed.emit()
	check(not editor.save.disabled, "Revisar la versión no habilitó el botón Guardar")
	editor.Apply(state, false)
	check(not editor.save.disabled and editor.description.text == "Mi borrador", "No conserva el borrador al revisar la versión nueva")
	state.permissions = []
	editor.Apply(state, false)
	check(editor.save.disabled and not editor._form.visible, "Un miembro o exlíder puede editar")
	editor.Apply({}, false)
	check(editor.description.text == "Mi borrador", "Un reset de conexión borró el borrador")
	editor.free()
	ClientInterface.capabilities.enabled = ClientCapabilities.REQUESTED
	ClientInterface.world_state.epoch = "a".repeat(32)
	var panel: BankPanel = load("res://ui/hub/bank_panel.tscn").instantiate()
	add_child(panel)
	var bank := Inventory.new(40)
	var item := Item.new()
	item.index = 15
	bank.SetProtocolSlot(1, ItemStack.new(2, false, item))
	panel.SetBankInventory(bank)
	panel.SetPlayerInventory(Inventory.new(30))
	panel._OnWorldState("bank", {"banker": "banker", "access": true, "capacity": 40, "slots": [[1, 15, 2]]}, "revision")
	GameProtocol.Clear()
	var drag = panel._bankInventoryContainer.CreateDragData(0)
	panel._bankInventoryContainer.DropItem(39, drag)
	check(not GameProtocol.Flush().is_empty(), "No envió el movimiento de bóveda")
	check(bank.GetSlot(0).quantity == 2 and bank.GetSlot(39).quantity == 0, "Movió el objeto sin confirmación del servidor")
	check(not panel._bankInventoryContainer.allow_reorder, "Permite movimientos concurrentes mientras espera")
	panel._OnWorldState("result", {"id": panel._pending.id, "applied": false, "message": "El banco cambió"}, "")
	check(panel._pending.is_empty() and panel._status.text == "El banco cambió", "No representa el rechazo")
	panel.free()
	GameProtocol.Clear()
	ClientInterface.capabilities.clear()
	ClientInterface.world_state.clear()
	print("STORAGE_UI: failures=", failures)
	get_tree().quit(1 if failures else 0)
