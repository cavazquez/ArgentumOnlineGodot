extends RefCounted
class_name WorldStateContext

signal changed(kind: String, data: Dictionary, revision: String)
var epoch := ""
var sequence := 0
var states: Dictionary = {}
var revisions: Dictionary = {}
var item_states: Dictionary = {}
var _trades: Dictionary = {}
var _active_trade := ""
var _trade_revision := -1

func clear() -> void:
	epoch = ""
	sequence = 0
	states.clear()
	item_states.clear()
	revisions.clear()
	_trades.clear()
	_active_trade = ""
	_trade_revision = -1
	changed.emit("reset", {}, "")

func accept(value: Dictionary) -> bool:
	if not epoch.is_empty() and value.epoch != epoch:
		return false
	if int(value.sequence) <= sequence:
		return false
	epoch = value.epoch
	sequence = int(value.sequence)
	var payload: Dictionary = value.data.duplicate(true)
	if value.kind == "tax" and has_money() and int(payload.money_revision) < int(states.tax.money_revision):
		return false
	if value.kind == "trade" and (payload.session != _active_trade or int(payload.trade_revision) != _trade_revision):
		return false
	if value.kind == "result":
		payload["id"] = value.id
	if value.kind == "items":
		if not item_states.has(payload.scope): item_states[payload.scope] = {}
		for row in payload.rows:
			item_states[payload.scope][int(row[0])] = row[1].duplicate(true)
	states[value.kind] = payload
	revisions[value.kind] = value.revision
	changed.emit(value.kind, payload.duplicate(true), value.revision)
	return true

func has_money() -> bool:
	return states.has("tax")


func observe_trade(value: Dictionary) -> void:
	var previous: Dictionary = _trades.get(value.id, {})
	if not previous.is_empty() and (previous.terminal or int(value.sequence) <= int(previous.sequence)): return
	var terminal: bool = value.state in ["completed", "cancelled"]
	_trades[value.id] = {"sequence": int(value.sequence), "terminal": terminal}
	if _trades.size() > 32: _trades.erase(_trades.keys()[0])
	if terminal:
		if _active_trade == value.id:
			_active_trade = ""
			_trade_revision = -1
	elif _active_trade != value.id or _trade_revision != int(value.revision):
		_active_trade = value.id
		_trade_revision = int(value.revision)
		states.erase("trade")
		item_states.erase("trade_mine")
		item_states.erase("trade_other")
