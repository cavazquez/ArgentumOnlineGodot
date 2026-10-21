extends Node

func _ready() -> void:
	get_tree().create_timer(360).timeout.connect(func():
		push_error("ALL_MAPS_AUDIT: timeout")
		get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Engine.max_fps = 120
	get_tree().root.size = Vector2i(800, 600)
	var holder := SubViewportContainer.new()
	holder.size = Vector2(544, 416)
	holder.stretch = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(544, 416)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(viewport)
	add_child(holder)
	var world = load("res://engine/map_container.tscn").instantiate()
	viewport.add_child(world)
	var camera := Camera2D.new()
	camera.position = Vector2(1600, 1600)
	viewport.add_child(camera)
	var evidence := {"maps": {}, "rendered_pairs": [], "engine": Engine.get_version_info(), "passed": true, "network_crossings": false, "display_server": DisplayServer.get_name()}
	var topology: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/world-topology.json"))
	var ids: Array[int] = []
	for key in topology.maps: ids.append(int(key))
	ids.sort()
	for mid in ids:
		if not world.LoadMap(mid):
			push_error("ALL_MAPS_AUDIT: no carga mapa %d" % mid)
			get_tree().quit(1)
			return
		camera.position = Vector2(1600, 1600)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		evidence.maps[str(mid)] = {"flags": Marshalls.raw_to_base64(world._tiles), "rendered": true, "cache": world._cache.snapshot()}
		if mid % 25 == 0: print("ALL_MAPS_AUDIT: maps=", mid)
	var seen := {}
	for edge in topology.edges:
		var a := int(edge.from)
		var b := int(edge.to)
		var key := "%d:%d" % [a,b]
		if seen.has(key): continue
		seen[key] = true
		var endpoint: Array = edge.exits[0]
		if not world.LoadMap(a):
			push_error("ALL_MAPS_AUDIT: no carga origen " + key)
			get_tree().quit(1)
			return
		camera.position = Vector2((int(endpoint[0]) - 0.5) * 32, (int(endpoint[1]) - 0.5) * 32)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not world.LoadMap(b):
			push_error("ALL_MAPS_AUDIT: no carga destino " + key)
			get_tree().quit(1)
			return
		camera.position = Vector2((int(endpoint[2]) - 0.5) * 32, (int(endpoint[3]) - 0.5) * 32)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var budget: Dictionary = world._cache.snapshot()
		if budget.views > budget.limit_views or budget.estimated_bytes > budget.limit_bytes:
			push_error("ALL_MAPS_AUDIT: excede presupuesto " + key)
			evidence.passed = false
		evidence.rendered_pairs.append([a,b])
		if evidence.rendered_pairs.size() % 100 == 0: print("ALL_MAPS_AUDIT: pairs=", evidence.rendered_pairs.size())
	var output := OS.get_environment("PYAO_MAP_AUDIT_OUTPUT")
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence))
	file.close()
	holder.queue_free()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	print("ALL_MAPS_AUDIT: PASS maps=", evidence.maps.size(), " pairs=", evidence.rendered_pairs.size())
	get_tree().quit(0 if evidence.passed else 1)
