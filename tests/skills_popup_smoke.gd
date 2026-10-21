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
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("SKILLS_POPUP: PASS late_response_does_not_reopen=true reopen_on_request=true")
	get_tree().quit()
