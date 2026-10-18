extends Node
# Prueba de migración del motor. No usa cuentas ni un servidor de red.

var _failed := false

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func():
		push_error("ENGINE_SMOKE: timeout")
		get_tree().quit(1)
	)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

func _run() -> void:
	await get_tree().process_frame
	var version := Engine.get_version_info()
	_check(version.major == 4 and version.minor == 7 and version.patch == 2 and version.status == "stable", "Motor diferente de 4.7.2 stable")
	var assets := get_tree().root.get_node("GameAssets")
	_check(assets.GrhDataList.size() > 1, "No se cargó el índice gráfico propio")
	var login = load("res://screens/login_screen.tscn").instantiate()
	get_tree().root.add_child(login)
	await get_tree().process_frame
	var panel: LoginPanel = login._loginPanel
	panel.get_node("%Username").text = "MotorTest"
	panel.get_node("%Password").text = "LocalTest"
	var submitted := [false]
	panel.submit.connect(func(): submitted[0] = true)
	panel._OnButtonLoginPressed()
	_check(submitted[0], "El formulario de login dejó de emitir submit")
	_check(panel.GetUsername() == "MotorTest", "El login alteró el nombre")
	login.queue_free()
	await get_tree().process_frame
	var creation = load("res://screens/character_creation_screen.tscn").instantiate()
	get_tree().root.add_child(creation)
	await get_tree().process_frame
	_check(creation._classOptionButton.item_count == 12, "Se perdieron clases propias")
	_check(creation._raceOptionButton.item_count == 5, "Se perdieron razas propias")
	_check(creation._homeOptionButton.item_count == 6, "El selector debe conservar las seis ciudades propias")
	var attributes: Array[int] = [18, 18, 18, 18, 18]
	creation._HandleDiceRoll(attributes)
	_check(creation._attributeContainer.get_child(0).text.contains("18"), "No se muestran los atributos")
	creation.queue_free()
	await get_tree().process_frame
	var guild = load("res://ui/hub/guild_foundation_window.tscn").instantiate()
	get_tree().root.add_child(guild)
	_check(guild.get_node("VBox/FormContainer/ClanNameEdit") is LineEdit, "La escena de clan tiene una jerarquía inválida")
	guild.queue_free()
	await get_tree().process_frame
	var world = load("res://engine/map_container.tscn").instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	world.LoadMap(1)
	_check(world._tiles.size() == 10000, "El mapa 1 no conserva 100x100 tiles")
	_check(world._view != null, "No se creó la vista del mapa")
	world.LoadMap(34)
	_check(world._view != null, "No se pudo cambiar a Nix")
	world.queue_free()
	var inventory: Inventory = Inventory.new(30)
	var container: InventoryContainer = load("res://ui/hub/inventory_container.tscn").instantiate()
	get_tree().root.add_child(container)
	container.SetInventory(inventory)
	var item := Item.new()
	item.index = 1
	item.name = "Prueba de migración"
	item.icon = assets.GetTexture(1)
	inventory.SetSlot(29, ItemStack.new(7, true, item))
	_check(container.get_child_count() == 30, "Se perdió el inventario durante la migración")
	_check(container.GetInventorySlot(29).get_node("%Quantity").text == "7", "No se actualizó la cantidad del slot")
	_check(container.GetInventorySlot(29).get_node("%Equipped").visible, "No se muestra el estado equipado")
	container.queue_free()
	for file in DirAccess.get_files_at("res://shaders"):
		if file.ends_with(".gdshader"):
			var shader = load("res://shaders/" + file)
			_check(shader is Shader, "Shader incompatible: " + file)
			var material := ShaderMaterial.new()
			material.shader = shader
			var sample := ColorRect.new()
			sample.size = Vector2(32, 32)
			sample.material = material
			add_child(sample)
	await get_tree().process_frame
	print("ENGINE_SMOKE: ", "FAIL" if _failed else "PASS", " (login, creación, mapas, inventario y shaders)")
	get_tree().quit(1 if _failed else 0)
