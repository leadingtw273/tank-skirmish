extends SceneTree

const RoadSnapPlugin = preload("res://addons/road_snap/road_snap_plugin.gd")
const EditorUndoSmoke = preload("res://tests/road_snap_editor_undo_smoke.gd")


func _init() -> void:
	_expect(RoadSnapPlugin != null, "Road Snap plugin must parse")
	_expect(EditorUndoSmoke != null, "Road Snap editor undo smoke must parse")
	print("road_snap_plugin_parse_smoke: PASS")
	quit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
