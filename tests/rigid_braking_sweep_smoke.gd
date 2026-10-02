## LEA-176：直接驗證 RigidBrakingSweep 的完整部位煞停包絡，不經 legacy predictor fallback。
extends SceneTree

const TankCatalog := preload("res://src/actors/tank/tank_catalog.gd")
const BrakingSweep := preload("res://src/ai/rigid_braking_sweep.gd")
const DT := 1.0 / 60.0
const SETTLE_FRAMES := 180
const MASK := 128

var _world: Node3D
var _failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	print("RIGID_BRAKING_SWEEP ticks=", Engine.physics_ticks_per_second)
	await _clear_path_is_proved_safe()
	await _middle_hull_obstacle_is_rejected()
	await _middle_gun_obstacle_is_rejected()
	await _shared_floor_rid_wall_is_rejected()
	await _support_edge_is_unknown()
	await _dynamic_obstacle_is_unknown()
	await _nonflat_support_is_unknown()
	await _fresh_snapshot_updates_geometry_velocity_and_safety()
	await _clear()
	for failure in _failures:
		push_error(failure)
	print("RIGID_BRAKING_SWEEP failures=", _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _clear_path_is_proved_safe() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank := await _spawn_tank()
	var snapshot := await _settled_snapshot(tank, "clear")
	if snapshot.is_empty(): return
	_assert_result(tank, snapshot, _path(snapshot), "clear", true, false)


func _middle_hull_obstacle_is_rejected() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank := await _spawn_tank()
	var snapshot := await _settled_snapshot(tank, "middle-hull")
	if snapshot.is_empty(): return
	var path := _path(snapshot)
	var obstacle := _box(_shape_center_at(snapshot, _hull_shape(snapshot), path[1]), Vector3(0.22, 0.22, 0.22))
	await physics_frame
	_assert_endpoints_clear(snapshot, path, obstacle, "middle-hull")
	_assert_result(tank, snapshot, path, "middle-hull", false, false)


func _middle_gun_obstacle_is_rejected() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank := await _spawn_tank()
	for unused in 120:
		tank.aim_turret_at(tank.global_position + Vector3(0.0, 0.0, 30.0), DT)
		await physics_frame
	var snapshot := await _settled_snapshot(tank, "middle-gun")
	if snapshot.is_empty(): return
	var path := _path(snapshot)
	var gun := _outer_gun_shape(snapshot, tank.global_position)
	_check(gun >= 0, "middle-gun requires a gun shape in the real tank1 snapshot")
	if gun < 0: return
	var obstacle := _box(_shape_center_at(snapshot, gun, path[1]), Vector3(0.18, 0.18, 0.18))
	obstacle.collision_layer = 64
	await physics_frame
	var geometry := _fixture_hits(snapshot, gun, path[1], 64)
	_check(bool(geometry.gun) and not bool(geometry.hull), "middle-gun obstacle must hit only gun geometry; geometry=%s" % [geometry])
	obstacle.collision_layer = MASK
	await _frames(2)
	_assert_endpoints_clear(snapshot, path, obstacle, "middle-gun")
	_assert_result(tank, snapshot, path, "middle-gun", false, false)


func _shared_floor_rid_wall_is_rejected() -> void:
	await _reset()
	var shared := StaticBody3D.new()
	shared.collision_layer = MASK
	_world.add_child(shared)
	_add_box_shape(shared, Vector3(100.0, 0.2, 80.0), Vector3(0.0, -0.1, 0.0))
	var tank := await _spawn_tank()
	var snapshot := await _settled_snapshot(tank, "shared-rid")
	if snapshot.is_empty(): return
	var path := _path(snapshot)
	_add_box_shape(shared, Vector3(0.22, 0.22, 0.22), _shape_center_at(snapshot, _hull_shape(snapshot), path[1]))
	await physics_frame
	_assert_result(tank, snapshot, path, "shared-rid-floor-wall", false, false)


func _support_edge_is_unknown() -> void:
	await _reset()
	_floor(Vector3(8.0, 0.2, 20.0))
	var tank := await _spawn_tank()
	var snapshot := await _settled_snapshot(tank, "support-edge")
	if snapshot.is_empty(): return
	_assert_result(tank, snapshot, _path(snapshot, -6.0), "support-edge", false, true)


func _dynamic_obstacle_is_unknown() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank := await _spawn_tank()
	var snapshot := await _settled_snapshot(tank, "dynamic")
	if snapshot.is_empty(): return
	var path := _path(snapshot)
	var dynamic := RigidBody3D.new()
	dynamic.freeze = true
	dynamic.collision_layer = MASK
	dynamic.position = _shape_center_at(snapshot, _hull_shape(snapshot), path[1])
	_world.add_child(dynamic)
	_add_box_shape(dynamic, Vector3(0.22, 0.22, 0.22))
	await physics_frame
	_assert_result(tank, snapshot, path, "dynamic-obstacle", false, true)


func _nonflat_support_is_unknown() -> void:
	await _reset()
	var floor := _floor(Vector3(100.0, 0.2, 80.0))
	floor.rotation.z = -deg_to_rad(6.0)
	var tank := await _spawn_tank()
	var snapshot := await _settled_snapshot(tank, "nonflat")
	if snapshot.is_empty(): return
	_assert_result(tank, snapshot, _path(snapshot), "nonflat-support", false, true)


func _fresh_snapshot_updates_geometry_velocity_and_safety() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank := await _spawn_tank()
	var before := await _settled_snapshot(tank, "fresh-before")
	if before.is_empty(): return
	var clear_path := _path(before)
	_assert_result(tank, before, clear_path, "fresh-before-clear", true, false)
	var gun_before := _shape_center_at(before, _outer_gun_shape(before, tank.global_position), before.root)
	for unused in 120:
		tank.aim_turret_at(tank.global_position + Vector3(0.0, 0.0, 30.0), DT)
		await physics_frame
	tank.request_fire()
	await _frames(2)
	var after: Dictionary = tank.predictive_driving_snapshot()
	var gun_after := _shape_center_at(after, _outer_gun_shape(after, tank.global_position), after.root)
	_check(gun_before.distance_to(gun_after) > 0.01, "turret change must be present in a fresh snapshot; before=%s after=%s" % [gun_before, gun_after])
	_check((after.linear_velocity as Vector3).distance_to(before.linear_velocity as Vector3) > 0.01, "recoil must update fresh snapshot world velocity; before=%s after=%s" % [before.linear_velocity, after.linear_velocity])
	var path := _path(after)
	_box(_shape_center_at(after, _hull_shape(after), path[1]), Vector3(0.22, 0.22, 0.22))
	await physics_frame
	_assert_result(tank, after, path, "fresh-after-obstacle", false, false)


func _assert_result(tank: RigidBody3D, snapshot: Dictionary, path: Array[Transform3D], label: String, expected_safe: bool, expected_unknown: bool) -> void:
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var result: Dictionary = BrakingSweep.check(solver, snapshot.root as Transform3D, path, 0.01)
	if expected_unknown:
		_check(result.is_empty(), "%s must return {} (unknown), not a safe/unsafe claim; result=%s" % [label, result])
	else:
		_check(not result.is_empty() and bool(result.get("safe", not expected_safe)) == expected_safe, "%s must directly return safe=%s; result=%s queries=%s" % [label, expected_safe, result, solver.queries])
	print("BRAKING_SWEEP ", label, " result=", result, " queries=", solver.queries)


func _path(snapshot: Dictionary, distance: float = -16.0) -> Array[Transform3D]:
	var start: Transform3D = snapshot.root
	var middle := start.translated(Vector3(distance * 0.5, 0.0, 0.0))
	var finish := start.translated(Vector3(distance, 0.0, 0.0))
	return [start, middle, finish]


func _assert_endpoints_clear(snapshot: Dictionary, path: Array[Transform3D], obstacle: StaticBody3D, label: String) -> void:
	var state := _world.get_world_3d().direct_space_state
	var endpoints_clear := true
	for pose in [path[0], path[2]]:
		for index in snapshot.shapes.size():
			endpoints_clear = endpoints_clear and not _shape_hits(state, snapshot.shapes[index], pose * (snapshot.root_local_transforms[index] as Transform3D), MASK, [snapshot.self_rid as RID]).any(func(hit): return hit.rid == obstacle.get_rid())
	_check(endpoints_clear, "%s obstacle must only intersect the swept middle, never either endpoint" % label)


func _fixture_hits(snapshot: Dictionary, gun: int, pose: Transform3D, mask: int) -> Dictionary:
	var state := _world.get_world_3d().direct_space_state
	var gun_hit := not _shape_hits(state, snapshot.shapes[gun], pose * (snapshot.root_local_transforms[gun] as Transform3D), mask, [snapshot.self_rid as RID]).is_empty()
	var hull_hit := false
	for part in snapshot.part_ranges:
		if String(part.anchor) != "hull": continue
		for index in range(int(part.start), int(part.start) + int(part.count)):
			hull_hit = hull_hit or not _shape_hits(state, snapshot.shapes[index], pose * (snapshot.root_local_transforms[index] as Transform3D), mask, [snapshot.self_rid as RID]).is_empty()
	return {"gun": gun_hit, "hull": hull_hit}


func _shape_hits(state: PhysicsDirectSpaceState3D, shape: Shape3D, transform: Transform3D, mask: int, exclude: Array[RID]) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = transform
	query.collision_mask = mask
	query.exclude = exclude
	return state.intersect_shape(query, 32)


func _hull_shape(snapshot: Dictionary) -> int:
	for part in snapshot.part_ranges:
		if String(part.anchor) == "hull": return int(part.start)
	return -1


func _outer_gun_shape(snapshot: Dictionary, hull_center: Vector3) -> int:
	var selected := -1
	var farthest := -INF
	for part in snapshot.part_ranges:
		if String(part.anchor) != "gun": continue
		for index in range(int(part.start), int(part.start) + int(part.count)):
			var distance := hull_center.distance_squared_to(_shape_center_at(snapshot, index, snapshot.root))
			if distance > farthest:
				farthest = distance
				selected = index
	return selected


func _shape_center_at(snapshot: Dictionary, index: int, root_pose: Transform3D) -> Vector3:
	if index < 0: return Vector3.INF
	var transform: Transform3D = root_pose * (snapshot.root_local_transforms[index] as Transform3D)
	var vertices: PackedVector3Array = snapshot.shape_vertices[index]
	var center := Vector3.ZERO
	for vertex in vertices:
		center += transform * vertex
	return center / float(vertices.size()) if not vertices.is_empty() else transform.origin


func _settled_snapshot(tank: RigidBody3D, label: String) -> Dictionary:
	await _frames(SETTLE_FRAMES)
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "%s needs a truly grounded TankCatalog.tank1 snapshot; snapshot=%s" % [label, snapshot])
	return snapshot if bool(snapshot.get("grounded", false)) else {}


func _reset() -> void:
	await _clear()
	_world = Node3D.new()
	root.add_child(_world)


func _clear() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		await _frames(2)
	_world = null


func _floor(size: Vector3) -> StaticBody3D:
	return _box(Vector3(0.0, -0.1, 0.0), size)


func _box(center: Vector3, size: Vector3, parent: Node3D = _world) -> StaticBody3D:
	var body := parent as StaticBody3D
	var local_center := center
	if body == null:
		body = StaticBody3D.new()
		body.collision_layer = MASK
		body.position = center
		_world.add_child(body)
		local_center = Vector3.ZERO
	_add_box_shape(body, size, local_center)
	return body


func _add_box_shape(parent: Node3D, size: Vector3, local_center: Vector3 = Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = local_center
	parent.add_child(collision)


func _spawn_tank() -> RigidBody3D:
	var tank := TankCatalog.instantiate(&"tank1") as RigidBody3D
	_check(tank != null, "TankCatalog.tank1 must instantiate as RigidBody3D")
	if tank == null: return null
	tank.position = Vector3(0.0, 2.0, 0.0)
	_world.add_child(tank)
	await _frames(2)
	return tank


func _frames(count: int) -> void:
	for unused in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
