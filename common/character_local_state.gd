extends RefCounted
class_name CharacterLocalState

var profile := ""
var visited: Dictionary = {}
var tax_receipt := ""
var _maps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://protocol/world-topology.json")).get("maps", {})

func open_profile(key: String) -> void:
	if key == profile: return
	profile = ""
	visited.clear()
	tax_receipt = ""
	if key.length() != 64: return
	for character in key:
		if not character in "0123456789abcdef": return
	profile = key
	var path := "user://characters/%s.json" % profile
	var text := WebPreferences.read_text(path)
	if text.is_empty(): return
	var parser := JSON.new()
	if parser.parse(text) != OK: return
	var value: Variant = parser.data
	if not value is Dictionary or not TradeSnapshot.integer(value.get("version", 0), 0, 1): return
	var maps: Variant = value.get("visited", [])
	if maps is Dictionary: maps = maps.keys()
	if not maps is Array: return
	for map in maps:
		if (map is String and map.is_valid_int()) or TradeSnapshot.integer(map, 1, 32767):
			var id := int(map)
			if _maps.has(str(id)): visited[id] = true
	if value.get("tax_receipt", "") is String and value.get("tax_receipt", "").length() <= 120:
		tax_receipt = value.get("tax_receipt", "")

func visit(map_id: int) -> void:
	if profile.is_empty() or not _maps.has(str(map_id)) or visited.has(map_id): return
	visited[map_id] = true
	_save()

func remember_tax(receipt: String) -> bool:
	if profile.is_empty() or receipt.is_empty() or receipt == tax_receipt: return false
	tax_receipt = receipt
	_save()
	return true

func _save() -> void:
	if profile.is_empty(): return
	var path := "user://characters/%s.json" % profile
	var maps := visited.keys()
	maps.sort()
	var text := JSON.stringify({"version": 1, "visited": maps, "tax_receipt": tax_receipt})
	if OS.has_feature("web"):
		WebPreferences.write_text(path, text)
		return
	if DirAccess.make_dir_recursive_absolute("user://characters") != OK: return
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(text)
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
