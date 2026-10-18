extends TextureRect
class_name Minimap

signal click(mouse_position: Vector2)
var _player_tile := Vector2i.ONE
var _selected_tile := Vector2i.ZERO

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	resized.connect(queue_redraw)

func load_thumbnail(map_id: int) -> void:
	texture = null
	_selected_tile = Vector2i.ZERO
	var path := "res://Assets/minimap_thumbnails/%d.bmp" % map_id
	if FileAccess.file_exists(path):
		_InstallThumbnail(FileAccess.get_file_as_bytes(path))
	elif ResourceLoader.exists(path, "Texture2D"):
		# Las exportaciones incluyen la textura importada, no el BMP original.
		var imported := load(path) as Texture2D
		if imported != null and imported.get_width() > 0 and imported.get_width() <= 4096 and imported.get_height() > 0 and imported.get_height() <= 4096:
			texture = imported
	queue_redraw()

func _InstallThumbnail(data: PackedByteArray) -> bool:
	texture = null
	queue_redraw()
	if data.size() < 54 or data.size() > 4194304 or data[0] != 66 or data[1] != 77:
		return false
	var width := data.decode_s32(18)
	var height := absi(data.decode_s32(22))
	var bits := data.decode_u16(28)
	var offset := data.decode_u32(10)
	if width < 1 or width > 4096 or height < 1 or height > 4096 or not bits in [1, 4, 8, 16, 24, 32] or data.decode_u32(30) != 0:
		return false
	var row_size := int((width * bits + 31) / 32) * 4
	if offset < 54 or offset + row_size * height > data.size():
		return false
	var image := Image.new()
	if image.load_bmp_from_buffer(data) != OK or image.is_empty():
		return false
	texture = ImageTexture.create_from_image(image)
	return true

func _MapRect() -> Rect2:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return Rect2(Vector2.ZERO, size)
	var original := texture.get_size()
	var fitted := original * minf(size.x / original.x, size.y / original.y)
	return Rect2((size - fitted) / 2.0, fitted)

func TileToPoint(tile: Vector2i) -> Vector2:
	var area := _MapRect()
	return area.position + Vector2((clampi(tile.x, 1, 100) - 0.5) / 100.0, (clampi(tile.y, 1, 100) - 0.5) / 100.0) * area.size

func PointToTile(point: Vector2) -> Vector2i:
	var area := _MapRect()
	if area.size.x <= 0 or area.size.y <= 0 or not area.has_point(point):
		return Vector2i.ZERO
	var ratio := (point - area.position) / area.size
	return Vector2i(clampi(int(floor(ratio.x * 100)) + 1, 1, 100), clampi(int(floor(ratio.y * 100)) + 1, 1, 100))

func update_player_position(x: int, y: int) -> void:
	_player_tile = Vector2i(clampi(x, 1, 100), clampi(y, 1, 100))
	queue_redraw()

func _draw() -> void:
	var area := _MapRect()
	if texture == null:
		draw_rect(area, Color(0.08, 0.08, 0.08))
		draw_rect(area, Color.GRAY, false)
	var marker := Rect2(TileToPoint(_player_tile) - Vector2(2, 2), Vector2(4, 4))
	draw_rect(marker.intersection(area), Color.RED)
	if _selected_tile != Vector2i.ZERO:
		draw_circle(TileToPoint(_selected_tile), 3.0, Color.YELLOW, false, 1.0)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tile := PointToTile(event.position)
		if tile != Vector2i.ZERO:
			_selected_tile = tile
			queue_redraw()
			click.emit(Vector2(tile))
