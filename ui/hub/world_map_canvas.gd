extends Control
class_name WorldMapCanvas

signal selected(map_id: int)
var topology := {}
var current := 0
var zoom := 1.0
var pan := Vector2.ZERO
var _drag := false
const CELL := Vector2(84, 52)

func point(id: int) -> Vector2:
	var row: Dictionary = topology.get("maps", {}).get(str(id), {})
	var position: Array = row.get("position", [0, 0])
	return Vector2(position[0], position[1]) * CELL * zoom + pan

func center_current() -> void:
	pan = size / 2.0 - point(current) + pan
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for edge in topology.get("edges", []):
		var from := point(int(edge.from))
		var to := point(int(edge.to))
		if not Rect2(Vector2.ZERO, size).grow(100).has_point(from) and not Rect2(Vector2.ZERO, size).grow(100).has_point(to): continue
		if edge.kind == "teleport": draw_dashed_line(from, to, Color.GRAY, 1.0, 4.0)
		else: draw_line(from, to, Color.DARK_GRAY, 1.0)
		if not edge.reciprocal:
			var direction := (to - from).normalized()
			var tip := to - direction * 24 * zoom
			draw_line(tip, tip - direction.rotated(0.6) * 8, Color.GRAY)
			draw_line(tip, tip - direction.rotated(-0.6) * 8, Color.GRAY)
	for key in topology.get("maps", {}):
		var id := int(key)
		var p := point(id)
		var rect := Rect2(p - CELL * zoom * 0.36, CELL * zoom * 0.72)
		if not Rect2(Vector2.ZERO, size).intersects(rect): continue
		draw_rect(rect, Color(0.17, 0.17, 0.17))
		draw_rect(rect, Color.GOLD if id == current else Color.GRAY, false, 2.0 if id == current else 1.0)
		draw_string(font, p + Vector2(-14, 4), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var previous := zoom
			zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.3, 3.0)
			pan = event.position - (event.position - pan) * zoom / previous
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for key in topology.get("maps", {}):
				if Rect2(point(int(key)) - CELL * zoom * 0.36, CELL * zoom * 0.72).has_point(event.position):
					selected.emit(int(key))
					break
		accept_event()
	if event is InputEventMouseMotion and _drag:
		pan += event.relative
		accept_event()
	queue_redraw()
