extends Node2D
class_name Character

const Speed = 120.0
const OUTLINE_SHADER = preload("res://shaders/outline.gdshader")
 
@onready var renderer: CharacterRenderer = $Renderer  
@onready var effect: CharacterEffect = $CharacterEffect

@export var _dialogLabel:Label
@export var _dialogShadowLabel:Label
@export var _nameLabel:Label
@export var _dialogClearTimer:Timer

var _pasoDerecho:bool
var _targetPosition:Vector2
var _charInvisible:bool
var _isPlayer:bool = false

var instanceId:int
var gridPosition:Vector2i
var isMoving:bool
var priv:int
var _dialog_revealing := false
var _dialog_progress := 0.0
var _dialog_length := 0
var _spawn_fade: Tween

func _ready() -> void:
	Global.connect("dialog_font_size_changed", Callable(self, "_on_dialog_font_size_changed"))
	Global.preferences_changed.connect(_apply_preferences)
	_apply_preferences()
	if _isPlayer:
		_apply_outline_effect()

func _physics_process(delta: float) -> void:
	_ProcessAnimation()
	_ProcessMovement(delta)
	if _dialog_revealing:
		_dialog_progress += delta * 35.0
		_dialogLabel.visible_characters = mini(_dialog_length, int(_dialog_progress))
		_dialogShadowLabel.visible_characters = _dialogLabel.visible_characters
		if int(_dialog_progress) >= _dialog_length: _reveal_dialog()

func SetAsPlayer(isPlayer: bool = true) -> void:
	_isPlayer = isPlayer
	if isPlayer and is_inside_tree():
		_apply_outline_effect()

func IsPlayer() -> bool:
	return _isPlayer

func _apply_outline_effect() -> void:
	return 
	
	for child in renderer.get_children():
		if child is AnimatedSprite2D:
			var material = ShaderMaterial.new()
			material.shader = OUTLINE_SHADER
			# Configurar el color y ancho del borde
			material.set_shader_parameter("outline_color", Color(0.0, 0.5, 1.0, 0.7))  # Azul con transparencia
			material.set_shader_parameter("outline_width", 2.0)
			child.material = material

func GetCharacterInvisible() -> bool:
	return _charInvisible
	
func SetCharacterInvisible(v:bool) -> void:
	_charInvisible = v
	if _spawn_fade != null: _spawn_fade.kill()
	renderer.modulate.a = 1.0
	renderer.visible = not v
	_nameLabel.visible = not v and Global.showNames

func FadeIn() -> void:
	if _spawn_fade != null: _spawn_fade.kill()
	if _charInvisible or not Global.transitionEffects or Global.effectsMode == 0:
		renderer.modulate.a = 1.0
		return
	renderer.modulate.a = 0.0
	_spawn_fade = create_tween()
	_spawn_fade.tween_property(renderer, "modulate:a", 1.0, 0.12)

func MoveTo(heading:int) -> void:
	if isMoving:
		position = _targetPosition
		isMoving = false
	
	var offset = Utils.HeadingToVector(heading)
	isMoving = true
	_targetPosition = position + (offset * Consts.TileSize)
	
func StopMoving() -> void:
	if isMoving:
		position = _targetPosition
	isMoving = false
 
func GetBoundaries() -> Rect2:
	return Rect2(global_position.x - 16, global_position.y - 64, 32, 64)
		
func SetCharacterName(text:String) -> void:
	_nameLabel.text = text
	
func SetCharacterNameColor(color:Color) -> void:
	_nameLabel.self_modulate = color

func GetCharacterName() -> String:
	return _nameLabel.text

func IsDead() -> bool:
	return renderer.head in [Consts.CabezaCasper, Consts.CuerpoFragataFantasmal]
	
func IsNavigating() -> bool:
	return renderer.body in Consts.ShipIds
	
func PlayWalkSound() -> void:
	_pasoDerecho = !_pasoDerecho
	AudioManager.PlayAudio(Consts.Paso1 if _pasoDerecho else Consts.Paso2)
	
func PlayNavigationSound() -> void:
	AudioManager.PlayAudio(Consts.PasoNavegando, true);

func Say(text:String, color:Color) -> void:
	_dialogClearTimer.stop()
	_dialog_revealing = false
	_dialog_progress = 0.0
	_dialog_length = text.length()
	_dialogLabel.label_settings.font_size = Global.dialogFontSize
	_dialogLabel.text = text
	_dialogShadowLabel.label_settings.font_size = _dialogLabel.label_settings.font_size
	_dialogShadowLabel.text = text
	_dialogLabel.modulate = color
	_dialog_revealing = Global.animateDialogs and not text.is_empty()
	_dialogLabel.visible_characters = 0 if _dialog_revealing else -1
	_dialogShadowLabel.visible_characters = _dialogLabel.visible_characters
	if not _dialog_revealing and not text.is_empty(): _reveal_dialog()

func _reveal_dialog() -> void:
	_dialog_revealing = false
	_dialogLabel.visible_characters = -1
	_dialogShadowLabel.visible_characters = -1
	_dialogClearTimer.wait_time = clampf(2.0 + float(_dialog_length) / 40.0, 2.0, 6.0)
	if _dialog_length > 0: _dialogClearTimer.start()

func ClearDialog() -> void:
	_dialog_revealing = false
	_dialog_progress = 0.0
	_dialog_length = 0
	_dialogClearTimer.stop()
	_dialogLabel.text = ""
	_dialogShadowLabel.text = ""

func _OnDialogClearTimerTimeout() -> void:
	ClearDialog()

func _exit_tree() -> void:
	_dialog_revealing = false
	if is_instance_valid(_dialogClearTimer): _dialogClearTimer.stop()

func _ProcessAnimation() -> void:
	if isMoving:
		renderer.Play()
	else:
		renderer.Stop()

func _ProcessMovement(delta:float) -> void:
	if !isMoving:
		return
	
	position = position.move_toward(_targetPosition, Speed * delta)
	if position == _targetPosition:
		isMoving = false

func _on_dialog_font_size_changed(value: int) -> void:
	_dialogLabel.label_settings.font_size = value
	_dialogShadowLabel.label_settings.font_size = value

func _apply_preferences() -> void:
	if _dialog_revealing and not Global.animateDialogs: _reveal_dialog()
	_nameLabel.visible = not _charInvisible and Global.showNames
	_nameLabel.add_theme_font_size_override("font_size", Global.nameFontSize)
