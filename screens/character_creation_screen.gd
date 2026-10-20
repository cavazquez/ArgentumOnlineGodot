extends Node

@export var _usernameLineEdit:LineEdit
@export var _passwordLineEdit:LineEdit
@export var _confirmPasswordLineEdit:LineEdit
@export var _emailLineEdit:LineEdit

@export var _classOptionButton:OptionButton
@export var _raceOptionButton:OptionButton
@export var _genderOptionButton:OptionButton
@export var _homeOptionButton:OptionButton

@export var _submitButton:Button
@export var _attributeContainer:VBoxContainer
var _preview: Character
var _preview_caption: Label
var _selected_head := 1
var _preview_heading := Enums.Heading.South
var _preview_home := -1
var _homes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/home-preview.json")).homes
const HEAD_RANGES := [[[1, 40], [101, 122], [201, 221], [401, 416], [301, 319]], [[70, 89], [170, 188], [270, 288], [470, 484], [370, 384]]]

func _ready() -> void:
	ClientInterface.disconnected.connect(_OnDisconnected)
	ClientInterface.dataReceived.connect(_OnDataReceivedd) 
	
	_Init()
	_BuildPreview()

func _Init() -> void:
	for i in range(1, Consts.NumClases + 1):
		_classOptionButton.add_item(Consts.ClassNames[i])
	
	for i in range(1, Consts.NumRazas + 1):
		_raceOptionButton.add_item(Consts.RaceNames[i])
		
	for i in range(1, Consts.NumCiudades + 1):
		_homeOptionButton.add_item(Consts.HomeNames[i])
		
	_ThrowDice()
  
func _OnDisconnected() -> void:
	if is_queued_for_deletion(): return
	_DetachNetwork()
	var screen = load("uid://cd452cndcck7v").instantiate()  
	ScreenController.SwitchScreen(screen) 

func _DetachNetwork() -> void:
	if ClientInterface.dataReceived.is_connected(_OnDataReceivedd):
		ClientInterface.dataReceived.disconnect(_OnDataReceivedd)
	if ClientInterface.disconnected.is_connected(_OnDisconnected):
		ClientInterface.disconnected.disconnect(_OnDisconnected)

func _OnDataReceivedd(data:PackedByteArray) -> void:
	var stream = StreamPeerBuffer.new()
	stream.data_array = data
	
	while stream.get_position() < stream.get_size():
		var packetId = stream.get_u8()
		match packetId:
			Enums.ServerPacketID.DiceRoll:
				_HandleDiceRoll(stream.get_data(5)[1])
			Enums.ServerPacketID.ErrorMsg:
				Utils.ShowAlertDialog("Creacion de personajes", Utils.GetUnicodeString(stream), self)
			Enums.ServerPacketID.Logged:
				_HandleLogged(data) 
				return 
				
func _HandleLogged(data:PackedByteArray) -> void:
	_DetachNetwork()
	var screen = load("uid://b2dyxo3826bub").instantiate() as GameScreen
	screen.networkMessages.append(data)
	
	ScreenController.SwitchScreen(screen)

func _HandleDiceRoll(collection:Array[int]) -> void:
	const names = ["Fuerza", "Agilidad", "Inteligencia", "Carisma", "Constitucion"]
	for i in collection.size():
		_attributeContainer.get_child(i).text = "{0}: {1}".format([names[i], collection[i]])
	
func _OnSubmitButtonPressed() -> void:
	var message := CredentialPolicy.validate(_usernameLineEdit.text, _passwordLineEdit.text)
	if not message.is_empty():
		Utils.ShowAlertDialog("Error", message, self)
		return

	if _passwordLineEdit.text != _confirmPasswordLineEdit.text:
		Utils.ShowAlertDialog("Error", "Las contraseñas no coinciden", self)
		return
		
	if !Utils.IsEmailValid(_emailLineEdit.text):
		Utils.ShowAlertDialog("Error", "Email invalido", self)
		return
	
	Global.username = _usernameLineEdit.text
	
	GameProtocol.WriteLoginNewChar(_usernameLineEdit.text, \
		_passwordLineEdit.text, \
		_emailLineEdit.text, \
		_classOptionButton.selected + 1, \
		_raceOptionButton.selected + 1, \
		_genderOptionButton.selected + 1, \
		_homeOptionButton.selected + 1, \
		_selected_head)
	_Flush()

func _Exit() -> void:
	ClientInterface.DisconnectFromHost()

