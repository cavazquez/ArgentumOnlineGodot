extends Node

var failures := 0
var audio_results := []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("ITEM_POLISH: " + message)

func _ready() -> void:
	await get_tree().process_frame
	check(GameAssets.loaded, "Recursos obligatorios sin cargar")
	check(GameResourcesAudit.missing_resources().is_empty(), "Instalación incompleta")
	var login: Node = load("res://screens/login_screen.tscn").instantiate()
	add_child(login)
	for size in [Vector2i(800, 600), Vector2i(1024, 768)]:
		get_window().size = size
		await get_tree().process_frame
		await get_tree().process_frame
		var password: Control = login._loginPanel.get_node("%Password")
		var tls: Control = login.get_node("%UseTLS")
		var ca: Control = login.get_node("%CaPath")
		check(tls.get_global_rect().position.y >= password.get_global_rect().end.y, "TLS no está debajo de la contraseña")
		check(ca.get_global_rect().position.y >= tls.get_global_rect().end.y, "Certificado no está debajo de TLS")
		check(ca.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "Certificado fuera de la ventana")
	var real_audio := "--real-audio" in OS.get_cmdline_user_args()
	check(not real_audio or AudioServer.get_driver_name() == "PulseAudio", "El ensayo audible exige PulseAudio")
	if real_audio:
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 0.3
		AudioServer.add_bus_effect(0, capture)
		for track in [1, 2, 3]:
			AudioManager.PlayMusic(track)
			var energy := 0.0
			var peak := 0.0
			var samples := 0
			for _sample in range(15):
				await get_tree().create_timer(0.1).timeout
				var buffer := capture.get_buffer(capture.get_frames_available())
				for frame in buffer:
					peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
					energy += frame.x * frame.x + frame.y * frame.y
					samples += 2
			check(samples > 1000 and peak > 0.001, "Pista %d sin salida de audio medible" % track)
			audio_results.append({"track": track, "samples": samples, "peak": peak, "rms": sqrt(energy / max(1, samples))})
		AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	else:
		AudioManager.PlayIntroduction()
		check(AudioManager._track == AudioManager.INTRO_TRACK, "No inicia la música de introducción")
	AudioManager.BeginGame()
	check(AudioManager._track == 0, "La introducción continúa al entrar sin música de mapa")
	login.free()
	await _equipment_slots()
	var state := {"id": "a".repeat(32), "item": 2, "version": 1, "created": 100, "expires": 200, "uses": 9, "max_uses": 10, "condition": 1000, "factor": 5500, "broken": false, "base": {"MinHit": 10}, "effective": {"MinHit": 6}}
	var text := ItemCondition.describe(state)
	check(text.contains("10.00") and text.contains("10 → 6") and text.contains("UTC") and text.contains("1 / 10"), "Descripción incompleta del ejemplar")
	var context := WorldStateContext.new()
	var frame := {"epoch": "b".repeat(32), "sequence": 1, "kind": "items", "revision": "1", "id": "", "data": {"scope": "inventory", "page": 0, "clock": 100, "rows": [[1, state]]}}
	check(WorldStatePacket._payload("items", frame.data), "Rechazó estado individual válido")
	check(context.accept(frame), "No aceptó estado individual")
	check(context.item_states.inventory[1].id == state.id, "Perdió la identidad del ejemplar")
	frame.sequence = 1
	frame.data.rows[0][1].version = 0
	check(not context.accept(frame), "Aceptó estado de una secuencia vieja")
	context.clear()
	check(context.item_states.is_empty(), "Retuvo equipo de otra conexión")
	AudioManager.StopAll()
	await get_tree().create_timer(0.2).timeout
	var output := OS.get_environment("PYAO_POLISH_EVIDENCE")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"failures": failures, "driver": AudioServer.get_driver_name(), "tracks": audio_results}, "  "))
	print("ITEM_POLISH: failures=", failures, " audio=", audio_results)
	get_tree().quit(1 if failures else 0)

