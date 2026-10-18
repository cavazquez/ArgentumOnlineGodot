extends SendSkills
class_name SkillCatalogPacket

var free_points := 0

func Deserialize(reader: StreamPeerBuffer) -> void:
	_initialize_skills()
	if reader.get_available_bytes() != 69:
		valid = false
		return
	if reader.get_u8() != 1:
		valid = false
		return
	free_points = reader.get_16()
	if free_points < 0:
		valid = false
		return
	for index in skills.size():
		var id := reader.get_u8()
		var level := reader.get_u8()
		var percentage := reader.get_u8()
		if id != index + 1 or level > 100 or percentage > 99:
			valid = false
			return
		skills[index].level = level
		skills[index].experience = percentage
