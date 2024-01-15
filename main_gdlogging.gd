@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("Log", "logger.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("Log")

func _get_plugin_icon():
	return preload("assets/icons/plugin_icon_white.svg")

func _get_plugin_name():
	return "gdlogging"
