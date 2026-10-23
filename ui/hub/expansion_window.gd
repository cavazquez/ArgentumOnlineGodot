extends WorldStateWindow
class_name ExpansionWindow

const TITLES := {"finder": "Buscar grupo", "diplomacy": "Relaciones del clan", "depot": "Depósito del clan", "faction": "Facciones", "quests": "Misiones"}
const STATES := {"available": "Disponible", "locked": "Requisitos pendientes", "active": "Activa", "completed": "Lista para cobrar", "claimed": "Cobrada", "abandoned": "Abandonada", "proposed": "Propuesta", "alliance": "Alianza", "war": "Guerra", "none": "Sin relación", "expired": "Vencida"}
var _summary: Label
var _list: ItemList
var _details: Label
var _second: ItemList
var _controls: Dictionary = {}
var _buttons: Dictionary = {}
var _selected: Dictionary = {}
var _second_selected: Dictionary = {}
var _page := 0
var _npc := 0
var _page_label: Label

func _init(kind: String = "quests") -> void:
	topic = kind
	title = TITLES.get(kind, "Mundo")

func _spin(caption: String, minimum: int, maximum: int, initial: int) -> SpinBox:
	var row := HBoxContainer.new()
	body.add_child(row)
	label(row, caption).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var control := SpinBox.new()
	control.min_value = minimum
	control.max_value = maximum
	control.value = initial
	row.add_child(control)
	return control

func _text(caption: String, maximum: int) -> LineEdit:
	var control := LineEdit.new()
	control.placeholder_text = caption
	control.max_length = maximum
	body.add_child(control)
	return control

func _action(caption: String, action: String, callback: Callable) -> void:
	_buttons[action] = button(body, caption, callback)

func _build() -> void:
	_summary = label(body)
	if topic == "finder":
		_controls.minimum = _spin("Nivel mínimo", 1, 100, 1)
		_controls.maximum = _spin("Nivel máximo", 1, 100, 100)
		var activities := OptionButton.new()
		for activity in ["Cualquier actividad", "Caza", "Recolección", "Misiones", "Social"]: activities.add_item(activity)
		body.add_child(activities)
		_controls.activity = activities
		_controls.map = _spin("Mapa (0 = todos)", 0, 10000, 0)
		_controls.text = _text("Descripción del grupo (máximo 120 caracteres)", 120)
		_action("Buscar", "search", func(): _page = 0; request_state())
		_action("Publicar mi grupo durante 10 minutos", "publish", _publish)
		_action("Cerrar mi anuncio", "close", func(): mutate("finder.close", {}))
	elif topic == "diplomacy":
		_controls.clan = _text("Nombre del otro clan", 30)
	elif topic == "faction":
		var factions := OptionButton.new()
		body.add_child(factions)
		_controls.faction = factions
	_list = ItemList.new()
	_list.custom_minimum_size.y = 100
	_list.item_selected.connect(_select)
	body.add_child(_list)
	_details = label(body)
	if topic in ["depot", "finder"]:
		label(body, "Tu inventario" if topic == "depot" else "Solicitudes recibidas")
		_second = ItemList.new()
		_second.custom_minimum_size.y = 90
		_second.item_selected.connect(func(index: int):
			_second_selected = _second.get_item_metadata(index)
			_update_actions())
		body.add_child(_second)
	match topic:
		"finder":
			_action("Solicitar ingreso al grupo seleccionado", "request", func(): mutate("finder.request", {"party": int(_selected.get("id", 0))}))
			_action("Invitar al solicitante seleccionado", "invite", func(): mutate("finder.invite", {"party": int(state.get("party", 0)), "user": int(_second_selected.get("id", 0))}))
		"diplomacy":
			for spec in [["Proponer alianza", "propose"], ["Aceptar alianza", "accept"], ["Rechazar propuesta", "reject"], ["Cancelar propuesta o alianza", "cancel"], ["Declarar guerra", "declare_war"], ["Finalizar guerra", "end_war"]]:
				_action(spec[0], spec[1], _diplomacy.bind(spec[1]))
		"depot":
			_controls.quantity = _spin("Cantidad", 1, 32767, 1)
			_action("Depositar del inventario", "deposit", _transfer.bind("deposit"))
			_action("Retirar del depósito", "withdraw", _transfer.bind("withdraw"))
		"faction":
			_action("Ingresar a la facción", "join", _join_faction)
			_action("Abandonar la facción", "leave", func(): confirm_action("faction.leave", {}, "Al abandonar perderás el prestigio y rango de esta facción. El plazo de cambio se conserva."))
		"quests":
			for spec in [["Aceptar misión", "accept"], ["Entregar objetos", "deliver"], ["Cobrar recompensa", "claim"], ["Abandonar misión", "abandon"]]:
				_action(spec[0], spec[1], _quest_action.bind(spec[1]))
	if topic != "faction":
		var pages := HBoxContainer.new()
		body.add_child(pages)
		button(pages, "Anterior", _change_page.bind(-1))
		_page_label = label(pages)
		button(pages, "Siguiente", _change_page.bind(1))
	button(body, "Cerrar", hide)

