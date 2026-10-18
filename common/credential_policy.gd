extends RefCounted
class_name CredentialPolicy

# Igual que el contrato y los validadores del servidor: bytes Latin-1 literales.
const MIN_USERNAME := 3
const MAX_USERNAME := 20
const MIN_PASSWORD := 6
const MAX_PASSWORD := 32

static func username_error(username: String) -> String:
	if not Utils.CanEncodeLatin1(username):
		return "El usuario contiene caracteres fuera de Latin-1"
	if username.length() < MIN_USERNAME or username.length() > MAX_USERNAME:
		return "El usuario debe tener entre 3 y 20 caracteres"
	return ""

static func validate(username: String, password: String) -> String:
	var message := username_error(username)
	if not message.is_empty():
		return message
	if not Utils.CanEncodeLatin1(password):
		return "La contraseña contiene caracteres fuera de Latin-1"
	if password.length() < MIN_PASSWORD or password.length() > MAX_PASSWORD:
		return "La contraseña debe tener entre 6 y 32 caracteres"
	return ""
