extends PanelContainer
class_name InventorySlot

signal pressed
signal activated
var _drag_started := false
   
var index:int = -1
  
func SetQuantity(quantity:int) -> void:
	%Quantity.text = str(quantity) if quantity > 1 else ""
	
func SetIcon(texture:Texture2D) -> void:
	$Icon.texture = texture
	
func SetEquipped(equipped:bool) -> void:
	%Equipped.visible = equipped
	
func SetSelected(selected:bool) -> void:
	%Selected.visible = selected

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed && event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_drag_started = false
			accept_event()
			pressed.emit()
		elif not event.pressed && event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			accept_event()
			if not _drag_started and Rect2(Vector2.ZERO, size).has_point(event.position):
				activated.emit()
			

func _get_drag_data(_at_position: Vector2) -> Variant:
	var container = get_parent()
	if not container is InventoryContainer:
		return null
	var data = container.CreateDragData(index)
	if data == null:
		return null
	_drag_started = true
	var preview := TextureRect.new()
	preview.texture = $Icon.texture
	preview.custom_minimum_size = Vector2(32, 32)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var container = get_parent()
	return container is InventoryContainer and container.CanDropItem(index, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var container = get_parent()
	if container is InventoryContainer:
		container.DropItem(index, data)
		get_viewport().set_input_as_handled()
