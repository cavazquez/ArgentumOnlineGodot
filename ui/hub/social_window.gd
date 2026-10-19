extends WorldStateWindow
class_name SocialWindow

const RANKS := {1: "Miembro", 2: "Oficial", 3: "Vicelíder", 4: "Líder"}
var _summary: Label
var _members: ItemList
var _invitations: ItemList
var _name: LineEdit
var _description: LineEdit
var _create: Button
var _target: LineEdit
var _invite: Button
var _accept: Button
var _reject: Button
var _leave: Button
var _member_actions: Dictionary = {}
var _selected_member := 0
var _selected_invitation := 0
var _previous: Button
var _next: Button
var _page: Label

func _init(kind: String = "party") -> void:
	topic = kind
	title = "Grupo" if kind == "party" else "Clan"

func _build() -> void:
	_summary = label(body)
	_name = LineEdit.new()
	_name.placeholder_text = "Nombre del clan"
	_name.max_length = 30
	body.add_child(_name)
	_description = LineEdit.new()
	_description.placeholder_text = "Descripción del clan"
	_description.max_length = 200
	body.add_child(_description)
	_create = button(body, "Crear grupo" if topic == "party" else "Crear clan", _create_group)
	_members = ItemList.new()
	_members.custom_minimum_size.y = 150
	_members.item_selected.connect(func(index: int):
		_selected_member = int(_members.get_item_metadata(index).id)
		_refresh_buttons())
	body.add_child(_members)
	var member_actions := HFlowContainer.new()
	body.add_child(member_actions)
	for action in (["kick", "leader"] if topic == "party" else ["kick", "promote", "demote", "transfer"]):
		var captions := {"kick": "Expulsar", "leader": "Hacer líder", "promote": "Ascender", "demote": "Degradar", "transfer": "Transferir liderazgo"}
		_member_actions[action] = button(member_actions, captions[action], _member_action.bind(action))
	_leave = button(member_actions, "Salir", func(): confirm_action(topic + ".leave", {}, "¿Querés abandonar este %s?" % ("grupo" if topic == "party" else "clan")))
	var pages := HBoxContainer.new()
	body.add_child(pages)
	_previous = button(pages, "Anterior", _change_page.bind(-1))
	_page = label(pages)
	_next = button(pages, "Siguiente", _change_page.bind(1))
	var invitation := HBoxContainer.new()
	body.add_child(invitation)
	_target = LineEdit.new()
	_target.max_length = 20
	_target.placeholder_text = "Nombre del jugador conectado"
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invitation.add_child(_target)
	_invite = button(invitation, "Invitar", func(): mutate(topic + ".invite", {"username": _target.text.strip_edges()}))
	label(body, "Invitaciones recibidas")
	_invitations = ItemList.new()
	_invitations.custom_minimum_size.y = 75
	_invitations.item_selected.connect(func(index: int):
		_selected_invitation = index
		_refresh_buttons())
	body.add_child(_invitations)
	var invitation_actions := HBoxContainer.new()
	body.add_child(invitation_actions)
	_accept = button(invitation_actions, "Aceptar", _invitation_action.bind("accept"))
	_reject = button(invitation_actions, "Rechazar", _invitation_action.bind("reject"))

