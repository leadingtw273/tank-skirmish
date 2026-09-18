extends SceneTree

const Solver = preload("res://addons/road_snap/road_snap_solver.gd")

func _init() -> void:
	_test_nearest_endpoint_wins()
	_test_inner_and_outer_are_name_agnostic()
	_test_opposing_angle_is_required()
	_test_selected_module_is_excluded()
	_test_group_translation_preserves_offsets()
	print("road_snap_solver_smoke: PASS")
	quit()

func _point(owner: String, position: Vector3, outward: Vector3) -> Dictionary:
	return {"owner": owner, "position": position, "outward": outward.normalized()}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)

func _test_nearest_endpoint_wins() -> void:
	var match := Solver.find_nearest_compatible([_point("moving", Vector3.ZERO, Vector3.FORWARD)], [_point("far", Vector3(1.0, 0, 0), Vector3.BACK), _point("near", Vector3(0.25, 0, 0), Vector3.BACK)], ["moving"], 1.25, 8.0)
	_expect(match.get("target", {}).get("owner") == "near", "nearest compatible endpoint must win")

func _test_inner_and_outer_are_name_agnostic() -> void:
	var match := Solver.find_nearest_compatible([_point("outer-ish", Vector3.ZERO, Vector3.FORWARD)], [_point("inner-ish", Vector3(0.5, 0, 0), Vector3.BACK)], ["outer-ish"], 1.25, 8.0)
	_expect(not match.is_empty(), "marker names must not affect matching")

func _test_opposing_angle_is_required() -> void:
	var match := Solver.find_nearest_compatible([_point("moving", Vector3.ZERO, Vector3.FORWARD)], [_point("same-way", Vector3(0.25, 0, 0), Vector3.FORWARD)], ["moving"], 1.25, 8.0)
	_expect(match.is_empty(), "same-direction endpoints must not snap")

func _test_selected_module_is_excluded() -> void:
	var match := Solver.find_nearest_compatible([_point("first", Vector3.ZERO, Vector3.FORWARD)], [_point("second", Vector3(0.25, 0, 0), Vector3.BACK)], ["first", "second"], 1.25, 8.0)
	_expect(match.is_empty(), "another module in the moving selection must not be a target")

func _test_group_translation_preserves_offsets() -> void:
	var before: Array[Vector3] = [Vector3(10, 0, 5), Vector3(13, 0, 9)]
	var after := Solver.translate_positions(before, Vector3(-2, 0, 4))
	_expect((after[1] - after[0]).is_equal_approx(before[1] - before[0]), "group translation must preserve offsets")
