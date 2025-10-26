extends Node

const MAP_WIDTH := 100
const MAP_HEIGHT := 100
const WATER_RANGES := [
	Vector2i(1505, 1520),
	Vector2i(5665, 5680),
	Vector2i(13547, 13562),
]
const OUTPUT_SUBDIR := "map_data"

static func export_all_maps_to_tmp() -> void:
	var output_dir := "user://".path_join(OUTPUT_SUBDIR)
	_ensure_clean_directory(output_dir)

	var map_files := Utils.GetFilesInDirectory("res://Assets/Maps/")
	map_files.sort()

	for file_name in map_files:
		if not file_name.ends_with(".map"):
			continue

		var raw_id := file_name.substr(4)
		var dot_index := raw_id.find(".")
		if dot_index >= 0:
			raw_id = raw_id.substr(0, dot_index)

		var map_id := raw_id.to_int()
		if map_id <= 0:
			push_warning("MapExporter: no se pudo obtener ID para %s" % file_name)
			continue

		var map_data := GameAssets.GetMap(map_id)
		if map_data == null:
			push_warning("MapExporter: no se pudo cargar el mapa %s" % file_name)
			continue

		_export_map(map_id, map_data, output_dir)

	print("[MapExporter] Mapas exportados a %s" % output_dir)

static func _export_map(map_id: int, map_data, output_dir: String) -> void:
	var prefix := "%03d" % map_id

	_save_json(output_dir.path_join("%s_metadata.json" % prefix), _build_metadata(map_id))
	_save_json(output_dir.path_join("%s_ground.json" % prefix), _build_grid(map_data.layer1))
	_save_json(output_dir.path_join("%s_flags.json" % prefix), _build_grid(map_data.flags))
	_save_json(output_dir.path_join("%s_upper.json" % prefix), _sprites_to_array(map_data.layer3))
	_save_json(output_dir.path_join("%s_graphics.json" % prefix), _sprites_to_array(map_data.layer4))
	_save_json(output_dir.path_join("%s_triggers.json" % prefix), [])

	var blocked_payload := _build_blocked_tiles(map_data)
	_save_json(output_dir.path_join("%s_blocked.json" % prefix), blocked_payload)

	var resources := _build_resources(map_data)
	_save_json(output_dir.path_join("%s_resources.json" % prefix), resources)

static func _build_metadata(map_id: int) -> Dictionary:
	return {
		"id": map_id,
		"name": "Mapa %d" % map_id,
		"width": MAP_WIDTH,
		"height": MAP_HEIGHT,
		"weather": {
			"rain": false,
			"snow": false,
		},
	}

static func _build_grid(data: Variant) -> Array:
	var rows: Array = []
	for y in range(MAP_HEIGHT):
		var row: Array = []
		for x in range(MAP_WIDTH):
			var idx := x + y * MAP_WIDTH
			var value := 0
			if data is PackedInt32Array:
				value = (data as PackedInt32Array)[idx]
			elif data is PackedByteArray:
				value = int((data as PackedByteArray)[idx])
			elif data is Array:
				value = int(data[idx])
			row.append(value)
		rows.append(row)
	return rows

static func _sprites_to_array(sprites: Array) -> Array:
	var result: Array = []
	for sprite in sprites:
		result.append({
			"x": sprite.x,
			"y": sprite.y,
			"grh_id": sprite.grhId,
		})
	return result

static func _build_blocked_tiles(map_data) -> Array:
	var entries := {}
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var idx := x + y * MAP_WIDTH
			var key := "%d,%d" % [x, y]
			var tile_flags := int(map_data.flags[idx])
			if _is_water_tile(tile_flags, map_data.layer1[idx]):
				entries[key] = {"x": x, "y": y, "type": "water"}
			elif (tile_flags & Enums.TileState.Blocked) != 0:
				entries[key] = {"x": x, "y": y, "type": "blocked"}

	var values: Array = entries.values()
	values.sort_custom(func(a, b):
		if a["y"] == b["y"]:
			return a["x"] < b["x"]
		return a["y"] < b["y"]
	)
	return values

static func _build_resources(map_data) -> Dictionary:
	var water: Array = []
	var seen := {}
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var idx := x + y * MAP_WIDTH
			var tile_flags := int(map_data.flags[idx])
			if _is_water_tile(tile_flags, map_data.layer1[idx]):
				var key := "%d,%d" % [x, y]
				if not seen.has(key):
					water.append([x, y])
					seen[key] = true

	return {
		"water": water,
		"trees": [],
		"mines": [],
	}

static func _is_water_tile(flags: int, ground_id: int) -> bool:
	if (flags & Enums.TileState.Water) != 0:
		return true
	for range_pair in WATER_RANGES:
		if ground_id >= range_pair.x and ground_id <= range_pair.y:
			return true
	return false

static func _save_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("MapExporter: no se pudo escribir %s" % path)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()

static func _ensure_clean_directory(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		_clear_directory(path)
	else:
		DirAccess.make_dir_recursive_absolute(path)

static func _clear_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full_path := path.path_join(name)
		if DirAccess.dir_exists_absolute(full_path):
			_clear_directory(full_path)
			DirAccess.remove_absolute(full_path)
		else:
			DirAccess.remove_absolute(full_path)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.make_dir_recursive_absolute(path)
