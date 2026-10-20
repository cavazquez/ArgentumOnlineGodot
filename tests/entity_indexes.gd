extends Node

var _failed := false

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

func actor(world: MapContainer, identity: int, cell: Vector2i) -> Character:
	var character := Character.new()
	character.instanceId = identity
	character.gridPosition = cell
	world._TrackCharacter(character)
	return character

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := MapContainer.new()
	add_child(world)
	var first := actor(world, 1, Vector2i(1, 1))
	var second := actor(world, 2, Vector2i(100, 100))
	_check(world.GetCharacter(1) == first and world.GetCharacter(-1) == null, "ID lookup")
	first.position = Vector2(1600, 1600)
	_check(world.GetCharacterAt(1, 1) == first, "Interpolación alteró la posición lógica")
	first.gridPosition = Vector2i(100, 100)
	_check(world.GetCharacterAt(1, 1) == null, "Movimiento retuvo la celda anterior")
	_check(world.GetCharacterAt(100, 100) == first, "Cambió el orden de selección al superponer actores")
	first.gridPosition = Vector2i(50, 50)
	_check(world.GetCharacterAt(100, 100) == second, "Teletransporte retuvo la celda anterior")
	first.instanceId = 3
	_check(world.GetCharacter(1) == null and world.GetCharacter(3) == first, "Cambio de ID dejó un alias")
	world.DeleteCharacter(3)
	var replacement := actor(world, 3, Vector2i(50, 50))
	await get_tree().process_frame
	_check(not is_instance_valid(first) and world.GetCharacter(3) == replacement, "Borrado diferido eliminó el ID reutilizado")
	second.free()
	_check(world.GetCharacter(2) == null and world.GetCharacterAt(100, 100) == null, "Liberación externa retuvo un personaje")
	# La baja intercambia el último slot; los índices deben apuntar a los supervivientes.
	for index in range(1000): actor(world, 100 + index, Vector2i(index % 100 + 1, index / 100 + 1))
	for index in range(0, 1000, 2): world.DeleteCharacter(100 + index)
	for index in range(1, 1000, 2):
		_check(world.GetCharacter(100 + index) != null, "Baja borró otro ID")
	var layer := Node2D.new()
	world.add_child(layer)
	for index in range(100):
		var item := Node2D.new()
		item.set_meta(world.GridPositionKey, Vector2i(index + 1, 1))
		layer.add_child(item)
		world._TrackObject(item)
	var original := world.GetObjectAt(1, 1)
	var new_item := Node2D.new()
	new_item.set_meta(world.GridPositionKey, Vector2i(1, 1))
	layer.add_child(new_item)
	world._TrackObject(new_item)
	await get_tree().process_frame
	_check(not is_instance_valid(original) and world.GetObjectAt(1, 1) == new_item, "Reemplazo de objeto borró el nuevo sprite")
	world.GetObjectAt(2, 1).free()
	_check(world.GetObjectAt(2, 1) == null, "Liberación externa retuvo el objeto")
	world.DeleteObject(3, 1)
	_check(world.GetObjectAt(100, 1) != null and world.GetObjectAt(3, 1) == null, "Baja de objeto corrompió slots")
	world._DeleteEntities()
	_check(world._characters_by_id.is_empty() and world._characters_by_position.is_empty(), "Cambio de mapa retuvo índices de actores")
	_check(world._objectCollection.is_empty() and world._objects_by_position.is_empty(), "Cambio de mapa retuvo índices de objetos")
	_check(world._character_slots.is_empty() and world._character_order.is_empty() and world._object_slots.is_empty(), "Cambio de mapa retuvo slots")
	var next := actor(world, 3, Vector2i(1, 1))
	await get_tree().process_frame
	_check(world.GetCharacter(3) == next and world.GetCharacterAt(1, 1) == next, "Bajas del mapa anterior afectaron el nuevo")
	next.free()
	world.queue_free()
	await get_tree().process_frame
	print("ENTITY_INDEXES: ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
