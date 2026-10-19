extends Node
class_name GameScreen

# Importar comandos de red
const ShowGuildAlignCommand = preload("res://network/commands/ShowGuildAlign.gd")
const ShowGuildFundationFormCommand = preload("res://network/commands/ShowGuildFundationForm.gd")
const Atributes = preload("res://network/commands/Atributes.gd")
const MiniStats = preload("res://network/commands/MiniStats.gd")
const Fame = preload("res://network/commands/Fame.gd")

# Cursor personalizado para selección de objetivo
var _crosshair_cursor: Texture2D = null
var _scaled_crosshair_cursor = null
@export var _gameInput:HubController
@export var _gameWorld:GameWorld
@export var _camera:Camera2D

var _gameContext:GameContext = GameContext.new()
var _mainCharacterInstanceId:int = -1
var networkMessages:Array[PackedByteArray]
var _dispatcher := AOMessageDispatcher.new()
var _visuals: CombatVisuals
var _presentation: WorldPresentation
var _map_ready := false

var _input:Dictionary[String, int] = {
	"ui_left" = Enums.Heading.West,
	"ui_right" = Enums.Heading.East,
	"ui_up" = Enums.Heading.North,
	"ui_down" = Enums.Heading.South,
}
 
func _ready() -> void:
	Global.pingStatus = "Sin medición"
	Global.ping_requested.connect(_OnPingTimerTimeout)
	_dispatcher.message_decoded.connect(_OnDecodedMessage)
	_dispatcher.protocol_error.connect(ClientInterface._fail)
	_visuals = CombatVisuals.new()
	_gameWorld.add_child(_visuals)
	_presentation = WorldPresentation.new()
	_presentation.viewport = _gameWorld.get_viewport()
	_gameInput.get_node("MainViewportContainer").add_child(_presentation)

	ClientInterface.disconnected.connect(_OnDisconnected)
	ClientInterface.dataReceived.connect(_OnDataReceived)
	ClientInterface.serialization_failed.connect(_OnSerializationFailed) 
	
	_gameInput.Init(_gameContext)
	_gameInput.update_name_label(Global.username)
	
	# Cargar el cursor después de que los recursos estén listos
	if ResourceLoader.exists("res://Assets/Cursors/crosshair.png", "Texture2D"):
		_crosshair_cursor = load("res://Assets/Cursors/crosshair.png")
		if _crosshair_cursor:
			_scaled_crosshair_cursor = _scale_cursor(_crosshair_cursor, 0.5)  # Ajusta el factor de escala según necesites

# Función para escalar el cursor a un tamaño más pequeño
func _scale_cursor(texture: Texture2D, scale_factor: float) -> Texture2D:
	# Obtener la imagen del cursor
	var image = texture.get_image()
	
	# Calcular el nuevo tamaño
	var original_size = image.get_size()
	var new_size = original_size * scale_factor
	
	# Redimensionar la imagen
	image.resize(int(new_size.x), int(new_size.y), Image.INTERPOLATE_BILINEAR)
	
	# Crear una nueva textura con la imagen redimensionada
	var new_texture = ImageTexture.create_from_image(image)
	
	return new_texture
	 
func _OnDisconnected() -> void:
	if _presentation != null: _presentation.reset()
	_gameContext.pingTime = 0
	Global.pingStatus = "Desconectado"
	set_process(false)
	networkMessages.clear()
	var screen = load("uid://cd452cndcck7v").instantiate() 
	ScreenController.SwitchScreen(screen)
	
func _OnDataReceived(data:PackedByteArray) -> void: 
	networkMessages.push_back(data)

func _process(_delta: float) -> void:
	_ProccessMessages()
	_UpdatePingStatus(Time.get_ticks_msec())
	_CheckKeys()
	_UpdateCameraPosition()
	if _presentation != null:
		_presentation.set_world_offset(_camera.position)
		if _presentation.waiting and _map_ready:
			_presentation.reveal()
			Global.character_local.open_profile(ClientInterface.local_character_key(Global.username))
			Global.character_local.visit(_gameContext.player_map)
	_FlushData()
	
func _UpdateCameraPosition() -> void:
	var character = _gameWorld.GetCharacter(_mainCharacterInstanceId)
	if character && _camera:
		_camera.position = character.position

func _CheckKeys() -> void:
	if _gameInput.IsWorldInputBlocked():
		return
	if _gameContext.traveling || _gameContext.mirandoForo ||\
		_gameContext.trading  || _gameContext.pause:
		return
	
	for k in _input:
		if Input.is_action_pressed(k):
			_MovePlayer(_input[k])
			return

