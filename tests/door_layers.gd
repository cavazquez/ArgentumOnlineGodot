extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world: MapContainer = load("res://engine/map_container.tscn").instantiate()
	add_child(world)
	for cycle in range(12):
		assert(world.LoadMap(1))
		world.AddObject(5593, 48, 65)
		world.AddObject(5593, 49, 65)
		world.AddObject(511, 48, 65)
		# Un objeto alto recogible usa la misma profundidad que una puerta,
		# pero no comparte su identidad ni su retirada.
		world.AddObject(5593, 47, 65)
		world.AddObject(5592, 47, 65)
		world.DeleteObject(47, 65)
		var door: WeakRef = weakref(world._door_sprites[Vector2i(48, 65)])
		world.DeleteObject(48, 65)
		await get_tree().process_frame
		assert(door.get_ref() != null)
		assert(world.GetObjectAt(48, 65) == null)
		world.AddObject(5592, 48, 65)
		world.AddObject(5592, 49, 65)
		await RenderingServer.frame_post_draw
		assert(door.get_ref() == null)
		assert(world._door_sprites.size() == 2)
		assert(world.LoadMap(2))
		assert(world._door_sprites.is_empty())
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var released: WeakRef = weakref(world)
	world.queue_free()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(released.get_ref() == null)
	print("DOOR_LAYERS: PASS cycles=12 independent_ground=true")
	get_tree().quit()
