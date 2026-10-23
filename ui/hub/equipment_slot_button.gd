extends Button
class_name EquipmentSlotButton

var equipment_panel: EquipmentPanel
var layer := ""

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return equipment_panel != null and equipment_panel.can_equip_drop(layer, data)

func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data):
		equipment_panel.request_slot(int(data.source), layer)
		get_viewport().set_input_as_handled()
