extends RefCounted
class_name TradeSnapshot

const STATES := ["pending", "active", "committing", "completed", "cancelled"]
var valid := false
var data: Dictionary = {}

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

func _init(stream: StreamPeerBuffer) -> void:
	if stream.get_available_bytes() < 3 or stream.get_u8() != 1:
		return
	var length := stream.get_u16()
	if length < 1 or length > 3072 or stream.get_available_bytes() != length:
		return
	var parsed: Variant = JSON.parse_string(stream.get_data(length)[1].get_string_from_ascii())
	if not parsed is Dictionary:
		return
	if not parsed.get("id") is String or not is_session_id(parsed.id):
		return
	if not integer(parsed.get("sequence"), 1, 2147483647) or not integer(parsed.get("revision"), 0, 2147483647) or not parsed.get("state") in STATES:
		return
	if not integer(parsed.get("viewer"), 1, 2147483647) or not parsed.get("reason") is String or parsed.reason.length() > 160:
		return
	if not parsed.get("players") is Array or parsed.players.size() != 2:
		return
	var owners := []
	for player in parsed.players:
		if not player is Array or player.size() != 5 or not integer(player[0], 1, 2147483647):
			return
		if player[0] in owners or not player[1] is String or player[1].length() < 1 or player[1].length() > 20:
			return
		owners.append(player[0])
		if not integer(player[2], 0, 999999999) or not player[3] is bool:
			return
		if not player[4] is Array or player[4].size() > 30:
			return
		var slots := []
		for item in player[4]:
			if not item is Array or item.size() != 3 or not integer(item[0], 1, 30) or item[0] in slots:
				return
			if not integer(item[1], 1, 32767) or not integer(item[2], 1, 32767):
				return
			slots.append(item[0])
	if not parsed.viewer in owners:
		return
	data = parsed
	valid = true

static func is_session_id(value: String) -> bool:
	if value.length() != 32:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true
