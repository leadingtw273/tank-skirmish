## Task 2：正式多 shape motion guard 的八個固定碰撞案例。
extends SceneTree

const Guard := preload("res://src/actors/tank/geometry/tank_motion_guard.gd")
const BARREL_SIZE := Vector3(0.4, 0.4, 6.0)
const BARREL_CENTER := Vector3(0.0, 0.0, -3.0)

var barrel := BoxShape3D.new()
var failures: Array[String] = []
var world := Node3D.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.add_child(world)
	barrel.size = BARREL_SIZE
	await _case_no_obstacle()
	await _case_self_excluded()
	await _case_middle_wall()
	await _case_stop_reverse()
	await _case_overlap_out_in()
	await _case_layer128()
	await _case_floor_yaw()
	await _case_old_wall_new_wall()
	if failures.is_empty():
		print("Tank motion guard fixture passed: 8 cases.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _body(label: String, size: Vector3, position: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	body.position = position
	world.add_child(body)
	return body


func _reset() -> void:
	for child in world.get_children():
		child.queue_free()
	await physics_frame


func _transform(yaw: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw)
	return Transform3D(basis, basis * BARREL_CENTER)


func _attempt(self_body: StaticBody3D, from: float, to: float) -> Dictionary:
	var guard := Guard.new()
	guard.configure(world.get_world_3d().direct_space_state, self_body.get_rid(), 1, get_node_count() + 8)
	var shape := {
		"shape": barrel,
		"start_transform": _transform(from),
		"radius": _radius(),
	}
	var candidate := func(fraction: float) -> Array[Transform3D]:
		return [_transform(lerpf(from, to, fraction))]
	return guard.attempt(to - from, [shape], candidate)


func _expect(name: String, result: Dictionary, clear: bool) -> void:
	var stats: Dictionary = result.stats
	print("%s clear=%s expected=%s fraction=%.6f actual=%.6f reason=%s queries=%d steps=%d" % [name, result.clear, clear, result.accepted_fraction, result.actual_angle, result.blocked_reason, stats.query_count, stats.substeps])
	if result.clear != clear:
		failures.append("%s expected clear=%s, got clear=%s (%s)" % [name, clear, result.clear, result.blocked_reason])


func _case_no_obstacle() -> void:
	await _reset()
	var self_body := _body("self", Vector3.ONE, Vector3(0, 0, 0.2))
	await physics_frame
	_expect("1-no-obstacle", _attempt(self_body, -0.8, 0.8), true)


func _case_self_excluded() -> void:
	await _reset()
	var self_body := _body("self-overlap", Vector3.ONE, Vector3(0, 0, -0.1))
	await physics_frame
	_expect("2-self-rid-excluded", _attempt(self_body, -0.1, 0.1), true)


func _case_middle_wall() -> void:
	await _reset()
	var self_body := _body("self", Vector3.ONE, Vector3(0, 0, 0.2))
	_body("middle-wall", Vector3(0.25, 2, 0.25), Vector3(0, 0, -5))
	await physics_frame
	_expect("3-middle-wall", _attempt(self_body, -0.8, 0.8), false)


func _case_stop_reverse() -> void:
	await _reset()
	var self_body := _body("self", Vector3.ONE, Vector3(0, 0, 0.2))
	_body("forward-wall", Vector3(0.25, 2, 0.25), Vector3(0, 0, -5))
	await physics_frame
	var forward := _attempt(self_body, -0.8, 0.8)
	_expect("4-forward-stops", forward, false)
	_expect("4-reverse-moves", _attempt(self_body, -0.8 + float(forward.actual_angle), -1.0 + float(forward.actual_angle)), true)


func _case_overlap_out_in() -> void:
	await _reset()
	var self_body := _body("self", Vector3.ONE, Vector3(0, 0, 0.2))
	_body("contact-wall", Vector3(0.2, 2, 2), Vector3(-0.3, 0, -2.5))
	await physics_frame
	_expect("5-overlap-outward", _attempt(self_body, 0.03, 0.02), true)
	_expect("5-overlap-inward", _attempt(self_body, 0.03, 0.04), false)


func _case_layer128() -> void:
	await _reset()
	var self_body := _body("self", Vector3.ONE, Vector3(0, 0, 0.2))
	_body("layer128-floor", Vector3(20, 0.2, 20), Vector3(0, -0.25, 0), 128)
	await physics_frame
	_expect("6-layer128-ignored", _attempt(self_body, 0.0, 0.5), true)


func _case_floor_yaw() -> void:
	await _reset()
	var self_body := _body("self", Vector3.ONE, Vector3(0, 0, 0.2))
	_body("layer1-floor", Vector3(20, 0.2, 20), Vector3(0, -0.25, 0), 1)
	await physics_frame
	_expect("7-layer1-floor-yaw", _attempt(self_body, 0.0, 0.3), true)


func _case_old_wall_new_wall() -> void:
	await _reset()
	var self_body := _body("self", Vector3.ONE, Vector3(0, 0, 0.2))
	_body("old-contact-wall", Vector3(0.2, 2, 2), Vector3(-0.3, 0, -2.5))
	var new_wall := _body("new-wall", Vector3(0.25, 2, 0.25), Vector3(0.35, 0, -5))
	await physics_frame
	var result := _attempt(self_body, 0.03, -0.55)
	_expect("8-old-wall-new-wall", result, false)
	if result.blocked_reason != "new-collider:%s" % new_wall.get_rid().get_id():
		failures.append("8 expected new collider gate, got %s" % result.blocked_reason)


func _radius() -> float:
	return sqrt(pow(BARREL_SIZE.x * 0.5, 2) + pow(BARREL_SIZE.y * 0.5, 2) + pow(absf(BARREL_CENTER.z) + BARREL_SIZE.z * 0.5, 2))
