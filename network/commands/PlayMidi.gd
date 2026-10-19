extends RefCounted
class_name PlayMidi

var midiId:int
var loops:int 

func _init(reader:StreamPeerBuffer = null) -> void:
	if reader: Deserialize(reader)

func Deserialize(reader:StreamPeerBuffer) -> void:
	midiId = reader.get_u8()
	loops = 0 # El contrato pyao envía únicamente un byte; las pistas de mapa repiten.
