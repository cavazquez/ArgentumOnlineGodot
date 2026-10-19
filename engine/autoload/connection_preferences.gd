extends Node

const FILE = "user://connection.cfg"

func load_preferences() -> Dictionary:
	var config := ConfigFile.new()
	WebPreferences.load_config(config, FILE, true)
	return {
		"host": str(config.get_value("connection", "host", WebPreferences.default_endpoint() if OS.has_feature("web") else "127.0.0.1")),
		"port": clampi(int(config.get_value("connection", "port", 7668 if OS.has_feature("web") else 7666)), 1, 65535),
		"tls": bool(config.get_value("connection", "tls", true)),
		"ca_path": str(config.get_value("connection", "ca_path", ""))
	}

func save_preferences(values: Dictionary) -> Error:
	var config := ConfigFile.new()
	for key in ["host", "port", "tls", "ca_path"]:
		config.set_value("connection", key, values[key])
	return WebPreferences.save_config(config, FILE, true)
