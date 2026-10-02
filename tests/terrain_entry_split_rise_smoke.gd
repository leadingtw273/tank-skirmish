extends SceneTree

const Entry := preload("res://src/ai/tank_terrain_entry.gd")
var failures: Array[String] = []

func _init() -> void:
	# Exact NE corner path points from r1-run-posx_negz, before any movement.
	var route := PackedVector3Array([
		Vector3(89.66222, 0.2, -94.73451),
		Vector3(89.16866, 0.444295, -94.43127),
		Vector3(88.47522, 0.7, -94.00525),
		Vector3(87.54999, 0.4, -90.39999),
	])
	_check(route[1].y-route[0].y < 0.3 and route[2].y-route[1].y < 0.3, "fixture must reproduce the missed split curb")
	_check(Entry._rise_end(route, 1) == 2, "the observed NE 0.5m curb must be identified before contact")
	_check(Entry._rise_end(route, 3) == -1, "descent must not trigger curb-entry guidance")
	_check(Entry._rise_end(PackedVector3Array([Vector3.ZERO, Vector3(1,0.5,0)]), 1) == 1, "single-step high curbs retain their existing behavior")
	_check(Entry._rise_end(PackedVector3Array([Vector3.ZERO, Vector3(1,0.21,0),Vector3(2,0.21,0)]), 1) == -1, "accepted low curbs must retain normal driving")
	_check(Entry._rise_end(PackedVector3Array([Vector3.ZERO,Vector3(1,0.2,0),Vector3(2,0,0),Vector3(3,0.5,0)]), 1) == -1, "separate rises cannot be merged across a descent")
	_check(Entry._rise_end(PackedVector3Array([Vector3.ZERO,Vector3(1,0.2,0),Vector3(5,0.5,0)]), 1) == -1, "long gradual terrain changes must not be combined as a short curb")
	_check(Entry._rise_end(PackedVector3Array([Vector3.ZERO,Vector3(4,0.2,0),Vector3(5,0.4,0)]), 1) == -1, "the first segment counts toward the entire short-rise distance")
	_check(Entry._rise_end(PackedVector3Array([Vector3.ZERO,Vector3(5,0.5,0)]), 1) == 1, "the existing single-jump detector retains its prior distance behavior")
	for failure in failures: push_error(failure)
	print("TERRAIN_ENTRY_SPLIT_RISE failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
