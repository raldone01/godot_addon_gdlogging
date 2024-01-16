@tool
extends Control

@onready
var option_button_log_level: OptionButton = $%OptionButtonLogLevel

func _ready() -> void:
	option_button_log_level.connect("item_selected", _on_option_button_log_level_item_selected)

func _on_option_button_log_level_item_selected(p_index: int) -> void:
	var log_level: Log.LogLevel = p_index
	Log.set_level(log_level)
