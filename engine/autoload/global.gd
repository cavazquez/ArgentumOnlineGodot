extends Node

var username:String = ""
var character_local := CharacterLocalState.new()
var skillPoints:int = 0

# Control de logging para paquetes salientes al servidor
var log_outgoing_packets:bool = false

signal ping_requested
signal ping_updated(value: String)
var pingStatus := "Sin medición":
	set(value):
		pingStatus = value
		ping_updated.emit(value)

signal preferences_changed

signal dialog_font_size_changed(value:int)
signal custom_cursor_changed(value:bool)
signal chromatic_mode_changed(value:int)

# Modos cromáticos (0 = desactivado, 1 = deuteranopia, 2 = protanopia, 3 = tritanopia)
var _chromaticMode:int = 0

var chromaticMode:int:
	set(value):
		_chromaticMode = clampi(value, 0, 3)
		emit_signal("chromatic_mode_changed", _chromaticMode)
	get:
		return _chromaticMode

# Opción para usar cursor personalizado
var _useCustomCursor:bool = false

var useCustomCursor:bool:
	set(value):
		_useCustomCursor = value
		emit_signal("custom_cursor_changed", _useCustomCursor)
	get:
		return _useCustomCursor

var _dialogFontSize:int = 12

var dialogFontSize:int:
	set(value):
		_dialogFontSize = clamp(value, 10, 24)
		emit_signal("dialog_font_size_changed", _dialogFontSize)
		preferences_changed.emit()
	get:
		return _dialogFontSize

func get_timestamp() -> String:
	var time = Time.get_time_dict_from_system()
	return " [%02d:%02d:%02d]" % [time.hour, time.minute, time.second]

var _normal_root_theme: Theme

func _ready() -> void:
	if not preferences_changed.is_connected(_apply_accessibility):
		_normal_root_theme = get_tree().root.theme
		preferences_changed.connect(_apply_accessibility)
	# Cargar configuración guardada
	var cfg = ConfigFile.new()
	if cfg.load("user://options.cfg") == OK:
		var bus = AudioServer.get_bus_index("Master")
		var saved_db = cfg.get_value("audio", "volume_db", AudioServer.get_bus_volume_db(bus))
		AudioServer.set_bus_volume_db(bus, saved_db)
		var saved_fs = cfg.get_value("ui", "dialog_font_size", dialogFontSize)
		dialogFontSize = int(saved_fs)
		
		# Cargar configuración de cursor personalizado
		var saved_cursor = cfg.get_value("ui", "use_custom_cursor", useCustomCursor)
		useCustomCursor = bool(saved_cursor)
		
		# Cargar configuración de modo cromático
		var saved_chromaticMode = cfg.get_value("ui", "chromatic_mode", chromaticMode)
		chromaticMode = int(saved_chromaticMode)
		consoleFontSize = int(cfg.get_value("ui", "console_font_size", 12))
		nameFontSize = int(cfg.get_value("ui", "name_font_size", 12))
		showNames = bool(cfg.get_value("ui", "show_names", true))
		showFPS = bool(cfg.get_value("ui", "show_fps", false))
		effectsMode = int(cfg.get_value("ui", "effects", 2))
		musicVolume = float(cfg.get_value("audio", "music_volume", 0.65))
		animateDialogs = bool(cfg.get_value("ui", "animate_dialogs", true))
		highContrast = bool(cfg.get_value("ui", "high_contrast", false))
		rainIntensity = float(cfg.get_value("ui", "rain_intensity", 1.0))
		peripheralFog = float(cfg.get_value("ui", "peripheral_fog", 0.0))
		transitionEffects = bool(cfg.get_value("ui", "transition_effects", true))
	_apply_accessibility()
		

var consoleFontSize := 12:
	set(value):
		consoleFontSize = clampi(value, 10, 24)
		preferences_changed.emit()
var nameFontSize := 12:
	set(value):
		nameFontSize = clampi(value, 10, 24)
		preferences_changed.emit()
var showNames := true:
	set(value):
		showNames = value
		preferences_changed.emit()
var showFPS := false:
	set(value):
		showFPS = value
		preferences_changed.emit()
var effectsMode := 2:
	set(value):
		effectsMode = clampi(value, 0, 2)
		preferences_changed.emit()
var musicVolume := 0.65:
	set(value):
		musicVolume = clampf(value, 0.0, 1.0)
		preferences_changed.emit()

func save_preferences() -> Error:
	var cfg := ConfigFile.new()
	var loaded := cfg.load("user://options.cfg")
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND: return loaded
	cfg.set_value("ui", "dialog_font_size", dialogFontSize)
	cfg.set_value("ui", "animate_dialogs", animateDialogs)
	cfg.set_value("ui", "high_contrast", highContrast)
	cfg.set_value("ui", "rain_intensity", rainIntensity)
	cfg.set_value("ui", "peripheral_fog", peripheralFog)
	cfg.set_value("ui", "transition_effects", transitionEffects)
	cfg.set_value("ui", "console_font_size", consoleFontSize)
	cfg.set_value("ui", "name_font_size", nameFontSize)
	cfg.set_value("ui", "show_names", showNames)
	cfg.set_value("ui", "show_fps", showFPS)
	cfg.set_value("ui", "effects", effectsMode)
	cfg.set_value("ui", "use_custom_cursor", useCustomCursor)
	cfg.set_value("ui", "chromatic_mode", chromaticMode)
	cfg.set_value("audio", "volume_db", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
	cfg.set_value("audio", "music_volume", musicVolume)
	var error := cfg.save("user://options.cfg.tmp")
	if error != OK: return error
	return DirAccess.rename_absolute("user://options.cfg.tmp", "user://options.cfg")


var animateDialogs := true:
	set(value):
		animateDialogs = value
		preferences_changed.emit()
var highContrast := false:
	set(value):
		highContrast = value
		preferences_changed.emit()
var rainIntensity := 1.0:
	set(value):
		rainIntensity = clampf(value, 0.0, 1.0)
		preferences_changed.emit()
var peripheralFog := 0.0:
	set(value):
		peripheralFog = clampf(value, 0.0, 1.0)
		preferences_changed.emit()
var transitionEffects := true:
	set(value):
		transitionEffects = value
		preferences_changed.emit()


func _apply_accessibility() -> void:
	get_tree().root.theme = AccessibleTheme.make(_normal_root_theme, true, dialogFontSize) if highContrast else _normal_root_theme
