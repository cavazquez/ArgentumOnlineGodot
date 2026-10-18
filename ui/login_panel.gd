extends PanelContainer
class_name LoginPanel

signal submit 
signal register
signal error(message:String)

func _ready() -> void:
	%Reg.pressed.connect(func(): register.emit())
	%ShowPasswordButton.toggled.connect(_on_show_password_toggled)
	%ShowPasswordButton.toggle_mode = true
	%ShowPasswordButton.button_pressed = false
	
	var username := SavedCredentials.load_username()
	%Username.text = username
	%Password.text = ""
	%RememberUsername.button_pressed = not username.is_empty()

func _on_show_password_toggled(button_pressed: bool) -> void:
	%Password.secret = !button_pressed
	if button_pressed:
		%ShowPasswordButton.text = "🙈"
		%ShowPasswordButton.tooltip_text = "Ocultar contraseña"
	else:
		%ShowPasswordButton.text = "👁️"
		%ShowPasswordButton.tooltip_text = "Mostrar contraseña"

func GetUsername() -> String:
	return %Username.text
	
func GetPassword() -> String:
	return %Password.text

func EnableAuthControls() -> void:
	%Submit.disabled = false
	%Reg.disabled = false
	%Username.editable = true
	%Password.editable = true
	
func DisableAuthControls() -> void:
	%Submit.disabled = true
	%Reg.disabled = true
	%Username.editable = false
	%Password.editable = false

func _OnButtonLoginPressed() -> void:
	var message := CredentialPolicy.validate(%Username.text, %Password.text)
	if not message.is_empty():
		error.emit(message)
		return

	Global.username = %Username.text
	
	if %RememberUsername.button_pressed:
		SavedCredentials.save_username(%Username.text)
	else:
		SavedCredentials.clear_credentials()
	
	submit.emit()
