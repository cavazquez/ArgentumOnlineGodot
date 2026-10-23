extends Node

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	var value := {"round": "a".repeat(32), "status": "open", "commitment": "b".repeat(64), "npc": "lottery-ullathorpe", "can_bet": true, "claim_pending": false, "last_winner": {}}
	for field in ["pool", "fees", "gross", "fee", "net", "participants", "minimum", "maximum", "closes_at", "server_time", "round_seconds", "devalued"]: value[field] = 0
	check(WorldStatePacket._payload("lottery", value), "Rechazó el estado inicial de lotería")
	for field in ["pool", "fees", "net", "server_time"]:
		var malformed := value.duplicate(true)
		malformed[field] = -1
		check(not WorldStatePacket._payload("lottery", malformed), "Aceptó saldo/reloj negativo: " + field)
	var malformed := value.duplicate(true)
	malformed["can_bet"] = 1
	check(not WorldStatePacket._payload("lottery", malformed), "Aceptó permiso sin booleano")
	check(WorldStatePacket._payload("lottery_open", {"npc": "lottery-ullathorpe"}), "No abre el puesto registrado")
	check(not WorldStatePacket._payload("lottery_open", {"npc": "forged"}), "Abre un NPC ajeno")
	var winner := {"name": "Player", "round": "a".repeat(32), "seed": "c".repeat(64), "commitment": "b".repeat(64), "snapshot_hash": "d".repeat(64), "number": 99}
	for field in ["user", "prize", "at", "draw_pool", "fees", "gross", "devalued"]: winner[field] = 1
	value["last_winner"] = winner
	check(WorldStatePacket._payload("lottery", value), "Rechazó la auditoría pública de un ganador")
	value.last_winner["name"] = "x".repeat(21)
	check(not WorldStatePacket._payload("lottery", value), "Aceptó nombre fuera del contrato")
	print("LOTTERY_PACKET: checks completed; failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
