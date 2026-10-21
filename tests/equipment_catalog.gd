extends Node

func _ready() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/equipment-catalog.json"))
	var checked := 0
	for row in report.rows:
		var frames := load("res://" + String(row.resource)) as SpriteFrames
		if frames == null:
			fail("Falta SpriteFrames del item %d: %s" % [row.item_id, row.resource])
			return
		for direction in ["north", "east", "south", "west"]:
			var modes := ["idle"] if row.slot == "helmet" else ["idle", "walk"]
			for mode in modes:
				var animation: String = mode + "_" + direction
				if not frames.has_animation(animation) or frames.get_frame_count(animation) == 0:
					fail("Animación vacía del item %d: %s / %s" % [row.item_id, row.resource, animation])
					return
				for index in range(frames.get_frame_count(animation)):
					var texture := frames.get_frame_texture(animation, index)
					if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
						fail("Frame vacío del item %d" % row.item_id)
						return
		checked += 1
	print("EQUIPMENT_CATALOG: PASS references=", checked, " boots=deferred")
	get_tree().quit()

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
