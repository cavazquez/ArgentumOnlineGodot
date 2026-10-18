extends RefCounted
class_name SkillCatalog

static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/skills.json"))

static func definitions() -> Array:
	return data.skills

static func names() -> Array[String]:
	var result: Array[String] = []
	for definition in definitions():
		result.append(definition.name)
	return result
