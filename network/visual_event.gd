extends RefCounted
class_name AOVisualEvent

var valid := false
var packet_id := 0
var event_id := ""
var map_id := 0
var actor := 0
var source := 0
var target := 0
var at := Vector2i.ZERO
var origin := Vector2i.ZERO
var amount := 0
var kind := 0
var asset := 0
var spell := 0

func _init(id: int, stream: StreamPeerBuffer) -> void:
	packet_id = id
	if id not in [246, 247] or stream.get_available_bytes() < 2: return
	var length := stream.get_u16()
	if length < 1 or length > 64 or stream.get_available_bytes() != length + (13 if id == 246 else 19): return
	event_id = stream.get_utf8_string(length)
	map_id = stream.get_16()
	if id == 246:
		actor = stream.get_32()
		at = Vector2i(stream.get_u8(), stream.get_u8())
		amount = stream.get_32()
		kind = stream.get_u8()
		valid = kind >= 0 and kind <= 6 and amount >= 0 and actor > 0
	elif id == 247:
		source = stream.get_32()
		target = stream.get_32()
		origin = Vector2i(stream.get_u8(), stream.get_u8())
		at = Vector2i(stream.get_u8(), stream.get_u8())
		kind = stream.get_u8()
		asset = stream.get_16()
		spell = stream.get_16()
		valid = kind in [1, 2] and source > 0 and target > 0 and _tile_valid(origin) and asset >= 0
	valid = valid and map_id > 0 and not event_id.is_empty() and event_id.length() <= 64 and _tile_valid(at) and stream.get_available_bytes() == 0

func _tile_valid(tile: Vector2i) -> bool:
	return tile.x >= 1 and tile.x <= 100 and tile.y >= 1 and tile.y <= 100
