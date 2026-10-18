extends Node

const LEGACY_FILE = "user://saved_credentials.dat"
const PREFERENCES_FILE = "user://login_preferences.cfg"

func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var result := DirAccess.remove_absolute(path)
	if result != OK:
		push_error("No se pudo eliminar una preferencia de autenticación antigua")
	return result

func save_username(username: String) -> Error:
	var preferences := ConfigFile.new()
	preferences.set_value("login", "username", username)
	var result := preferences.save(PREFERENCES_FILE)
	if result != OK:
		push_error("No se pudo guardar la preferencia de usuario")
	var legacy_result := _remove_file(LEGACY_FILE)
	return legacy_result if legacy_result != OK else result

func load_username() -> String:
	# Leer exclusivamente la primera línea del formato anterior; nunca la contraseña.
	if FileAccess.file_exists(LEGACY_FILE):
		var legacy := FileAccess.open(LEGACY_FILE, FileAccess.READ)
		var username := legacy.get_line() if legacy else ""
		if legacy:
			legacy.close()
		if _remove_file(LEGACY_FILE) != OK:
			return ""
		if not FileAccess.file_exists(PREFERENCES_FILE) and not username.is_empty():
			save_username(username)
	var preferences := ConfigFile.new()
	if preferences.load(PREFERENCES_FILE) != OK:
		return ""
	return str(preferences.get_value("login", "username", ""))

func clear_credentials() -> void:
	_remove_file(PREFERENCES_FILE)
	_remove_file(LEGACY_FILE)