func _MovePlayer(heading:int) -> void:
	if heading == Enums.Heading.None:
		return

	var character = _gameWorld.GetCharacter(_mainCharacterInstanceId)
	if character == null || character.isMoving:
		return
		
	var newGridLocation = character.gridPosition + Vector2i(Utils.HeadingToVector(heading))
	if _CanMoveTo(newGridLocation.x, newGridLocation.y) && !_gameContext.userParalizado:
		#TODO 
		#No se porque esto esta asi. Lo unico que logra es que el personaje pegue un salto cuando camina
		#Obligando al usuario a presionar la tecla L(PosUpdate)
		GameProtocol.WriteWalk(heading)
		if !_gameContext.userDescansar && !_gameContext.userMeditar:
			_gameWorld.MoveCharacter(_mainCharacterInstanceId, heading)
	else:
		if character.renderer.heading != heading:
			GameProtocol.WriteChangeHeading(heading)
	
	_gameInput.minimap.update_player_position(character.gridPosition.x, character.gridPosition.y)
	 
func _CanMoveTo(x:int, y:int) -> bool:
	var map = _gameWorld.GetMapContainer()
	
	#Limites del mapa
	#If X < MinXBorder Or X > MaxXBorder Or Y < MinYBorder Or Y > MaxYBorder Then
	#    Exit Function
	#End If
	
	#Tile Bloqueado?
	var destination := map.GetTile(x - 1, y - 1)
	if destination & Enums.TileState.Blocked and not (_gameContext.userNavegando and destination & Enums.TileState.Water):
		return false
	
	var character = map.GetCharacterAt(x, y)
	var mainCharacter = map.GetCharacter(_mainCharacterInstanceId)
	var playerPos = Vector2i(mainCharacter.gridPosition)
	
	if character:
		if map.GetTile(playerPos.x - 1, playerPos.y - 1) & Enums.TileState.Blocked:
			return false
			
		#Si no es casper, no puede pasar
		if character.renderer.head != Consts.CabezaCasper && character.renderer.body != Consts.CuerpoFragataFantasmal:
			return false
		else:
			#No puedo intercambiar con un casper que este en la orilla (Lado tierra)
			if map.GetTile(playerPos.x - 1, playerPos.y - 1) & Enums.TileState.Water:
				if !bool(map.GetTile(x - 1, y -1) & Enums.TileState.Water):
					return false
			else:
				#No puedo intercambiar con un casper que este en la orilla (Lado agua)
				if map.GetTile(x - 1, y -1) & Enums.TileState.Water:
					return false
			#Los admins no pueden intercambiar pos con caspers cuando estan invisibles
			if mainCharacter.priv > 0 && mainCharacter.priv < 6:
				if mainCharacter.GetCharacterInvisible():
					return false
		 
	if _gameContext.userNavegando != bool(map.GetTile(x - 1, y -1) & Enums.TileState.Water):
		return false
	
	return true

#region Network
func _ProccessMessages() -> void: 
	while !networkMessages.is_empty():
		var data = networkMessages.pop_front()
		_HandleIncomingData(data) 

func _HandleIncomingData(data:PackedByteArray) -> void:
	# ClientInterface entrega exactamente un paquete, ya reconstruido y validado.
	_dispatcher.dispatch(data)

func _OnDecodedMessage(handler: StringName, payload: Variant, has_payload: bool) -> void:
	match handler:
		&"_ApplyWorldState": _ApplyWorldState(payload)
		&"_ApplySkillAction": _gameInput.ApplySkillAction(payload)
		&"_ApplyPasswordReply": _gameInput.ApplyPasswordReply(payload)
		&"_ApplySkillAllocation": _gameInput.ApplySkillAllocation(payload)
		&"_ApplyTradeSnapshot":
			ClientInterface.world_state.observe_trade(payload)
			_gameInput.ApplyTradeSnapshot(payload)
		&"_ApplyClanDetails": _gameInput.ApplyClanDetails(payload)
		&"_ApplySkillCatalog":
			Global.skillPoints = payload.free_points
			_HandleSendSkills(payload)
		&"_ShowGuildAlignment": ShowGuildAlignCommand.new(self).handle()
		&"_ShowGuildFoundation": ShowGuildFundationFormCommand.new(self).handle()
		_:
			if has_method(handler):
				if has_payload: call(handler, payload)
				else: call(handler)


func _handle_character_change_nick(p:CharacterChangeNick) -> void:
	var character = _gameWorld.GetCharacter(p.char_index)
	if character:
		character.SetCharacterName(p.char_name)
	
	
func _handle_user_commerce_init(p:UserCommerceInit) -> void:
	pass


#TODO Completar
func _handle_commerce_end() -> void:
	_gameContext.trading = false


func _handle_user_offer_confirm() -> void:
	pass


