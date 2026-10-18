extends RefCounted
class_name PasswordChangeReply

var valid := false
var operation_id := ""
var next_operation_id := ""
var status := 0
var message := ""

func _init(reader: StreamPeerBuffer) -> void:
	if reader.get_available_bytes() < 1 or reader.get_u8() != 1:
		return
	operation_id = Utils.GetUnicodeString(reader)
	next_operation_id = Utils.GetUnicodeString(reader)
	status = reader.get_u8()
	message = Utils.GetUnicodeString(reader)
	valid = (operation_id.is_empty() or SkillAllocationState.valid_identity(operation_id)) and SkillAllocationState.valid_identity(next_operation_id) and status in [0, 1, 2, 3] and message.length() <= 160 and reader.get_available_bytes() == 0
