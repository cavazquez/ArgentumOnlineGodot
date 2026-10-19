extends RefCounted
class_name ResponsiveHUD

var hub: CanvasLayer
var records: Array[Dictionary] = []
var background: NinePatchRect

func install(owner: CanvasLayer) -> void:
	hub = owner
	_collect(hub)
	var previous := hub.get_node("TextureRect") as TextureRect
	background = NinePatchRect.new()
	background.texture = previous.texture
	background.patch_margin_left = 12
	background.patch_margin_right = 244
	background.patch_margin_top = 134
	background.patch_margin_bottom = 48
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hub.add_child(background)
	hub.move_child(background, 0)
	previous.hide()
	hub.get_viewport().size_changed.connect(layout)
	layout()

func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			records.append({"node": child, "rect": Rect2(child.position, child.size)})
		elif not child is Window and not child is SubViewport and not child is CanvasLayer:
			_collect(child)

func layout() -> void:
	var view := hub.get_viewport().get_visible_rect().size
	var extra := Vector2(maxf(0, view.x - 800), maxf(0, view.y - 600))
	background.size = Vector2(800, 600) + extra
	for record in records:
		var control: Control = record.node
		var rect: Rect2 = record.rect
		control.position = rect.position + Vector2(extra.x if rect.position.x >= 555 else 0, extra.y if rect.position.y >= 550 else 0)
		if control.name == &"MainViewportContainer":
			control.size = rect.size + extra
		elif control.name in [&"Console", &"ConsoleInput"]:
			control.size.x = rect.size.x + extra.x
		elif control.name == &"Minimap":
			control.position.x = rect.position.x + extra.x
