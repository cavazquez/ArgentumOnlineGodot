extends Node

func samples(operation: Callable, loops := 100) -> Dictionary:
	var values: Array[float] = []
	for repeat in range(31):
		var start := Time.get_ticks_usec()
		for index in range(loops): operation.call()
		values.append(float(Time.get_ticks_usec() - start) / loops)
	values.sort()
	return {"unit": "microseconds_per_operation", "p50": values[15], "p95": values[29], "p99": values[30], "samples": 31, "loops": loops}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 120
	var report := {"engine": Engine.get_version_info(), "os": OS.get_name(), "entities": [], "limitations": ["Synthetic Character nodes exclude renderer children, textures and network", "Memory monitors are process observations, not additive object sizes", "Map cache estimated bytes are not measured RSS or VRAM", "Wall clock samples are not CI capacity gates"]}
	for count in [100, 1000, 5000]:
		var before := Performance.get_monitor(Performance.MEMORY_STATIC)
		var world := MapContainer.new()
		var by_id := {}
		var by_position := {}
		for index in range(count):
			var actor := Character.new()
			actor.instanceId = index + 1
			actor.gridPosition = Vector2i(index % 100 + 1, index / 100 + 1)
			world._characterCollection.append(actor)
			by_id[actor.instanceId] = actor
			by_position[actor.gridPosition] = actor
		assert(world.GetCharacter(count) == by_id[count])
		assert(world.GetCharacter(-1) == null)
		var last_position: Vector2i = by_id[count].gridPosition
		report.entities.append({"count": count,
			"character_last_linear": samples(func(): return world.GetCharacter(count)),
			"character_missing_linear": samples(func(): return world.GetCharacter(-1)),
			"character_id_dictionary": samples(func(): return by_id.get(count)),
			"position_linear": samples(func(): return world.GetCharacterAt(last_position.x, last_position.y)),
			"position_dictionary": samples(func(): return by_position.get(last_position)),
			"static_memory_delta_bytes_including_prototypes": Performance.get_monitor(Performance.MEMORY_STATIC) - before})
		for actor in world._characterCollection: actor.free()
		world._characterCollection.clear()
		world.free()
	var data := MapData.new()
	report.map_packed_payload_bytes = data.layer1.size() * 4 + data.layer2.size() * 4 + data.flags.size()
	assert(report.map_packed_payload_bytes == 90000)
	if DisplayServer.get_name() != "headless":
		var container := SubViewportContainer.new()
		container.size = Vector2(544, 416)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(544, 416)
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var world: MapContainer = load("res://engine/map_container.tscn").instantiate()
		viewport.add_child(world)
		var camera := Camera2D.new()
		camera.position = Vector2(1600, 1600)
		viewport.add_child(camera)
		add_child(container)
		var changes := []
		for cycle in range(4):
			for map_id in [1, 2, 34, 1]:
				var begin := Time.get_ticks_usec()
				assert(world.LoadMap(map_id))
				var load_usec := Time.get_ticks_usec() - begin
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var cache := world._cache.snapshot()
				assert(cache.views <= cache.limit_views and cache.estimated_bytes <= cache.limit_bytes)
				changes.append({"map": map_id, "cycle":cycle, "load_call_usec":load_usec, "through_next_draw_usec": Time.get_ticks_usec() - begin, "cache":cache, "static_memory":Performance.get_monitor(Performance.MEMORY_STATIC), "video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
		report.graphical_map_changes = changes
		container.queue_free()
		await get_tree().process_frame
	var output := OS.get_environment("PYAO_STRUCTURE_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  ") + "\n")
	print("STRUCTURE_BENCHMARK: ", JSON.stringify(report))
	get_tree().quit(0)
