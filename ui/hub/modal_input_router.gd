extends Node
class_name ModalInputRouter

var route: Callable
var _previous: WeakRef

func _ready() -> void:
	var window := get_parent() as Window
	if window == null: return
	window.about_to_popup.connect(func():
		_previous = null
		var parent := window.get_parent()
		if parent:
			var focused := parent.get_viewport().gui_get_focus_owner()
			if focused: _previous = weakref(focused)
		_focus_first.call_deferred(window))
	window.visibility_changed.connect(func(): if not window.visible: _restore())
	window.tree_exiting.connect(_restore)

func _focus_first(node: Node) -> bool:
	for child in node.get_children():
		if child is Control and child.focus_mode == Control.FOCUS_ALL and child.is_visible_in_tree():
			child.grab_focus()
			return true
		if _focus_first(child): return true
	return false

func _restore() -> void:
	if _previous and is_instance_valid(_previous.get_ref()):
		_previous.get_ref().grab_focus.call_deferred()

func _input(event: InputEvent) -> void:
	if InputBindings.capturing: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		route.call()
