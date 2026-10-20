extends RefCounted
class_name AOPacketFramer

# Contrato compartido con pyao-server. 0 es un ID válido (Logged).
const MAX_BUFFER_BYTES := 4096
const WIDTHS := {"u8": 1, "i16": 2, "i32": 4, "u32": 4, "f32": 4}
var _contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/contract.json"))
var _pending := PackedByteArray()
var error := ""

func clear() -> void:
	_pending.clear()
	error = ""

func pending_size() -> int:
	return _pending.size()

func _invalid(message: String) -> int:
	error = message
	return -1

func _fields_end(fields: Array, offset: int) -> int:
	for field in fields:
		if field.type == "str16":
			if _pending.size() < offset + 2:
				return 0
			var length := int(_pending[offset]) | (int(_pending[offset + 1]) << 8)
			offset += 2
			if length < int(field.get("min_bytes", 0)) or length > int(field.max_bytes):
				return _invalid("Longitud de cadena fuera del contrato")
			offset += length
		else:
			offset += int(WIDTHS[field.type])
		if offset > MAX_BUFFER_BYTES:
			return _invalid("Paquete demasiado grande")
		if offset > _pending.size():
			return 0
	return offset

func _next_length() -> int:
	if _pending.is_empty():
		return 0
	var entry: Dictionary = _contract.directions.server.get(str(_pending[0]), {})
	if entry.is_empty() or entry.status != "supported":
		return _invalid("ID de paquete desconocido o no soportado")
	var end := _fields_end(entry.fields, 1)
	if end <= 0 or not entry.has("variants"):
		return end
	var variant: Array = entry.variants.get(str(_pending[1]), [])
	if variant.is_empty():
		return _invalid("Subtipo de paquete no soportado")
	return _fields_end(variant, end)

func feed(data: PackedByteArray) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	if not error.is_empty():
		return packets
	var offset := 0
	while offset < data.size():
		# Drenar cada tramo evita rechazar una lectura grande de mensajes pequeños.
		var available := MAX_BUFFER_BYTES - _pending.size()
		if available <= 0:
			_invalid("Buffer de recepción agotado")
			break
		var count := mini(available, data.size() - offset)
		_pending.append_array(data.slice(offset, offset + count))
		offset += count
		while true:
			var length := _next_length()
			if length <= 0:
				break
			packets.append(_pending.slice(0, length))
			_pending = _pending.slice(length)
		if not error.is_empty():
			break
	if not error.is_empty():
		_pending.clear()
		packets.clear()
	return packets

func required_capability(packet_id: int) -> int:
	var entry: Dictionary = _contract.directions.server.get(str(packet_id), {})
	return int(entry.get("requires_capability", 0))
