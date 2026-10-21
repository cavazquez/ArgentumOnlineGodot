extends Node2D
class_name CharacterRenderer

const DefaultSpriteFramePath = "uid://750ochum2vjs"

@export var _verticalAlign:bool

@export var _bodyAnimatedSprite:AnimatedSprite2D
@export var _headAnimatedSprite:AnimatedSprite2D
@export var _helmetAnimatedSprite:AnimatedSprite2D
@export var _weaponAnimatedSprite:AnimatedSprite2D
@export var _shieldAnimatedSprite:AnimatedSprite2D

var _head_base := Vector2.ZERO
var _helmet_base := Vector2.ZERO
var _alignment_ready := false

func _ensure_alignment() -> void:
	if _alignment_ready: return
	_head_base = _headAnimatedSprite.position
	_helmet_base = _helmetAnimatedSprite.position
	_alignment_ready = true

func _align_head() -> void:
	_ensure_alignment()
	var offset := Vector2.ZERO
	if _body > 0 and _body < GameAssets.BodyAnimationList.size():
		var data = GameAssets.BodyAnimationList[_body]
		offset = Vector2(data.offsetX, data.offsetY)
	_headAnimatedSprite.position = _head_base + offset
	var helmet_offset: Vector2 = _helmetAnimatedSprite.sprite_frames.get_meta("avatar_offset", Vector2.ZERO)
	_helmetAnimatedSprite.position = _helmet_base + offset + helmet_offset

var _body:int
var _head:int
var _helmet:int
var _weapon:int
var _shield:int

var heading:int = Enums.Heading.South

var body:int:
	get:
		return _body
	set(value):
		_set_body(value)

var head: int:
	get:
		return _head
	set(value):
		_set_head(value)

var helmet: int:
	get:
		return _helmet
	set(value):
		_set_helmet(value)

var weapon: int:
	get:
		return _weapon
	set(value):
		_set_weapon(value)

var shield: int:
	get:
		return _shield
	set(value):
		_set_shield(value)

func Play() -> void:
	var key = (Enums.Heading.keys()[heading]).to_lower()  
	_bodyAnimatedSprite.play("walk_" + key)
	_shieldAnimatedSprite.play("walk_" + key)
	_weaponAnimatedSprite.play("walk_" + key)
	_headAnimatedSprite.play("idle_" + key)
	_helmetAnimatedSprite.play("idle_" + key)
	
func Stop() -> void:
	var key = (Enums.Heading.keys()[heading]).to_lower()  
	_bodyAnimatedSprite.play("idle_" + key)
	_shieldAnimatedSprite.play("idle_" + key)
	_weaponAnimatedSprite.play("idle_" + key)
	_headAnimatedSprite.play("idle_" + key)
	_helmetAnimatedSprite.play("idle_" + key)

func _set_weapon(id:int) -> void:
	_weapon = id 
	_weaponAnimatedSprite.sprite_frames = _LoadSpriteFrames("res://Resources/Character/Weapons/weapon_%d.tres" % id)

func _set_shield(id:int) -> void:
	_shield = id
	_shieldAnimatedSprite.sprite_frames = _LoadSpriteFrames("res://Resources/Character/Shields/shield_%d.tres" % id)

func _set_helmet(id:int) -> void:
	_helmet = id
	_helmetAnimatedSprite.sprite_frames = _LoadSpriteFrames("res://Resources/Character/Helmets/helmet_%d.tres" % id)
	_align_head()

func _set_head(id:int) -> void:
	_head = id
	_align_head()
	_headAnimatedSprite.sprite_frames = _LoadSpriteFrames("res://Resources/Character/Heads/head_%d.tres" % id)

func _set_body(id:int) -> void:
	_body = id
	_align_head()
	_bodyAnimatedSprite.sprite_frames = _LoadSpriteFrames("res://Resources/Character/Bodies/body_%d.tres" % id)
	
	if _verticalAlign:
		if _bodyAnimatedSprite.sprite_frames.get_frame_count("idle_south"):
			var offset_y = _bodyAnimatedSprite \
				.sprite_frames \
				.get_frame_texture("idle_south", 0) \
				.get_height() / 2.0
			position = Vector2(position.x, -offset_y)

func _LoadSpriteFrames(path:String) -> SpriteFrames:
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path)
	else:
		return ResourceLoader.load(DefaultSpriteFramePath)
