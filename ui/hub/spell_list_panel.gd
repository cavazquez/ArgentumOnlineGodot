extends TextureRect
class_name SpellListPanel

@onready var _item_list: ItemList = $ItemList
var _spell_ids: Array[int] = []
var _pending_move := {}
var _deadline := 0

func _ready() -> void:
	_spell_ids.resize(Consts.MaxUserHechizos)
	for i in Consts.MaxUserHechizos:
		_item_list.add_item("(None)")
	ClientInterface.disconnected.connect(_ResetPending)

func _process(_delta: float) -> void:
	if not _pending_move.is_empty() and Time.get_ticks_msec() >= _deadline:
		_ResetPending()

func _ResetPending() -> void:
	_pending_move.clear()

func get_selected_slot() -> int:
	var selected := _item_list.get_selected_items()
	return -1 if selected.is_empty() else selected[0]

func set_slot_text(slot: int, text: String, spell_id: int = 0) -> void:
	if slot < 0 or slot >= _spell_ids.size() or spell_id < 0:
		return
	_spell_ids[slot] = spell_id
	_item_list.set_item_text(slot, text if spell_id != 0 else "(None)")
	if not _pending_move.is_empty() and slot in [_pending_move.source, _pending_move.destination]:
		_pending_move.seen[slot] = true
		if _pending_move.seen.size() == 2:
			if _spell_ids[_pending_move.destination] == _pending_move.spell and _spell_ids[_pending_move.source] == _pending_move.other:
				_item_list.select(_pending_move.destination)
			_ResetPending()

func _valid_selection() -> bool:
	var selected := get_selected_slot()
	return selected >= 0 and selected < _spell_ids.size() and _spell_ids[selected] > 0

func _on_btn_cast_pressed() -> void:
	if not _valid_selection() or not _pending_move.is_empty():
		return
	GameProtocol.WriteCastSpell(get_selected_slot() + 1)
	GameProtocol.WriteWork(Enums.Skill.Magia)

func _on_btn_info_pressed() -> void:
	if _valid_selection():
		GameProtocol.WriteSpellInfo(get_selected_slot() + 1)

func _RequestMove(direction: int) -> void:
	if not _valid_selection() or not _pending_move.is_empty():
		return
	var original := get_selected_slot()
	var destination := original + direction
	if destination < 0 or destination >= _spell_ids.size():
		return
	if GameProtocol.WriteMoveSpell(direction > 0, original + 1):
		_pending_move = {"source": original, "destination": destination, "spell": _spell_ids[original], "other": _spell_ids[destination], "seen": {}}
		_deadline = Time.get_ticks_msec() + 5000

func _on_btn_move_up_pressed() -> void:
	_RequestMove(-1)

func _on_btn_move_down_pressed() -> void:
	_RequestMove(1)
