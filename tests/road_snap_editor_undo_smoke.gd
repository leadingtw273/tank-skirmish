@tool
extends EditorScript

const RoadSnapPlugin = preload("res://addons/road_snap/road_snap_plugin.gd")


func _run() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var plugin := RoadSnapPlugin.new()
	tree.root.add_child(plugin)
	await tree.process_frame

	var owner := Node3D.new()
	tree.root.add_child(owner)
	owner.global_position = Vector3(2.0, 0.0, 0.0)
	plugin._drag_start_positions = [{"owner": owner, "position": Vector3.ZERO}]
	plugin._snap_applied_during_drag = true
	plugin._schedule_snap_undo_action_after_editor_gizmo()

	_expect(plugin._snap_commit_deferred, "mouse release must leave the snap action deferred")
	# Stand in for the native gizmo release transaction. It must commit before the
	# deferred snap action, so the snap remains the top UndoRedo action.
	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("Native Move")
	undo_redo.add_do_property(owner, "global_position", Vector3(1.0, 0.0, 0.0))
	undo_redo.add_undo_property(owner, "global_position", Vector3.ZERO)
	undo_redo.commit_action(false)
	await tree.process_frame
	_expect(not plugin._snap_commit_deferred, "deferred snap action must drain after the editor idle pass")

	var owner_history := undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(owner))
	owner_history.undo()
	_expect(owner.global_position.is_equal_approx(Vector3.ZERO), "Undo must restore the drag-start position")
	owner_history.redo()
	_expect(owner.global_position.is_equal_approx(Vector3(2.0, 0.0, 0.0)), "Redo must restore the snapped position")

	owner.queue_free()
	plugin.queue_free()
	print("road_snap_editor_undo_smoke: PASS")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		(Engine.get_main_loop() as SceneTree).quit(1)
