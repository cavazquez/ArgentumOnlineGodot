extends Node

var currentScreen:Node
var _web_acceptance_started := false

func SwitchScreen(screen:Node) -> void:
	if currentScreen:
		Utils.DismissAlerts(currentScreen)
		currentScreen.queue_free()
		
	currentScreen = screen
	add_child(currentScreen)
	if OS.has_feature("web") and not _web_acceptance_started and JavaScriptBridge.eval("new URLSearchParams(location.search).get('pyao_acceptance') === '1'", true):
		_web_acceptance_started = true
		var driver: Node = load("res://tests/web_client.gd").new()
		add_child.call_deferred(driver)