func _handle_cancel_offer_item(p:CancelOfferItem) -> void:
	pass


func _handle_commerce_chat(p:CommerceChat) -> void:
	pass


func _handle_show_blacksmith_form() -> void:
	pass


func _handle_blacksmith_weapons(p:BlacksmithWeapons) -> void:
	pass


func _handle_blacksmith_armors(p:BlacksmithArmors) -> void:
	pass


func _handle_show_carpenter_form() -> void:
	pass


func _handle_carpenter_objects(p:CarpenterObjects) -> void:
	pass
	
	
func _handle_update_mana(p:UpdateMana) -> void:
	_gameInput.mana_stat_bar.value = p.min_mana
	_gameContext.player_stats.mana = p.min_mana
			
			
func _HandelUpdateExp(p:UpdateExp) -> void:
	_gameInput.experience_stat_bar.value = p.experience
			
			
func _HandleShowMessageBox(p:ShowMessageBox) -> void:
	Utils.ShowAlertDialog("Server", p.message, get_parent())


func _HandlePong(now: int = -1) -> void:
	if _gameContext.pingTime == 0: return
	if now < 0: now = Time.get_ticks_msec()
	var elapsed := now - _gameContext.pingTime
	_gameContext.pingTime = 0
	# PONG no tiene identificador. No abrir otra medición hasta drenar el tardío.
	Global.pingStatus = "%d ms" % elapsed if elapsed <= 5000 else "Sin respuesta"

func _UpdatePingStatus(now: int) -> void:
	if _gameContext.pingTime != 0 and now - _gameContext.pingTime > 5000:
		Global.pingStatus = "Sin respuesta"


func _handle_navigate_toggle() -> void:
	_gameContext.userNavegando = !_gameContext.userNavegando


func _handle_pause_toggle() -> void:
	_gameContext.pause = !_gameContext.pause


func _handle_stop_working() -> void:
	_gameInput.ShowConsoleMessage("¡Has terminado de trabajar!", \
		GameAssets.FontDataList[Enums.FontTypeNames.FontType_Info])
	#TODO Completar
	#If frmMain.macrotrabajo.Enabled Then Call frmMain.DesactivarMacroTrabajo


func _HandleUpdateDexterity(p:UpdateDexterity) -> void:
	_gameInput.update_agility_label(p.dexterity)

	
func _HandleUpdateStrenght(p:UpdateStrenght) -> void:
	_gameInput.update_strength_label(p.strenght)


func _HandleUpdateGold(p:UpdateGold) -> void:
	if ClientInterface.world_state.has_money(): return
	_gameContext.player_gold = p.gold
	_gameInput.update_gold_label(p.gold)


func _HandleUpdateBankGold(p:UpdateBankGold) -> void:
	if ClientInterface.world_state.has_money(): return
	_gameInput.SetBankGold(p.gold)


func _handle_meditate_toggle() -> void:
	_gameContext.userMeditar = !_gameContext.userMeditar


func _handle_rest_ok() -> void:
	_gameContext.userDescansar = !_gameContext.userDescansar

func _handle_blind() -> void:
	_gameContext.userCiego = true

	
func _handle_blind_no_more() -> void:
	_gameContext.userCiego = false


func _handle_dumb() -> void:
	_gameContext.userEstupido = true


func _handle_dumb_no_more() -> void:
	_gameContext.userEstupido = false 


func _handle_paralize_ok() -> void:
	_gameContext.userParalizado = !_gameContext.userParalizado
	
func _handle_send_night(_p:SendNight) -> void:
	pass

func _handle_error_message(p:ErrorMsg) -> void:
	Utils.ShowAlertDialog("Server", p.message, get_tree().root)
	ClientInterface.DisconnectFromHost()


func _HandleChangeBankSlot(p:ChangeBankSlot) -> void:
	var item = Item.new()
	item.index = p.index
	item.name = p.name
	item.type = p.type
	item.maxHit = p.maxHit
	item.minHit = p.minHit
	item.maxDef = p.maxDef
	item.minDef = p.minDef
	item.salePrice = p.salePrice
	
	if p.grhId > 0:
		item.icon = GameAssets.GetTexture(GameAssets.GrhDataList[p.grhId].fileId)
	
	var itemStack = ItemStack.new(p.amount, false, item)
	_gameContext.bankInventory.SetSlot(p.slot -1, itemStack)


func _HandleCommerceInit() -> void:
	_gameInput.OpenMerchant()
	
func _HandleCommerceEnd() -> void:
	_gameInput.CloseMerchant()
	
func _HandleBankInit(p:BankInit) -> void:
	_gameInput.OpenBank()

func _HandleBankEnd() -> void:
	_gameInput.CloseBank()

