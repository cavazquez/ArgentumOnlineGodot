extends RefCounted
class_name SendSkills

class Skill:
	var id: int
	var name: String
	var available: bool
	var level := 0
	# Porcentaje dentro del nivel, NO experiencia acumulada ni nivel.
	var experience := 0

var skills: Array[Skill]
var valid := true

func _init(reader: StreamPeerBuffer = null) -> void:
	if reader:
		Deserialize(reader)

func _initialize_skills() -> void:
	skills.clear()
	for definition in SkillCatalog.definitions():
		var skill := Skill.new()
		skill.id = int(definition.id)
		skill.name = definition.name
		skill.available = definition.implemented
		skills.append(skill)

func Deserialize(reader: StreamPeerBuffer) -> void:
	_initialize_skills()
	if reader.get_available_bytes() != 18:
		valid = false
		return
	# El formato legacy de pyao contiene nueve int16; no veinte pares u8.
	for id in SkillCatalog.data.legacy_wire_order:
		var level := reader.get_16()
		if level < 0 or level > 100:
			valid = false
			return
		skills[int(id) - 1].level = level
