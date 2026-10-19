extends RefCounted
class_name ResponsiveHUD

var hub: CanvasLayer
var records: Array[Dictionary] = []
var background: NinePatchRect
var _footer_left: TextureRect
var _footer_middle: NinePatchRect
var _footer_right: TextureRect
var _last_size := Vector2(-1, -1)

func _slice(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = texture
	result.region = region
	return result

func _add_background(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hub.add_child(node)
	hub.move_child(node, 0)

func install(owner: CanvasLayer) -> void:
	hub = owner
	_collect(hub)
	var previous := hub.get_node("TextureRect") as TextureRect
	background = NinePatchRect.new()
	background.texture = _slice(previous.texture, Rect2(0, 0, 800, 550))
	background.patch_margin_left = 12
	background.patch_margin_right = 244
	background.patch_margin_top = 134
	background.patch_margin_bottom = 162
	_add_background(background)
	_footer_left = TextureRect.new()
	_footer_left.texture = _slice(previous.texture, Rect2(0, 550, 250, 50))
	_add_background(_footer_left)
	_footer_middle = NinePatchRect.new()
	_footer_middle.texture = _slice(previous.texture, Rect2(250, 550, 180, 50))
	_add_background(_footer_middle)
	_footer_right = TextureRect.new()
	_footer_right.texture = _slice(previous.texture, Rect2(430, 550, 370, 50))
	_add_background(_footer_right)
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
	if view == _last_size: return
	_last_size = view
	var extra := Vector2(maxf(0, view.x - 800), maxf(0, view.y - 600))
	background.size = Vector2(800, 550) + extra
	_footer_left.position = Vector2(0, 550 + extra.y)
	_footer_left.size = Vector2(250, 50)
	_footer_middle.position = Vector2(250, 550 + extra.y)
	_footer_middle.size = Vector2(180 + extra.x, 50)
	_footer_right.position = Vector2(430 + extra.x, 550 + extra.y)
	_footer_right.size = Vector2(370, 50)
	for record in records:
		var control: Control = record.node
		var rect: Rect2 = record.rect
		var right := rect.position.x >= 555 or (rect.position.y >= 550 and rect.position.x >= 430)
		var bottom := rect.position.y >= 550 or (rect.position.x >= 555 and rect.position.y >= 388)
		control.position = rect.position + Vector2(extra.x if right else 0, extra.y if bottom else 0)
		if control.name == &"MainViewportContainer":
			control.size = rect.size + extra
		elif control.name in [&"Console", &"ConsoleInput"]:
			control.size.x = rect.size.x + extra.x
		elif control.name == &"Minimap":
			control.position.x = rect.position.x + extra.x
