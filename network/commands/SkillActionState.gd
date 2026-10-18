extends RefCounted
class_name SkillActionState

var valid := false
var data: Dictionary = {}

func _init(reader: StreamPeerBuffer) -> void:
	if reader.get_available_bytes() < 3 or reader.get_u8() != 1:
		return
	var value = JSON.parse_string(Utils.GetUnicodeString(reader))
	if typeof(value) != TYPE_DICTIONARY or reader.get_available_bytes() != 0:
		return
	if typeof(value.get("id")) != TYPE_STRING or not SkillAllocationState.valid_identity(value.id) or typeof(value.get("applied")) != TYPE_BOOL:
		return
	if value.get("kind", "") == "recipes":
		if typeof(value.get("recipes")) != TYPE_ARRAY or value.recipes.size() > 4 or not value.get("skill", "") in ["herreria", "carpinteria", "mineria"]:
			return
		for recipe in value.recipes:
			if typeof(recipe) != TYPE_DICTIONARY or typeof(recipe.get("id")) != TYPE_STRING or typeof(recipe.get("materials")) != TYPE_ARRAY:
				return
	data = value
	valid = true
