extends Window
class_name WorldMapWindow

var current_map := 0
var _canvas: WorldMapCanvas
var _description: Label

func _ready() -> void:
	title = "Mapa mundial"
	size = Vector2i(680, 460)
	exclusive = true
	close_requested.connect(queue_free)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var legend := Label.new()
	legend.text = "Rueda: zoom · botón central: desplazar · flecha: una dirección · punteada: teleport o borde plegado (naranja) · punto blanco: visitado"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(legend)
	_canvas = WorldMapCanvas.new()
	_canvas.topology = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/world-topology.json"))
	_canvas.current = current_map
	_canvas.visited = Global.character_local.visited.duplicate()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	box.add_child(_canvas)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_description)
	_canvas.selected.connect(_select)
	var center := Button.new()
	center.text = "Centrar mapa actual"
	center.pressed.connect(_canvas.center_current)
	box.add_child(center)
	_select(current_map)
	_canvas.center_current.call_deferred()

func _select(id: int) -> void:
	var row: Dictionary = _canvas.topology.get("maps", {}).get(str(id), {})
	var outgoing := PackedStringArray()
	var incoming := PackedStringArray()
	for edge in _canvas.topology.get("edges", []):
		if int(edge.from) == id: outgoing.append("%d (%s)" % [edge.to, edge.kind])
		if int(edge.to) == id: incoming.append(str(edge.from))
	var access := " · reservado (acceso administrativo)" if row.get("role", "playable") == "reserved" else ""
	_description.text = "%s · #%d\nSalidas: %s\nEntradas: %s" % [row.get("name", "Sin miniatura") + access + (" · visitado" if Global.character_local.visited.has(id) else " · no visitado"), id, ", ".join(outgoing), ", ".join(incoming)]
