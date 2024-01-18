@tool
extends Node

class AddonsPanelManager:
	const ADDONS_DOCK_NAME = "addons_dock_2c39d5937171140c1faaadb702029b32"
	static var _addons_dock: Control
	var _editor_plugin: EditorPlugin
	var _main_panel: Control
	var _tree: SceneTree

	func _init(p_editor_plugin) -> void:
		_editor_plugin = p_editor_plugin
		_tree = EditorInterface.get_editor_main_screen().get_tree()

	func _find_addons_dock() -> Control:
		var group = _tree.get_nodes_in_group(ADDONS_DOCK_NAME)
		if group.size() > 0:
			return group[0]
		return null

	func add_main_panel(p_panel) -> void:
		if not _addons_dock:
			_addons_dock = _find_addons_dock()
		if not _addons_dock:
			_addons_dock = preload("res://addons/gdlogging/addons_shared_gen/addons_panel_manager/scenes/ui_addons_dock.tscn").instantiate()
			_addons_dock.add_to_group(ADDONS_DOCK_NAME)
			_editor_plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _addons_dock)

		_main_panel = p_panel
		_addons_dock.child_container.add_child(p_panel)
		_sort_children_alphabetically(_addons_dock.child_container)

	func _sort_children_alphabetically(p_container) -> void:
		const LABEL_NAME = "AddonTitle"
		var children: Array[Dictionary] = []
		for child in p_container.get_children():
			var label = child.find_child(LABEL_NAME)
			children.append({"label": label, "node": child})

		var sorter := func (p_a: Dictionary, p_b: Dictionary):
			var a_label: Label = p_a["label"]
			var b_label: Label = p_b["label"]

			# sort null labels to the end
			if a_label == null or b_label == null:
				return false

			return a_label.get_text().to_lower() < b_label.get_text().to_lower()

		children.sort_custom(sorter)
		for child in children:
			p_container.move_child(child["node"], p_container.get_child_count() - 1)

	func remove_main_panel() -> void:
		if not _addons_dock:
			return
		_addons_dock.child_container.remove_child(_main_panel)
		if _addons_dock.child_container.get_child_count() == 0:
			_editor_plugin.remove_control_from_docks(_addons_dock)
			_addons_dock.free()
			_addons_dock = null
