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
	var controls := ControlsWindow.new()
	add_child(controls)
	controls.popup_centered()
	await get_tree().process_frame
	var previous_file := FileAccess.get_file_as_string(InputBindings.PATH)
	controls._action = &"Attack"
	InputBindings.capturing = true
	key.pressed = true
	controls._input(key)
	_check(controls._confirmation.visible and controls._confirmation.dialog_text.contains("Equipar objeto"), "La colisión no se mostró antes de aplicar")
	controls._confirmation.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	_check(FileAccess.get_file_as_string(InputBindings.PATH) == previous_file, "Cancelar una colisión modificó los controles")
	controls._action = &"Attack"
	InputBindings.capturing = true
	var replacement := InputEventKey.new()
	replacement.physical_keycode = KEY_Z
	replacement.ctrl_pressed = true
	replacement.alt_pressed = true
	replacement.pressed = true
	controls._input(replacement)
	_check(InputMap.action_get_events(&"Attack")[0].physical_keycode == KEY_Z, "No se aplicó la reasignación desde la ventana")
	InputBindings._install(&"Attack", original)
	var reload = load("res://engine/autoload/input_bindings.gd").new()
	add_child(reload)
	_check(InputMap.action_get_events(&"Attack")[0].physical_keycode == KEY_Z and InputMap.action_get_events(&"Attack")[0].ctrl_pressed, "El reinicio perdió el binding guardado")
	reload.restore(&"Attack")
	reload.queue_free()
	controls.close_requested.emit()
	await get_tree().process_frame
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
	var cfg := ConfigFile.new()
	cfg.set_value("foreign", "keep", 99)
	cfg.set_value("audio", "volume_db", -7.5)
	cfg.set_value("ui", "use_custom_cursor", true)
	cfg.set_value("ui", "console_font_size", 99)
	cfg.save("user://options.cfg")
	Global._ready()
	_check(Global.consoleFontSize == 24 and Global.useCustomCursor, "No se normalizó la preferencia anterior")
	Global.nameFontSize = 18
	Global.showNames = false
	Global.showFPS = true
	_check(not character._nameLabel.visible and character._nameLabel.get_theme_font_size("font_size") == 18, "Las preferencias no llegaron al personaje existente")
	_check(Global.save_preferences() == OK, "No se guardaron preferencias")
	Global.nameFontSize = 12
	Global.showNames = true
	Global._ready()
	cfg.load("user://options.cfg")
	_check(Global.nameFontSize == 18 and not Global.showNames and Global.showFPS, "Reiniciar perdió las preferencias visuales")
	_check(cfg.get_value("foreign", "keep") == 99 and cfg.get_value("audio", "volume_db") == -7.5, "La migración perdió claves o volumen anteriores")
	var newcomer: Character = load("res://engine/character/character.tscn").instantiate()
	add_child(newcomer)
	_check(not newcomer._nameLabel.visible and newcomer._nameLabel.get_theme_font_size("font_size") == 18, "Los personajes nuevos ignoran las preferencias")
	newcomer.queue_free()
	Global.consoleFontSize = 12
	Global.nameFontSize = 12
	Global.showNames = true
	Global.showFPS = false
	Global.useCustomCursor = false
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
	# Cuerpos raciales que publica pyao, cabezas propias y cuatro orientaciones.
	var weapon_position := character.renderer._weaponAnimatedSprite.position
	var shield_position := character.renderer._shieldAnimatedSprite.position
	for racial in [[1, 1], [5, 301], [4, 401]]:
		character.renderer.body = racial[0]
		character.renderer.head = racial[1]
		var data = GameAssets.BodyAnimationList[racial[0]]
		var expected_head := character.renderer._head_base + Vector2(data.offsetX, data.offsetY)
		var expected_helmet := character.renderer._helmet_base + Vector2(data.offsetX, data.offsetY)
		for heading in [Enums.Heading.North, Enums.Heading.East, Enums.Heading.South, Enums.Heading.West]:
			character.renderer.heading = heading
			character.renderer.Stop()
			_check(character.renderer._headAnimatedSprite.position == expected_head and character.renderer._helmetAnimatedSprite.position == expected_helmet, "Alineación racial incorrecta en una orientación")
			_check(character.renderer._weaponAnimatedSprite.position == weapon_position and character.renderer._shieldAnimatedSprite.position == shield_position, "Cambiar raza/orientación desplazó arma o escudo")
	character.renderer.body = GameAssets.BodyAnimationList.size() + 1
	character.renderer.head = -1
	character.renderer.helmet = -1
	_check(character.renderer._headAnimatedSprite.sprite_frames != null and character.renderer._bodyAnimatedSprite.sprite_frames != null and character.renderer._helmetAnimatedSprite.sprite_frames != null, "Falta fallback de apariencia ausente")
	character.queue_free()
	# El timeout pertenece al efecto: fin natural, watchdog y cambio de mapa
	# deben liberar ambos sin callbacks posteriores sobre nodos desaparecidos.
	var world: MapContainer = load("res://engine/map_container.tscn").instantiate()
	add_child(world)
	world.LoadMap(2)
	for cleanup in ["finished", "timeout", "map"]:
		world.PlayWorldEffect(Vector2(32, 32), 1, 1)
		var anchors := world._GetLayer("Layer3").get_children().filter(func(node): return node.get_meta("pyao_dynamic_fx", false))
		_check(anchors.size() == 1, "FX del mundo ausente")
		if anchors.size() != 1: continue
		var anchor: Node2D = anchors[0]
		var watchdog := anchor.get_node_or_null("EffectTimeout") as Timer
		_check(watchdog != null and is_equal_approx(watchdog.wait_time, 10.0), "Watchdog no pertenece al efecto o cambió su plazo")
		if watchdog == null: continue
		var released_anchor: WeakRef = weakref(anchor)
		var released_watchdog: WeakRef = weakref(watchdog)
		watchdog.start(0.02)
		match cleanup:
			"finished": (anchor.get_child(0) as CharacterEffect).stop_effect()
			"map": world.LoadMap(1)
		await get_tree().create_timer(0.06).timeout
		await get_tree().process_frame
		_check(released_anchor.get_ref() == null and released_watchdog.get_ref() == null, "FX o watchdog sobrevive a " + cleanup)
	world.queue_free()
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
