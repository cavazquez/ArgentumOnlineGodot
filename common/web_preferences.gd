extends RefCounted
class_name WebPreferences

# Browser storage contains preferences only. Passwords and authentication hashes
# stay in memory. Each server owns a separate namespace on the same web origin.
const PREFIX := "pyao:v1:"
const MAX_TEXT_BYTES := 524288
const SECRET_KEYS := ["password", "session_password", "account_hash", "token", "access_token", "refresh_token"]
static var _endpoint := ""
static var _session: Dictionary = {}
static var last_error := ""
static var _reported := false

static func default_endpoint() -> String:
	if not OS.has_feature("web"): return ""
	var hostname: Variant = JavaScriptBridge.eval("window.location.hostname", true)
	return "wss://%s:7668" % str(hostname if hostname else "localhost")

static func select_endpoint(url: String) -> void:
	if not OS.has_feature("web") or url == _endpoint: return
	_endpoint = url
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	var global := tree.root.get_node_or_null("Global")
	if global != null: global.reload_preferences()
	var bindings := tree.root.get_node_or_null("InputBindings")
	if bindings != null: bindings.reload_profile()

static func _ensure_endpoint() -> void:
	if not _endpoint.is_empty(): return
	_endpoint = default_endpoint()
	var config := ConfigFile.new()
	var text := read_text("user://connection.cfg", true)
	if not text.is_empty() and config.parse(text) == OK:
		var saved := str(config.get_value("connection", "host", _endpoint))
		if saved.begins_with("wss://"): _endpoint = saved

static func _key(path: String, global_scope: bool) -> String:
	if not global_scope: _ensure_endpoint()
	return PREFIX + ("global" if global_scope else _endpoint.sha256_text()) + ":" + path.trim_prefix("user://")

static func _warn() -> void:
	last_error = "El navegador no pudo guardar las preferencias. Se conservarán sólo durante esta sesión."
	if _reported: return
	_reported = true
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var global := tree.root.get_node_or_null("Global")
		if global != null: global.call_deferred("show_storage_warning", last_error)

static func _javascript(operation: String, key: String, value: String = "") -> Dictionary:
	# JSON literals escape all input before evaluating a fixed, small program.
	var args := JSON.stringify([operation, key, value])
	var script := "(function(a){try{let v=null;if(a[0]==='get')v=localStorage.getItem(a[1]);else if(a[0]==='set')localStorage.setItem(a[1],a[2]);else localStorage.removeItem(a[1]);return JSON.stringify({ok:true,value:v});}catch(e){return JSON.stringify({ok:false});}})(%s)" % args
	var result: Variant = JavaScriptBridge.eval(script, true)
	var parsed: Variant = JSON.parse_string(str(result))
	return parsed if parsed is Dictionary else {"ok": false}

static func read_text(path: String, global_scope: bool = false) -> String:
	if not OS.has_feature("web"):
		return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var key := _key(path, global_scope)
	if _session.has(key): return str(_session[key])
	var result := _javascript("get", key)
	if not result.get("ok", false):
		_warn()
		return ""
	if result.get("value") == null: return ""
	var raw := str(result.value)
	if raw.to_utf8_buffer().size() > MAX_TEXT_BYTES:
		_warn()
		return ""
	var stored: Variant = JSON.parse_string(raw)
	if not stored is Dictionary or stored.get("version") != 1 or not stored.get("text") is String:
		_warn()
		return ""
	_session[key] = stored.text
	return stored.text

static func write_text(path: String, value: String, global_scope: bool = false) -> Error:
	if value.to_utf8_buffer().size() > MAX_TEXT_BYTES: return ERR_OUT_OF_MEMORY
	var key := _key(path, global_scope)
	_session[key] = value
	if not _javascript("set", key, JSON.stringify({"version": 1, "text": value})).get("ok", false): _warn()
	return OK

static func remove(path: String) -> Error:
	var key := _key(path, false)
	_session[key] = ""
	if not _javascript("remove", key).get("ok", false): _warn()
	return OK

static func load_config(config: ConfigFile, path: String, global_scope: bool = false) -> Error:
	if not OS.has_feature("web"): return config.load(path)
	var text := read_text(path, global_scope)
	if text.is_empty(): return ERR_FILE_NOT_FOUND
	var result := config.parse(text)
	if result != OK: _warn()
	return result

static func save_config(config: ConfigFile, path: String, global_scope: bool = false) -> Error:
	if not OS.has_feature("web"): return config.save(path)
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			if key.to_lower() in SECRET_KEYS: config.erase_section_key(section, key)
	return write_text(path, config.encode_to_text(), global_scope)

static func remove_legacy_secrets() -> void:
	if not OS.has_feature("web"): return
	for key in ["password", "session_password", "account_hash", "pyao:password", "pyao:session_password", "pyao:account_hash", "pyao:saved_credentials"]:
		if not _javascript("remove", key).get("ok", false): _warn()
	if FileAccess.file_exists("user://saved_credentials.dat"):
		DirAccess.remove_absolute("user://saved_credentials.dat")
