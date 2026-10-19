extends Window
class_name PlayerTradePanel

signal finished
var snapshot: Dictionary = {}
var inventory: Inventory
var _pending := false
var _closing := false
var _ended := false
var status: Label
var offers: Array[Label] = []
var offer_items: Array[ItemList] = []
var _metadata: Dictionary = {}
var _metadata_pages: Dictionary = {}
var _metadata_total := 0
var _metadata_revision := -1
var _metadata_requesting := false
var _details: Label
var _metadata_retry: Button
var available: OptionButton
var slot: SpinBox
var quantity: SpinBox
var gold: SpinBox
var item_button: Button
var gold_button: Button
var accept_button: Button
var confirm_button: Button
var cancel_button: Button

func _ready() -> void:
	title = "Intercambio entre jugadores"
	Utils.ApplyDialogTheme(self)
	size = Vector2i(640, 440)
	min_size = Vector2i(450, 360)
	transient = true
	exclusive = true
	close_requested.connect(RequestClose)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(columns)
	for index in range(2):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		var offer := Label.new()
		offer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(offer)
		offers.append(offer)
		var items := ItemList.new()
		items.custom_minimum_size = Vector2(240, 150)
		items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		items.fixed_icon_size = Vector2i(32, 32)
		items.item_selected.connect(_show_description.bind(items))
		column.add_child(items)
		offer_items.append(items)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_details)
	_metadata_retry = _button(root, "Volver a pedir los datos de los objetos", _retry_metadata)
	_metadata_retry.hide()
	available = OptionButton.new()
	root.add_child(available)
	available.item_selected.connect(func(index: int): slot.value = available.get_item_id(index))
	var editor := HBoxContainer.new()
	root.add_child(editor)
	slot = _number(editor, "Slot", 1, 30)
	quantity = _number(editor, "Cantidad (0: quitar)", 0, 32767)
	quantity.value = 1
	item_button = _button(editor, "Ofrecer objeto", func(): _send(1, int(slot.value), int(quantity.value)))
	var gold_row := HBoxContainer.new()
	root.add_child(gold_row)
	gold = _number(gold_row, "Oro", 0, 999999999)
	gold_button = _button(gold_row, "Ofrecer oro", func(): _send(2, 0, int(gold.value)))
	var actions := HBoxContainer.new()
	root.add_child(actions)
	accept_button = _button(actions, "Aceptar invitación", func(): _send(0))
	confirm_button = _button(actions, "Confirmar esta revisión", func(): _send(3))
	cancel_button = _button(actions, "Cancelar", RequestClose)
	if inventory != null:
		inventory.slotChanged.connect(_InventoryChanged)
		_RefreshInventoryChoices()
	if not snapshot.is_empty():
		ApplySnapshot(snapshot)

func _number(parent: Node, caption: String, minimum: int, maximum: int) -> SpinBox:
	var column := VBoxContainer.new()
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	column.add_child(label)
	var value := SpinBox.new()
	value.min_value = minimum
	value.max_value = maximum
	value.step = 1
	column.add_child(value)
	return value

func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func ApplySnapshot(value: Dictionary) -> void:
	if not snapshot.is_empty() and (value.id != snapshot.id or value.sequence < snapshot.sequence):
		return
	if _ended:
		return
	if _metadata_revision != int(value.revision):
		_metadata.clear()
		_metadata_pages.clear()
		_metadata_total = 0
		_metadata_revision = int(value.revision)
		_metadata_requesting = false
		if _details != null: _details.text = ""
	snapshot = value
	_pending = false
	if status == null: return
	_render_offers()
	if value.state in ["completed", "cancelled"]:
		_ended = true
		finished.emit()

func ApplyMetadata(value: Dictionary) -> void:
	if snapshot.is_empty() or value.session != snapshot.id or int(value.trade_revision) != int(snapshot.revision) or _ended: return
	_metadata_total = int(value.pages)
	_metadata_pages[int(value.page)] = true
	for item in value.items: _metadata[int(item.id)] = item.duplicate(true)
	_render_offers()
	if _metadata_requesting and not _metadata_ready(): _request_metadata()

