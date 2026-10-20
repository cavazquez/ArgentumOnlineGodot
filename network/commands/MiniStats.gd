extends RefCounted
class_name MiniStats

var CiudadanosMatados:int
var CriminalesMatados:int
var UsuariosMatados:int
var NpcsMatados:int
var Muertes:int
var Clase:int
var PenaCarcel:int

func _init(reader: StreamPeerBuffer = null) -> void:
	if reader:
		Deserialize(reader)

func Deserialize(reader: StreamPeerBuffer) -> void:
	CiudadanosMatados = reader.get_u32()
	CriminalesMatados = reader.get_u32()
	UsuariosMatados = reader.get_u32()
	NpcsMatados = reader.get_u32()
	Muertes = reader.get_u32()
	Clase = reader.get_u8()
	PenaCarcel = reader.get_u32()
