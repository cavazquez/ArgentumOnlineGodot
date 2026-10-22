extends RefCounted
class_name ChatCommandCatalog

static var definitions: Dictionary = _load_definitions()
const MODERN := ["/METRICS", "/CREARCLAN", "/INVITARCLAN", "/ACEPTARCLAN", "/RECHAZARCLAN", "/EXPULSARCLAN", "/PROMOVERCLAN", "/DEGRADARCLAN", "/TRANSFERIRLIDERAZGO", "/CLAN", "/PET", "/MUTE", "/UNMUTE"]

static func _load_definitions() -> Dictionary:
	var result: Dictionary = {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/chat_commands.json"))
	for entry in data.commands:
		result[entry.name] = entry
	return result

static func completion(names: Array) -> Array:
	var result: Array = []
	for name in names:
		var definition: Dictionary = definitions.get(name, {})
		result.append({"text": name, "syntax": definition.get("syntax", name)})
	return result
