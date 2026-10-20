extends Node

func _ready() -> void:
	var failed := false
	for path: String in ["res://tests/integration_world.gd", "res://tests/r10_client.gd", "res://tests/mechanics_client.gd", "res://tests/web_client.gd"]:
		var candidate := GDScript.new()
		candidate.source_code = FileAccess.get_file_as_string(path)
		if candidate.reload() != OK or not candidate.can_instantiate():
			failed = true
			push_error("R10_COMPILE_SMOKE: no compila " + path)
	print("R10_COMPILE_SMOKE: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
