extends Node2D
class_name GameWorld
const CharacterScene = preload("uid://twhhld7du3lq")

@export var _mapContainer:MapContainer
var _recent_removed := {}
const REMOVED_FX_WINDOW_MS := 1500

func GetMapContainer() -> MapContainer:
	return _mapContainer

func CreateCharacter(data:CharacterCreate) -> Character:
	_recent_removed.erase(data.charIndex)
	_mapContainer.DeleteCharacter(data.charIndex)
	
	var character = CharacterScene.instantiate() as Character
	character.instanceId = data.charIndex
	character.gridPosition = Vector2i(data.x, data.y)
	character.showName = data.showName
	_mapContainer.AddCharacter(character)
	
	character.SetCharacterName(data.name)
	character.SetCharacterNameColor(Utils.GetNickColor(data.nickColor, data.privileges))
	character.position = Vector2((data.x - 1) * 32, (data.y - 1) * 32) + Vector2(16, 32);
	character.priv = data.privileges
	
	character.renderer.body = data.body 
	character.renderer.head = data.head;
	character.renderer.helmet = data.helmet;
	character.renderer.boots = data.boots;
	character.renderer.weapon = data.weapon;
	character.renderer.shield = data.shield;
	character.renderer.heading = data.heading; 
	return character
	
func MoveCharacter(instanceId:int, heading:int) -> void:
	var character = GetCharacter(instanceId);
	if !character: return
	
	var offset = Utils.HeadingToVector(heading)
	character.renderer.heading = heading
	character.gridPosition += Vector2i(offset)
	character.MoveTo(heading)
	
	if character.effect.effect_id >= 40 && character.effect.effect_id <= 49:
		character.effect.stop_effect()
	
	_PlayerWalkSound(character)
	
func GetCharacter(instanceId:int) -> Character:
	return _mapContainer.GetCharacter(instanceId)
	
func GetCharacterAt(x:int, y:int) -> Character:
	return _mapContainer.GetCharacterAt(x, y)
	
func DeleteCharacter(instanceId:int) -> void:
	var now := Time.get_ticks_msec()
	for key in _recent_removed.keys():
		if now - int(_recent_removed[key].tick) > REMOVED_FX_WINDOW_MS:
			_recent_removed.erase(key)
	var character := GetCharacter(instanceId)
	if character:
		_recent_removed[instanceId] = {"tick": now, "position": character.position}
		if _recent_removed.size() > 256:
			_recent_removed.erase(_recent_removed.keys()[0])
	_mapContainer.DeleteCharacter(instanceId)

func PlayCharacterEffect(instanceId: int, fx: int, loops: int) -> void:
	var character := GetCharacter(instanceId)
	if character:
		character.effect.play_effect(fx, loops)
	elif fx > 0 and loops >= 0 and _recent_removed.has(instanceId):
		var removed: Dictionary = _recent_removed[instanceId]
		if Time.get_ticks_msec() - int(removed.tick) <= REMOVED_FX_WINDOW_MS:
			_mapContainer.PlayWorldEffect(removed.position, fx, loops)
	
func DeleteObject(x:int, y:int) -> void:
	_mapContainer.DeleteObject(x, y)

func AddObject(grhId:int, x:int, y:int) -> void:
	DeleteObject(x, y);
	_mapContainer.AddObject(grhId, x, y)
	
func SwitchMap(id:int) -> bool:
	_recent_removed.clear()
	return _mapContainer.LoadMap(id)

func _PlayerWalkSound(character:Character) -> void:
	if character.IsDead():
		return
	var camera = get_viewport().get_camera_2d()
	if Utils.GetCameraBounds(camera).intersects(character.GetBoundaries()):
		if character.IsNavigating():
			character.PlayNavigationSound()
		else:
			character.PlayWalkSound()