func _HandleChangeNPCInventorySlot(p:ChangeNPCInventorySlot) -> void:
	var item = Item.new()
	item.index = p.index
	item.name = p.name
	item.type = p.type
	item.maxHit = p.maxHit
	item.minHit = p.minHit
	item.maxDef = p.maxDef
	item.minDef = p.minDef
	item.salePrice = p.salePrice
	
	if p.grhId > 0:
		item.icon = GameAssets.GetTexture(GameAssets.GrhDataList[p.grhId].fileId)
	
	var itemStack = ItemStack.new(p.amount, false, item)
	_gameContext.merchantInventory.SetSlot(p.slot -1, itemStack)
		
		
func _HandleChatOverHead(p:ChatOverHead) -> void:
	var character = _gameWorld.GetCharacter(p.charIndex)
	if character:
		character.Say(p.chat, p.color)
			
				
func _HandleUpdateTagAndStatus(p:UpdateTagAndStatus) -> void:
	var character = _gameWorld.GetCharacter(p.charIndex)
	if character:
		character.SetCharacterName(p.userTag)
		character.SetCharacterNameColor(Utils.GetNickColor(p.nickColor, character.priv))


func _HandlePosUpdate(p:PosUpdate) -> void:
	var character = _gameWorld.GetCharacter(_mainCharacterInstanceId)
	if character:
		character.StopMoving()
		character.gridPosition = Vector2i(p.x, p.y)
		character.position = Vector2((p.x - 1) * 32, (p.y - 1) * 32) + Vector2(16, 32);
		_gameInput.minimap.update_player_position(p.x, p.y)
		_map_ready = true
		_gameInput.InvalidateCrafting()


func _HandleForceCharMove(p:ForceCharMove) -> void:
	var character = _gameWorld.GetCharacter(_mainCharacterInstanceId)
	if character:
		character.StopMoving()
		_gameWorld.MoveCharacter(_mainCharacterInstanceId, p.heading)
		_gameInput.InvalidateCrafting()


func _HandleLogged(_p:Logged) -> void:
	pass


func _HandleCharacterChange(p:CharacterChange) -> void:
	var character = _gameWorld.GetCharacter(p.charIndex)
	if character == null: return
	
	character.renderer.body = p.body
	character.renderer.head = p.head
	character.renderer.helmet = p.helmet
	character.renderer.weapon = p.weapon
	character.renderer.shield = p.shield
	character.renderer.heading = p.heading
	
	
func _HandleUpdateHP(p:UpdateHP) -> void:
	_gameInput.health_stat_bar.value = p.hp
	_gameContext.player_stats.hp = p.hp
	if p.hp <= 0:
		_gameInput._restore_default_cursor()


func _HandleCharacterRemove(p:CharacterRemove) -> void:
	_visuals.remove_actor(p.charIndex)
	_gameWorld.DeleteCharacter(p.charIndex)


func _HandleRemoveCharDialog(p:RemoveCharDialog) -> void:
	var character = _gameWorld.GetCharacter(p.charIndex)
	if character:
		character.ClearDialog()


func _HandleConsoleMessage(p:ConsoleMessage) -> void:
	_gameInput.ShowConsoleMessage(p.message, GameAssets.FontDataList[p.fontIndex])


func _HandleUpdateSta(p:UpdateSta) -> void:
	_gameInput.stamina_stat_bar.value = p.stamina
	_gameContext.player_stats.sta = p.stamina

func _HandleRemoveDialogs() -> void:
	_gameWorld.GetMapContainer().ClearDialogs()

func _HandleLevelUp(p:LevelUp) -> void:
	GameProtocol.WriteRequestSkills()

func _HandleSendSkills(p:SendSkills) -> void:
	if not p.valid:
		ClientInterface._fail("Estado de habilidades inválido")
		return
	_gameInput._show_skills_window(p.skills)
	if is_instance_valid(_gameInput._skills_window):
		_gameInput._skills_window.ApplyProgressUpdate(p.skills)
	# Actualizar también la ventana de estadísticas si está abierta
	_gameInput.update_stats_skills(p.skills)

func _HandleAtributes(p:Atributes) -> void:
	# p.attributes: [Fuerza, Agilidad, Inteligencia, Carisma, Constitución]
	_gameInput.update_stats_attributes(p.attributes)

func _HandleFame(p:Fame) -> void:
	var fame = {
		"AsesinoRep": p.AsesinoRep,
		"BandidoRep": p.BandidoRep,
		"BurguesRep": p.BurguesRep,
		"LadronesRep": p.LadronesRep,
		"NobleRep": p.NobleRep,
		"PlebeRep": p.PlebeRep,
		"Promedio": p.Promedio,
	}
	_gameInput.update_stats_fame(fame)