func _render_offers() -> void:
	var value := snapshot
	status.text = "Revisión %d · %s\n%s" % [int(value.revision), value.state, value.reason]
	for index in range(2):
		var player: Array = value.players[index]
		offers[index].text = "%s%s\nOro: %d\n%s" % [player[1], " (vos)" if player[0] == value.viewer else "", int(player[2]), "Confirmado" if player[3] else "Sin confirmar"]
		offer_items[index].clear()
		for item in player[4]:
			var info := _item_info(int(item[1]))
			var row := offer_items[index].add_item("%s × %d" % [info.name, int(item[2])], _icon(info))
			offer_items[index].set_item_tooltip(row, _description(info))
			offer_items[index].set_item_metadata(row, info)
	var active: bool = value.state == "active" and not _pending and not _closing
	item_button.disabled = not active
	gold_button.disabled = not active
	accept_button.disabled = _pending or _closing
	accept_button.visible = value.state == "pending" and value.viewer == value.players[1][0]
	var own_index := 0 if value.viewer == value.players[0][0] else 1
	confirm_button.disabled = not active or bool(value.players[own_index][3]) or not _metadata_ready()
	_metadata_retry.visible = not _metadata_ready() and value.state == "active" and ClientInterface.capabilities.has_feature(ClientCapabilities.WORLD_STATE)
	if value.state == "active" and not _metadata_ready(): status.text += "\nFaltan datos de los objetos: confirmar está deshabilitado. Podés cancelar."

func _metadata_ready() -> bool:
	if snapshot.is_empty(): return false
	for player in snapshot.players:
		for item in player[4]:
			if not _item_info(int(item[1])).known: return false
	return true

func _item_info(item_id: int) -> Dictionary:
	if _metadata.has(item_id): return _metadata[item_id]
	if not ClientInterface.capabilities.has_feature(ClientCapabilities.WORLD_STATE) and inventory != null:
		for index in inventory.GetSize():
			var own := inventory.GetSlot(index)
			if own != null and own.item.index == item_id:
				return {"known": true, "name": own.item.name, "icon": own.item.icon, "min_hit": own.item.minHit, "max_hit": own.item.maxHit, "min_def": own.item.minDef, "max_def": own.item.maxDef}
	return {"known": false, "name": "Objeto #%d (sin datos)" % item_id}

func _icon(info: Dictionary) -> Texture2D:
	if info.get("icon") is Texture2D: return info.icon
	var graphic := int(info.get("graphic", 0))
	if graphic <= 0 or graphic >= GameAssets.GrhDataList.size() or GameAssets.GrhDataList[graphic] == null: return null
	var grh: GrhData = GameAssets.GrhDataList[graphic]
	if grh.frameCount > 1:
		if grh.frames.size() < 2: return null
		var first := int(grh.frames[1])
		if first <= 0 or first >= GameAssets.GrhDataList.size() or GameAssets.GrhDataList[first] == null: return null
		grh = GameAssets.GrhDataList[first]
	var texture := AtlasTexture.new()
	texture.atlas = GameAssets.GetTexture(grh.fileId)
	texture.region = grh.region
	return texture

func _description(info: Dictionary) -> String:
	if not info.known: return info.name + " · Esperando el catálogo del servidor."
	return "%s\nDaño: %d/%d · Defensa: %d/%d" % [info.name, int(info.get("min_hit", 0)), int(info.get("max_hit", 0)), int(info.get("min_def", 0)), int(info.get("max_def", 0))]

func _show_description(index: int, source: ItemList) -> void:
	_details.text = _description(source.get_item_metadata(index))

func _request_metadata() -> void:
	if snapshot.is_empty() or not ClientInterface.capabilities.has_feature(ClientCapabilities.WORLD_STATE): return
	_metadata_requesting = true
	for page in maxi(1, _metadata_total):
		if not _metadata_pages.has(page):
			GameProtocol.WriteWorldAction("trade.read", {"session": snapshot.id, "revision": int(snapshot.revision), "page": page})
			return

func _send(action: int, source: int = 0, amount: int = 0) -> void:
	if _pending or _closing or snapshot.is_empty() or (action == 3 and not _metadata_ready()):
		return
	if GameProtocol.WriteTradeAction(snapshot.id, int(snapshot.revision), action, source, amount):
		_pending = true
		item_button.disabled = true
		gold_button.disabled = true
		confirm_button.disabled = true
		accept_button.disabled = true

func RequestClose() -> void:
	if _closing or snapshot.is_empty():
		return
	_closing = GameProtocol.WriteTradeAction(snapshot.id, int(snapshot.revision), 4)
	if _closing:
		status.text = "Esperando el resultado de la cancelación…"
		cancel_button.disabled = true

func _InventoryChanged(_index: int, _stack: ItemStack) -> void:
	_RefreshInventoryChoices()

func _RefreshInventoryChoices() -> void:
	available.clear()
	available.add_item("Tu inventario · elegí un objeto", 0)
	for index in range(inventory.GetSize()):
		var stack := inventory.GetSlot(index)
		if stack != null and stack.quantity > 0:
			available.add_item("Slot %d · %s × %d%s" % [index + 1, stack.item.name, stack.quantity, " (equipado)" if stack.equipped else ""], index + 1)


func _retry_metadata() -> void:
	_metadata_pages.clear()
	_request_metadata()
