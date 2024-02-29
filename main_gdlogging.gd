@tool
extends EditorPlugin

var main_panel: Control
var addons_panel_manager: Variant

func _enter_tree() -> void:
	add_autoload_singleton("Log", "res://addons/gdlogging/funcs/logger.gd")
	addons_panel_manager = load("res://addons/gdlogging/addons_shared_gen/addons_panel_manager.gd").AddonsPanelManager.new(self, "gdlogging")
	main_panel = load("res://addons/gdlogging/scenes_editor/ui_addon_panel.tscn").instantiate()
	addons_panel_manager.add_main_panel(main_panel)

func _exit_tree() -> void:
	remove_autoload_singleton("Log")
	addons_panel_manager.remove_main_panel()

func _get_plugin_icon() -> Texture2D:
	return preload ("res://addons/gdlogging/assets/icons_editor/plugin_icon_white.svg")

func _get_plugin_name() -> String:
	return "gdlogging"