func _render() -> void:
	_members.clear()
	_invitations.clear()
	if state.is_empty():
		_refresh_buttons()
		return
	var group_id := int(state.get(topic + "_id", 0))
	_summary.text = "Sin grupo" if topic == "party" and group_id == 0 else "Sin clan" if group_id == 0 else "Grupo #%d" % group_id if topic == "party" else "%s · %d miembros · Tu rango: %s" % [state.name, int(state.member_count), RANKS.get(int(state.own_rank), "Miembro")]
	_name.visible = topic == "clan" and group_id == 0
	_description.visible = _name.visible
	_create.visible = group_id == 0
	for member in state.get("members", []):
		var details := "%s · nivel %d · %s" % [member.name, int(member.level), "conectado" if member.online else "desconectado"]
		if topic == "party": details += " · %d/%d vida · mapa %d%s" % [int(member.hp), int(member.max_hp), int(member.map), " · líder" if int(member.id) == int(state.leader) else ""]
		else: details += " · " + RANKS.get(int(member.rank), "Miembro")
		var index := _members.add_item(details)
		_members.set_item_metadata(index, member.duplicate(true))
		if int(member.id) == _selected_member: _members.select(index)
	var invitations: Array = state.get("invitations", []) if topic == "party" else ([] if state.get("invitation", {}).is_empty() else [state.invitation])
	for invitation in invitations:
		var remaining := maxi(0, int(invitation.expires) - int(Time.get_unix_time_from_system()))
		var description := "%s · invitó %s · vence en %d s" % ["Grupo #%d" % int(invitation.party_id) if topic == "party" else invitation.name, invitation.from, remaining]
		var index := _invitations.add_item(description)
		_invitations.set_item_metadata(index, invitation.duplicate(true))
	if _invitations.item_count > 0:
		_selected_invitation = clampi(_selected_invitation, 0, _invitations.item_count - 1)
		_invitations.select(_selected_invitation)
	_previous.visible = topic == "clan"
	_next.visible = topic == "clan"
	_page.visible = topic == "clan"
	_page.text = "Página %d de %d" % [int(state.get("page", 0)) + 1, int(state.get("pages", 1))]
	_refresh_buttons()

func _refresh_buttons() -> void:
	var permissions: Array = state.get("permissions", [])
	_create.disabled = pending() or not "create" in permissions
	_invite.disabled = pending() or not "invite" in permissions
	_leave.disabled = pending() or not "leave" in permissions
	_previous.disabled = pending() or int(state.get("page", 0)) <= 0
	_next.disabled = pending() or int(state.get("page", 0)) >= int(state.get("pages", 1)) - 1
	var row := _selected_row()
	for action in _member_actions:
		var permitted: bool = not row.is_empty() and int(row.id) != int(state.get("user", 0)) and (action in row.get("actions", []) if topic == "clan" else action in permissions)
		_member_actions[action].disabled = pending() or not permitted
	var invitation := _selected_invite()
	_accept.disabled = pending() or invitation.is_empty() or int(invitation.get("expires", 0)) <= int(Time.get_unix_time_from_system()) or int(state.get(topic + "_id", 0)) != 0
	_reject.disabled = pending() or invitation.is_empty()

func _selected_row() -> Dictionary:
	for index in _members.item_count:
		var row: Dictionary = _members.get_item_metadata(index)
		if int(row.id) == _selected_member: return row
	return {}

func _selected_invite() -> Dictionary:
	if _invitations.item_count == 0: return {}
	return _invitations.get_item_metadata(clampi(_selected_invitation, 0, _invitations.item_count - 1))

func _create_group() -> void:
	mutate(topic + ".create", {} if topic == "party" else {"name": _name.text.strip_edges(), "description": _description.text.strip_edges()})

func _member_action(action: String) -> void:
	var row := _selected_row()
	if row.is_empty(): return
	var messages := {"kick": "¿Expulsar a %s?", "leader": "¿Entregar el liderazgo a %s?", "transfer": "¿Transferir el liderazgo del clan a %s? Vas a dejar de ser su líder."}
	var params := {"username": row.name}
	if action in messages:
		confirm_action(topic + "." + action, params, messages[action] % row.name)
	else:
		mutate(topic + "." + action, params)

func _invitation_action(action: String) -> void:
	var invitation := _selected_invite()
	if invitation.is_empty(): return
	mutate(topic + "." + action, {"party_id": int(invitation.party_id)} if topic == "party" else {})

func _change_page(delta: int) -> void:
	if pending(): return
	GameProtocol.WriteWorldAction("clan.read", {"page": int(state.get("page", 0)) + delta})

func _process(delta: float) -> void:
	super._process(delta)
	if visible and _accept != null: _refresh_buttons()