func request_state() -> void:
	if not ClientInterface.capabilities.has_feature(ClientCapabilities.EXPANSION):
		status.text = "Esta función requiere el servidor actualizado."
		return
	var params := {"page": _page}
	if topic == "finder": params = _filters()
	elif topic == "quests": params.npc = _npc
	elif topic == "faction": params = {}
	request_topic_state(params)

func _filters() -> Dictionary:
	var activities := ["", "caza", "recoleccion", "misiones", "social"]
	return {"min_level": int(_controls.minimum.value), "max_level": int(_controls.maximum.value), "activity": activities[_controls.activity.selected], "map": int(_controls.map.value), "page": _page}

func _publish() -> void:
	var values := _filters()
	values.erase("map")
	values.erase("page")
	if values.activity.is_empty():
		status.text = "Elegí una actividad para publicar."
		return
	values.text = _controls.text.text.strip_edges()
	values.seconds = 600
	mutate("finder.publish", values)

func _change_page(delta: int) -> void:
	_page = clampi(_page + delta, 0, maxi(0, int(state.get("pages", 1)) - 1))
	request_state()

func _select(index: int) -> void:
	_selected = _list.get_item_metadata(index)
	if topic == "diplomacy": _controls.clan.text = _selected.name
	if topic == "quests":
		var lines := [_selected.description, "Recompensa: %d oro · %d experiencia" % [int(_selected.gold), int(_selected.experience)]]
		for objective in _selected.objectives:
			lines.append("%s: %d/%d" % ["Derrotados" if objective.kind == "kill" else "Objetos entregados", int(objective.progress), int(objective.quantity)])
		_details.text = "\n".join(lines)
	else:
		_details.text = str(_selected.get("text", ""))
	_update_actions()

func _render() -> void:
	if _list == null: return
	_list.clear()
	_selected = {}
	_second_selected = {}
	_details.text = ""
	if _second != null: _second.clear()
	if state.get("enabled", true) == false:
		_summary.text = state.get("message", "Función deshabilitada")
		_update_actions()
		return
	match topic:
		"finder":
			_summary.text = "Busca un grupo o publica el tuyo. El ingreso requiere invitación y aceptación."
			for request in state.get("requests", []):
				var index := _second.add_item("%s · nivel %d" % [request.name, int(request.level)])
				_second.set_item_metadata(index, request)
		"diplomacy": _summary.text = "%s · Sólo el líder administra relaciones." % state.get("name", "Sin clan")
		"depot":
			_summary.text = "%s · %d espacios. Miembros depositan; oficiales y líderes retiran." % [state.get("name", "Sin clan"), int(state.get("capacity", 60))]
			for event in state.get("history", []):
				_summary.text += "\n%s %s %s × %s" % [event.get("name", "Miembro"), "depositó" if event.action == "deposit" else "retiró", event.quantity, event.item_name]
			for item in state.get("inventory", []):
				var index := _second.add_item("%s × %d" % [item.name, int(item.quantity)])
				_second.set_item_metadata(index, item)
		"faction":
			_summary.text = "%s · %s · Prestigio %d%s" % [state.get("name", "Neutral"), state.get("rank", "Sin rango"), int(state.get("prestige", 0)), " · Próximo rango: %d" % int(state.next) if state.get("next") != null else ""]
			_controls.faction.clear()
			for faction in state.get("options", []):
				var index: int = _controls.faction.item_count
				_controls.faction.add_item("%s · nivel %d" % [faction.name, int(faction.min_level)])
				_controls.faction.set_item_metadata(index, faction.id)
		"quests":
			_npc = int(state.get("npc", 0))
			_summary.text = "Ofertas del NPC cercano y tu diario." if _npc else "Acercate al NPC de la misión para aceptar, entregar o cobrar."
	for row in state.get("rows", []):
		var caption := ""
		match topic:
			"finder": caption = "%s · %s · niveles %d–%d · mapa %d · %d lugares" % [row.name, row.activity, int(row.min_level), int(row.max_level), int(row.map), int(row.free)]
			"diplomacy": caption = "%s · %s" % [row.name, STATES.get(row.state, row.state)]
			"depot": caption = "%s × %d" % [row.name, int(row.quantity)]
			"quests": caption = "%s · %s" % [row.title, STATES.get(row.status, row.status)]
		var index := _list.add_item(caption)
		_list.set_item_metadata(index, row)
	if _page_label != null:
		_page = int(state.get("page", 0))
		_page_label.text = "%d / %d" % [_page + 1, int(state.get("pages", 1))]
	_update_actions()

