extends VBoxContainer
class_name ClanProfileEditor

signal save_requested(params: Dictionary)
var description: LineEdit
var news: LineEdit
var website: LineEdit
var save: Button
var rebase: Button
var public_profile: Label
var notice: Label
var _form: VBoxContainer
var _remote := {}
var _clan := 0
var _version := 0
var _accepted_version := -1
var _dirty := false
var _loading := false
var _pending := false

func _ready() -> void:
	public_profile = Label.new()
	public_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(public_profile)
	_form = VBoxContainer.new()
	add_child(_form)
	for field in ["Códice / descripción", "Noticias", "Sitio web (https://…)"]:
		var caption := Label.new()
		caption.text = field
		_form.add_child(caption)
		var input := LineEdit.new()
		input.max_length = 200
		input.text_changed.connect(func(_value: String):
			if not _loading: _dirty = true)
		_form.add_child(input)
		match field:
			"Códice / descripción": description = input
			"Noticias": news = input
			_: website = input
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(notice)
	var buttons := HFlowContainer.new()
	_form.add_child(buttons)
	save = Button.new()
	save.text = "Guardar ficha pública"
	save.pressed.connect(func(): save_requested.emit({"clan": _clan, "version": _version, "description": description.text, "news": news.text, "website": website.text}))
	buttons.add_child(save)
	rebase = Button.new()
	rebase.text = "Revisé los cambios; conservar mi borrador"
	rebase.pressed.connect(func():
		_version = int(_remote.get("version", 0))
		notice.text = "Borrador conservado sobre la versión revisada. Podés guardarlo."
		rebase.hide()
		save.disabled = _pending or not _form.visible)
	buttons.add_child(rebase)
	_form.hide()

func Apply(state: Dictionary, pending: bool) -> void:
	_pending = pending
	if state.is_empty():
		_form.hide()
		public_profile.hide()
		save.disabled = true
		return
	var profile: Dictionary = state.get("profile", {})
	var clan_id := int(state.get("clan_id", 0))
	public_profile.visible = clan_id > 0
	public_profile.text = "Códice: %s\nNoticias: %s\nSitio: %s" % [profile.get("description", ""), profile.get("news", ""), profile.get("website", "")]
	_form.visible = "profile" in state.get("permissions", [])
	if _clan != clan_id:
		_clan = clan_id
		_dirty = false
		_accepted_version = -1
	_remote = profile.duplicate(true)
	var version := int(profile.get("version", 0))
	if not _dirty and version >= _accepted_version:
		_loading = true
		description.text = profile.get("description", "")
		news.text = profile.get("news", "")
		website.text = profile.get("website", "")
		_version = version
		_loading = false
	var conflict := _dirty and version != _version
	if conflict: notice.text = "La ficha publicada cambió. Tu borrador sigue intacto; comparalo con los datos de arriba."
	rebase.visible = conflict
	rebase.disabled = pending
	save.disabled = pending or not _form.visible or profile.is_empty() or conflict
	for input in [description, news, website]: input.editable = not pending

func Confirmed(result: Dictionary) -> void:
	if result.get("applied", false):
		_accepted_version = int(result.get("version", _version + 1))
		_dirty = false
		notice.text = "Ficha guardada por el servidor."
