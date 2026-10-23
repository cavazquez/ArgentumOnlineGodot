extends Node

signal resources_loaded()

@export var progressBar:ProgressBar 

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)	
	
	if !DirAccess.dir_exists_absolute("user://screenshots"):
		DirAccess.make_dir_absolute("user://screenshots")

	var packages = {
		"Index": "res://index.pck",
		"Graphics": "res://graphics.pck",
		"Sounds": "res://sounds.pck",
		"Maps": "res://maps.pck",
	}

	progressBar.value = 0
	progressBar.max_value = packages.size()

	for package in packages:
		if FileAccess.file_exists(packages[package]):
			var ok = ProjectSettings.load_resource_pack(packages[package])
			if ok:
				print("%s loaded" % package)
			else:
				progressBar.hide()
				push_error("Paquete adicional inválido: " + str(packages[package]))
				Utils.ShowAlertDialog("Recursos del juego", "No se pudo abrir el paquete adicional " + str(packages[package]) + ". Repará la instalación.", self)
				return
		progressBar.value += 1
	
	# Emitir señal cuando todo esté listo
	resources_loaded.emit()
	if not GameAssets.loaded:
		var ok: bool = await GameAssets.assets_ready
		if not ok:
			progressBar.hide()
			Utils.ShowAlertDialog("Recursos del juego", "La instalación está incompleta. No se pudo cargar: " + ", ".join(GameAssets.load_errors), self)
			return

	await get_tree().create_timer(0.25).timeout
	progressBar.hide()
	
	#LoginScreen
	var screen = load("uid://cd452cndcck7v").instantiate() 
	ScreenController.SwitchScreen(screen)
