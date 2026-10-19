extends WorldStateWindow
class_name TaxWindow

var _summary: Label
var _balances: Label
var _last: Label

func _init() -> void:
	topic = "tax"
	title = "Oro y devaluación"

func _build() -> void:
	_summary = label(body)
	_balances = label(body)
	_last = label(body)
	label(body, "Cada día desaparece el porcentaje indicado del oro, estés conectado o no. Se aplica al bolsillo, al banco y a los montones del suelo. Tirar o recoger oro no evita la devaluación. Los montos recién generados empiezan en el próximo corte.")

func _render() -> void:
	if state.is_empty(): return
	_summary.text = "Devaluación diaria: %.2f%% · %s" % [float(state.rate_bps) / 100.0, "activo" if state.enabled else "desactivado"]
	_balances.text = "Bolsillo: %d oro\nBanco: %d oro\nTotal en bolsillo y banco: %d oro" % [int(state.wallet), int(state.bank), int(state.wallet) + int(state.bank)]
	_last.text = "Última reducción: %d oro\nReducción acumulada: %d oro\nPróximo corte: %s UTC" % [int(state.last_charge), int(state.total_paid), Time.get_datetime_string_from_unix_time(int(state.next_cutoff), true)]
