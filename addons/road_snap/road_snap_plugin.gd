@tool
extends EditorPlugin

const RoadSnapSolver = preload("res://addons/road_snap/road_snap_solver.gd")
const SETTING_RADIUS := "road_snap/snapping/radius_meters"
const SETTING_ANGLE := "road_snap/snapping/opposing_angle_tolerance_degrees"
const DEFAULT_RADIUS := 1.25
const DEFAULT_ANGLE_DEGREES := 8.0

var _right_alt_down := false
var _left_drag_down := false
var _snap_deferred := false
var _snap_commit_deferred := false
var _drag_start_positions: Array[Dictionary] = []
var _snap_applied_during_drag := false


func _enter_tree() -> void:
	_register_settings()
	set_input_event_forwarding_always_enabled()


func _handles(_object: Object) -> bool:
	return true


func _forward_3d_gui_input(_viewport_camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ALT and key_event.location == KEY_LOCATION_RIGHT:
			_right_alt_down = key_event.pressed
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_left_drag_down = mouse_button.pressed
			if _left_drag_down:
				_capture_drag_start_positions()
			else:
				_schedule_snap_undo_action_after_editor_gizmo()
	elif event is InputEventMouseMotion and _left_drag_down and _right_alt_down:
		_schedule_snap_after_editor_gizmo()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _register_settings() -> void:
	var settings := get_editor_interface().get_editor_settings()
	_register_setting(settings, SETTING_RADIUS, DEFAULT_RADIUS, "0.05,10.0,0.05,suffix:m")
	_register_setting(settings, SETTING_ANGLE, DEFAULT_ANGLE_DEGREES, "0.5,45.0,0.5,suffix:°")


func _register_setting(settings: EditorSettings, name: String, default_value: float, hint: String) -> void:
	settings.set_initial_value(name, default_value, false)
	if not settings.has_setting(name):
		settings.set_setting(name, default_value)
	settings.add_property_info({"name": name, "type": TYPE_FLOAT, "hint": PROPERTY_HINT_RANGE, "hint_string": hint})


func _schedule_snap_after_editor_gizmo() -> void:
	if _snap_deferred:
		return
	_snap_deferred = true
	call_deferred("_snap_after_editor_gizmo")


func _snap_after_editor_gizmo() -> void:
	_snap_deferred = false
	if not _left_drag_down or not _right_alt_down:
		return
	var owners := _selected_transform_owners()
	if owners.is_empty():
		return
	var selected_modules := _modules_below(owners)
	if selected_modules.is_empty():
		return
	var source_points: Array[Dictionary] = []
	for module in selected_modules:
		source_points.append_array(RoadSnapSolver.collect_module_endpoints(module))
	var target_points: Array[Dictionary] = []
	var scene_root := get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return
	for module in _modules_below([scene_root]):
		if not selected_modules.has(module):
			target_points.append_array(RoadSnapSolver.collect_module_endpoints(module))
	var settings := get_editor_interface().get_editor_settings()
	var match := RoadSnapSolver.find_nearest_compatible(source_points, target_points, selected_modules, float(settings.get_setting(SETTING_RADIUS)), float(settings.get_setting(SETTING_ANGLE)))
	if match.is_empty():
		return
	var translation := match["translation"] as Vector3
	if translation.is_zero_approx():
		return
	# Only origins change. Bases and local child transforms remain intact, so a
	# selected container moves as one rigid group.
	for owner in owners:
		owner.global_position += translation
	_snap_applied_during_drag = true


func _capture_drag_start_positions() -> void:
	_drag_start_positions.clear()
	_snap_applied_during_drag = false
	for owner in _selected_transform_owners():
		_drag_start_positions.append({"owner": owner, "position": owner.global_position})


func _schedule_snap_undo_action_after_editor_gizmo() -> void:
	if _snap_commit_deferred:
		return
	_snap_commit_deferred = true
	# The native gizmo creates its Move action when it handles mouse release.
	# Commit afterward so Undo first reverses this snap instead of a later native
	# action replacing its final position.
	call_deferred("_commit_snap_undo_action_after_editor_gizmo")


func _commit_snap_undo_action_after_editor_gizmo() -> void:
	_snap_commit_deferred = false
	_commit_snap_undo_action()


func _commit_snap_undo_action() -> void:
	if not _snap_applied_during_drag or _drag_start_positions.is_empty():
		_drag_start_positions.clear()
		return
	var undo_redo := get_undo_redo()
	# A separate transaction makes the plugin-owned deferred translation
	# reversible even if a Godot version does not fold it into the gizmo action.
	undo_redo.create_action("Snap Road Modules")
	for entry in _drag_start_positions:
		var owner := entry["owner"] as Node3D
		if is_instance_valid(owner):
			undo_redo.add_do_property(owner, "global_position", owner.global_position)
			undo_redo.add_undo_property(owner, "global_position", entry["position"])
	undo_redo.commit_action(false)
	_drag_start_positions.clear()
	_snap_applied_during_drag = false


func _selected_transform_owners() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for selected in get_editor_interface().get_selection().get_selected_nodes():
		if selected is Node3D:
			candidates.append(selected)
	var owners: Array[Node3D] = []
	for candidate in candidates:
		var nested := false
		for other in candidates:
			if candidate != other and other.is_ancestor_of(candidate):
				nested = true
				break
		if not nested:
			owners.append(candidate)
	return owners


func _modules_below(roots: Array) -> Array[Node]:
	var modules: Array[Node] = []
	for root in roots:
		_collect_modules(root, modules)
	return modules


func _collect_modules(node: Node, modules: Array[Node]) -> void:
	if node is StaticBody3D and node.get_meta("road_module", false):
		modules.append(node)
		return
	for child in node.get_children():
		_collect_modules(child, modules)
