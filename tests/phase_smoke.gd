extends Node

var _failed := false

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error("PHASE_SMOKE: " + message)

func _ready() -> void:
	Engine.max_fps = 120
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	# El dispatcher puede probarse sin instanciar GameScreen ni una sesión.
	var decoder := AOMessageDispatcher.new()
	var received := []
	decoder.message_decoded.connect(func(handler, payload, has_payload): received.append([handler, payload, has_payload]))
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/fixtures.json"))
	for fixture in fixtures:
		if fixture.name not in ["logged", "visual_damage", "projectile_explicit_endpoints"]: continue
		decoder.dispatch(String(fixture.hex).hex_decode())
	_check(received.size() == 3, "No se decodificaron los tres mensajes independientes")
	if received.size() != 3:
		get_tree().quit(1)
		return
	_check(received[0][0] == &"_HandleLogged", "Logged=0 dejó de despacharse")
	_check(received[1][1].valid and received[1][1].amount == 20, "Daño visual no coincide con la fixture")
	_check(received[2][1].valid and received[2][1].source == 7 and received[2][1].target == 8, "Se mezclaron extremos del proyectil")
	var ping_game := GameScreen.new()
	ping_game._gameContext.pingTime = 1000
	ping_game._HandlePong(1042)
	_check(Global.pingStatus == "42 ms", "RTT no mide el reloj monotónico")
	ping_game._gameContext.pingTime = 2000
	ping_game._UpdatePingStatus(8000)
	_check(Global.pingStatus == "Sin respuesta" and ping_game._gameContext.pingTime == 2000, "El timeout abrió una medición ambigua")
	ping_game._HandlePong(8050)
	_check(Global.pingStatus == "Sin respuesta" and ping_game._gameContext.pingTime == 0, "Pong tardío produjo un RTT engañoso")
	ping_game._HandlePong(8051)
	_check(Global.pingStatus == "Sin respuesta", "Pong sin petición actualizó la UI")
	ping_game.free()
	# Reasignar un dispositivo conserva los demás, y restaurar recupera el preset.
	var original := InputMap.action_get_events(&"Attack").duplicate(true)
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	_check(InputBindings.assign(&"Attack", joy) == OK, "No se guardó gamepad")
	_check(InputMap.action_get_events(&"Attack").size() == original.size() + 1, "Reasignar gamepad perdió las teclas")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	_check(not InputBindings.conflicts(&"Attack", key).is_empty(), "No se detectó conflicto con equipar")
	_check(InputBindings.decode({"type":"joy_button", "button":-1}) == null, "Se aceptó un botón inválido")
	_check(InputBindings.restore(&"Attack") == OK, "No se restauró el preset")
	_check(InputMap.action_get_events(&"Attack").size() == original.size(), "Restauración incompleta")
	# El mismo slot deja de mostrar información vieja al vaciarse.
	var slot: InventorySlot = load("res://ui/hub/inventory_slot.tscn").instantiate()
	add_child(slot)
	var item := Item.new()
	item.index = 139
	item.name = "Pescado"
	var stack := ItemStack.new(2, false, item)
	slot.SetDescription(stack)
	_check(slot.tooltip_text.contains("Pescado") and slot.tooltip_text.contains("2"), "Tooltip incompleto")
	stack.quantity = 0
	slot.SetDescription(stack)
	_check(slot.tooltip_text.is_empty(), "Tooltip de un slot vacío")
	slot.queue_free()
	# Las cantidades rápidas se reconstruyen al cambiar el stock y nunca lo exceden.
	var merchant := MerchantPanel.new()
	add_child(merchant)
	var inventory := Inventory.new(30)
	merchant.SetMerchantInventory(inventory)
	merchant.SetPlayerInventory(Inventory.new(30))
	item.salePrice = 8
	for count in [0, 1, 99, 100, 101, 32767]:
		inventory.SetSlot(0, ItemStack.new(count, false, item))
		merchant._Select(0, "buy")
		_check(merchant._quantitySpinBox.max_value == maxi(1, count), "Stock y máximo divergen")
		var labels := {}
		for button in merchant._quick.get_children():
			_check(not labels.has(button.text), "Presets duplicados")
			labels[button.text] = true
		_check((count == 0) == labels.is_empty(), "Presets inválidos para stock cero")
	merchant.queue_free()
	# Cambios repetidos de apariencia no acumulan offset de cabeza/casco.
	var character: Character = load("res://engine/character/character.tscn").instantiate()
	add_child(character)
	character.renderer.body = 1
	character.renderer.head = 1
	character.renderer.helmet = 1
	var head := character.renderer._headAnimatedSprite.position
	var helmet := character.renderer._helmetAnimatedSprite.position
	for i in range(5):
		character.renderer.body = Consts.CuerpoFragataFantasmal
		character.renderer.head = Consts.CabezaCasper
		character.renderer.body = 1
		character.renderer.head = 1
	_check(character.renderer._headAnimatedSprite.position == head and character.renderer._helmetAnimatedSprite.position == helmet, "La cabeza o el casco acumulan desplazamiento")
	character.queue_free()
	# Bounded damage nodes, de-duplicación por recibo, limpieza al cambiar de mapa.
	var visual := CombatVisuals.new()
	add_child(visual)
	visual.reset(2)
	var event = received[1][1]
	for i in range(100):
		event.event_id = str(i)
		visual.display(event, null)
	_check(visual.get_child_count() <= CombatVisuals.MAX_NODES, "Demasiados nodos de daño")
	var count := visual.get_child_count()
	visual.display(event, null)
	_check(visual.get_child_count() == count, "Evento visual duplicado")
	visual.remove_actor(event.actor)
	await get_tree().process_frame
	_check(visual.get_child_count() == 0, "Textos de un actor retirado permanecen activos")
	for id in [1, 7, 15]:
		var projectile = received[2][1]
		projectile.asset = id
		projectile.kind = 1
		var sprite := visual._projectile_sprite(projectile)
		_check(sprite is AnimatedSprite2D, "Proyectil mágico sin su FX propio")
		if sprite: sprite.free()
	var arrow_event = received[2][1]
	arrow_event.asset = 752
	arrow_event.kind = 2
	var arrow := visual._projectile_sprite(arrow_event)
	_check(arrow is Sprite2D, "Munición sin su gráfico propio")
	if arrow: arrow.free()
	visual.reset(3)
	await get_tree().process_frame
	_check(visual.get_child_count() == 0, "Efectos de otro mapa permanecen activos")
	visual.queue_free()
	# Una voz no superpuesta, música reemplazable y limpieza completa de audio.
	AudioManager.StopAll()
	AudioManager.PlayAudio(25, true)
	AudioManager.PlayAudio(25, true)
	_check(AudioManager.get_child_count() == 1, "El sonido protegido se superpone")
	AudioManager.PlayAudio(25, false)
	_check(AudioManager.get_child_count() == 2, "Se perdió la superposición solicitada")
	AudioManager.PlayMusic(1)
	var first = AudioManager._music
	AudioManager.PlayMusic(1)
	_check(AudioManager._music == first, "La misma pista creó otro reproductor")
	AudioManager.PlayMusic(2)
	await get_tree().process_frame
	_check(AudioManager._track == 2 and AudioManager._music.stream.loop, "La música no cambió o perdió loop")
	AudioManager.StopAll()
	var deadline := Time.get_ticks_msec() + 3000
	while not AudioManager.IsDrained() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout
	_check(AudioManager.IsDrained(), "Audio retenido después de desconectar")
	if not _failed: print("PHASE_SMOKE: PASS")
	get_tree().quit(1 if _failed else 0)