func _update_actions() -> void:
	var ready: bool = not pending() and not revision.is_empty() and state.get("enabled", true) != false
	for key in _buttons: _buttons[key].disabled = not ready
	match topic:
		"finder":
			_buttons.publish.disabled = not ready or not state.get("leader", false)
			_buttons.close.disabled = _buttons.publish.disabled
			_buttons.request.disabled = not ready or _selected.is_empty() or int(state.get("party", 0)) != 0
			_buttons.invite.disabled = not ready or not state.get("leader", false) or _second_selected.is_empty()
		"diplomacy":
			for key in _buttons: _buttons[key].disabled = not ready or not state.get("leader", false)
		"depot":
			_buttons.deposit.disabled = not ready or not state.get("deposit", false) or _second_selected.is_empty()
			_buttons.withdraw.disabled = not ready or not state.get("withdraw", false) or _selected.is_empty()
		"faction":
			_buttons.join.disabled = not ready or state.get("faction", "neutral") != "neutral" or _controls.faction.item_count == 0
			_buttons.leave.disabled = not ready or state.get("faction", "neutral") == "neutral"
		"quests":
			for key in _buttons: _buttons[key].disabled = not ready or _selected.is_empty() or not _selected.get(key, false)

func _diplomacy(action: String) -> void:
	var target: String = _controls.clan.text.strip_edges()
	if target.is_empty():
		status.text = "Ingresá el nombre del otro clan."
		return
	var captions := {"propose": "la propuesta de alianza", "accept": "la aceptación de alianza", "reject": "el rechazo de la propuesta", "cancel": "la cancelación de la relación", "declare_war": "la declaración de guerra", "end_war": "el fin de la guerra"}
	confirm_action("diplomacy." + action, {"clan": target}, "Confirmar %s con %s. Las guerras sólo afectan el combate fuera de zonas seguras." % [captions.get(action, "el cambio de relación"), target])

func _transfer(action: String) -> void:
	var item := _second_selected if action == "deposit" else _selected
	if item.is_empty(): return
	mutate("depot." + action, {"slot": int(item.slot), "item": int(item.item), "quantity": int(_controls.quantity.value)})

func _join_faction() -> void:
	if _controls.faction.selected < 0: return
	confirm_action("faction.join", {"faction": _controls.faction.get_item_metadata(_controls.faction.selected)}, "El cambio de facción tiene un plazo de espera de 24 horas. El prestigio comienza en cero.")

func _quest_action(action: String) -> void:
	if _selected.is_empty(): return
	var params := {"quest": _selected.id, "npc": _npc}
	if action == "abandon":
		confirm_action("quests.abandon", params, "Se perderá el progreso de esta misión. Los objetos que ya entregaste no se devuelven.")
	else:
		mutate("quests." + action, params)
