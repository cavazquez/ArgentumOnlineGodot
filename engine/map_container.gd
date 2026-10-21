extends Node2D
class_name MapContainer

const GridPositionKey = "GridPosition"

var _view:Node2D
var _map_id := 0
var _door_locations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/door-locations.json"))
var _door_graphics: Dictionary[int, bool] = {}
var _cache: MapViewCache

var _characterCollection:Array[Character]
var _objectCollection:Array[Node2D]
var _tiles:PackedByteArray
var _characters_by_id: Dictionary[int, Character] = {}
var _characters_by_position: Dictionary[Vector2i, Array] = {}
var _character_slots: Dictionary[int, int] = {}
var _character_order: Dictionary[int, int] = {}
var _next_character_order := 0
var _objects_by_position: Dictionary[Vector2i, Node2D] = {}
var _object_slots: Dictionary[int, int] = {}
var _door_sprites: Dictionary[Vector2i, Sprite2D] = {}
var _active_doors: Dictionary[Vector2i, bool] = {}

func _ready() -> void:
	for graphic in _door_locations.graphics: _door_graphics[int(graphic)] = true
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
	_ClearBakedDoors(id)
	_cache.schedule(id)
	return true

func _ClearBakedDoors(id: int) -> void:
	var cleared := _view.has_meta("dynamic_doors_cleared")
	var cells: Array = _door_locations.maps.get(str(id), [])
	_active_doors.clear()
	for cell in cells:
		_active_doors[Vector2i(int(cell[0]), int(cell[1]))] = true
		if cleared: continue
		var layer2 := _view.get_node_or_null("Layer2") as TileMapLayer
		if layer2 != null: layer2.erase_cell(Vector2i(int(cell[0])-1, int(cell[1])-1))
		var layer3 := _view.get_node_or_null("Layer3")
		if layer3 != null:
			var position := Vector2((int(cell[0])-1)*32+16, int(cell[1])*32)
			for node in layer3.get_children():
				if node is Sprite2D and node.position == position and not node.has_meta(GridPositionKey):
					node.hide()
	_view.set_meta("dynamic_doors_cleared", true)

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
	_TrackCharacter(character)
	_GetLayer("Layer3").add_child(character)

func _TrackCharacter(character: Character) -> void:
	# También lo usa el benchmark: registra exactamente los índices de producción.
	if _character_slots.has(character.get_instance_id()): return
	DeleteCharacter(character.instanceId)
	_character_slots[character.get_instance_id()] = _characterCollection.size()
	_character_order[character.get_instance_id()] = _next_character_order
	_next_character_order += 1
	_characterCollection.append(character)
	_characters_by_id[character.instanceId] = character
	_AddCharacterPosition(character)
	character.grid_position_changed.connect(_CharacterPositionChanged)
	character.instance_id_changed.connect(_CharacterIdChanged)
	character.retiring.connect(_UntrackCharacter)
	character.tree_exiting.connect(_UntrackCharacter.bind(character))

func _AddCharacterPosition(character: Character) -> void:
	var cell: Array = _characters_by_position.get(character.gridPosition, [])
	# Conserva la selección del primer personaje creado incluso si se superponen.
	var order: int = _character_order[character.get_instance_id()]
	var slot := cell.size()
	while slot > 0 and _character_order[cell[slot - 1].get_instance_id()] > order:
		slot -= 1
	cell.insert(slot, character)
	_characters_by_position[character.gridPosition] = cell

func _RemoveCharacterPosition(character: Character, previous: Vector2i) -> void:
	var cell: Array = _characters_by_position.get(previous, [])
	cell.erase(character)
	if cell.is_empty():
		_characters_by_position.erase(previous)

func _CharacterPositionChanged(character: Character, previous: Vector2i) -> void:
	_RemoveCharacterPosition(character, previous)
	_AddCharacterPosition(character)

func _CharacterIdChanged(character: Character, previous: int) -> void:
	if _characters_by_id.get(previous) == character:
		_characters_by_id.erase(previous)
	DeleteCharacter(character.instanceId)
	_characters_by_id[character.instanceId] = character

func _UntrackCharacter(character: Character) -> void:
	var identity := character.get_instance_id()
	if not _character_slots.has(identity): return
	_RemoveCharacterPosition(character, character.gridPosition)
	if _characters_by_id.get(character.instanceId) == character:
		_characters_by_id.erase(character.instanceId)
	var slot: int = _character_slots[identity]
	var last: Character = _characterCollection.pop_back()
	if slot < _characterCollection.size():
		_characterCollection[slot] = last
		_character_slots[last.get_instance_id()] = slot
	_character_slots.erase(identity)
	_character_order.erase(identity)
	character.grid_position_changed.disconnect(_CharacterPositionChanged)
	character.instance_id_changed.disconnect(_CharacterIdChanged)
	character.retiring.disconnect(_UntrackCharacter)
	character.tree_exiting.disconnect(_UntrackCharacter.bind(character))
		
