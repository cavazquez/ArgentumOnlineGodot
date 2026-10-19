extends Window
class_name ControlsWindow

var _action := &""
var _pending: InputEvent
var _message: Label
var _list: VBoxContainer
var _confirmation: ConfirmationDialog

func _ready() -> void:
	Utils.ApplyDialogTheme(self)
	title = "Controles"
	size = Vector2i(520, 420)
	exclusive = true
	close_requested.connect(_close)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_message = Label.new()
	_message.text = "Elegí una acción para reasignar. Escape cancela la captura."
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var reset := Button.new()
	reset.text = "Restaurar todos los controles"
	reset.pressed.connect(func(): InputBindings.restore(); _refresh())
	box.add_child(reset)
	var close := Button.new()
	close.text = "Cerrar"
	close.pressed.connect(_close)
	box.add_child(close)
	_confirmation = ConfirmationDialog.new()
	add_child(_confirmation)
	_confirmation.confirmed.connect(_apply)
	_confirmation.canceled.connect(_cancel)
	_refresh()

func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for action in InputBindings.defaults:
		if action in InputBindings.UNSUPPORTED: continue
		var row := HBoxContainer.new()
		_list.add_child(row)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var names := PackedStringArray()
		for event in InputMap.action_get_events(action): names.append(event.as_text())
		button.text = "%s: %s" % [InputBindings.label(action), ", ".join(names)]
		button.pressed.connect(func():
			_action = action
			InputBindings.capturing = true
			_message.text = "Presioná el control para %s" % InputBindings.label(action))
		row.add_child(button)
		var restore := Button.new()
		restore.text = "Restaurar"
		restore.pressed.connect(func(): InputBindings.restore(action); _refresh())
		row.add_child(restore)

func _input(event: InputEvent) -> void:
	if not InputBindings.capturing: return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel()
		return
	if not event.is_pressed() or event.is_echo() or InputBindings.encode(event).is_empty(): return
	_pending = event.duplicate()
	InputBindings.capturing = false
	var conflicts := InputBindings.conflicts(_action, _pending)
	if conflicts.is_empty(): _apply()
	else:
		var labels := PackedStringArray()
		for conflict in conflicts: labels.append(InputBindings.label(conflict))
		_confirmation.dialog_text = "Este control también se usa en %s. ¿Asignarlo igualmente?" % ", ".join(labels)
		_confirmation.popup_centered()

func _apply() -> void:
	var result := InputBindings.assign(_action, _pending)
	_message.text = "Control guardado." if result == OK else "No se pudo guardar el control."
	_cancel()
	_refresh()

func _cancel() -> void:
	InputBindings.capturing = false
	_action = &""
	_pending = null

func _close() -> void:
	_cancel()
	queue_free()

func _exit_tree() -> void:
	InputBindings.capturing = false
