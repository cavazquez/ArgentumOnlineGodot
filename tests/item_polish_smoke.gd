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
	var panel := EquipmentPanel.new()
	panel.size = Vector2(203, 216)
	add_child(panel)
	var bag := Inventory.new(30)
	panel.setup(bag)
	var requests: Array[int] = []
	panel.equip_requested.connect(func(index: int): requests.append(index))
	check(panel.buttons.size() == 6 and not panel.buttons.has("head"), "Ranuras incompletas o rostro equipable")
	for row in [[2, "weapon"], [3, "armor"], [17, "helmet"], [16, "shield"], [36, "boots"], [18, "accessory"]]:
		var item := Item.new()
		item.index = row[0]
		item.type = row[0]
		item.name = "Pieza " + row[1]
		var stack := ItemStack.new(1, false, item)
		stack.instance_state = {"id": str(row[0]).sha256_text().substr(0, 32), "condition": 10000, "max_uses": 0, "uses": 0, "created": 100, "expires": 0, "base": {}, "effective": {}, "broken": false}
		bag.SetSlot(0, stack)
		var drag := {"kind": "pyao_player_inventory", "inventory": bag.get_instance_id(), "source": 0}
		check(panel.can_equip_drop(row[1], drag), "Rechazó su tipo de equipo")
		check(not panel.can_equip_drop("head", drag), "Admitió una ranura de rostro")
		check(not panel.can_equip_drop("boots" if row[1] != "boots" else "weapon", drag), "Admitió una pieza en la ranura incorrecta")
		panel.request_slot(0, row[1])
		check(not panel.slots.has(row[1]), "Equipó antes de confirmar el servidor")
		stack.equipped = true
		bag.SetSlot(0, stack)
		check(panel.slots.get(row[1], -1) == 0, "No actualizó la ranura confirmada")
	check(requests.size() == 6, "No envió las seis solicitudes tipadas")
	panel.buttons.boots.pressed.emit()
	await get_tree().process_frame
	check(panel.choices.item_count == 1 and panel.choices.is_item_disabled(0), "Selector vacío permite equipar otra categoría")
	panel.choices.hide()
	panel.buttons.accessory.pressed.emit()
	await get_tree().process_frame
	bag.SetSlot(0, ItemStack.new())
	panel.choices.id_pressed.emit(0)
	panel.choices.hide()
	check(requests.size() == 6, "Aceptó una opción obsoleta del selector")
	await get_tree().process_frame
	check(panel.get_combined_minimum_size().x <= 203 and panel.get_combined_minimum_size().y <= 216, "Ranuras fuera del panel de 800×600")
	panel.free()