func _HandleMiniStats(p:MiniStats) -> void:
	var mini_stats = {
		"CiudadanosMatados": p.CiudadanosMatados,
		"CriminalesMatados": p.CriminalesMatados,
		"UsuariosMatados": p.UsuariosMatados,
		"NpcsMatados": p.NpcsMatados,
		"Clase": p.Clase,
		"PenaCarcel": p.PenaCarcel,
	}
	_gameInput.update_stats_ministats(mini_stats)

				
func _HandleGuildChat(p:GuildChat) -> void:
	pass


func _HandleUpdateStrengthAndDexterity(p:UpdateStrengthAndDexterity) -> void:
	_gameInput.update_agility_label(p.dexterity)
	_gameInput.update_strength_label(p.strength)


func _HandleUpdateHungerAndThirst(p:UpdateHungerAndThirst) -> void: 
	_gameInput.hunger_stat_bar.max_value = p.maxHam
	_gameInput.hunger_stat_bar.value = p.minHam
	
	_gameInput.thirst_stat_bar.max_value = p.maxAgua
	_gameInput.thirst_stat_bar.value = p.minAgua
	
	
func _HandleUpdateUserStats(p:UpdateUserStats) -> void: 
	# Actualizar la interfaz
	if not ClientInterface.world_state.has_money():
		_gameInput.update_gold_label(p.gold)
	_gameInput.update_level_label(p.elv)
	
	_gameInput.experience_stat_bar.max_value = p.elu
	_gameInput.experience_stat_bar.value = p.experience
	
	_gameInput.health_stat_bar.max_value = p.maxHp
	_gameInput.health_stat_bar.value = p.minHp
	
	# Actualizar el contexto del juego
	_gameContext.player_level = p.elv
	if not ClientInterface.world_state.has_money():
		_gameContext.player_gold = p.gold
	_gameContext.player_experience = p.experience
	_gameContext.player_experience_to_next_level = p.elu
	
	_gameContext.player_stats.max_hp = p.maxHp
	_gameContext.player_stats.hp = p.minHp
	if p.minHp <= 0:
		_gameInput._restore_default_cursor()
	
	_gameInput.mana_stat_bar.max_value = p.maxMana
	_gameInput.mana_stat_bar.value = p.minMana
	
	_gameContext.player_stats.max_mana = p.maxMana
	_gameContext.player_stats.mana = p.minMana
	
	_gameInput.stamina_stat_bar.max_value = p.maxSta
	_gameInput.stamina_stat_bar.value = p.minSta
	
	_gameContext.player_stats.max_sta = p.maxSta
	_gameContext.player_stats.sta = p.minSta


func _HandleUserCharIndexInServer(p:UserCharIndexInServer) -> void:
	_mainCharacterInstanceId = p.charIndex
	var character = _gameWorld.GetCharacter(p.charIndex)
	
	if character:
		character.SetAsPlayer(true)  # Marcar este personaje como el del jugador
		_map_ready = true
		_gameInput.minimap.update_player_position(
			character.gridPosition.x,\
			 character.gridPosition.y)


func _HandleCreateFx(p:CreateFx) -> void:
	_gameWorld.PlayCharacterEffect(p.charIndex, p.fx, p.fxLoops)


func _HandleSetInvisible(p:SetInvisible) -> void:
	var character = _gameWorld.GetCharacter(p.charIndex)
	if character:
		character.SetCharacterInvisible(p.invisible)
				
func _HandleCharacterCreate(p:CharacterCreate) -> void:
	var privileges = p.privileges
	if privileges != 0:
		if (privileges & Enums.PlayerType.ChaosCouncil) != 0 && (privileges & Enums.PlayerType.User) == 0:
			privileges  = privileges ^ Enums.PlayerType.ChaosCouncil
		
		if (privileges & Enums.PlayerType.RoyalCouncil) != 0 && (privileges & Enums.PlayerType.User) == 0:
			privileges  = privileges ^ Enums.PlayerType.RoyalCouncil
		
		if (privileges & Enums.PlayerType.RoleMaster) != 0:
			privileges = Enums.PlayerType.RoleMaster
		
		privileges = log(privileges) / log(2)
		
	p.privileges = privileges
	var character := _gameWorld.CreateCharacter(p)
	if p.charIndex == _mainCharacterInstanceId:
		character.SetAsPlayer(true)
		_gameInput.minimap.update_player_position(p.x, p.y)
		_map_ready = true
	character.FadeIn()

