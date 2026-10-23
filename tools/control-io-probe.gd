extends SceneTree

const Reader = preload("res://tests/control_request_reader.gd")

func _initialize() -> void:
	_run.call_deferred()

func _observed(code: int, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"io_error": code}))
	file.close()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var options := {}
	for index in range(0, arguments.size(), 2):
		options[arguments[index]] = arguments[index + 1]
	var result: Dictionary
	if options["--mode"] == "legacy":
		var exists := FileAccess.file_exists(options["--request"])
		var text := FileAccess.get_file_as_string(options["--request"])
		var error := FileAccess.get_open_error()
		result = {"file_exists": exists, "byte_count": text.to_utf8_buffer().size(), "io_error": error}
	else:
		var reader := Reader.new()
		reader.io_retry.connect(_observed.bind(options["--observed"]), CONNECT_ONE_SHOT)
		result = await reader.read_request(options["--request"], self, int(options["--timeout-ms"]))
		if result.ok: result.operation = result.command.op
		result.erase("command")
	var destination: String = options["--result"]
	var output := FileAccess.open(destination + ".pending", FileAccess.WRITE)
	output.store_string(JSON.stringify(result))
	output.close()
	assert(DirAccess.rename_absolute(destination + ".pending", destination) == OK)
	quit(0)
