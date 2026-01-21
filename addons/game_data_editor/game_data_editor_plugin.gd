@tool
extends EditorPlugin

var dock: Control
var dock_button: Button

func _enter_tree():
	var dock_class = preload("res://addons/game_data_editor/game_data_dock.gd")
	dock = dock_class.new()
	dock.owner = get_editor_interface().get_base_control()
	dock_button = add_control_to_bottom_panel(dock, "Game Data Editor")
	make_bottom_panel_item_visible(dock)

func _exit_tree():
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
		dock = null
	dock_button = null