func DeleteCharacter(instanceId:int) -> void:
	var character = GetCharacter(instanceId)
	if character:
		_UntrackCharacter(character)
		character.queue_free()
			
func GetCharacter(instanceId:int) -> Character:
	return _characters_by_id.get(instanceId)

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
	var cell: Array = _characters_by_position.get(Vector2i(x, y), [])
	return cell[0] if not cell.is_empty() else null
	
func AddObject(grhId:int, x:int, y:int) -> void:
	var cell := Vector2i(x, y)
	if _active_doors.has(cell) and _door_graphics.has(grhId):
		if _door_sprites.has(cell):
			_RetireDoor(_door_sprites[cell])
		var graphic := grhId
		if GameAssets.GrhDataList[graphic].frameCount > 1: graphic = GameAssets.GrhDataList[graphic].frames[1]
		var door := _CreateSprite(GameAssets.GrhDataList[graphic], x-1, y-1)
		door.set_meta(GridPositionKey, cell)
		_door_sprites[cell] = door
		_AddSortedSprite(door)
		return
	if grhId > 0:
		if GameAssets.GrhDataList[grhId].frameCount > 1:
			grhId = GameAssets.GrhDataList[grhId].frames[1]
		
		var grhData = GameAssets.GrhDataList[grhId]
		var sprite = _CreateSprite(grhData, x -1, y - 1)
		sprite.set_meta(GridPositionKey, Vector2i(x, y))
		_TrackObject(sprite)
		
		if sprite.region_rect.size == Vector2(32, 32):
			_GetLayer("Layer2").add_child(sprite)
		else:
			_AddSortedSprite(sprite)
	
func DeleteObject(x:int, y:int) -> void:
	var node := GetObjectAt(x, y)
	if node:
		_UntrackObject(node)
		_RetireGraphic(node)

func GetObjectAt(x: int, y: int) -> Node2D:
	return _objects_by_position.get(Vector2i(x, y))

func _TrackObject(node: Node2D) -> void:
	if _object_slots.has(node.get_instance_id()): return
	var cell: Vector2i = node.get_meta(GridPositionKey)
	DeleteObject(cell.x, cell.y)
	_object_slots[node.get_instance_id()] = _objectCollection.size()
	_objectCollection.append(node)
	_objects_by_position[cell] = node
	node.tree_exiting.connect(_UntrackObject.bind(node))

func _UntrackObject(node: Node2D) -> void:
	var identity := node.get_instance_id()
	if not _object_slots.has(identity): return
	var cell: Vector2i = node.get_meta(GridPositionKey)
	if _objects_by_position.get(cell) == node:
		_objects_by_position.erase(cell)
	var slot: int = _object_slots[identity]
	var last: Node2D = _objectCollection.pop_back()
	if slot < _objectCollection.size():
		_objectCollection[slot] = last
		_object_slots[last.get_instance_id()] = slot
	_object_slots.erase(identity)
	node.tree_exiting.disconnect(_UntrackObject.bind(node))
	
func _DeleteEntities() -> void:
	for door in _door_sprites.values(): _RetireDoor(door)
	_door_sprites.clear()
	var entities := _characterCollection + _objectCollection
	for character in _characterCollection.duplicate(): _UntrackCharacter(character)
	for object in _objectCollection.duplicate(): _UntrackObject(object)
	_next_character_order = 0
	for entity in entities:
		if is_instance_valid(entity):
			_RetireGraphic(entity)
	if _view:
		for layer in _view.get_children():
			for child in layer.get_children():
				if child.get_meta("pyao_dynamic_fx", false): child.queue_free()

func _RetireDoor(door: Sprite2D) -> void:
	_RetireGraphic(door)

func _RetireGraphic(graphic: Node2D) -> void:
	var parent := graphic.get_parent()
	var owner: Node2D = parent if parent != null and parent.get_meta("pyao_graphic_anchor", false) else graphic
	owner.hide()
	owner.queue_free()

func _AddSortedSprite(sprite: Sprite2D) -> void:
	# El ancla participa en y-sort. El Sprite2D se libera como hijo de un
	# propietario normal, igual que las capas visuales de CharacterRenderer.
	# La regresión door_layers cubre reemplazos y cambios de mapa en un frame.
	var anchor := Node2D.new()
	anchor.set_meta("pyao_graphic_anchor", true)
	anchor.position = sprite.position
	sprite.position = Vector2.ZERO
	anchor.add_child(sprite)
	_GetLayer("Layer3").add_child(anchor)

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
