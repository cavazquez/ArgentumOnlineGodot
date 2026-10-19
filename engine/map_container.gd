extends Node2D
class_name MapContainer

const GridPositionKey = "GridPosition"

var _view:Node2D
var _map_id := 0
var _cache: MapViewCache

var _characterCollection:Array[Character]
var _objectCollection:Array[Node2D]
var _tiles:PackedByteArray

func _ready() -> void:
	_cache = MapViewCache.new()
	add_child(_cache)
	_tiles.resize(100 * 100)
	_tiles.fill(Enums.TileState.Blocked)  
	
func LoadMap(id:int) -> bool:
	var next_view := _cache.take(id)
	if next_view == null:
		var path := "res://Maps/Map%d.tscn" % id
		if not ResourceLoader.exists(path):
			push_warning("Vista de mapa no disponible: %d" % id)
			return false
		var scene := load(path) as PackedScene
		if scene == null: return false
		next_view = scene.instantiate()
	_DeleteEntities()
	if _view: _cache.keep(_map_id, _view)
	_view = next_view
	_map_id = id
	_tiles = GameAssets.ApplyWaterMask(id, _view.get_meta("data"))
	%MapView.add_child(_view)
	_cache.schedule(id)
	return true

func GetTile(x:int, y:int) -> int:
	if x < 0 or y < 0 or x >= 100 or y >= 100: return Enums.TileState.Blocked
	return _tiles[x + y * 100]
	
func SetTile(x:int, y:int, state:int) -> void:
	_tiles[x + y * 100] = state
	
func BlockTile(x:int, y:int) -> void:
	var tile = GetTile(x, y) | Enums.TileState.Blocked
	SetTile(x, y, tile) 
		
func UnblockTile (x:int, y:int) -> void:
	var tile = GetTile(x, y) & ~Enums.TileState.Blocked
	SetTile(x, y, tile) 

func AddCharacter(character:Character) -> void:
	_characterCollection.append(character)
	_GetLayer("Layer3").add_child(character) 
		
func DeleteCharacter(instanceId:int) -> void:
	var character = GetCharacter(instanceId)
	if character:
		_characterCollection.erase(character)
		character.queue_free()
			
func GetCharacter(instanceId:int) -> Character:
	for node in _characterCollection:
		if node.instanceId == instanceId:
			return node
	return null

func PlayWorldEffect(at: Vector2, fx: int, loops: int) -> void:
	# El NPC puede desaparecer antes de que llegue el FX del golpe que lo mató.
	var anchor := Node2D.new()
	anchor.set_meta("pyao_dynamic_fx", true)
	anchor.position = at
	_GetLayer("Layer3").add_child(anchor)
	var effect := CharacterEffect.new()
	anchor.add_child(effect)
	# El watchdog desaparece con el FX o con el mapa. Un SceneTreeTimer puede
	# sobrevivir a ambos e intentar invocar una lambda con un anchor liberado.
	var timeout := Timer.new()
	timeout.name = "EffectTimeout"
	timeout.one_shot = true
	timeout.wait_time = 10.0
	anchor.add_child(timeout)
	timeout.timeout.connect(anchor.queue_free, CONNECT_ONE_SHOT)
	timeout.start()
	effect.finished.connect(anchor.queue_free, CONNECT_ONE_SHOT)
	effect.play_effect(fx, clampi(loops, 0, 5))
	
func GetCharacterAt(x:int, y:int) -> Character:
	for node in _characterCollection:
		if node.gridPosition == Vector2i(x, y):
			return node
	return null
	
func AddObject(grhId:int, x:int, y:int) -> void:
	if grhId > 0:
		if GameAssets.GrhDataList[grhId].frameCount > 1:
			grhId = GameAssets.GrhDataList[grhId].frames[1]
		
		var grhData = GameAssets.GrhDataList[grhId]
		var sprite = _CreateSprite(grhData, x -1, y - 1)
		sprite.set_meta(GridPositionKey, Vector2i(x, y))
		_objectCollection.append(sprite)
		
		if sprite.region_rect.size == Vector2(32, 32):
			_GetLayer("Layer2").add_child(sprite)
		else:
			_GetLayer("Layer3").add_child(sprite)
	
func DeleteObject(x:int, y:int) -> void:
	var node:Node2D = null
	
	for object in _objectCollection:
		if object.get_meta(GridPositionKey) == Vector2i(x, y):
			node = object
			break
	
	if node:
		_objectCollection.erase(node)
		node.queue_free()
	
func _DeleteEntities() -> void:
	for entity in _characterCollection + _objectCollection:
		if is_instance_valid(entity):
			if entity.get_parent(): entity.get_parent().remove_child(entity)
			entity.queue_free()
	if _view:
		for layer in _view.get_children():
			for child in layer.get_children():
				if child.get_meta("pyao_dynamic_fx", false): child.queue_free()
	_characterCollection.clear()
	_objectCollection.clear()

func _CreateSprite(grhData:GrhData, x:int, y:int) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.texture = GameAssets.GetTexture(grhData.fileId)
	sprite.position = Vector2((x * 32) + 16, (y * 32) + 32);
	sprite.region_enabled = true
	sprite.region_rect = grhData.region;
	sprite.offset = Vector2(0, -sprite.region_rect.size.y / 2);
	
	return sprite

func _GetLayer(layerName: String) -> Node2D:

	for node in _view.get_children():
		if node.name == layerName: 
			return node
			
	push_error("MapContainer: layer %s not found" % layerName)
	return null


func ClearDialogs() -> void:
	for character in _characterCollection:
		character.ClearDialog()
