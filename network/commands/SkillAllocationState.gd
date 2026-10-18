extends SkillCatalogPacket
class_name SkillAllocationState

var operation_id := ""
var next_operation_id := ""
var status := 0
var message := ""

static func valid_identity(value: String) -> bool:
	var parts := value.split(".")
	if parts.size() != 2 or parts[0].length() < 10 or parts[0].length() > 13 or parts[1].length() != 32:
		return false
	for character in parts[0]:
		if not character in "0123456789":
			return false
	for character in parts[1]:
		if not character in "0123456789abcdef":
			return false
	return true

func Deserialize(reader: StreamPeerBuffer) -> void:
	valid = false
	if reader.get_available_bytes() < 1 or reader.get_u8() != 1:
		return
	operation_id = Utils.GetUnicodeString(reader)
	next_operation_id = Utils.GetUnicodeString(reader)
	status = reader.get_u8()
	message = Utils.GetUnicodeString(reader)
	if not operation_id.is_empty() and not valid_identity(operation_id):
		return
	if not valid_identity(next_operation_id) or not status in [0, 1, 2] or message.length() > 160 or reader.get_available_bytes() != 68:
		return
	var catalog := StreamPeerBuffer.new()
	catalog.put_u8(1)
	catalog.put_data(reader.get_data(68)[1])
	catalog.seek(0)
	valid = true
	super.Deserialize(catalog)
