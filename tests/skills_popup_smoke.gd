extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var game: GameScreen = load("res://screens/game_screen.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var hub: HubController = game._gameInput
	var skills: Array = []
	skills.resize(22)
	skills.fill(0)
	hub._on_btn_skills_pressed()
	assert(hub._waiting_for_skills_popup)
	hub._skills_window.close_requested.emit()
	hub._show_skills_window(skills)
	assert(not hub._skills_window.visible)
	assert(not hub._waiting_for_skills_popup)
	# Un clic nuevo permite abrir; Cancelar vuelve a invalidar el pedido.
	hub._on_btn_skills_pressed()
	hub._show_skills_window(skills)
	assert(hub._skills_window.visible)
	hub._on_btn_skills_pressed()
	hub._skills_window.cancel_button.pressed.emit()
	hub._show_skills_window(skills)
	assert(not hub._skills_window.visible)
	# Una actualización de red no debe borrar el control que usa el teclado.
	var previous_capabilities := ClientInterface.capabilities.enabled
	var previous_points := Global.skillPoints
	ClientInterface.capabilities.enabled |= ClientCapabilities.SKILL_ALLOCATION
	Global.skillPoints = 5
	var window = hub._skills_window
	window.operation_id = "focus-regression"
	window.set_skills(skills)
	window.popup_centered()
	await get_tree().process_frame
	var plus: Button = window.skills_container.get_child(0).get_child(3)
	plus.grab_focus()
	assert(window.gui_get_focus_owner() == plus)
	window.set_skills(skills)
	await get_tree().process_frame
	plus = window.skills_container.get_child(0).get_child(3)
	assert(window.gui_get_focus_owner() == plus, "Actualizar habilidades perdió el foco del teclado")
	# Si el botón deja de estar disponible, Cancelar sigue siendo accesible.
	skills[0] = 100
	window.set_skills(skills)
	await get_tree().process_frame
	assert(window.gui_get_focus_owner() == window.cancel_button)
	window.hide()
	window.set_skills(skills)
	await get_tree().process_frame
	assert(not window.visible)
	ClientInterface.capabilities.enabled = previous_capabilities
	Global.skillPoints = previous_points
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("SKILLS_POPUP: PASS late_response_does_not_reopen=true reopen_on_request=true focus_preserved=true focus_fallback=true")
	get_tree().quit()
