extends WorldStateWindow
class_name TaxWindow

var _summary: Label
var _balances: Label
var _last: Label

func _init() -> void:
	topic = "tax"
	title = "Oro e impuestos"

func _build() -> void:
	_summary = label(body)
	_balances = label(body)
	_last = label(body)
	label(body, "El servidor liquida el impuesto aunque estés desconectado. Se aplica sobre el oro de bolsillo y del banco. Los ingresos nuevos no pagan por días anteriores a recibirlos.")

func _render() -> void:
	if state.is_empty(): return
	_summary.text = "Impuesto diario: %.2f%% · %s" % [float(state.rate_bps) / 100.0, "activo" if state.enabled else "desactivado"]
	_balances.text = "Bolsillo: %d oro\nBanco: %d oro\nTotal: %d oro" % [int(state.wallet), int(state.bank), int(state.wallet) + int(state.bank)]
	_last.text = "Último impuesto cobrado: %d oro\nTotal pagado: %d oro\nPróximo corte: %s UTC" % [int(state.last_charge), int(state.total_paid), Time.get_datetime_string_from_unix_time(int(state.next_cutoff), true)]
