extends Window

# Se emite cuando se actualiza un skill
signal draft_changed(skill_index: int, new_value: int)

# Lista de skills y sus nombres
var SKILL_NAMES: Array[String] = SkillCatalog.names()

@onready var free_skills: Label
@onready var skills_container = $VBox/Scroll/SkillsContainer
@onready var accept_button = $VBox/ButtonsContainer/AcceptButton
@onready var cancel_button = $VBox/ButtonsContainer/CancelButton

var operation_id := ""
var _pending_id := ""
var _deadline := 0
var _status: Label
var skill_values: Array[int] = []
var initial_free_skills: int 
var current_free_skills: int  # Puntos de skills locales (no afectan Global hasta aceptar)
var initial_skill_values: Array[int] = []
var skill_labels: Array[Label] = []
var skill_names: Array[String] = []

func _ready():
	title = "Habilidades"
	
	free_skills = $VBox/HBoxContainer/SkillsPts
	accept_button.pressed.connect(_on_accept_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$VBox.add_child(_status)
	$VBox.move_child(_status, 1)
	update_free_skills()
	# Inicialmente deshabilitar el botón de aceptar ya que no hay cambios
	accept_button.disabled = true

# Se llama cuando se presiona el botón + de un skill
func _on_plus_pressed(skill_index: int):
	if not _can_edit(skill_index):
		return
	if current_free_skills > 0 and skill_index < skill_values.size() and skill_values[skill_index] < 100:
		skill_values[skill_index] += 1
		skill_labels[skill_index].text = str(skill_values[skill_index])
		current_free_skills -= 1
		update_free_skills()
		_status.text = "Borrador sin guardar."
		emit_signal("draft_changed", skill_index, skill_values[skill_index])
		update_buttons_state()

# Se llama cuando se presiona el botón - de un skill
func _on_minus_pressed(skill_index: int):
	if not _can_edit(skill_index):
		return
	if (skill_index < skill_values.size() and 
		skill_values[skill_index] > initial_skill_values[skill_index]):
		skill_values[skill_index] -= 1
		skill_labels[skill_index].text = str(skill_values[skill_index])
		current_free_skills += 1
		update_free_skills()
		_status.text = "Borrador sin guardar."
		emit_signal("draft_changed", skill_index, skill_values[skill_index])
		update_buttons_state()

# Actualiza el estado de los botones + y - según las reglas
func update_buttons_state():
	var supported := ClientInterface.capabilities.can_send(Enums.ClientPacketID.ModifySkills) and not operation_id.is_empty() and _pending_id.is_empty()
	accept_button.tooltip_text = "Asignación no disponible en este servidor" if not supported else "Guardar cambios"
	for i in range(skills_container.get_child_count()):
		var child = skills_container.get_child(i)
		if child is HBoxContainer and child.get_child_count() > 3:
			var minus_btn = child.get_child(1)
			var plus_btn = child.get_child(3)
			
			if minus_btn is Button:
				minus_btn.disabled = not supported or not _can_edit(i)
				minus_btn.visible = !(i >= skill_values.size() or 
					skill_values[i] <= initial_skill_values[i])
			
			if plus_btn is Button:
				plus_btn.disabled = not supported or not _can_edit(i)
				plus_btn.visible = !(i >= skill_values.size() or 
					skill_values[i] >= 100 or current_free_skills <= 0)
	
	# Actualizar el estado del botón de aceptar
	accept_button.disabled = not supported or not has_skill_changes()

func update_free_skills():
	free_skills.text = str(current_free_skills)

# Función para verificar si hay cambios en las habilidades
func has_skill_changes() -> bool:
	# Verificar si los puntos libres han cambiado
	if current_free_skills != initial_free_skills:
		return true
	
	# Verificar si algún valor de habilidad ha cambiado
	for i in range(min(skill_values.size(), initial_skill_values.size())):
		if skill_values[i] != initial_skill_values[i]:
			return true
	
	# No hay cambios
	return false

func _on_cancel_pressed():
	if _pending_id.is_empty():
		set_skills(initial_skill_values.duplicate())
	hide()

func _on_accept_pressed():
	if not _pending_id.is_empty() or operation_id.is_empty() or not has_skill_changes():
		return
	var deltas: Array[int] = []
	for index in skill_values.size():
		deltas.append(skill_values[index] - initial_skill_values[index])
	if GameProtocol.WriteModifySkills(deltas, operation_id):
		_pending_id = operation_id
		operation_id = ""
		_deadline = Time.get_ticks_msec() + 5000
		_status.text = "Guardando; esperando confirmación del servidor…"
		update_buttons_state()

func _can_edit(index: int) -> bool:
	return index >= 0 and index < skill_values.size() and _pending_id.is_empty() and not operation_id.is_empty() and SkillCatalog.definitions()[index].implemented and ClientInterface.capabilities.can_send(Enums.ClientPacketID.ModifySkills)

func ApplyAllocationState(state: SkillAllocationState) -> void:
	if not _pending_id.is_empty() and (state.status == 0 or state.operation_id != _pending_id):
		return
	_pending_id = ""
	operation_id = state.next_operation_id
	Global.skillPoints = state.free_points
	set_skills(state.skills)
	_status.text = state.message if state.status != 0 else "Estado confirmado por el servidor."

func _process(_delta: float) -> void:
	if not _pending_id.is_empty() and Time.get_ticks_msec() >= _deadline:
		_pending_id = ""
		operation_id = ""
		_status.text = "Sin confirmación; consultando el estado actual…"
		update_buttons_state()
		GameProtocol.WriteRequestSkills()

func set_skills(skills:Array):
	# Limpiar arrays
	skill_values.clear()
	initial_skill_values.clear()
	skill_labels.clear()
	
	# Eliminar todos los hijos existentes inmediatamente
	for child in skills_container.get_children():
		child.free()  # Usar free() en lugar de queue_free() para eliminación inmediata
	
	# Asegurarse de que la ventana tenga un tamaño adecuado y compacto
	size = Vector2(300, 400)
	
	# Inicializar valores de skills
	for i in range(SKILL_NAMES.size()):
		var skill_value = 0
		if i < skills.size():
			if skills[i] is Object and skills[i].get("level") != null:
				skill_value = skills[i].level
			elif typeof(skills[i]) == TYPE_DICTIONARY and skills[i].has("level"):
				skill_value = skills[i].level
			elif typeof(skills[i]) == TYPE_INT or typeof(skills[i]) == TYPE_FLOAT:
				skill_value = int(skills[i])
		skill_values.append(skill_value)
		initial_skill_values.append(skill_value)
	
	# Inicializar puntos de skills locales
	initial_free_skills = Global.skillPoints
	current_free_skills = Global.skillPoints
	
	_create_skills_interface()
	
	# Actualizar el estado de los botones
	update_buttons_state()
	update_free_skills()

# Nueva función para crear la interfaz de skills
func _create_skills_interface():
	for i in range(SKILL_NAMES.size()):
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.custom_minimum_size = Vector2(0, 32)

		var name_label = Label.new()
		name_label.text = SKILL_NAMES[i]
		if not SkillCatalog.definitions()[i].implemented:
			name_label.text += " (pendiente)"
			name_label.tooltip_text = "Progresión no implementada; se conserva el valor histórico"
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_label.custom_minimum_size = Vector2(120, 0)

		var minus_btn = Button.new()
		minus_btn.text = "-"
		minus_btn.custom_minimum_size = Vector2(30, 0)
		minus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		minus_btn.pressed.connect(_on_minus_pressed.bind(i))

		var value_label = Label.new()
		# Mostrar el valor del skill
		if i < skill_values.size():
			value_label.text = str(skill_values[i])
		else:
			value_label.text = "0"
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value_label.custom_minimum_size = Vector2(40, 0)

		var plus_btn = Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(30, 0)
		plus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus_btn.pressed.connect(_on_plus_pressed.bind(i))

		hbox.add_child(name_label)
		hbox.add_child(minus_btn)
		hbox.add_child(value_label)
		hbox.add_child(plus_btn)
		skills_container.add_child(hbox)
		skill_labels.append(value_label)
