extends Node

signal bindings_changed
const PATH := "user://controls.cfg"
const UNSUPPORTED := [&"TalkWithGuild", &"ToggleResuscitationSafe"]
const LABELS := {"EquipObject":"Equipar objeto", "UseObject":"Usar objeto", "Pickup":"Recoger", "Attack":"Atacar", "Hide":"Ocultarse", "RequestRefresh":"Actualizar posición", "TamAnimal":"Domar", "Steal":"Robar", "DropObject":"Tirar objeto", "ExitGame":"Salir", "Meditate":"Meditar", "TakeScreenShot":"Captura de pantalla", "ToggleSafeMode":"Modo seguro", "Talk":"Hablar", "ui_left":"Caminar a la izquierda", "ui_right":"Caminar a la derecha", "ui_up":"Caminar hacia arriba", "ui_down":"Caminar hacia abajo"}
var defaults := {}
var capturing := false

func label(action: StringName) -> String:
	return LABELS.get(String(action), String(action))

func _ready() -> void:
	for property in ProjectSettings.get_property_list():
		var key := String(property.name)
		if key.begins_with("input/"):
			var action := StringName(key.trim_prefix("input/"))
			defaults[action] = InputMap.action_get_events(action).duplicate(true)
	for action in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		defaults[action] = InputMap.action_get_events(action).duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK: return
	for action in defaults:
		var encoded = cfg.get_value("bindings", String(action), null)
		if encoded == null: continue
		if not encoded is Array or encoded.size() > 16: continue
		var events: Array[InputEvent] = []
		var valid := true
		for row in encoded:
			var event := decode(row)
			if event == null:
				valid = false
				break
			events.append(event)
		if valid and not events.is_empty(): _install(action, events)

func decode(row: Variant) -> InputEvent:
	if not row is Dictionary: return null
	var event: InputEvent
	match row.get("type", ""):
		"key":
			event = InputEventKey.new()
			event.physical_keycode = int(row.get("physical", 0))
			event.keycode = int(row.get("key", 0))
			event.location = int(row.get("location", 0))
			event.shift_pressed = bool(row.get("shift", false))
			event.ctrl_pressed = bool(row.get("ctrl", false))
			event.alt_pressed = bool(row.get("alt", false))
			event.meta_pressed = bool(row.get("meta", false))
			if event.keycode == 0 and event.physical_keycode == 0: return null
		"joy_button":
			event = InputEventJoypadButton.new()
			event.button_index = int(row.get("button", -1))
			if event.button_index < 0 or event.button_index >= JOY_BUTTON_MAX: return null
		"joy_motion":
			event = InputEventJoypadMotion.new()
			event.axis = int(row.get("axis", -1))
			event.axis_value = float(row.get("value", 0))
			if event.axis < 0 or event.axis >= JOY_AXIS_MAX or absf(event.axis_value) != 1.0: return null
		_: return null
	event.device = int(row.get("device", -1))
	return event

func encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type":"key", "device":event.device, "physical":event.physical_keycode, "key":event.keycode, "location":event.location, "shift":event.shift_pressed, "ctrl":event.ctrl_pressed, "alt":event.alt_pressed, "meta":event.meta_pressed}
	if event is InputEventJoypadButton: return {"type":"joy_button", "device":event.device, "button":event.button_index}
	if event is InputEventJoypadMotion: return {"type":"joy_motion", "device":event.device, "axis":event.axis, "value":event.axis_value}
	return {}

func conflicts(action: StringName, event: InputEvent) -> Array[StringName]:
	var result: Array[StringName] = []
	for other in defaults:
		if other == action: continue
		for previous in InputMap.action_get_events(other):
			if previous.is_match(event):
				result.append(other)
				break
	return result

func _install(action: StringName, events: Array) -> void:
	InputMap.action_erase_events(action)
	for event in events: InputMap.action_add_event(action, event)

func assign(action: StringName, event: InputEvent) -> Error:
	if not defaults.has(action) or encode(event).is_empty(): return ERR_INVALID_PARAMETER
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) < 0.5: return ERR_INVALID_PARAMETER
		event = event.duplicate()
		event.axis_value = signf(event.axis_value)
	var previous := InputMap.action_get_events(action)
	# Conservar gamepad al reasignar teclado, y viceversa.
	var events: Array[InputEvent] = [event]
	for old in previous:
		if (event is InputEventKey) != (old is InputEventKey): events.append(old)
	_install(action, events)
	var result := save()
	if result != OK: _install(action, previous)
	bindings_changed.emit()
	return result

func restore(action: StringName = &"") -> Error:
	var previous := {}
	for key in defaults:
		previous[key] = InputMap.action_get_events(key)
		if action == &"" or action == key: _install(key, defaults[key])
	var result := save()
	if result != OK:
		for key in previous: _install(key, previous[key])
	bindings_changed.emit()
	return result

func save() -> Error:
	var cfg := ConfigFile.new()
	for action in defaults:
		var events := []
		for event in InputMap.action_get_events(action): events.append(encode(event))
		cfg.set_value("bindings", String(action), events)
	var error := cfg.save(PATH + ".tmp")
	if error != OK: return error
	return DirAccess.rename_absolute(PATH + ".tmp", PATH)
