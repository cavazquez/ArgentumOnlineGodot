extends RefCounted

# Un archivo publicado puede existir y seguir bloqueado para lectura en Windows.
# Sólo se reintenta su apertura; los JSON vacíos o inválidos se rechazan.
signal io_retry(error: int)

func read_request(path: String, tree: SceneTree, timeout_ms: int = 1000) -> Dictionary:
	var started := Time.get_ticks_msec()
	var attempts := 0
	var errors: Array[int] = []
	while true:
		attempts += 1
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			var open_error := FileAccess.get_open_error()
			if not errors.has(open_error): errors.append(open_error)
			if open_error != ERR_FILE_CANT_OPEN or Time.get_ticks_msec() - started >= timeout_ms:
				return _result(false, "open", attempts, started, 0, open_error, errors)
			io_retry.emit(open_error)
			await tree.create_timer(0.02).timeout
			continue
		var expected := file.get_length()
		var bytes := file.get_buffer(expected)
		var read_error := file.get_error()
		file.close()
		if bytes.size() != expected or read_error not in [OK, ERR_FILE_EOF]:
			return _result(false, "read", attempts, started, bytes.size(), read_error, errors)
		if bytes.is_empty():
			return _result(false, "empty", attempts, started, 0, OK, errors)
		var parser := JSON.new()
		if parser.parse(bytes.get_string_from_utf8()) != OK:
			var rejected := _result(false, "json", attempts, started, bytes.size(), OK, errors)
			rejected.parse_line = parser.get_error_line()
			return rejected
		var data: Variant = parser.data
		if not data is Dictionary or not data.get("op") is String or data.op.is_empty():
			return _result(false, "shape", attempts, started, bytes.size(), OK, errors)
		var accepted := _result(true, "accepted", attempts, started, bytes.size(), OK, errors)
		accepted.command = data
		return accepted
	return {}

func _result(ok: bool, kind: String, attempts: int, started: int, size: int, code: int, errors: Array[int]) -> Dictionary:
	return {"ok": ok, "kind": kind, "attempts": attempts, "byte_count": size,
		"elapsed_ms": Time.get_ticks_msec() - started, "io_error": code, "io_errors": errors.duplicate()}