func _HandleCharacterMove(p:CharacterMove) -> void:
	var character = _gameWorld.GetCharacter(p.charIndex)
	if character == null:
		return
		
	var addX = p.x - character.gridPosition.x
	var addY = p.y - character.gridPosition.y
	
	var heading = Enums.Heading.South
	if Utils.Sgn(addX) == 1:
		heading = Enums.Heading.East;
	elif Utils.Sgn(addX) == -1:
		heading = Enums.Heading.West;
	elif Utils.Sgn(addY) == 1:
		heading = Enums.Heading.South;
	elif Utils.Sgn(addY) == -1:
		heading = Enums.Heading.North;
		
	_gameWorld.MoveCharacter(p.charIndex, heading)

func _HandleBlockPosition(p:BlockPosition) -> void:
	if p.blocked:
		_gameWorld.GetMapContainer().BlockTile(p.x -1, p.y - 1)
	else:
		_gameWorld.GetMapContainer().UnblockTile(p.x -1, p.y - 1)


func _HandleObjectCreate(p:ObjectCreate) -> void:
	_gameWorld.AddObject(p.grhId, p.x, p.y)


func _HandleObjectDelete(p:ObjectDelete) -> void:
	_gameWorld.DeleteObject(p.x, p.y)


func _HandleAreaChanged(_p:AreaChanged) -> void:
	pass


func _HandlePlayMidi(p:PlayMidi) -> void:
	AudioManager.PlayMusic(p.midiId)
	
	
func _handle_show_signal(p:ShowSignal) -> void:
	pass
	
	
func _HandlePlayWave(p:PlayWave) -> void:
	AudioManager.PlayAudio(p.wave)


func _HandleChangeMap(p:ChangeMap) -> void:
	_gameInput._restore_default_cursor()
	_visuals.reset(p.mapId)
	AudioManager.StopAll()
	_gameInput.InvalidateCrafting()
	_map_ready = false
	_presentation.begin(p.mapId)
	if not _gameWorld.SwitchMap(p.mapId):
		ClientInterface._fail("No se pudo cargar el mapa %d." % p.mapId)
		return
	_gameContext.player_map = p.mapId
	_gameInput.minimap.load_thumbnail(p.mapId)
	if ClientInterface.capabilities.has_feature(ClientCapabilities.WORLD_STATE):
		GameProtocol.WriteWorldAction("weather.read", {})
		
		
func _HandleChangeSpellSlot(p:ChangeSpellSlot) -> void:
	_gameInput.spell_list_panel.set_slot_text(p.slot - 1, p.name, p.spellId) 


func _HandleChangeInventorySlot(p:ChangeInventorySlot) -> void:
	if p.slot < 1 or p.slot > _gameContext.playerInventory.GetSize():
		return
	var item = Item.new()
	item.index = p.index
	item.name = p.name
	item.type = p.type
	item.maxHit = p.maxHit
	item.minHit = p.minHit
	item.maxDef = p.maxDef
	item.minDef = p.minDef
	item.salePrice = p.salePrice
	
	if p.grhId > 0:
		item.icon = GameAssets.GetTexture(GameAssets.GrhDataList[p.grhId].fileId)
	
	var itemStack = ItemStack.new(p.amount, p.equipped, item)
	_gameContext.playerInventory.SetProtocolSlot(p.slot, itemStack)
	_gameInput.update_equipment_label(p.slot - 1, itemStack)

