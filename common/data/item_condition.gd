extends RefCounted
class_name ItemCondition

const STAT_NAMES := {"MinHit": "Daño mínimo", "MaxHit": "Daño máximo", "MinDef": "Defensa mínima", "MaxDef": "Defensa máxima", "DefensaMagicaMin": "Resistencia mágica mínima", "DefensaMagicaMax": "Resistencia mágica máxima", "StaffPower": "Poder del foco"}

static func describe(state: Dictionary) -> String:
	if state.is_empty(): return ""
	var lines := PackedStringArray()
	if state.get("preview", false) and int(state.get("quantity", 1)) > 1:
		lines.append("Próximo ejemplar de un stock de %d. Cada unidad tiene su propia condición." % int(state.quantity))
	lines.append("ROTO: no aporta estadísticas" if state.broken else "Condición: %.2f %%" % (float(state.condition) / 100.0))
	lines.append("Usos restantes: %d / %d" % [maxi(0, int(state.max_uses) - int(state.uses)), state.max_uses] if int(state.max_uses) > 0 else "Sin límite de usos")
	lines.append("Creado: " + Time.get_datetime_string_from_unix_time(int(state.created)).replace("T", " ") + " UTC")
	lines.append("Vence: " + Time.get_datetime_string_from_unix_time(int(state.expires)).replace("T", " ") + " UTC" if int(state.expires) > 0 else "Sin vencimiento")
	for key in state.base:
		lines.append("%s: %d → %d" % [STAT_NAMES.get(key, key), state.base[key], state.effective[key]])
	lines.append("Ejemplar: " + str(state.id).left(8))
	return "\n".join(lines)
