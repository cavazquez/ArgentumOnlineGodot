extends RefCounted
class_name ClanDetailsPacket

var valid := false
var values := {}

func _init(stream: StreamPeerBuffer) -> void:
	for field in ["name", "founder", "foundation_date", "leader", "website"]:
		values[field] = Utils.GetUnicodeString(stream)
	values.members = stream.get_32()
	var elections := stream.get_u8()
	values.elections = elections
	values.alignment = Utils.GetUnicodeString(stream)
	values.enemies = stream.get_32()
	values.allies = stream.get_32()
	for field in ["antifaction_points", "codex", "description"]:
		values[field] = Utils.GetUnicodeString(stream)
	valid = stream.get_available_bytes() == 0 and elections in [0, 1] and values.members >= 0 and values.enemies >= 0 and values.allies >= 0
