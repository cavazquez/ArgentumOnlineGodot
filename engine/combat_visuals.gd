extends Node2D
class_name CombatVisuals

const MAX_NODES := 64
var _seen := {}
var _order: Array[String] = []
var active_map := 0

func reset(map_id: int) -> void:
	active_map = map_id
	_seen.clear()
	_order.clear()
	for child in get_children():
		child.queue_free()

func display(event: AOVisualEvent, world: GameWorld) -> void:
	if not event.valid or event.map_id != active_map or Global.effectsMode == 0:
		return
	var key := "%d:%s" % [event.packet_id, event.event_id]
	if _seen.has(key): return
	_seen[key] = true
	_order.append(key)
	if _order.size() > 1024: _seen.erase(_order.pop_front())
	if get_child_count() >= MAX_NODES:
		get_child(0).free()
	if event.packet_id == 246:
		_damage(event)
	else:
		_projectile(event, world)

func _point(tile: Vector2i) -> Vector2:
	return Vector2(tile - Vector2i.ONE) * 32.0 + Vector2(16, 12)

func _damage(event: AOVisualEvent) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("target", event.actor)
	label.text = [str(event.amount), "+%d" % event.amount, "Fallo", "Bloqueo", "%d!" % event.amount, "Inmune", "Estado"][event.kind]
	label.add_theme_color_override("font_color", Color.LIGHT_GREEN if event.kind == 1 else Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", Global.dialogFontSize + 2)
	label.position = _point(event.at) - Vector2(12, 20 + get_child_count() % 3 * 8)
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 24, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)

func _projectile(event: AOVisualEvent, world: GameWorld) -> void:
	# Los actores pueden morir o cambiar de mapa antes del evento. FX nativo permanece.
	if world.GetCharacter(event.source) == null or world.GetCharacter(event.target) == null:
		return
	var arrow := _projectile_sprite(event)
	if arrow == null: return # El FX nativo continúa si falta el asset propio.
	arrow.position = _point(event.origin)
	arrow.rotation = (_point(event.at) - arrow.position).angle()
	arrow.set_meta("source", event.source)
	arrow.set_meta("target", event.target)
	add_child(arrow)
	var duration := 0.08 if Global.effectsMode == 1 else clampf(arrow.position.distance_to(_point(event.at)) / 900.0, 0.08, 0.35)
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "position", _point(event.at), duration)
	if event.kind == 2 and Global.effectsMode == 2:
		tween.tween_interval(0.6)
	tween.tween_callback(arrow.queue_free)

func _projectile_sprite(event: AOVisualEvent) -> Node2D:
	if event.kind == 1:
		var path := "res://Resources/Fxs/fx_%d.tres" % event.asset
		if event.asset <= 0 or not ResourceLoader.exists(path): return null
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = load(path)
		var texture := sprite.sprite_frames.get_frame_texture("default", 0)
		if texture == null:
			sprite.free()
			return null
		sprite.scale = Vector2.ONE * minf(1.0, 32.0 / maxf(texture.get_width(), texture.get_height()))
		sprite.play("default")
		return sprite
	if event.asset <= 0 or event.asset >= GameAssets.GrhDataList.size(): return null
	var graphic := GameAssets.GrhDataList[event.asset]
	if graphic.frameCount > 1: graphic = GameAssets.GrhDataList[graphic.frames[1]]
	var path := "res://Assets/Gfx/%d.png" % graphic.fileId
	if not ResourceLoader.exists(path): return null
	var sprite := Sprite2D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = graphic.region
	sprite.texture = atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * minf(1.0, 20.0 / maxf(graphic.region.size.x, graphic.region.size.y))
	return sprite

func remove_actor(actor: int) -> void:
	for child in get_children():
		if child.get_meta("source", 0) == actor or child.get_meta("target", 0) == actor:
			child.queue_free()
