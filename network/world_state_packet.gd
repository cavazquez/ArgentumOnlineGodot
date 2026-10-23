extends RefCounted
class_name WorldStatePacket

const MAX_SAFE_INTEGER := 9007199254740991
const KINDS := ["tax", "party", "clan", "pets", "weather", "commands", "trade", "result", "chat", "finder", "diplomacy", "depot", "faction", "quests", "lottery", "lottery_open"]
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
		"lottery_open":
			return value.get("npc") == "lottery-ullathorpe"
		"lottery":
			return _lottery(value)
		"finder", "diplomacy", "depot", "faction", "quests":
			return _expansion(kind, value)
		"result":
			return value.get("applied") is bool and _text(value.get("message", "")) and value.get("uncertain", false) is bool
		"tax":
			for field in ["wallet", "bank", "rate_bps", "last_day", "last_charge", "from_day", "total_paid", "next_cutoff", "money_revision"]:
				if not _number(value.get(field), MAX_SAFE_INTEGER): return false
			return value.get("enabled") is bool and value.get("scope") == "wallet_and_bank" and _text(value.get("receipt"), 120)
		"weather":
			return _number(value.get("map"), 32767) and value.get("raining") is bool and value.get("outdoor") is bool and _number(value.get("intensity"), 100) and value.get("night", false) is bool
		"commands":
			if value.has("names"):
				if not value.names is Array or value.names.size() > 256: return false
				var seen: Dictionary = {}
				for name in value.names:
					if not _text(name, 30) or seen.has(name): return false
					if not ChatCommandCatalog.definitions.has(name) and not name in ChatCommandCatalog.MODERN: return false
					seen[name] = true
				return true
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
			if value.has("color"):
				if not value.color is Array or value.color.size() != 3: return false
				for component in value.color:
					if not _number(component, 255): return false
			return value.get("channel") in ["system", "public", "whisper", "party", "clan"] and _number(value.get("sender_id")) and _text(value.get("sender"), 20) and _text(value.get("text"), 512) and _text(value.get("context"), 80) and _number(value.get("font"), 255) and _number(value.get("recipient", 0)) and _text(value.get("recipient_name", ""), 20)
	return false

static func _lottery(value: Dictionary) -> bool:
	if not _text(value.get("round"), 32) or not _text(value.get("commitment"), 64) or value.get("npc") != "lottery-ullathorpe": return false
	if not value.get("status") in ["open", "pending", "cancelling", "paid", "cancelled"]: return false
	if not value.get("can_bet") is bool or not value.get("claim_pending") is bool: return false
	for field in ["pool", "fees", "gross", "fee", "net", "participants", "minimum", "maximum", "closes_at", "server_time", "round_seconds", "devalued"]:
		if not _number(value.get(field), MAX_SAFE_INTEGER): return false
	var winner: Variant = value.get("last_winner")
	if not winner is Dictionary: return false
	if winner.is_empty(): return true
	if not _text(winner.get("name"), 20) or not _text(winner.get("round"), 32) or not _text(winner.get("seed"), 64) or not _text(winner.get("snapshot_hash"), 64) or not _text(winner.get("commitment"), 64): return false
	for field in ["user", "prize", "at", "draw_pool", "fees", "gross", "devalued"]:
		if not _number(winner.get(field), MAX_SAFE_INTEGER): return false
	return TradeSnapshot.integer(winner.get("number"), -1, 2147483647)

