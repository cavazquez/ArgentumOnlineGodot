extends Node

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("La prueba de bandeja requiere un escritorio real o display gráfico.")
		get_tree().quit(1)
		return
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	var logo := TextureRect.new()
	logo.texture = preload("res://Assets/Branding/pyao-client-128.png")
	logo.custom_minimum_size = Vector2(128, 128)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(logo)
	var label := Label.new()
	label.text = "PyAO Client · " + OS.get_name() + "\nPrueba nativa de bandeja y restauración"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var deadline := Time.get_ticks_msec() + 8000
	while not DesktopTray.available and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not DesktopTray.available:
		push_error("No hay un host de bandeja disponible; no se acredita mostrar/ocultar.")
		get_tree().quit(1)
		return
	if OS.get_name() == "Linux":
		var stored := Image.load_from_file(DesktopTray._icon_path)
		var expected := preload("res://Assets/Branding/pyao-client-128.png").get_image()
		stored.convert(Image.FORMAT_RGBA8)
		expected.convert(Image.FORMAT_RGBA8)
		if stored.get_size() != Vector2i(128, 128) or stored.get_data() != expected.get_data():
			push_error("El puente de bandeja no recibió los píxeles del icono empaquetado.")
			get_tree().quit(1)
			return
	Global.minimizeToTray = true
	get_window().close_requested.emit()
	await get_tree().create_timer(0.5).timeout
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED:
		push_error("Minimizar a bandeja no ocultó la ventana.")
		get_tree().quit(1)
		return
	DesktopTray.Show()
	await get_tree().create_timer(0.5).timeout
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		push_error("Mostrar no restauró la ventana.")
		get_tree().quit(1)
		return
	var screenshot := OS.get_environment("PYAO_DESKTOP_SCREENSHOT")
	if not screenshot.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(screenshot)
	print("DESKTOP_TRAY: PASS platform=", OS.get_name(), " minimize=true restore=true")
	get_tree().quit()
