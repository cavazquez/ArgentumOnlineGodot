extends RefCounted
class_name GameResourcesAudit

const RAW_REQUIRED := ["Assets/Init/graficos.ind", "Assets/Init/personajes.ind", "Assets/Init/cabezas.ind", "Assets/Init/cascos.ind", "Assets/Init/armas.dat", "Assets/Init/escudos.dat", "Assets/Init/colores.dat", "Assets/Maps/mapa1.map", "protocol/contract.json", "protocol/water-masks.json"]
const IMPORTED_REQUIRED := ["Resources/Character/Bodies/body_1.tres", "Resources/Character/Heads/head_1.tres", "Resources/Character/none.tres", "Assets/Sfx/1.wav", "Assets/Music/1.ogg"]

static func missing_resources() -> PackedStringArray:
	var missing := PackedStringArray()
	var required := RAW_REQUIRED.duplicate()
	for map_id in range(1, 291): required.append("Assets/Maps/mapa%d.map" % map_id)
	for path in required:
		var file := FileAccess.open("res://" + path, FileAccess.READ)
		if file == null or file.get_length() == 0: missing.append(path)
	for path in IMPORTED_REQUIRED:
		if not ResourceLoader.exists("res://" + path): missing.append(path)
	return missing
