extends Window
class_name CraftingWindow

var skill := "carpinteria"
var page := 0
var recipes: Array = []
var _list: ItemList
var _details: Label
var _status: Label
var _quantity: SpinBox
var _craft: Button
var _previous: Button
var _next: Button
var _retry: Button
var _help: Label
var _pending_id := ""
var _pending_action := ""
var _pending_params: Dictionary = {}
var _deadline := 0
var _context_valid := false

func _ready() -> void:
	size = Vector2i(510, 400)
	title = "Fabricación"
	close_requested.connect(hide)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_help = Label.new()
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_help)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select_recipe)
	box.add_child(_list)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_details)
	var pages := HBoxContainer.new()
	box.add_child(pages)
	_previous = _button(pages, "Anterior", func(): _request_page(page - 1))
	_next = _button(pages, "Siguiente", func(): _request_page(page + 1))
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = 100
	_quantity.value = 1
	pages.add_child(_quantity)
	_craft = _button(pages, "Fabricar", _submit)
	_retry = _button(box, "Reintentar", _resend)
	_retry.hide()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_craft.disabled = true

func _button(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func open_skill(value: String) -> void:
	popup_centered()
	if not _pending_id.is_empty():
		_status.text = "Hay una operación pendiente; espera la respuesta o reinténtala."
		return
	skill = value
	_context_valid = true
	title = {"herreria": "Herrería", "carpinteria": "Carpintería", "mineria": "Fundición"}.get(skill, "Fabricación")
	_help.text = {
		"herreria": "Usá un martillo de herrero junto a un yunque.",
		"carpinteria": "Necesitás un serrucho y los materiales de la receta.",
		"mineria": "Acercate a una fragua para convertir minerales en lingotes."
	}.get(skill, "Seleccioná una receta y la cantidad.")
	_request_page(0)

func _request_page(value: int) -> void:
	if not _pending_id.is_empty() or value < 0:
		return
	_send("recipes", {"skill": skill, "page": value})

func _send(action: String, params: Dictionary) -> void:
	_pending_id = GameProtocol.NewSkillActionId()
	_pending_action = action
	_pending_params = params.duplicate(true)
	_resend()

func _resend() -> void:
	if GameProtocol.WriteSkillAction(_pending_action, _pending_params, _pending_id):
		_deadline = Time.get_ticks_msec() + 5000
		_status.text = "Esperando confirmación del servidor…"
		_retry.hide()
		_craft.disabled = true
		_previous.disabled = true
		_next.disabled = true

func _process(_delta: float) -> void:
	if not _pending_id.is_empty() and _deadline > 0 and Time.get_ticks_msec() > _deadline:
		_deadline = 0
		_status.text = "No llegó la confirmación. Podés reintentar sin duplicar la fabricación."
		_retry.show()

func apply_result(value: Dictionary) -> void:
	if value.id != _pending_id:
		return
	_pending_id = ""
	_deadline = 0
	_retry.hide()
	if value.get("kind", "") == "recipes" and value.applied:
		page = int(value.page)
		recipes = value.recipes
		_list.clear()
		for recipe in recipes:
			_list.add_item("%s · habilidad %d" % [recipe.name, int(recipe.required)])
		_next.disabled = not bool(value.has_next)
		if not recipes.is_empty():
			_list.select(0)
			_select_recipe(0)
	else:
		if _pending_action == "recipes":
			recipes.clear()
			_list.clear()
			_details.text = ""
		_next.disabled = recipes.size() < 4
	_previous.disabled = page == 0
	_craft.disabled = not _context_valid or recipes.is_empty() or _list.get_selected_items().is_empty()
	_status.text = String(value.get("message", "Seleccioná una receta y la cantidad."))

func _select_recipe(index: int) -> void:
	if index < 0 or index >= recipes.size():
		return
	var materials := PackedStringArray()
	for material in recipes[index].materials:
		materials.append("%d × %s" % [int(material.quantity), String(material.get("name", "Material"))])
	_details.text = "Por unidad: %s. Éxito base: %d%%. Un fallo consume la mitad de los materiales." % [", ".join(materials), int(recipes[index].success_rate)]
	_craft.disabled = not _context_valid or not _pending_id.is_empty()

func _submit() -> void:
	if not _context_valid or not _pending_id.is_empty() or _list.get_selected_items().is_empty():
		return
	var index := _list.get_selected_items()[0]
	_send("craft", {"recipe": recipes[index].id, "quantity": int(_quantity.value)})

func invalidate_context() -> void:
	_context_valid = false
	_craft.disabled = true
	_status.text = "Cambió tu posición. Abrí nuevamente la fabricación para consultar las recetas."
	hide()
