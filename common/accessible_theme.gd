extends RefCounted
class_name AccessibleTheme

static func make(base: Theme, high_contrast: bool, font_size: int) -> Theme:
	var theme: Theme = base.duplicate() if base != null else Theme.new()
	theme.default_font_size = font_size
	if not high_contrast: return theme
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("101010")
	panel.border_color = Color.WHITE
	panel.set_border_width_all(2)
	panel.content_margin_left = 8
	panel.content_margin_right = 8
	panel.content_margin_top = 6
	panel.content_margin_bottom = 6
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("ffe070")
	focus.set_border_width_all(3)
	var selected := panel.duplicate() as StyleBoxFlat
	selected.bg_color = Color("ffe070")
	var pressed := panel.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("173c66")
	for type in ["Label", "Button", "CheckBox", "CheckButton", "LineEdit", "TextEdit", "SpinBox", "ItemList", "OptionButton", "PopupMenu", "Tree"]:
		for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			theme.set_color(color, type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color("d0d0d0"))
		theme.set_stylebox("focus", type, focus)
	for type in ["Button", "OptionButton", "LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, panel)
		theme.set_stylebox("hover", type, pressed)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("disabled", type, panel)
	for type in ["ItemList", "Tree"]:
		theme.set_stylebox("panel", type, panel)
		theme.set_stylebox("selected", type, selected)
		theme.set_stylebox("selected_focus", type, selected)
		theme.set_color("font_selected_color", type, Color.BLACK)
		theme.set_color("font_unselected_color", type, Color.WHITE)
	for type in ["AcceptDialog", "PopupPanel", "PopupMenu"]:
		theme.set_stylebox("panel", type, panel)
	theme.set_color("default_color", "RichTextLabel", Color.WHITE)
	theme.set_color("font_color", "RichTextLabel", Color.WHITE)
	theme.set_color("caret_color", "LineEdit", Color.WHITE)
	theme.set_color("selection_color", "LineEdit", Color("173c66"))
	return theme
