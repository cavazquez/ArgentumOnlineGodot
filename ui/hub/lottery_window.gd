extends WorldStateWindow
class_name LotteryWindow

var _summary: Label
var _winner: Label
var _quote: Label
var _clock: Label
var _audit: Label
var _amount: SpinBox
var _bet: Button
var _received_at := 0

func _init() -> void:
	topic = "lottery"
	title = "Lotero de Ullathorpe"

func _build() -> void:
	_summary = label(body)
	_winner = label(body, "Todavía no hubo ganador.")
	_clock = label(body)
	label(body, "Apostá junto al lotero, a tres casillas como máximo. La primera apuesta inicia la ronda. Con un solo participante recibe el pozo, descontada la comisión.")
	_amount = SpinBox.new()
	_amount.min_value = 100
	_amount.max_value = 2147483647
	_amount.step = 1
	_amount.value = 100
	_amount.value_changed.connect(func(_value: float): _update_quote())
	body.add_child(_amount)
	_quote = label(body)
	_bet = button(body, "Confirmar apuesta…", _confirm_bet)
	label(body, "Comisión acumulada del 1%, redondeada hacia arriba. La probabilidad depende del aporte neto. El pozo pierde 1% diario por devaluación, también si el premio queda pendiente. Alejarte o desconectarte conserva tu apuesta.")
	_audit = label(body)

func _render() -> void:
	if _summary == null: return
	_received_at = Time.get_ticks_msec()
	var pool := int(state.get("pool", 0))
	var net := int(state.get("net", 0))
	var chance := 100.0 * net / pool if pool > 0 else 0.0
	_summary.text = "Pozo: %d oro · Participantes: %d\nTu aporte bruto: %d · Comisión: %d · Neto vigente: %d (%.2f%%)" % [pool, int(state.get("participants", 0)), int(state.get("gross", 0)), int(state.get("fee", 0)), net, chance]
	var winner: Dictionary = state.get("last_winner", {})
	_winner.text = "Último ganador: %s · Premio: %d oro" % [winner.get("name", ""), int(winner.get("prize", 0))] if not winner.is_empty() else "Todavía no hubo ganador."
	if state.get("claim_pending", false):
		_summary.text += "\n¡Ganaste! Premio reservado: liberá capacidad en bolsillo o banco para recibirlo completo."
	_audit.text = "Compromiso de esta ronda: " + String(state.get("commitment", ""))
	if not winner.is_empty():
		_audit.text += "\nÚltimo sorteo · Ronda: %s\nSemilla: %s\nHash de aportes: %s\nBoleto: %d de %d" % [winner.round, winner.seed, winner.snapshot_hash, int(winner.number), int(winner.draw_pool)]
	_update_quote()

func _update_quote() -> void:
	if _quote == null: return
	var gross := int(_amount.value)
	var total := int(state.get("gross", 0)) + gross
	@warning_ignore("integer_division")
	var fee := (total + 99) / 100 - int(state.get("fee", 0))
	_quote.text = "Pagarás %d oro: comisión %d; se agregan %d al pozo y a tu participación." % [gross, fee, gross - fee]
	_bet.disabled = pending() or not state.get("can_bet", false) or revision.is_empty()

func _confirm_bet() -> void:
	if _bet.disabled: return
	confirm_action("lottery.bet", {"round": state.round, "npc": state.npc, "gross": int(_amount.value)}, _quote.text + "\nLa apuesta confirmada no se puede retirar. ¿Confirmar?")

func _process(delta: float) -> void:
	super._process(delta)
	if _clock == null or state.is_empty(): return
	var closes := int(state.get("closes_at", 0))
	var elapsed := (Time.get_ticks_msec() - _received_at) / 1000
	var remaining: int = maxi(0, closes - int(state.get("server_time", 0)) - elapsed)
	var stage: String = {"open": "Ronda abierta", "pending": "Premio reservado", "cancelling": "Devolviendo apuestas", "paid": "Premio pagado", "cancelled": "Ronda cancelada"}.get(state.get("status", "open"), "Esperando estado")
	_clock.text = "Esperando la primera apuesta · Ronda de %d segundos" % int(state.get("round_seconds", 300)) if closes == 0 else "Cierre en aproximadamente %d segundos · %s" % [remaining, stage]
