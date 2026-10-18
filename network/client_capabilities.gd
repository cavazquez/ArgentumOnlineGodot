extends RefCounted
class_name ClientCapabilities

const PACKET_ID := 250
const VERSION := 1
const SKILLS_CATALOG := 1
const TARGETED_CAST := 2
const SKILL_ALLOCATION := 4
const PASSWORD_CHANGE := 8
const VISUAL_DAMAGE := 16
const PROJECTILES := 32
const WEATHER := 64
const TRADE_STATE := 128
const REQUESTED := SKILLS_CATALOG | TRADE_STATE | SKILL_ALLOCATION | PASSWORD_CHANGE
const REQUIRED := {38: SKILL_ALLOCATION, 107: PASSWORD_CHANGE, 252: TRADE_STATE}
var enabled := 0
var _requested := 0
var _deadline_msec := 0
var _pending := false
var _contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/contract.json"))

func clear() -> void:
	enabled = 0
	_requested = 0
	_deadline_msec = 0
	_pending = false

func begin(timeout_seconds: float = 2.0) -> PackedByteArray:
	clear()
	_requested = REQUESTED
	_deadline_msec = Time.get_ticks_msec() + int(timeout_seconds * 1000)
	_pending = true
	var packet := StreamPeerBuffer.new()
	packet.put_u8(PACKET_ID)
	packet.put_u8(VERSION)
	packet.put_32(_requested)
	return packet.data_array

func expire() -> bool:
	if _pending and Time.get_ticks_msec() > _deadline_msec:
		clear()
		return true
	return false

func accept(data: PackedByteArray) -> bool:
	if not _pending or expire():
		return false
	var reader := StreamPeerBuffer.new()
	reader.data_array = data
	if data.size() != 6 or reader.get_u8() != PACKET_ID or reader.get_u8() != VERSION:
		clear()
		return false
	var allowed := reader.get_32()
	if allowed < 0 or (allowed & ~_requested) != 0:
		clear()
		return false
	enabled = allowed
	_pending = false
	return true

func has_feature(feature: int) -> bool:
	expire()
	return (enabled & feature) == feature

func can_send(packet_id: int, subcommand: int = -1) -> bool:
	var entry: Dictionary = _contract.directions.client.get(str(packet_id), {})
	if entry.is_empty() or entry.status != "supported":
		return false
	if entry.has("variants") and not entry.variants.has(str(subcommand)):
		return false
	return not REQUIRED.has(packet_id) or has_feature(REQUIRED[packet_id])