static func _expansion(kind: String, value: Dictionary) -> bool:
	if value.get("enabled", true) == false:
		return _text(value.get("message"), 200)
	if kind == "faction":
		if not value.get("faction") in ["neutral", "royal", "chaos"] or not _text(value.get("name"), 60) or not _text(value.get("rank"), 60) or not _number(value.get("prestige"), 1000000) or not _number(value.get("change_after"), MAX_SAFE_INTEGER): return false
		if value.get("next") != null and not _number(value.next, 1000000): return false
		if not value.get("options") is Array or value.options.size() > 2: return false
		for row in value.options:
			if not row is Dictionary or not row.get("id") in ["royal", "chaos"] or not _text(row.get("name"), 60) or not TradeSnapshot.integer(row.get("min_level"), 1, 100): return false
		return true
	if not value.get("rows") is Array or value.rows.size() > 8: return false
	if not TradeSnapshot.integer(value.get("pages"), 1, 2001) or not TradeSnapshot.integer(value.get("page"), 0, int(value.pages) - 1): return false
	if kind in ["diplomacy", "depot"]:
		if not _number(value.get("clan")): return false
		if int(value.clan) == 0: return value.rows.is_empty()
		if not _text(value.get("name"), 30): return false
	if kind == "finder":
		if not _number(value.get("party")) or not value.get("leader") is bool or not value.get("requests") is Array or value.requests.size() > 10: return false
		for request in value.requests:
			if not request is Dictionary or not _number(request.get("id")) or not _text(request.get("name"), 20) or not _number(request.get("level"), 100) or not _number(request.get("expires"), MAX_SAFE_INTEGER): return false
	elif kind == "depot":
		if not value.get("deposit") is bool or not value.get("withdraw") is bool or not _number(value.get("capacity"), 60) or not value.get("inventory") is Array or value.inventory.size() > 8 or not value.get("history") is Array or value.history.size() > 5: return false
		for row in value.inventory:
			if not _depot_item(row): return false
		for row in value.history:
			if not row is Dictionary or not row.get("action") in ["deposit", "withdraw"] or not _text(row.get("actor"), 20) or not _text(row.get("quantity"), 10) or not _text(row.get("item"), 10): return false
			if not _text(row.get("item_name"), 80) or not _text(row.get("name"), 20): return false
	elif kind == "diplomacy":
		if not value.get("leader") is bool: return false
	elif kind == "quests":
		if not _number(value.get("npc"), 65535) or not _number(value.get("max_active"), 5): return false
	for row in value.rows:
		if not row is Dictionary: return false
		match kind:
			"finder":
				if not _number(row.get("id")) or not _text(row.get("name"), 20) or not _text(row.get("text"), 120) or not row.get("activity") in ["caza", "recoleccion", "misiones", "social"]: return false
				for key in ["leader", "map", "min_level", "max_level", "free", "expires"]:
					if not _number(row.get(key), MAX_SAFE_INTEGER): return false
			"diplomacy":
				if not _number(row.get("clan")) or not _text(row.get("name"), 30) or not row.get("state") in ["none", "proposed", "alliance", "war", "expired"] or not _number(row.get("proposer")) or not _number(row.get("revision")) or not _number(row.get("expires"), MAX_SAFE_INTEGER): return false
			"depot":
				if not _depot_item(row): return false
			"quests":
				if not _text(row.get("id"), 40) or not _text(row.get("title"), 60) or not _text(row.get("description"), 300) or not row.get("status") in ["available", "locked", "active", "completed", "claimed", "abandoned"]: return false
				if not _number(row.get("gold"), 100000000) or not _number(row.get("experience"), 100000000): return false
				for key in ["accept", "deliver", "claim", "abandon"]:
					if not row.get(key) is bool: return false
				if not row.get("objectives") is Array or row.objectives.size() > 8 or not row.get("rewards") is Array or row.rewards.size() > 8: return false
				for goal in row.objectives:
					if not goal is Dictionary or not goal.get("kind") in ["kill", "deliver"] or not _number(goal.get("target"), 32767) or not TradeSnapshot.integer(goal.get("quantity"), 1, 1000) or not TradeSnapshot.integer(goal.get("progress"), 0, int(goal.quantity)): return false
				for reward in row.rewards:
					if not reward is Dictionary or not TradeSnapshot.integer(reward.get("item_id"), 1, 32767) or not TradeSnapshot.integer(reward.get("quantity"), 1, 10000): return false
	return true

static func _depot_item(value: Variant) -> bool:
	return value is Dictionary and TradeSnapshot.integer(value.get("slot"), 1, 60) and TradeSnapshot.integer(value.get("item"), 1, 32767) and TradeSnapshot.integer(value.get("quantity"), 1, 32767) and _text(value.get("name"), 80)

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