func _HandleMultiMessage(p:MultiMessage) -> void:
	match p.index:
		Enums.Messages.SafeModeOn:
			_gameInput.ShowConsoleMessage(">>SEGURO ACTIVADO<<", FontData.new(Color.GREEN, true))
		Enums.Messages.SafeModeOff:
			_gameInput.ShowConsoleMessage(">>SEGURO DESACTIVADO<<", FontData.new(Color.RED, true))
		Enums.Messages.ResuscitationSafeOn:
			_gameInput.ShowConsoleMessage("SEGURO DE RESURRECCION ACTIVADO", FontData.new(Color.GREEN, true))
		Enums.Messages.ResuscitationSafeOff:
			_gameInput.ShowConsoleMessage("SEGURO DE RESURRECCION DESACTIVADO", FontData.new(Color.RED, true))
		#Enums.Messages.DontSeeAnything:
		#	_gameInput.ShowConsoleMessage("No ves nada interesante.", FontData.new(Color.from_rgba8(65, 190, 156)))
		Enums.Messages.NPCSwing:
			_gameInput.ShowConsoleMessage("¡¡¡La criatura falló el golpe!!!", FontData.new(Color.RED, true))
		Enums.Messages.NPCKillUser:
			_gameInput.ShowConsoleMessage("¡¡¡La criatura te ha matado!!!", FontData.new(Color.RED, true))
		Enums.Messages.BlockedWithShieldUser:
			_gameInput.ShowConsoleMessage("¡¡¡Has rechazado el ataque con el escudo!!!", FontData.new(Color.RED, true))
		Enums.Messages.BlockedWithShieldother:
			_gameInput.ShowConsoleMessage("¡¡¡El usuario rechazó el ataque con su escudo!!!", FontData.new(Color.RED, true))
		Enums.Messages.UserSwing:
			_gameInput.ShowConsoleMessage("¡¡¡Has fallado el golpe!!!", FontData.new(Color.RED, true))
		Enums.Messages.NobilityLost:
			_gameInput.ShowConsoleMessage("¡Has perdido nobleza y ganado criminalidad! Sigue así y las tropas te perseguirán.", FontData.new(Color.RED))
		Enums.Messages.CantUseWhileMeditating:
			_gameInput.ShowConsoleMessage("¡Estás meditando! Debes dejar de meditar para usar objetos.", FontData.new(Color.RED))
		Enums.Messages.NPCHitUser:
			match p.arg1:
				Consts.bCabeza:
					_gameInput.ShowConsoleMessage("¡¡La criatura te ha pegado en la cabeza por " + str(p.arg2) + "!!", FontData.new(Color.RED, true))
				Consts.bBrazoIzquierdo:
					_gameInput.ShowConsoleMessage("¡¡La criatura te ha pegado el brazo izquierdo por " + str(p.arg2) + "!!", FontData.new(Color.RED, true))
				Consts.bBrazoDerecho:
					_gameInput.ShowConsoleMessage("¡¡La criatura te ha pegado el brazo derecho por " + str(p.arg2) + "!!", FontData.new(Color.RED, true))
				Consts.bPiernaIzquierda:
					_gameInput.ShowConsoleMessage("¡¡La criatura te ha pegado la pierna izquierda por " + str(p.arg2) + "!!", FontData.new(Color.RED, true))
				Consts.bPiernaDerecha:
					_gameInput.ShowConsoleMessage("¡¡La criatura te ha pegado la pierna derecha por " + str(p.arg2) + "!!", FontData.new(Color.RED, true))
				Consts.bTorso:
					_gameInput.ShowConsoleMessage("¡¡La criatura te ha pegado en el torso por " + str(p.arg2) + "!!", FontData.new(Color.RED, true))
		Enums.Messages.UserHitNPC:
			_gameInput.ShowConsoleMessage("¡¡Le has pegado a la criatura por " + str(p.arg1) + "!!", FontData.new(Color.RED, true))
		Enums.Messages.UserAttackedSwing:
			_gameInput.ShowConsoleMessage("¡¡ " + _gameWorld.GetCharacter(p.arg1).GetCharacterName() + " te atacó y falló!!", FontData.new(Color.RED, true))
		Enums.Messages.UserHittedByUser:
			var charName = _gameWorld.GetCharacter(p.arg1).GetCharacterName() 
			_gameInput.ShowConsoleMessage(Consts.MessageUserHittedByUser[p.arg2].format([charName, p.arg3]), FontData.new(Color.RED)) 
		Enums.Messages.UserHittedUser:
			var charName = _gameWorld.GetCharacter(p.arg1).GetCharacterName()
			_gameInput.ShowConsoleMessage(Consts.MessageUserHittedUser[p.arg2].format([charName, p.arg3]), FontData.new(Color.RED)) 
		Enums.Messages.WorkRequestTarget:
			_gameContext.usingSkill = p.arg1
			_gameInput.ShowConsoleMessage(Consts.MessageWorkRequestTarget[p.arg1], FontData.new(Color.from_rgba8(100, 100, 120)))
			# Asegurarse de que el mouse sea visible
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			
			# Usar cursor personalizado o del sistema según la configuración
			if Global.useCustomCursor and _crosshair_cursor:
				# Escalar el cursor si aún no lo hemos hecho
				if _scaled_crosshair_cursor == null:
					_scaled_crosshair_cursor = _scale_cursor(_crosshair_cursor, 0.1) # Factor de escala 0.5 (50% del tamaño original)
				
				# Usar el cursor escalado
				var cursor_to_use = _scaled_crosshair_cursor if _scaled_crosshair_cursor else _crosshair_cursor
				
				# Usar el centro de la imagen como punto de acción (hotspot)
				var image_size = cursor_to_use.get_size()
				var hotspot = Vector2(image_size.x / 2, image_size.y / 2)
				
				# Usar CURSOR_ARROW para evitar problemas con CURSOR_CROSS
				Input.set_custom_mouse_cursor(cursor_to_use, Input.CURSOR_ARROW, hotspot)
				print("Cursor personalizado activado. Tamaño: %s, Hotspot: %s" % [image_size, hotspot])
			else:
				# Usar cursor de puntería del sistema
				Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		Enums.Messages.HaveKilledUser:
			var charName = _gameWorld.GetCharacter(p.arg1).GetCharacterName()
			_gameInput.ShowConsoleMessage("Has matado a {0}!".format([charName]), FontData.new(Color.RED, true)) 
			_gameInput.ShowConsoleMessage("Has ganado {0} puntos de experiencia.".format([p.arg2]), FontData.new(Color.RED, true)) 
		Enums.Messages.UserKill:
			var charName = _gameWorld.GetCharacter(p.arg1).GetCharacterName()
			_gameInput.ShowConsoleMessage("{0} te ha matado!".format([charName]), FontData.new(Color.RED, true)) 
		Enums.Messages.Home:
			var distance = p.arg1
			var time = p.arg2
			var home = p.string_arg1
			var message = ""
			
			if time >= 60:
				if time % 60 == 0:
					message = "{0} minutos.".format([time / 60.0])
				else:
					message = "{0} minutos y {1} segundos.".format([int(time / 60.0), int(time % 60)]) 
			else:
				message = "{0} segundos.".format([time])
			_gameInput.ShowConsoleMessage("Te encuentras a {0} mapas de la {1}, este viaje durará {2}".format([distance, home, message]), FontData.new(Color.RED, true)) 
			_gameContext.traveling = true
		Enums.Messages.FinishHome:
			_gameInput.ShowConsoleMessage("Has llegado a tu hogar. El viaje ha finalizado.", FontData.new(Color.WHITE)) 
			_gameContext.traveling = false
		Enums.Messages.CancelHome:
			_gameInput.ShowConsoleMessage("Tu viaje ha sido cancelado.", FontData.new(Color.RED)) 
			_gameContext.traveling = false
	
