extends SceneTree

const Reader = preload("res://tests/control_request_reader.gd")

func _initialize() -> void:
	_run.call_deferred()

func _observed(code: int, path: String) -> void:
	print("CONTROL_IO_PHASE: observer-open unix=", Time.get_unix_time_from_system(), " path=", path)
	var file := FileAccess.open(path + ".pending", FileAccess.WRITE)
	if file == null:
		print("CONTROL_IO_PHASE: observer-open-error ", FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify({"io_error": code}))
	file.close()
	var error := DirAccess.rename_absolute(path + ".pending", path)
	print("CONTROL_IO_PHASE: observer-published unix=", Time.get_unix_time_from_system(), " error=", error, " exists=", FileAccess.file_exists(path))
	assert(error == OK)

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var options := {}
	for index in range(0, arguments.size(), 2):
		options[arguments[index]] = arguments[index + 1]
	var result: Dictionary
	print("CONTROL_IO_PHASE: unix=", Time.get_unix_time_from_system(), " ticks=", Time.get_ticks_msec(), " mode=", options["--mode"])
	if options["--mode"] == "legacy":
		print("CONTROL_IO_PHASE: before-existence-check")
		var exists := FileAccess.file_exists(options["--request"])
		print("CONTROL_IO_PHASE: existence=", exists)
		_observed(OK, options["--observed"])
		while not FileAccess.file_exists(options["--observed"] + ".continue"):
			await create_timer(0.01).timeout
		print("CONTROL_IO_PHASE: legacy-read-after-lock")
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
