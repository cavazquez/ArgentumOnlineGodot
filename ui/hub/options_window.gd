extends AcceptDialog
class_name OptionsWindow

@onready var sliderVolume = $VBox/hbox_volume/SliderVolume
@onready var sliderFontSize = $VBox/hbox_font_size/SliderFontSize
@onready var optionChromaticMode = $VBox/hbox_chromatic_mode/OptionButton

# El checkbox se creará dinámicamente
var checkCustomCursor: CheckBox
var _content: VBoxContainer
var _ping_label: Label

func _ready() -> void:
	Utils.ApplyDialogTheme(self)
	_content = $VBox
	# Configurar la ventana como no-exclusiva para permitir inputs globales
	exclusive = false
	# Permitir cerrar con la X de la ventana
	close_requested.connect(hide)
	# Asegurar que la X sea visible y funcional
	title = "Opciones"
	
	get_ok_button().text = "Guardar"
	
	var bus = AudioServer.get_bus_index("Master")
	sliderVolume.value = db_to_linear(AudioServer.get_bus_volume_db(bus))
	sliderVolume.connect("value_changed", Callable(self, "_on_slider_value_changed"))
	sliderFontSize.value = Global.dialogFontSize
	sliderFontSize.connect("value_changed", Callable(self, "_on_slider_font_size_changed"))
	
	# Configurar el selector de modo cromático
	optionChromaticMode.selected = Global.chromaticMode
	optionChromaticMode.connect("item_selected", Callable(self, "_on_chromatic_mode_selected"))
	
	# Crear dinámicamente el checkbox para cursor personalizado
	_create_custom_cursor_option()
	_add_extended_options()
	
	# Guardar configuración al confirmar
	connect("confirmed", Callable(self, "_on_save_settings"))

func _on_slider_value_changed(value: float) -> void:
	var bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(value))

func _on_slider_font_size_changed(value: float) -> void:
	Global.dialogFontSize = int(value)

func _on_custom_cursor_toggled(button_pressed: bool) -> void:
	Global.useCustomCursor = button_pressed

func _on_chromatic_mode_selected(index: int) -> void:
	Global.chromaticMode = index

# Función para crear dinámicamente el checkbox de cursor personalizado
func _create_custom_cursor_option() -> void:
	# Crear directamente el checkbox
	checkCustomCursor = CheckBox.new()
	checkCustomCursor.name = "CheckCustomCursor"
	checkCustomCursor.text = "Usar cursor personalizado"
	checkCustomCursor.button_pressed = Global.useCustomCursor
	checkCustomCursor.connect("toggled", Callable(self, "_on_custom_cursor_toggled"))
	
	# Añadir el checkbox directamente al VBox principal
	_content.add_child(checkCustomCursor)

func _on_save_settings() -> void:
	if Global.save_preferences() != OK:
		Utils.ShowAlertDialog("Opciones", "No se pudieron guardar las preferencias. Se conserva el archivo anterior.", self)

func _add_extended_options() -> void:
	min_size = Vector2i(420, 500)
	size = min_size
	var content := _content
	remove_child(content)
	var scroll := ScrollContainer.new()
	add_child(scroll)
	scroll.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var layout := func():
		scroll.position = Vector2(12, 12)
		scroll.size = Vector2(size) - Vector2(24, 65)
	size_changed.connect(layout)
	layout.call()

	for info in [["Mostrar nombres", "showNames"], ["Mostrar FPS", "showFPS"]]:
		var check := CheckBox.new()
		check.text = info[0]
		check.button_pressed = Global.get(info[1])
		check.toggled.connect(func(value): Global.set(info[1], value))
		_content.add_child(check)
	for info in [["Texto de consola", "consoleFontSize"], ["Nombres", "nameFontSize"]]:
		var row := HBoxContainer.new()
		_content.add_child(row)
		var label := Label.new()
		label.text = info[0]
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 10
		spin.max_value = 24
		spin.value = Global.get(info[1])
		spin.value_changed.connect(func(value): Global.set(info[1], int(value)))
		row.add_child(spin)
	var effects := OptionButton.new()
	for label in ["Efectos adicionales: desactivados", "Efectos adicionales: reducidos", "Efectos adicionales: completos"]: effects.add_item(label)
	effects.selected = Global.effectsMode
	effects.item_selected.connect(func(value): Global.effectsMode = value)
	_content.add_child(effects)
	var music_label := Label.new()
	music_label.text = "Volumen de música"
	_content.add_child(music_label)
	var music := HSlider.new()
	music.min_value = 0
	music.max_value = 1
	music.step = 0.05
	music.value = Global.musicVolume
	music.tooltip_text = "Volumen de música"
	music.value_changed.connect(func(value): Global.musicVolume = value)
	_content.add_child(music)
	var controls := Button.new()
	controls.text = "Configurar controles"
	controls.pressed.connect(func():
		var window := ControlsWindow.new()
		add_child(window)
		window.popup_centered())
	_content.add_child(controls)
	var ping_row := HBoxContainer.new()
	_content.add_child(ping_row)
	_ping_label = Label.new()
	_update_ping(Global.pingStatus)
	Global.ping_updated.connect(_update_ping)
	ping_row.add_child(_ping_label)
	var measure := Button.new()
	measure.text = "Medir latencia"
	measure.pressed.connect(func(): Global.ping_requested.emit())
	ping_row.add_child(measure)
	var diagnostics := Label.new()
	diagnostics.text = "Versión %s · Godot %s · %s · %s" % [ProjectSettings.get_setting("application/config/version", "desconocida"), Engine.get_version_info().string, OS.get_name(), RenderingServer.get_current_rendering_method()] + "\nCompilación: " + _build_commit()
	diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(diagnostics)
	var copy := Button.new()
	copy.text = "Copiar diagnóstico"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(diagnostics.text + "\nCommit: " + _build_commit()))
	_content.add_child(copy)

func _build_commit() -> String:
	if not FileAccess.file_exists("res://build-info.json"): return "no disponible"
	var value = JSON.parse_string(FileAccess.get_file_as_string("res://build-info.json"))
	return String(value.get("commit", "no disponible")) if value is Dictionary else "no disponible"

func _update_ping(value: String) -> void:
	if is_instance_valid(_ping_label): _ping_label.text = value
