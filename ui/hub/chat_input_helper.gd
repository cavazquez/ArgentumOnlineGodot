extends RefCounted
class_name ChatInputHelper

const MAX_HISTORY := 50
const SENSITIVE := ["/password", "/passwd", "/pass", "/login", "/clave", "/cambiarclave", "/contrasena", "/contraseña"]
var history := PackedStringArray()
var _cursor := 0
var _draft := ""
var _line: LineEdit
var _hint: Label
var _commands: Array = []
var _matches: Array = []
var _completion_index := -1
var _inserting := false

func install(line: LineEdit) -> void:
	_line = line
	_hint = Label.new()
	_hint.position = Vector2(0, -44)
	_hint.size = Vector2(line.size.x, 44)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.hide()
	line.add_child(_hint)
	line.gui_input.connect(_input)
	line.text_changed.connect(_changed)
	line.focus_entered.connect(_focus_entered)
	line.focus_exited.connect(_focus_exited)
	line.tree_exiting.connect(dispose)
	ClientInterface.disconnected.connect(clear)
	ClientInterface.world_state.changed.connect(_state_changed)
	var saved: Dictionary = ClientInterface.world_state.states.get("commands", {})
	_commands = saved.get("commands", []).duplicate(true)

func dispose() -> void:
	clear()
	if ClientInterface.disconnected.is_connected(clear): ClientInterface.disconnected.disconnect(clear)
	if ClientInterface.world_state.changed.is_connected(_state_changed): ClientInterface.world_state.changed.disconnect(_state_changed)
	_line = null

func clear() -> void:
	history.clear()
	_cursor = 0
	_draft = ""
	_matches.clear()
	_commands.clear()
	if is_instance_valid(_hint): _hint.hide()

func record(text: String) -> void:
	var value := text.strip_edges()
	var first := value.split(" ", false, 1)[0].to_lower() if not value.is_empty() else ""
	if not value.is_empty() and value.length() <= 512 and not first in SENSITIVE and not _line.secret:
		if history.is_empty() or history[-1] != value: history.append(value)
		if history.size() > MAX_HISTORY: history.remove_at(0)
	_cursor = history.size()
	_draft = ""
	_matches.clear()
	_hint.hide()

func _focus_entered() -> void:
	if ClientInterface.capabilities.has_feature(ClientCapabilities.WORLD_STATE): GameProtocol.WriteWorldAction("subscribe", {"topic": "commands", "enabled": true})
	_changed(_line.text)

func _focus_exited() -> void:
	_hint.hide()
	if ClientInterface.capabilities.has_feature(ClientCapabilities.WORLD_STATE): GameProtocol.WriteWorldAction("subscribe", {"topic": "commands", "enabled": false})

func _state_changed(kind: String, data: Dictionary, _revision: String) -> void:
	if kind == "reset": clear()
	elif kind == "commands":
		_commands = data.get("commands", []).duplicate(true)
		if is_instance_valid(_line) and _line.has_focus(): _changed(_line.text)

func dismiss_completion() -> bool:
	if is_instance_valid(_hint) and _hint.visible:
		_hint.hide()
		_matches.clear()
		return true
	return false

func _changed(text: String) -> void:
	if _inserting: return
	_matches.clear()
	_completion_index = -1
	var prefix := text.split(" ", true, 1)[0].to_upper()
	if text.begins_with("/"):
		for command in _commands:
			if String(command.text).to_upper().begins_with(prefix): _matches.append(command)
	if _matches.is_empty():
		_hint.hide()
		return
	var names := PackedStringArray()
	for index in mini(3, _matches.size()): names.append(_matches[index].syntax)
	_hint.text = "Tab: " + " · ".join(names)
	_hint.size.x = _line.size.x
	_hint.visible = _line.has_focus()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	if event.keycode in [KEY_UP, KEY_DOWN]:
		if history.is_empty(): return
		if _cursor == history.size(): _draft = _line.text
		_cursor = clampi(_cursor + (-1 if event.keycode == KEY_UP else 1), 0, history.size())
		_insert(history[_cursor] if _cursor < history.size() else _draft)
		_line.accept_event()
	elif event.keycode == KEY_TAB and not _matches.is_empty():
		_completion_index = posmod(_completion_index + (-1 if event.shift_pressed else 1), _matches.size())
		var command: Dictionary = _matches[_completion_index]
		var space := _line.text.find(" ")
		var tail := _line.text.substr(space) if space >= 0 else " "
		_insert(command.text + tail)
		_hint.text = command.syntax + " · Enter envía; Tab sólo completa."
		_line.accept_event()

func _insert(text: String) -> void:
	_inserting = true
	_line.text = text
	_line.caret_column = text.length()
	_inserting = false
