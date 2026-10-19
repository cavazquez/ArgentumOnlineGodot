extends WorldStateWindow
class_name PetsWindow

var _list: ItemList
var _follow: Button
var _wait: Button
var _release: Button
var _selected := ""

func _init() -> void:
	topic = "pets"
	title = "Mascotas"

func _build() -> void:
	label(body, "Seguir y esperar cambian la orden de tu mascota. El servidor conserva sus reglas de vida, combate y expiración.")
	_list = ItemList.new()
	_list.custom_minimum_size.y = 220
	_list.item_selected.connect(func(index: int):
		_selected = _list.get_item_metadata(index)
		_refresh_buttons())
	body.add_child(_list)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	_follow = button(actions, "Seguir", _order.bind("follow"))
	_wait = button(actions, "Esperar", _order.bind("wait"))
	_release = button(actions, "Liberar", _release_pet)

func _render() -> void:
	_list.clear()
	for pet in state.get("pets", []):
		var text := "%s · %d/%d vida · %s · mapa %d" % [pet.name, int(pet.hp), int(pet.max_hp), "esperando" if pet.order == "wait" else "siguiendo", int(pet.map)]
		text += " · permanente" if pet.permanent else " · vence en %d s" % maxi(0, int(pet.expires) - int(Time.get_unix_time_from_system()))
		var index := _list.add_item(text)
		_list.set_item_metadata(index, pet.id)
		if pet.id == _selected: _list.select(index)
	_refresh_buttons()

func _refresh_buttons() -> void:
	var selected := false
	for index in _list.item_count:
		if _list.get_item_metadata(index) == _selected: selected = true
	_follow.disabled = pending() or not selected
	_wait.disabled = pending() or not selected
	_release.disabled = pending() or not selected

func _order(order: String) -> void:
	mutate("pets.order", {"instance": _selected, "order": order})

func _release_pet() -> void:
	confirm_action("pets.release", {"instance": _selected}, "¿Liberar esta mascota? Dejará de pertenecerte.")