func _FlushData() -> void:
	if !GameProtocol.IsEmpty(): 
		ClientInterface.Send(GameProtocol.Flush())

# Maneja la visualización de la ventana de alineación de gremio
func _HandleShowGuildAlign(show_guild_align) -> void:
	show_guild_align.handle()

# Maneja la visualización del formulario de fundación de gremio
func _HandleShowGuildFundationForm(show_guild_fundation_form) -> void:
	show_guild_fundation_form.handle()

#endregion


func _OnPingTimerTimeout() -> void:
	if _gameContext.pingTime != 0 or not ClientInterface.IsConnected(): return
	GameProtocol.WritePing()
	_FlushData()
	_gameContext.pingTime = maxi(1, Time.get_ticks_msec())
	Global.pingStatus = "Midiendo…"

func _OnSerializationFailed(message: String) -> void:
	_gameInput.ShowConsoleMessage(message, GameAssets.FontDataList[Enums.FontTypeNames.FontType_Warning] if GameAssets.FontDataList.size() > Enums.FontTypeNames.FontType_Warning else FontData.new(Color.YELLOW))

func _HandleVisualEvent(event: AOVisualEvent) -> void:
	_visuals.display(event, _gameWorld)


func _ApplyWorldState(value: Dictionary) -> void:
	if not ClientInterface.world_state.accept(value):
		return
	if value.kind == "chat":
		var chat: Dictionary = value.data
		var prefix: String = {"system": "", "public": "", "party": "[Grupo] ", "clan": "[Clan] ", "whisper": "[Privado] "}.get(chat.channel, "")
		if chat.channel == "whisper" and int(chat.sender_id) == _mainCharacterInstanceId:
			prefix += "A %s: " % chat.get("recipient_name", "destinatario")
		elif int(chat.sender_id) > 0:
			prefix += String(chat.sender) + (" grita: " if String(chat.context).ends_with(":yell") else ": ")
		var font := FontData.new(Color.WHITE)
		if int(chat.font) >= 0 and int(chat.font) < GameAssets.FontDataList.size(): font = GameAssets.FontDataList[int(chat.font)]
		_gameInput.ShowConsoleMessage(prefix + String(chat.text), font)
	if value.kind == "tax":
		Global.character_local.open_profile(ClientInterface.local_character_key(Global.username))
		if Global.character_local.remember_tax(String(value.data.receipt)) and int(value.data.last_charge) > 0:
			_gameInput.ShowConsoleMessage("Impuesto diario: se cobraron %d oro sobre bolsillo y banco, incluso desconectado." % int(value.data.last_charge))
		_gameContext.player_gold = int(value.data.wallet)
		_gameInput.update_gold_label(int(value.data.wallet))
		_gameInput.SetBankGold(int(value.data.bank))
	if value.kind == "weather" and _presentation != null:
		_presentation.apply_weather(value.data)
	if _gameInput.has_method("ApplyWorldState"):
		_gameInput.ApplyWorldState(value)
