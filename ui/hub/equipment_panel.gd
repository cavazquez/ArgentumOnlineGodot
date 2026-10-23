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
var choices: VBoxContainer
var choice_buttons: Dictionary = {}
var _grid: GridContainer
var _choice_title: Label
var _choice_rows: VBoxContainer

func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("15100c")
	background.set_content_margin_all(4)
	add_theme_stylebox_override("panel", background)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	add_child(content)
	var grid := GridContainer.new()
	_grid = grid
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
	choices = VBoxContainer.new()
	choices.name = "EquipmentChoices"
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choice_title = Label.new()
	_choice_title.add_theme_font_size_override("font_size", 12)
	choices.add_child(_choice_title)
	var back := Button.new()
	back.text = "Volver al equipo"
	back.add_theme_font_size_override("font_size", 11)
	back.pressed.connect(close_choices)
	choices.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_rows = VBoxContainer.new()
	_choice_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_choice_rows)
	choices.add_child(scroll)
	content.add_child(choices)
	choices.hide()
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
	choice_buttons.clear()
	for child in _choice_rows.get_children(): child.free()
	_choice_title.text = LAYERS[layer]
	for index in inventory.GetSize():
		var stack := inventory.GetSlot(index)
		if stack.item == null or stack.quantity < 1 or TYPES.get(stack.item.type, "") != layer: continue
		_choices[index] = {"item": stack.item.index, "instance": stack.instance_state.get("id", "")}
		var button := Button.new()
		button.text = ("Quitar: " if stack.equipped else "") + stack.item.name
		button.icon = stack.item.icon
		button.expand_icon = true
		button.clip_text = true
		button.custom_minimum_size.y = 34
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_constant_override("icon_max_width", 28)
		button.tooltip_text = ("Desequipar " if stack.equipped else "Equipar ") + stack.item.name + " · mochila %d" % (index + 1)
		if not stack.instance_state.is_empty():
			button.tooltip_text += "\n" + ItemCondition.describe(stack.instance_state)
		button.pressed.connect(_choose.bind(index))
		_choice_rows.add_child(button)
		choice_buttons[index] = button
	if choice_buttons.is_empty():
		var empty := Label.new()
		empty.text = "No tenés piezas para esta ranura."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 11)
		_choice_rows.add_child(empty)
	_grid.hide()
	choices.show()
	if not choice_buttons.is_empty(): choice_buttons.values()[0].call_deferred("grab_focus")

func close_choices() -> void:
	choices.hide()
	_grid.show()
	get_viewport().gui_release_focus()

func _choose(index: int) -> void:
	if not _choices.has(index) or inventory == null: return
	var stack := inventory.GetSlot(index)
	var expected: Dictionary = _choices[index]
	if stack == null or stack.item == null or stack.item.index != expected.item or stack.instance_state.get("id", "") != expected.instance: return
	request_slot(index, _choice_layer)
	close_choices()

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