func _equipment_slots() -> void:
	var controls := Control.new()
	add_child(controls)
	var panel := EquipmentPanel.new()
	panel.size = Vector2(203, 216)
	controls.add_child(panel)
	var bag := Inventory.new(30)
	panel.setup(bag)
	var backpack := InventoryContainer.new()
	backpack.columns = 5
	backpack.hide_equipped = true
	backpack.allow_reorder = true
	controls.add_child(backpack)
	backpack.SetInventory(bag)
	var bank_inventory := InventoryContainer.new()
	controls.add_child(bank_inventory)
	bank_inventory.SetInventory(bag)
	var requests: Array[int] = []
	panel.equip_requested.connect(func(index: int): requests.append(index))
	var activations: Array[int] = []
	backpack.slotActivated.connect(func(index: int): activations.append(index))
	var uses: Array[int] = []
	panel.use_requested.connect(func(index: int): uses.append(index))
	check(panel.buttons.size() == 6 and not panel.buttons.has("head"), "Ranuras incompletas o rostro equipable")
	for row in [[2, "weapon"], [3, "armor"], [17, "helmet"], [16, "shield"], [36, "boots"], [18, "accessory"]]:
		var item := Item.new()
		item.index = row[0]
		item.type = row[0]
		item.name = "Pieza " + row[1]
		var stack := ItemStack.new(1, false, item)
		stack.instance_state = {"id": str(row[0]).sha256_text().substr(0, 32), "condition": 10000, "max_uses": 0, "uses": 0, "created": 100, "expires": 0, "base": {}, "effective": {}, "broken": false}
		bag.SetSlot(0, stack)
		check(backpack.GetInventorySlot(0).visible and not panel.slots.has(row[1]), "Pieza sin equipar fuera de la mochila o en el equipo")
		var drag := {"kind": "pyao_player_inventory", "inventory": bag.get_instance_id(), "source": 0}
		check(panel.can_equip_drop(row[1], drag), "Rechazó su tipo de equipo")
		check(not panel.can_equip_drop("head", drag), "Admitió una ranura de rostro")
		check(not panel.can_equip_drop("boots" if row[1] != "boots" else "weapon", drag), "Admitió una pieza en la ranura incorrecta")
		panel.request_slot(0, row[1])
		check(not panel.slots.has(row[1]) and backpack.GetInventorySlot(0).visible, "Movió la pieza antes de confirmar el servidor")
		backpack._InventorySlotOnPressed(0)
		stack.equipped = true
		bag.SetSlot(0, stack)
		check(panel.slots.get(row[1], -1) == 0, "No actualizó la ranura confirmada")
		check(not backpack.GetInventorySlot(0).visible and backpack.GetSelectedSlot() == -1, "Equipo duplicado o seleccionado en la mochila")
		check(bank_inventory.GetInventorySlot(0).visible, "El filtro de mochila alteró el inventario del banco")
		check(backpack.CreateDragData(0) == null and not backpack.CanDropItem(0, drag), "Reordenó una ranura reservada al equipo")
		backpack._InventorySlotOnPressed(0)
		backpack.GetInventorySlot(0).activated.emit()
		check(backpack.GetSelectedSlot() == -1, "Seleccionó una pieza que ya está equipada")
		check(activations.is_empty(), "Activó una pieza oculta de la mochila")
	check(requests.size() == 6, "No envió las seis solicitudes tipadas")
	panel.buttons.boots.pressed.emit()
	await get_tree().process_frame
	check(panel.choice_buttons.is_empty(), "Selector vacío permite equipar otra categoría")
	panel.close_choices()
	panel.buttons.accessory.pressed.emit()
	await get_tree().process_frame
	bag.SetSlot(0, ItemStack.new())
	panel._choose(0)
	panel.close_choices()
	check(requests.size() == 6, "Aceptó una opción obsoleta del selector")
	# Reemplazar una pieza y quitarla conserva la identidad y los índices reales.
	var sword := Item.new()
	sword.index = 2
	sword.type = 2
	sword.name = "Espada"
	var old := ItemStack.new(1, true, sword)
	old.instance_state = {"id": "a".repeat(32), "condition": 10000, "max_uses": 0, "uses": 0, "created": 100, "expires": 0, "base": {}, "effective": {}, "broken": false}
	var replacement := ItemStack.new(1, false, sword)
	replacement.instance_state = old.instance_state.duplicate(true)
	replacement.instance_state.id = "b".repeat(32)
	bag.SetSlot(3, old)
	bag.SetSlot(29, replacement)
	panel.buttons.weapon.pressed.emit()
	panel.choice_buttons[29].pressed.emit()
	check(panel.slots.weapon == 3 and backpack.GetInventorySlot(29).visible, "Reemplazo optimista antes de la confirmación")
	old.equipped = false
	bag.SetSlot(3, old)
	replacement.equipped = true
	bag.SetSlot(29, replacement)
	check(panel.slots.weapon == 29 and backpack.GetInventorySlot(3).visible and not backpack.GetInventorySlot(29).visible, "No devolvió la pieza anterior a la mochila")
	panel.buttons.weapon.pressed.emit()
	panel.use_buttons[29].pressed.emit()
	check(uses == [29] and panel.slots.weapon == 29 and not backpack.GetInventorySlot(29).visible, "Usar equipo lo movió a la mochila o emitió el slot equivocado")
	var drag = backpack.CreateDragData(3)
	check(drag.source == 3 and backpack.CanDropItem(28, drag), "El filtro cambió los índices de protocolo")
	check(backpack.CreateDragData(29) == null and not backpack.CanDropItem(29, drag), "La mochila permite arrastrar o pisar una pieza equipada")
	var moves: Array = []
	backpack.reorder_handler = func(source, destination): moves.append([source, destination])
	backpack.DropItem(28, drag)
	check(moves == [[4, 29]] and bag.GetSlot(3) == old, "Reordenar no respetó los slots originales o mutó antes de confirmar")
	var first := backpack.GetInventorySlot(28)
	check(first.find_next_valid_focus() != backpack.GetInventorySlot(29), "La navegación por teclado apunta a equipo oculto")
	check(not backpack.is_ancestor_of(first.find_next_valid_focus()), "Tab queda encerrado en la mochila")
	panel.buttons.weapon.pressed.emit()
	panel.choice_buttons[29].pressed.emit()
	check(panel.slots.weapon == 29 and not backpack.GetInventorySlot(29).visible, "Quitó equipo antes de recibir confirmación")
	replacement.equipped = false
	bag.SetSlot(29, replacement)
	check(not panel.slots.has("weapon") and backpack.GetInventorySlot(29).visible and bag.GetSlot(29).instance_state.id == "b".repeat(32), "Desequipar no devolvió el mismo ejemplar a la mochila")
	panel._use_choice(29)
	check(uses == [29], "Usó una pieza que ya no está equipada")
	backpack.SetInventory(bag)
	check(backpack.GetInventorySlot(3).visible and backpack.GetInventorySlot(29).visible and panel.slots.is_empty(), "Reconstruir la mochila perdió piezas o duplicó equipo")
	await get_tree().process_frame
	check(panel.get_combined_minimum_size().x <= 203 and panel.get_combined_minimum_size().y <= 216, "Ranuras fuera del panel de 800×600")
	panel.free()
	backpack.free()
	bank_inventory.free()
	controls.free()