func _ThrowDice() -> void:
	GameProtocol.WriteThrowDice()
	_Flush()

func _Flush() -> void:
	ClientInterface.Send(GameProtocol.Flush())

func _GetHead(race:int, gender:int) -> int:
	match gender:
		0: #Hombre
			match race:
				Enums.Race.Human:
					return randi_range(1, 40)
				Enums.Race.Elf:
					return randi_range(101, 122)
				Enums.Race.Drow:
					return randi_range(201, 221)
				Enums.Race.Dwarf:
					return randi_range(301, 319)
				Enums.Race.Gnome:
					return randi_range(401, 416)
					
		1: #Mujer
			match race:
				Enums.Race.Human:
					return randi_range(70, 89)
				Enums.Race.Elf:
					return randi_range(170, 188)
				Enums.Race.Drow:
					return randi_range(270, 288)
				Enums.Race.Dwarf:
					return randi_range(370, 384)
				Enums.Race.Gnome:
					return randi_range(470, 484)
					
	push_error("CLASE O RAZA INVALIDA")
	return 0

func _BuildPreview() -> void:
	var panel := HBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-145, 8)
	panel.custom_minimum_size = Vector2(290, 125)
	$CanvasLayer.add_child(panel)
	var view := SubViewportContainer.new()
	view.custom_minimum_size = Vector2(100, 120)
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(view)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(100, 120)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	view.add_child(viewport)
	_preview = preload("res://engine/character/character.tscn").instantiate()
	viewport.add_child(_preview)
	_preview.position = Vector2(50, 100)
	_preview.scale = Vector2(2, 2)
	var controls := VBoxContainer.new()
	panel.add_child(controls)
	_preview_caption = Label.new()
	controls.add_child(_preview_caption)
	var heads := HBoxContainer.new()
	controls.add_child(heads)
	for step in [-1, 1]:
		var button := Button.new()
		button.text = "Cabeza anterior" if step == -1 else "Siguiente"
		button.pressed.connect(_ChangeHead.bind(step))
		heads.add_child(button)
	var turn := Button.new()
	turn.text = "Girar personaje"
	turn.pressed.connect(func():
		_preview_heading = _preview_heading % 4 + 1
		_UpdatePreview())
	controls.add_child(turn)
	_raceOptionButton.item_selected.connect(func(_index): _SelectHead())
	_genderOptionButton.item_selected.connect(func(_index): _SelectHead())
	_classOptionButton.item_selected.connect(func(_index): _UpdatePreview())
	_homeOptionButton.item_selected.connect(func(_index): _UpdatePreview())
	_SelectHead()

func _SelectHead() -> void:
	_selected_head = _GetHead(_raceOptionButton.selected + 1, _genderOptionButton.selected)
	_UpdatePreview()

func _ChangeHead(step: int) -> void:
	var bounds: Array = HEAD_RANGES[_genderOptionButton.selected][_raceOptionButton.selected]
	_selected_head = wrapi(_selected_head + step, bounds[0], bounds[1] + 1)
	_UpdatePreview()

func _UpdatePreview() -> void:
	if _preview == null: return
	# pyao usa el ID de raza como cuerpo inicial; la clase no inventa equipo.
	_preview.renderer.body = _raceOptionButton.selected + 1
	_preview.renderer.head = _selected_head
	_preview.renderer.heading = _preview_heading
	_preview.renderer.Stop()
	_preview_caption.text = "%s · %s\nCabeza %d · %s" % [_raceOptionButton.get_item_text(_raceOptionButton.selected), _classOptionButton.get_item_text(_classOptionButton.selected), _selected_head, _homeOptionButton.get_item_text(_homeOptionButton.selected)]
	var home := _homeOptionButton.selected + 1
	if home == _preview_home: return
	_preview_home = home
	var spawn: Dictionary = _homes.get(str(home), _homes["1"])
	var path := "res://Maps/Map%d.tscn" % int(spawn.map)
	if not ResourceLoader.exists(path):
		path = "res://Maps/Map1.tscn"
		spawn = _homes["1"]
	var scene := load(path) as PackedScene
	if scene == null: return
	var old := get_node_or_null("MapView")
	if old != null:
		remove_child(old)
		old.queue_free()
	var map := scene.instantiate()
	map.name = "MapView"
	add_child(map)
	$Camera2D.position = Vector2(int(spawn.x) * 32 - 16, int(spawn.y) * 32)
