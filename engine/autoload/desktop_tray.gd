extends Node

var available := false
var _indicator: StatusIndicator
var _menu: PopupMenu
var _bridge := {}
var _incoming := ""
var _title := ""
var _poll := 0.0
var _started := 0
var _icon_path := ""
var _minimized_to_tray := false
var _restore_mode := DisplayServer.WINDOW_MODE_WINDOWED

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web") or DisplayServer.get_name() == "headless": return
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(Close)
	if OS.get_name() in ["Windows", "macOS"]:
		_menu = PopupMenu.new()
		_menu.prefer_native_menu = true
		_menu.add_item("Mostrar cliente", 0)
		_menu.add_item("Salir del cliente", 1)
		_menu.id_pressed.connect(_menu_pressed)
		add_child(_menu)
		_indicator = StatusIndicator.new()
		_indicator.icon = preload("res://Assets/Branding/pyao-client-128.png")
		add_child(_indicator)
		_indicator.menu = _indicator.get_path_to(_menu)
		_indicator.tooltip = "PyAO Client"
		available = true
	elif OS.get_name() == "Linux":
		_start_bridge()

func _menu_pressed(id: int) -> void:
	if id == 0: Show()
	else: Exit()

func _start_bridge() -> void:
	var base := OS.get_executable_path().get_base_dir()
	var executable := base.path_join("pyao-tray")
	if not FileAccess.file_exists(executable): executable = ProjectSettings.globalize_path("res://build/desktop/pyao-tray")
	if not FileAccess.file_exists(executable): return
	# GTK necesita un archivo del sistema, también cuando res:// está dentro
	# del PCK. Usar la misma ruta en editor y export evita depender de tags.
	_icon_path = ProjectSettings.globalize_path("user://tray-icon.png")
	if preload("res://Assets/Branding/pyao-client-128.png").get_image().save_png(_icon_path) != OK:
		push_warning("No se pudo preparar el icono de bandeja.")
		return
	_bridge = OS.execute_with_pipe(executable, ["client", _icon_path, "PyAO Client"], false)
	_started = Time.get_ticks_msec()

func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.2: return
	_poll = 0.0
	var title := "PyAO Client · %s" % (Global.username if ClientInterface.IsConnected() else "Desconectado")
	if title != _title:
		_title = title
		if _indicator != null: _indicator.tooltip = title
		if available and not _bridge.is_empty(): _bridge.stdio.store_line("TITLE " + title)
	if _bridge.is_empty(): return
	var bytes: PackedByteArray = _bridge.stdio.get_buffer(4096)
	_incoming += bytes.get_string_from_utf8()
	while _incoming.contains("\n"):
		var at := _incoming.find("\n")
		var event := _incoming.left(at).strip_edges()
		_incoming = _incoming.substr(at + 1)
		match event:
			"READY":
				available = true
				_bridge.stdio.store_line("TITLE " + _title)
			"SHOW": Show()
			"EXIT": Exit()
			"UNAVAILABLE":
				available = false
				if _minimized_to_tray: Show()
	if not OS.is_process_running(int(_bridge.pid)) or (not available and Time.get_ticks_msec() - _started > 7000):
		available = false
		if _minimized_to_tray: Show()
		_stop_bridge()

func Minimize() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode != DisplayServer.WINDOW_MODE_MINIMIZED: _restore_mode = mode
	_minimized_to_tray = available and Global.minimizeToTray
	# Godot forbids hiding its main Window. Use the native minimized state;
	# both the taskbar/dock and the tray can restore it, without reparenting UI.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func Show() -> void:
	_minimized_to_tray = false
	DisplayServer.window_set_mode(_restore_mode)
	get_window().grab_focus()

func Exit() -> void:
	ClientInterface.DisconnectFromHost()
	get_tree().quit()

func Close() -> void:
	if available and Global.minimizeToTray: Minimize()
	else: Exit()

func _stop_bridge() -> void:
	if _bridge.is_empty(): return
	_bridge.stdio.store_line("QUIT")
	_bridge.clear()

func _exit_tree() -> void:
	_stop_bridge()
