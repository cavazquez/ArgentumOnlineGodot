extends RefCounted
class_name AOMessageDispatcher

signal message_decoded(handler: StringName, payload: Variant, has_payload: bool)
signal protocol_error(message: String)

const Atributes = preload("res://network/commands/Atributes.gd")
const MiniStats = preload("res://network/commands/MiniStats.gd")
const Fame = preload("res://network/commands/Fame.gd")

func dispatch(data: PackedByteArray) -> void:
	if data.is_empty():
		protocol_error.emit("Paquete vacío")
		return
	var stream := StreamPeerBuffer.new()
	stream.data_array = data
	dispatch_stream(stream)

func _emit(handler: StringName, payload: Variant = null, has_payload: bool = true) -> void:
	message_decoded.emit(handler, payload, has_payload)

func dispatch_stream(stream: StreamPeerBuffer) -> void:
	var packetId = stream.get_u8()
	if packetId == 248:
		var state := WorldStatePacket.new(stream)
		if not state.valid:
			protocol_error.emit("Estado de interfaz inválido")
			return
		_emit(&"_ApplyWorldState", state.data)
		return
	if packetId in [246, 247]:
		var visual := AOVisualEvent.new(packetId, stream)
		if not visual.valid:
			protocol_error.emit("Evento visual inválido")
			return
		_emit(&"_HandleVisualEvent", visual)
		return
	if packetId == 255:
		var action := SkillActionState.new(stream)
		if not action.valid:
			protocol_error.emit("Respuesta de habilidad inválida")
			return
		_emit(&"_ApplySkillAction", action.data)
		return
	if packetId == 253:
		var password_result := PasswordChangeReply.new(stream)
		if not password_result.valid:
			protocol_error.emit("Respuesta de contraseña inválida")
			return
		_emit(&"_ApplyPasswordReply", password_result)
		return
	if packetId == 254:
		var allocation := SkillAllocationState.new(stream)
		if not allocation.valid:
			protocol_error.emit("Asignación de habilidades inválida")
			return
		_emit(&"_ApplySkillAllocation", allocation)
		return
	if packetId == 252:
		var trade := TradeSnapshot.new(stream)
		if not trade.valid:
			protocol_error.emit("Estado de intercambio inválido")
			return
		_emit(&"_ApplyTradeSnapshot", trade.data)
		return
	if packetId == 251:
		var update := SkillCatalogPacket.new(stream)
		if not update.valid:
			protocol_error.emit("Catálogo de habilidades inválido")
			return
		_emit(&"_ApplySkillCatalog", update)
		return
	var pname = ""
	if packetId < Enums.ServerPacketID.keys().size():
		pname = Enums.ServerPacketID.keys()[packetId]
	else:
		pname = "Paquete desconocido"
		print("[DEBUG] Paquete no reconocido recibido. ID: ", packetId, " (0x", "%02X" % packetId, ")")
		return
		
	match packetId:
		Enums.ServerPacketID.MultiMessage:
			_emit(&"_HandleMultiMessage", MultiMessage.new(stream))
		Enums.ServerPacketID.ChangeInventorySlot:
			_emit(&"_HandleChangeInventorySlot", ChangeInventorySlot.new(stream))
		Enums.ServerPacketID.ChangeSpellSlot:
			_emit(&"_HandleChangeSpellSlot", ChangeSpellSlot.new(stream))
		Enums.ServerPacketID.UserIndexInServer:
			UserIndexInServer.new(stream)
		Enums.ServerPacketID.ChangeMap:
			_emit(&"_HandleChangeMap", ChangeMap.new(stream))
		Enums.ServerPacketID.PlayMIDI:
			_emit(&"_HandlePlayMidi", PlayMidi.new(stream))
		Enums.ServerPacketID.ShowGuildAlign:
			_emit(&"_ShowGuildAlignment", null, false)
		Enums.ServerPacketID.ShowGuildFundationForm:
			_emit(&"_ShowGuildFoundation", null, false)
		Enums.ServerPacketID.PlayWave:
			_emit(&"_HandlePlayWave", PlayWave.new(stream))
		Enums.ServerPacketID.AreaChanged:
			_emit(&"_HandleAreaChanged", AreaChanged.new(stream))
		Enums.ServerPacketID.ObjectCreate:
			_emit(&"_HandleObjectCreate", ObjectCreate.new(stream))
		Enums.ServerPacketID.ObjectDelete:
			_emit(&"_HandleObjectDelete", ObjectDelete.new(stream))
		Enums.ServerPacketID.BlockPosition:
			_emit(&"_HandleBlockPosition", BlockPosition.new(stream))
		Enums.ServerPacketID.CharacterCreate:
			_emit(&"_HandleCharacterCreate", CharacterCreate.new(stream))
		Enums.ServerPacketID.CharacterMove:
			_emit(&"_HandleCharacterMove", CharacterMove.new(stream))
		Enums.ServerPacketID.SetInvisible:
			_emit(&"_HandleSetInvisible", SetInvisible.new(stream))
		Enums.ServerPacketID.CreateFX:
			_emit(&"_HandleCreateFx", CreateFx.new(stream))
		Enums.ServerPacketID.UserCharIndexInServer:
			_emit(&"_HandleUserCharIndexInServer", UserCharIndexInServer.new(stream))
		Enums.ServerPacketID.UpdateUserStats:
			_emit(&"_HandleUpdateUserStats", UpdateUserStats.new(stream))
		Enums.ServerPacketID.Atributes:
			_emit(&"_HandleAtributes", Atributes.new(stream))
		Enums.ServerPacketID.UpdateHungerAndThirst:
			_emit(&"_HandleUpdateHungerAndThirst", UpdateHungerAndThirst.new(stream))
		Enums.ServerPacketID.UpdateStrenghtAndDexterity:
			_emit(&"_HandleUpdateStrengthAndDexterity", UpdateStrengthAndDexterity.new(stream))
		Enums.ServerPacketID.GuildDetails:
			var clan := ClanDetailsPacket.new(stream)
			if not clan.valid:
				protocol_error.emit("Detalles del clan inválidos")
				return
			_emit(&"_ApplyClanDetails", clan.values)
		Enums.ServerPacketID.GuildChat:
			_emit(&"_HandleGuildChat", GuildChat.new(stream))
		Enums.ServerPacketID.SendSkills:
			_emit(&"_HandleSendSkills", SendSkills.new(stream))
		Enums.ServerPacketID.Fame:
			_emit(&"_HandleFame", Fame.new(stream))
		Enums.ServerPacketID.MiniStats:
			_emit(&"_HandleMiniStats", MiniStats.new(stream))
		Enums.ServerPacketID.LevelUp:
			_emit(&"_HandleLevelUp", LevelUp.new(stream))
		Enums.ServerPacketID.Logged:
			_emit(&"_HandleLogged", Logged.new(stream))
		Enums.ServerPacketID.RainToggle:
			pass
		Enums.ServerPacketID.RemoveDialogs:
			_emit(&"_HandleRemoveDialogs", null, false)
		Enums.ServerPacketID.UpdateSta:
			_emit(&"_HandleUpdateSta", UpdateSta.new(stream))
		Enums.ServerPacketID.ConsoleMsg:
			_emit(&"_HandleConsoleMessage", ConsoleMessage.new(stream))
		Enums.ServerPacketID.RemoveCharDialog:
			_emit(&"_HandleRemoveCharDialog", RemoveCharDialog.new(stream))
		Enums.ServerPacketID.CharacterRemove:
			_emit(&"_HandleCharacterRemove", CharacterRemove.new(stream))
		Enums.ServerPacketID.UpdateHP:
			_emit(&"_HandleUpdateHP", UpdateHP.new(stream))
		Enums.ServerPacketID.CharacterChange:
			_emit(&"_HandleCharacterChange", CharacterChange.new(stream))
		Enums.ServerPacketID.ForceCharMove:
			_emit(&"_HandleForceCharMove", ForceCharMove.new(stream))
		Enums.ServerPacketID.PosUpdate:
			_emit(&"_HandlePosUpdate", PosUpdate.new(stream))
		Enums.ServerPacketID.UpdateTagAndStatus:
			_emit(&"_HandleUpdateTagAndStatus", UpdateTagAndStatus.new(stream))
		Enums.ServerPacketID.ChatOverHead:
			_emit(&"_HandleChatOverHead", ChatOverHead.new(stream))
		Enums.ServerPacketID.ChangeNPCInventorySlot:
			_emit(&"_HandleChangeNPCInventorySlot", ChangeNPCInventorySlot.new(stream))
		Enums.ServerPacketID.CommerceInit:
			_emit(&"_HandleCommerceInit", null, false)
		Enums.ServerPacketID.CommerceEnd:
			_emit(&"_HandleCommerceEnd", null, false)
		Enums.ServerPacketID.TradeOK:
			pass
		Enums.ServerPacketID.BankOK:
			pass
		Enums.ServerPacketID.Blind:
			_emit(&"_handle_blind", null, false)
		Enums.ServerPacketID.BlindNoMore:
			_emit(&"_handle_blind_no_more", null, false)
		Enums.ServerPacketID.RestOK:
			_emit(&"_handle_rest_ok", null, false)
		Enums.ServerPacketID.Dumb:
			_emit(&"_handle_dumb", null, false)
		Enums.ServerPacketID.DumbNoMore:
			_emit(&"_handle_dumb_no_more", null, false)
		Enums.ServerPacketID.UserCommerceInit:
			_emit(&"_handle_user_commerce_init", UserCommerceInit.new(stream))
		Enums.ServerPacketID.UserCommerceEnd:
			_emit(&"_handle_commerce_end", null, false)
		Enums.ServerPacketID.UserOfferConfirm:
			_emit(&"_handle_user_offer_confirm", null, false)
		Enums.ServerPacketID.CommerceChat:
			_emit(&"_handle_commerce_chat", CommerceChat.new(stream))
		Enums.ServerPacketID.CancelOfferItem:
			_emit(&"_handle_cancel_offer_item", CancelOfferItem.new(stream))
		Enums.ServerPacketID.ParalizeOK:
			_emit(&"_handle_paralize_ok", null, false)
		Enums.ServerPacketID.SendNight:
			_emit(&"_handle_send_night", SendNight.new(stream))
		Enums.ServerPacketID.ErrorMsg:
			_emit(&"_handle_error_message", ErrorMsg.new(stream))
		Enums.ServerPacketID.ChangeBankSlot:
			_emit(&"_HandleChangeBankSlot", ChangeBankSlot.new(stream))
		Enums.ServerPacketID.BankInit:
			_emit(&"_HandleBankInit", BankInit.new(stream))
		Enums.ServerPacketID.BankEnd:
			_emit(&"_HandleBankEnd", null, false)
		Enums.ServerPacketID.UpdateBankGold:
			_emit(&"_HandleUpdateBankGold", UpdateBankGold.new(stream))
		Enums.ServerPacketID.UpdateGold:
			_emit(&"_HandleUpdateGold", UpdateGold.new(stream))
		Enums.ServerPacketID.UpdateStrenght:
			_emit(&"_HandleUpdateStrenght", UpdateStrenght.new(stream))
		Enums.ServerPacketID.UpdateDexterity:
			_emit(&"_HandleUpdateDexterity", UpdateDexterity.new(stream))
		Enums.ServerPacketID.Pong:
			_emit(&"_HandlePong", null, false)
		Enums.ServerPacketID.ShowMessageBox:
			_emit(&"_HandleShowMessageBox", ShowMessageBox.new(stream))
		Enums.ServerPacketID.UpdateExp:
			_emit(&"_HandelUpdateExp", UpdateExp.new(stream))
		Enums.ServerPacketID.MeditateToggle:
			_emit(&"_handle_meditate_toggle", null, false)
		Enums.ServerPacketID.UpdateMana:
			_emit(&"_handle_update_mana", UpdateMana.new(stream))
		Enums.ServerPacketID.NavigateToggle:
			_emit(&"_handle_navigate_toggle", null, false)
		Enums.ServerPacketID.PauseToggle:
			_emit(&"_handle_pause_toggle", null, false)
		Enums.ServerPacketID.StopWorking:
			_emit(&"_handle_stop_working", null, false)
		Enums.ServerPacketID.ShowBlacksmithForm:
			_emit(&"_handle_show_blacksmith_form", null, false)
		Enums.ServerPacketID.ShowCarpenterForm:
			_emit(&"_handle_show_carpenter_form", null, false)
		Enums.ServerPacketID.CarpenterObjects:
			_emit(&"_handle_carpenter_objects", CarpenterObjects.new(stream))
		Enums.ServerPacketID.BlacksmithWeapons:
			_emit(&"_handle_blacksmith_weapons", BlacksmithWeapons.new(stream))
		Enums.ServerPacketID.BlacksmithArmors:
			_emit(&"_handle_blacksmith_armors", BlacksmithArmors.new(stream))
		Enums.ServerPacketID.CharacterChangeNick:
			_emit(&"_handle_character_change_nick", CharacterChangeNick.new(stream))
		_:
			print(pname)
	

