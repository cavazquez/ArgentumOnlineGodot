extends PanelContainer
class_name EquipmentPanel

signal equip_requested(index: int)

# Las mismas seis ranuras tipadas del servidor. No hay ranura de rostro.
const LAYERS := {"weapon": "Arma / herramienta", "armor": "Armadura", "helmet": "Casco", "shield": "Escudo", "boots": "Botas", "accessory": "Accesorio"}
const TYPES := {2: "weapon", 3: "armor", 16: "shield", 17: "helmet", 18: "accessory", 26: "accessory", 36: "boots"}
var inventory: Inventory
var buttons: Dictionary = {}
var slots: Dictionary = {}
var _choices: Dictionary = {}
var _choice_layer := ""
var choices: PopupMenu

func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("15100c")
	background.set_content_margin_all(4)
	add_theme_stylebox_override("panel", background)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	add_child(content)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for layer in LAYERS:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(92, 60)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 1)
		var label := Label.new()
		label.text = LAYERS[layer]
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color("e7bc72"))
		cell.add_child(label)
		var button := EquipmentSlotButton.new()
		button.name = layer.capitalize()
		button.equipment_panel = self
		button.layer = layer
		button.custom_minimum_size = Vector2(92, 42)
		button.clip_text = true
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(show_choices.bind(layer))
		buttons[layer] = button
		cell.add_child(button)
		grid.add_child(cell)
	var face_note := Label.new()
	face_note.text = "Rostro: elegido al crear el personaje"
	face_note.add_theme_font_size_override("font_size", 10)
	face_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(face_note)
	choices = PopupMenu.new()
	choices.name = "EquipmentChoices"
	choices.id_pressed.connect(_choose)
	choices.close_requested.connect(choices.hide)
	add_child(choices)
	ClientInterface.world_state.changed.connect(_state_changed)
	refresh()

func setup(value: Inventory) -> void:
	if inventory != null and inventory.slotChanged.is_connected(_slot_changed):
		inventory.slotChanged.disconnect(_slot_changed)
	inventory = value
	inventory.slotChanged.connect(_slot_changed)
	if is_node_ready(): refresh()

func _slot_changed(_index: int, _stack: ItemStack) -> void:
	refresh()

func _state_changed(kind: String, data: Dictionary, _revision: String) -> void:
	if kind == "items" and data.get("scope") == "inventory":
		refresh.call_deferred()

func refresh() -> void:
	slots.clear()
	if inventory != null:
		for index in inventory.GetSize():
			var stack := inventory.GetSlot(index)
			if stack.equipped and stack.item != null and TYPES.has(stack.item.type):
				slots[TYPES[stack.item.type]] = index
	for layer in buttons:
		var button: Button = buttons[layer]
		var stack := inventory.GetSlot(int(slots[layer])) if slots.has(layer) else null
		button.icon = stack.item.icon if stack != null else null
		button.text = stack.item.name if stack != null else "Vacío"
		button.tooltip_text = LAYERS[layer] + ": " + button.text + "\nClic para elegir una pieza o desequipar."
		if stack != null and not stack.instance_state.is_empty():
			button.tooltip_text += "\n" + ItemCondition.describe(stack.instance_state)

func show_choices(layer: String) -> void:
	if inventory == null or not LAYERS.has(layer): return
	_choice_layer = layer
	_choices.clear()
	choices.clear()
	for index in inventory.GetSize():
		var stack := inventory.GetSlot(index)
		if stack.item == null or stack.quantity < 1 or TYPES.get(stack.item.type, "") != layer: continue
		_choices[index] = {"item": stack.item.index, "instance": stack.instance_state.get("id", "")}
		choices.add_icon_item(stack.item.icon, ("Desequipar " if stack.equipped else "Equipar ") + stack.item.name + " · mochila %d" % (index + 1), index)
		if not stack.instance_state.is_empty():
			choices.set_item_tooltip(choices.item_count - 1, ItemCondition.describe(stack.instance_state))
	if choices.item_count == 0:
		choices.add_item("No tenés piezas para esta ranura.")
		choices.set_item_disabled(0, true)
	var rect: Rect2 = buttons[layer].get_global_rect()
	choices.position = get_window().position + Vector2i(rect.position.x, rect.end.y)
	choices.popup()

func _choose(index: int) -> void:
	if not _choices.has(index) or inventory == null: return
	var stack := inventory.GetSlot(index)
	var expected: Dictionary = _choices[index]
	if stack == null or stack.item == null or stack.item.index != expected.item or stack.instance_state.get("id", "") != expected.instance: return
	request_slot(index, _choice_layer)

func request_slot(index: int, layer: String) -> void:
	if inventory == null: return
	var stack := inventory.GetSlot(index)
	if stack != null and stack.item != null and stack.quantity > 0 and TYPES.get(stack.item.type, "") == layer:
		equip_requested.emit(index)

func can_equip_drop(layer: String, data: Variant) -> bool:
	if inventory == null or not data is Dictionary or data.get("kind") != "pyao_player_inventory" or data.get("inventory") != inventory.get_instance_id(): return false
	var index = data.get("source", -1)
	if not index is int: return false
	var stack := inventory.GetSlot(index)
	return stack != null and stack.item != null and stack.quantity > 0 and not stack.equipped and TYPES.get(stack.item.type, "") == layer
