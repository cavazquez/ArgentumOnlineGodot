extends RefCounted
class_name WorldStatePacket

const MAX_SAFE_INTEGER := 9007199254740991
const KINDS := ["tax", "party", "clan", "pets", "weather", "commands", "trade", "result", "chat"]
var valid := false
var data: Dictionary = {}

func _init(stream: StreamPeerBuffer) -> void:
	if stream.get_available_bytes() < 3 or stream.get_u8() != 1:
		return
	var length := stream.get_u16()
	if length < 1 or length > 3800 or stream.get_available_bytes() != length:
		return
	var value: Variant = JSON.parse_string(stream.get_data(length)[1].get_string_from_ascii())
	if not value is Dictionary or not value.get("kind") in KINDS or not value.get("data") is Dictionary:
		return
	if not value.get("epoch") is String or not TradeSnapshot.is_session_id(value.epoch):
		return
	if not TradeSnapshot.integer(value.get("sequence"), 1, MAX_SAFE_INTEGER):
		return
	if not _text(value.get("id"), 64) or not _text(value.get("revision"), 64):
		return
	if not _payload(value.kind, value.data):
		return
	data = value
	valid = true

static func _text(value: Variant, maximum: int = 200) -> bool:
	return value is String and value.length() <= maximum

static func _number(value: Variant, maximum: int = 2147483647) -> bool:
	return TradeSnapshot.integer(value, 0, maximum)

static func _permissions(value: Variant) -> bool:
	if not value is Array or value.size() > 12:
		return false
	for action in value:
		if not action in ["create", "invite", "leave", "kick", "leader", "promote", "demote", "transfer"]:
			return false
	return true

static func _payload(kind: String, value: Dictionary) -> bool:
	match kind:
		"result":
			return value.get("applied") is bool and _text(value.get("message", "")) and value.get("uncertain", false) is bool
		"tax":
			for field in ["wallet", "bank", "rate_bps", "last_day", "last_charge", "from_day", "total_paid", "next_cutoff", "money_revision"]:
				if not _number(value.get(field), MAX_SAFE_INTEGER): return false
			return value.get("enabled") is bool and value.get("scope") == "wallet_and_bank" and _text(value.get("receipt"), 120)
		"weather":
			return _number(value.get("map"), 32767) and value.get("raining") is bool and value.get("outdoor") is bool and _number(value.get("intensity"), 100)
		"commands":
			if not value.get("commands") is Array or value.commands.size() > 25: return false
			for command in value.commands:
				if not command is Dictionary or not _text(command.get("text"), 30) or not _text(command.get("syntax"), 120): return false
			return true
		"party", "clan":
			return _social(kind, value)
		"pets":
			if not value.get("pets") is Array or value.pets.size() > 10: return false
			for pet in value.pets:
				if not pet is Dictionary or not _text(pet.get("id"), 36) or not _text(pet.get("name"), 120): return false
				if not pet.get("order") in ["follow", "wait"] or not _number(pet.get("hp")) or not _number(pet.get("max_hp")) or not _number(pet.get("expires"), MAX_SAFE_INTEGER) or not _number(pet.get("map")) or not pet.get("permanent") is bool: return false
			return true
		"trade":
			if not value.get("session") is String or not TradeSnapshot.is_session_id(value.session) or not _number(value.get("trade_revision")): return false
			if not TradeSnapshot.integer(value.get("pages"), 1, 20) or not TradeSnapshot.integer(value.get("page"), 0, int(value.pages) - 1): return false
			if not value.get("items") is Array or value.items.size() > 3: return false
			for item in value.items:
				if not item is Dictionary or not TradeSnapshot.integer(item.get("id"), 1, 32767) or not item.get("known") is bool or not _text(item.get("name"), 80): return false
				if item.known:
					for field in ["graphic", "type", "min_hit", "max_hit", "min_def", "max_def", "value"]:
						if not _number(item.get(field)): return false
			return true
		"chat":
			return value.get("channel") in ["system", "public", "whisper", "party", "clan"] and _number(value.get("sender_id")) and _text(value.get("sender"), 20) and _text(value.get("text"), 512) and _text(value.get("context"), 80) and _number(value.get("font"), 255) and _number(value.get("recipient", 0)) and _text(value.get("recipient_name", ""), 20)
	return false

static func _social(kind: String, value: Dictionary) -> bool:
	if not _number(value.get("user")) or not _number(value.get("leader")) or not _number(value.get(kind + "_id")) or not _permissions(value.get("permissions")): return false
	if not value.get("members") is Array or value.members.size() > 8: return false
	var identities := []
	for member in value.members:
		if not member is Dictionary or not _number(member.get("id")) or member.id in identities or not _text(member.get("name"), 20) or not _number(member.get("level")) or not member.get("online") is bool: return false
		identities.append(member.id)
		if kind == "clan" and (not TradeSnapshot.integer(member.get("rank"), 1, 4) or not _permissions(member.get("actions"))): return false
		if kind == "party" and (not _number(member.get("hp")) or not _number(member.get("max_hp")) or not _number(member.get("map"))): return false
	if kind == "clan":
		var invitation: Variant = value.get("invitation")
		if not invitation is Dictionary: return false
		if not invitation.is_empty() and (not _number(invitation.get("clan_id")) or not _text(invitation.get("from"), 20) or not _text(invitation.get("name"), 30) or not _number(invitation.get("expires"), MAX_SAFE_INTEGER)): return false
		return _text(value.get("name"), 30) and value.get("invitation") is Dictionary and TradeSnapshot.integer(value.get("pages"), 1, 100) and TradeSnapshot.integer(value.get("page"), 0, int(value.pages) - 1)
	if not value.get("invitations") is Array or value.invitations.size() > 8: return false
	for invitation in value.invitations:
		if not invitation is Dictionary or not _number(invitation.get("party_id")) or not _text(invitation.get("from"), 20) or not _number(invitation.get("expires"), MAX_SAFE_INTEGER): return false
	return true
