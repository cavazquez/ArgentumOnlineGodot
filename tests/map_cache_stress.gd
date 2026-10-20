extends Node

var failed := false

func _check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("MAP_CACHE_STRESS: " + message)

func _ready() -> void:
	Engine.max_fps = 120
	get_window().size = Vector2i(800, 600)
	get_tree().create_timer(180).timeout.connect(func():
		push_error("MAP_CACHE_STRESS: timeout")
		get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	var cycles := 80
	if not OS.get_environment("PYAO_MAP_STRESS_CYCLES").is_empty():
		cycles = clampi(int(OS.get_environment("PYAO_MAP_STRESS_CYCLES")), 10, 300)
	for cycle in range(cycles):
		var container := SubViewportContainer.new()
		container.size = Vector2(544, 416)
		container.stretch = true
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
		for map_id in [1, 2, 1, 34, 23, 28, 91]:
			world.LoadMap(map_id)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var budget := world._cache.snapshot()
			_check(budget.views <= budget.limit_views and budget.estimated_bytes <= budget.limit_bytes, "Caché fuera de presupuesto")
			_check(world._view.get_viewport() == viewport, "Vista activa en otro viewport")
			for view in world._cache._views.values():
				_check(view.get_viewport() == viewport, "Vecino cacheado en otro viewport")
		var released: WeakRef = weakref(container)
		container.queue_free()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check(released.get_ref() == null, "Un viewport anterior no se liberó")
		if cycle % 10 == 0: print("MAP_CACHE_STRESS: cycles=", cycle + 1)
		if failed:
			get_tree().quit(1)
			return
	print("MAP_CACHE_STRESS: PASS cycles=", cycles)
	get_tree().quit(0)
