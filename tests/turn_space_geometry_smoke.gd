extends SceneTree

const Helper := preload("res://src/ai/tank_turn_space.gd")
var failures: Array[String] = []

func _init() -> void:
	var helper := Helper.new()
	var route := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(4, 0, 8), Vector3(8, 0, 8)])
	var corners: Array[Dictionary] = helper._nms([
		{"arc": 4.0, "angle": 30.0}, {"arc": 5.0, "angle": 80.0}, {"arc": 12.0, "angle": 45.0}])
	_check(corners.size() == 2 and float(corners[0].arc) == 5.0, "NMS must keep the sharper nearby corner")
	helper.capture(route, RID())
	_check(helper.has_plan(), "first route must be retained")
	helper.capture(PackedVector3Array([Vector3.ZERO, Vector3(1,0,0), Vector3(2,0,0)]), RID())
	_check(helper.get_trace().captured == route.size(), "duplicate capture must be rejected")
	var no_budget := helper.step(Time.get_ticks_usec() + 1000000, 0)
	_check(int(no_budget.query_count) == 0, "zero budget must not query")
	helper._path = route
	helper._arc = helper._arc_lengths(route)
	_check(helper._rise_end(1) == -1, "flat route cannot be classified as a rise")
	## Ranking input is candidate-floor minus the measured upstream floor, never route-point Y.
	helper._candidate_accepted = [
		{"point": Vector3(1, 9, 1), "arc": 4.0, "score": 1.0, "height_delta": 0.023},
		{"point": Vector3(2, 9, 2), "arc": 4.0, "score": 99.0, "height_delta": 0.014}]
	helper._finish_corner_candidates()
	_check((helper._queue[0].point as Vector3).is_equal_approx(Vector3(2, 9, 2)), "upstream-floor .015m bucket must rank before path score even when route Y differs")
	# A completed earlier corner must not wait for later candidate work.
	helper._state = &"evaluating"
	var first_ready := helper.take_next(route[0])
	_check(not first_ready.is_empty() and first_ready.point == Vector3(2, 9, 2), "a completed first guide must be available while later corners are still evaluating")
	_check(helper._state == &"evaluating" and helper.take_next(route[0]).is_empty(), "taking a ready guide must not finish planning or expose an unfinished candidate")
	var expired := {"deadline": Time.get_ticks_usec() - 1, "count": 0, "max": 4096}
	_check(helper._nms(corners, expired).is_empty() and bool(expired.get("exhausted", false)), "expired corner scan must remain unknown, not publish partial NMS")
	_check(not helper._point_at(4.0, expired).is_finite(), "expired route lookup must not return an unverified point")
	_check(not is_finite(helper._path_length(route, expired)), "expired path scoring must not rank a partial path")
	var ground := StaticBody3D.new()
	var roads := Node3D.new()
	var unknown := StaticBody3D.new()
	helper._ground = ground
	helper._roads = roads
	_check(helper._is_support({"collider": ground}), "Ground itself is a support collider even without a shape-hit normal")
	_check(not helper._is_support({"collider": unknown}) and not helper._is_support({}), "unknown and missing colliders must not become support")
	ground.free(); roads.free(); unknown.free()
	for failure: String in failures: push_error(failure)
	print("TURN_SPACE_GEOMETRY failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
