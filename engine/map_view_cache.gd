extends Node
class_name MapViewCache

const MAX_VIEWS := 3
const MAX_BYTES := 67108864
var _views := {}
var _order: Array[int] = []
var _queue: Array[int] = []
var _generation := 0
var _bytes := 0
var _costs := {}
var _topology: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/world-topology.json"))

func neighbours(map_id: int) -> Array[int]:
	var result: Array[int] = []
	for edge in _topology.get("edges", []):
		if int(edge.from) == map_id and edge.kind != "teleport" and not result.has(int(edge.to)):
			result.append(int(edge.to))
	return result

func schedule(map_id: int) -> void:
	_generation += 1
	_queue.clear()
	var wanted := neighbours(map_id)
	for id in _views.keys():
		if not wanted.has(id): _evict(id)
	for id in wanted:
		if not _views.has(id): _queue.append(id)
	_queue.resize(mini(MAX_VIEWS, _queue.size()))

func take(map_id: int) -> Node2D:
	if not _views.has(map_id): return null
	var view: Node2D = _views[map_id]
	_views.erase(map_id)
	_order.erase(map_id)
	_bytes -= int(_costs.get(map_id, 0))
	_costs.erase(map_id)
	remove_child(view)
	view.visible = true
	view.position = Vector2.ZERO
	view.modulate = Color.WHITE
	view.z_index = 0
	return view

func keep(map_id: int, view: Node2D) -> void:
	if view == null: return
	if view.get_parent(): view.get_parent().remove_child(view)
	if _views.has(map_id): _evict(map_id)
	var cost := _estimate(view)
	while not _order.is_empty() and (_views.size() >= MAX_VIEWS or _bytes + cost > MAX_BYTES):
		_evict(_order.front())
	if cost > MAX_BYTES:
		view.queue_free()
		return
	add_child(view)
	view.hide()
	_views[map_id] = view
	_costs[map_id] = cost
	_order.append(map_id)
	_bytes += cost

func _estimate(view: Node) -> int:
	# Presupuesto conservador de nodos y datos; las texturas del Tileset se comparten.
	var total := 4096
	if view is TileMapLayer: total += view.get_used_cells().size() * 128
	for child in view.get_children(): total += _estimate(child)
	return total

func _evict(id: int) -> void:
	if not _views.has(id): return
	var view: Node = _views[id]
	_views.erase(id)
	_order.erase(id)
	_bytes -= int(_costs.get(id, 0))
	_costs.erase(id)
	remove_child(view)
	view.queue_free()

func _process(_delta: float) -> void:
	if _queue.is_empty() or _views.size() >= MAX_VIEWS or _bytes >= MAX_BYTES: return
	var id: int = _queue.pop_front()
	var path := "res://Maps/Map%d.tscn" % id
	if not ResourceLoader.exists(path): return
	var generation := _generation
	# Los mapas comparten Tilesets/texturas con la vista activa. Cargar esos
	# recursos desde otro hilo mientras el login los usa o libera produce RIDs
	# todavía no inicializados. La precarga sigue diferida y acotada por frame.
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	if scene == null or generation != _generation or not is_inside_tree(): return
	keep(id, scene.instantiate())

func snapshot() -> Dictionary:
	return {"views": _views.size(), "estimated_bytes": _bytes, "limit_views": MAX_VIEWS, "limit_bytes": MAX_BYTES}

func _exit_tree() -> void:
	_generation += 1
	_queue.clear()
