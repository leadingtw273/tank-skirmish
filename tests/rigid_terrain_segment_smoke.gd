## LEA-177：TerrainSegment 只可取代舊 _ground_segment 微步，不能擴張可通行幾何。
extends SceneTree

const Tank2 := preload("res://src/actors/rigid_tank/player_rigid_tank.tscn")
const TerrainSegment := preload("res://src/ai/rigid_terrain_segment.gd")
const MeshSupport := preload("res://src/ai/planar_mesh_support.gd")
const DT := 0.01
const STEPS := 10
const SETTLE_TICKS := 180

var world: Node3D
var failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	await _safe_equivalence("flat", false, false)
	await _slope_falls_back()
	await _curb_equivalence()
	await _high_wall_falls_back()
	await _gun_bridge_margin_falls_back()
	await _adjacent_concave_high_point_keeps_equivalence()
	await _concave_thin_wall_falls_back()
	await _rotating_gun_concave_wall_falls_back()
	await _unknown_and_dynamic_fall_back()
	await _old_contact_and_cap_fall_back()
	await _clear()
	for failure: String in failures: push_error(failure)
	print("RIGID_TERRAIN_SEGMENT failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _safe_equivalence(label: String, pitched: bool, curb: bool) -> void:
	await _reset()
	var floor: StaticBody3D = _floor(Vector3(100.0, 0.2, 80.0))
	if pitched: floor.rotation.z = deg_to_rad(8.0)
	if curb: _box(Vector3(0.8, 0.44, 8.0), Vector3(-2.5, 0.22, 0.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, label)
	if snapshot.is_empty(): return
	var states: Array[Dictionary] = _states()
	var old_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var new_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var old_result: Dictionary = _oracle(old_solver, snapshot.root as Transform3D, states, DT, 0.0, true)
	var new_result: Dictionary = TerrainSegment.try_segment(new_solver, snapshot.root as Transform3D, states, DT, 0.0, true)
	_assert_no_false_safe(label, old_result, new_result)
	_check(bool(old_result.get("safe", false)) and bool(new_result.get("safe", false)),
		"%s requires both old and new terrain microsteps safe; old=%s new=%s" % [label, old_result, new_result])
	if bool(old_result.get("safe", false)) and bool(new_result.get("safe", false)):
		_assert_equivalent(label, old_result, new_result)
		print("TERRAIN_SEGMENT_QUERY_DATA label=", label, " new=", new_solver.queries, " old=", old_solver.queries)
		if curb:
			var root_after: Transform3D = new_result.root as Transform3D
			_check(root_after.basis.y.angle_to(Vector3.UP) > 0.001,
				"curb-0.44 must retain a non-flat support state, not merely a distant curb; root=%s" % root_after)


func _curb_equivalence() -> void:
	await _safe_equivalence("curb-0.44", false, true)


func _slope_falls_back() -> void:
	await _reset()
	var floor: StaticBody3D = _floor(Vector3(100.0, 0.2, 80.0))
	floor.rotation.z = deg_to_rad(8.0)
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "pitched-support")
	if snapshot.is_empty(): return
	var old_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var new_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var states: Array[Dictionary] = _states()
	var old_result: Dictionary = _oracle(old_solver, snapshot.root as Transform3D, states, DT, 0.0, true)
	var new_result: Dictionary = TerrainSegment.try_segment(new_solver, snapshot.root as Transform3D, states, DT, 0.0, true)
	_assert_no_false_safe("pitched-support", old_result, new_result)
	_check(bool(old_result.get("safe", false)) and new_result.is_empty(),
		"non-flat slope must leave the conservative segment helper as fallback while old microsteps remain available; old=%s new=%s" % [old_result, new_result])


func _high_wall_falls_back() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "high-wall")
	if snapshot.is_empty(): return
	var root_pose: Transform3D = snapshot.root as Transform3D
	_box(Vector3(0.3, 5.0, 8.0), root_pose.origin - root_pose.basis.x.normalized() * 2.7 + Vector3.UP * 2.0)
	await physics_frame
	_assert_empty("high-wall", tank, snapshot)


func _gun_bridge_margin_falls_back() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "gun-bridge")
	if snapshot.is_empty(): return
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var gun_part: Dictionary = _gun_part(snapshot, solver)
	_check(not gun_part.is_empty(), "gun bridge fixture requires a readable Tank2 gun part")
	if gun_part.is_empty(): return
	var box: AABB = (snapshot.root as Transform3D) * (gun_part.box as AABB)
	var bridge: StaticBody3D = StaticBody3D.new()
	bridge.collision_layer = 128
	world.add_child(bridge)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(box.size.x + 0.10, 0.02, box.size.z + 0.10)
	shape.margin = 0.05
	collision.shape = shape
	bridge.add_child(collision)
	collision.global_position = Vector3(box.get_center().x, box.end.y + shape.margin * 0.5, box.get_center().z)
	await physics_frame
	_assert_empty("thin-gun-bridge-with-shape-margin", tank, snapshot)


## Concave AABB 可因相鄰高點進入 broad phase；若所有真三角面都在完整 padded part volume 外，segment 仍須與舊微步同樣可通行。
func _adjacent_concave_high_point_keeps_equivalence() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "adjacent-concave-high-point")
	if snapshot.is_empty(): return
	var probe: RefCounted = tank.create_ground_motion_query(snapshot)
	var gun: Dictionary = _gun_part(snapshot, probe)
	_check(not gun.is_empty(), "adjacent Concave fixture requires gun part")
	if gun.is_empty(): return
	var start: Transform3D = snapshot.root as Transform3D
	# cache 假命中只驗 broad cache 邊界，不混入曲線積分；曲線由既有 curb／gun AC 覆蓋。
	var states: Array[Dictionary] = _stationary_states()
	var padded_parts: Array[AABB] = _swept_part_volumes(probe, start, states)
	_check(not padded_parts.is_empty(), "adjacent Concave fixture requires all padded swept part volumes")
	if padded_parts.is_empty(): return
	var outer := AABB()
	for index in padded_parts.size():
		outer = outer.merge(padded_parts[index]) if index > 0 else padded_parts[index]
	# 選完整 all-parts 聯集的最右 padded 邊界外 .15m：在 .25m broad 膨脹帶內，但與每個真 part 包絡分離。
	var x: float = outer.end.x + 0.15
	var center: Vector3 = outer.get_center()
	var building: StaticBody3D = _concave(_vertical_wall(x, center.z - 1.0, center.z + 1.0, outer.position.y, outer.end.y + 3.0))
	await physics_frame
	var hits: Array = probe._broad_hits(outer, 64)
	var broad_hit := false
	for hit: Dictionary in hits:
		if hit.rid == building.get_rid(): broad_hit = true
	_check(broad_hit, "adjacent high Concave must enter expanded broad phase while remaining outside padded gun volume")
	var building_hit := {"rid": building.get_rid(), "shape": 0, "collider": building}
	_check(MeshSupport.outside_parts(probe, building_hit, Transform3D.IDENTITY, padded_parts),
		"adjacent high Concave must be natively separated from every full padded swept part volume")
	var old_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var new_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var old_result: Dictionary = _oracle(old_solver, start, states, DT, 0.0, true)
	var new_result: Dictionary = TerrainSegment.try_segment(new_solver, start, states, DT, 0.0, true)
	_check(bool(old_result.get("safe", false)) and bool(new_result.get("safe", false)),
		"expanded-broad-only Concave high point must retain safe old/new segment results; old=%s new=%s" % [old_result, new_result])
	if bool(old_result.get("safe", false)) and bool(new_result.get("safe", false)): _assert_equivalent("adjacent-concave-high-point", old_result, new_result)


func _swept_part_volumes(solver: RefCounted, start: Transform3D, states: Array[Dictionary]) -> Array[AABB]:
	var poses: Array[Transform3D] = [start]
	var current: Transform3D = start
	var maximum_angle := 0.0
	var previous: Transform3D = start
	for state: Dictionary in states:
		current.basis = Basis(Vector3.UP, float(state.angular_speed) * DT) * current.basis
		current.origin += current.basis * Vector3.LEFT * float(state.forward_speed) * DT + (state.get("drift", Vector3.ZERO) as Vector3)
		poses.append(current)
		var difference := (previous.basis.x-current.basis.x).length_squared() + (previous.basis.y-current.basis.y).length_squared() + (previous.basis.z-current.basis.z).length_squared()
		maximum_angle = maxf(maximum_angle, 2.0 * asin(minf(1.0, sqrt(difference) * 0.5)))
		previous = current
	var result: Array[AABB] = []
	for part: Dictionary in solver.part_bounds:
		var volume: AABB = poses[0] * (part.box as AABB)
		for pose: Transform3D in poses: volume = volume.merge(pose * (part.box as AABB))
		result.append(volume.grow(float(part.radius) * maximum_angle + solver.MARGIN * 2.0))
	return result


func _stationary_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unused: int in STEPS: result.append({"forward_speed": 0.0, "angular_speed": 0.0, "drift": Vector3.ZERO})
	return result


func _concave_thin_wall_falls_back() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "concave-thin-wall")
	if snapshot.is_empty(): return
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var gun: Dictionary = _gun_part(snapshot, solver)
	_check(not gun.is_empty(), "Concave thin wall requires gun part")
	if gun.is_empty(): return
	var box: AABB = (snapshot.root as Transform3D) * (gun.box as AABB)
	_concave(_vertical_wall(box.get_center().x, box.get_center().z - 0.30, box.get_center().z + 0.30, box.position.y, box.end.y))
	await physics_frame
	_assert_empty("concave-thin-wall-in-gun-volume", tank, snapshot)


func _rotating_gun_concave_wall_falls_back() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "rotating-gun-concave-wall")
	if snapshot.is_empty(): return
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var gun: Dictionary = _gun_part(snapshot, solver)
	_check(not gun.is_empty(), "rotating Concave wall requires gun part")
	if gun.is_empty(): return
	var start: Transform3D = snapshot.root as Transform3D
	var middle := start
	middle.basis = Basis(Vector3.UP, PI * 0.5) * start.basis
	var finish := start
	finish.basis = Basis(Vector3.UP, PI) * start.basis
	var middle_box: AABB = middle * (gun.box as AABB)
	_concave(_vertical_wall(middle_box.get_center().x, middle_box.get_center().z - 0.30, middle_box.get_center().z + 0.30, middle_box.position.y, middle_box.end.y))
	await physics_frame
	_check(not TerrainSegment._clear(solver, [start, middle, finish]),
		"Concave thin wall in gun rotation swept volume must reject full-part clear proof")


func _unknown_and_dynamic_fall_back() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "unknown")
	if snapshot.is_empty(): return
	var root_pose: Transform3D = snapshot.root as Transform3D
	var unknown: StaticBody3D = StaticBody3D.new()
	unknown.collision_layer = 128
	world.add_child(unknown)
	var mesh: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	mesh.data = PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 1, 1)])
	var unknown_collision: CollisionShape3D = CollisionShape3D.new()
	unknown_collision.shape = mesh
	unknown.add_child(unknown_collision)
	unknown.global_position = root_pose.origin - root_pose.basis.x.normalized() * 2.7 + Vector3.UP
	await physics_frame
	_assert_empty("unknown-concave", tank, snapshot)
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	tank = await _spawn()
	await _frames(SETTLE_TICKS)
	snapshot = _snapshot(tank, "dynamic")
	if snapshot.is_empty(): return
	root_pose = snapshot.root as Transform3D
	var moving: RigidBody3D = RigidBody3D.new()
	moving.freeze = true
	moving.collision_layer = 128
	moving.position = root_pose.origin - root_pose.basis.x.normalized() * 2.7 + Vector3.UP * 2.0
	world.add_child(moving)
	_add_shape(moving, Vector3(0.3, 5.0, 8.0))
	await physics_frame
	_assert_empty("dynamic-obstacle", tank, snapshot)


func _old_contact_and_cap_fall_back() -> void:
	await _reset()
	_floor(Vector3(100.0, 0.2, 80.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = _snapshot(tank, "old-contact-cap")
	if snapshot.is_empty(): return
	var states: Array[Dictionary] = _states()
	var policy_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	policy_solver.set_contact_policy(Callable(self, "_old_contact_policy"))
	var policy_result: Dictionary = TerrainSegment.try_segment(policy_solver, snapshot.root as Transform3D, states, DT, 0.0, true)
	_check(policy_result.is_empty(), "old-contact policy must retain per-pose fallback; result=%s" % policy_result)
	var cap_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	cap_solver.query_limit = 0
	var cap_result: Dictionary = TerrainSegment.try_segment(cap_solver, snapshot.root as Transform3D, states, DT, 0.0, true)
	_check(cap_result.is_empty() and cap_solver.at_cap, "query cap must return fallback, never segment safe; result=%s cap=%s" % [cap_result, cap_solver.at_cap])


func _assert_empty(label: String, tank: RigidBody3D, snapshot: Dictionary) -> void:
	var before: Transform3D = tank.global_transform
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var result: Dictionary = TerrainSegment.try_segment(solver, snapshot.root as Transform3D, _states(), DT, 0.0, true)
	_check(result.is_empty(), "%s must return {} and leave old microsteps available; result=%s" % [label, result])
	_check(tank.global_transform.is_equal_approx(before), "%s must not write the true Tank2 root" % label)


func _oracle(solver: RefCounted, start: Transform3D, states: Array[Dictionary], delta: float, vertical: float, grounded: bool) -> Dictionary:
	var current: Transform3D = start
	for state: Dictionary in states:
		solver.blocker = {}
		var rotated: Transform3D = Transform3D(Basis(Vector3.UP, float(state.angular_speed) * delta) * current.basis, current.origin)
		var result: Dictionary = {"safe": false}
		if is_zero_approx(float(state.angular_speed)) or solver.clear_pose(rotated):
			var motion: Vector3 = rotated.basis * Vector3.LEFT * float(state.forward_speed) * delta + (state.get("drift", Vector3.ZERO) as Vector3)
			result = solver.advance(rotated, motion, delta, vertical, grounded)
		if not bool(result.get("safe", false)): return {"safe": false}
		current = result.root as Transform3D
		vertical = float(result.vertical_speed)
		grounded = bool(result.grounded)
	return {"safe": true, "root": current, "speed": float(states[-1].forward_speed), "angular": float(states[-1].angular_speed), "vertical_speed": vertical, "grounded": grounded}


func _states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for unused: int in STEPS:
		states.append({"forward_speed": 2.0, "angular_speed": 0.2, "drift": Vector3.ZERO})
	return states


func _assert_no_false_safe(label: String, old_result: Dictionary, new_result: Dictionary) -> void:
	_check(not (bool(new_result.get("safe", false)) and not bool(old_result.get("safe", false))),
		"%s must not be safe in full segment proof when old microsteps reject; old=%s new=%s" % [label, old_result, new_result])


func _assert_equivalent(label: String, old_result: Dictionary, new_result: Dictionary) -> void:
	var old_root: Transform3D = old_result.root as Transform3D
	var new_root: Transform3D = new_result.root as Transform3D
	_check(old_root.origin.distance_to(new_root.origin) <= 0.00001 and old_root.basis.get_rotation_quaternion().angle_to(new_root.basis.get_rotation_quaternion()) <= 0.00001
		and absf(float(old_result.speed) - float(new_result.speed)) <= 0.00001 and absf(float(old_result.angular) - float(new_result.angular)) <= 0.00001
		and absf(float(old_result.vertical_speed) - float(new_result.vertical_speed)) <= 0.00001 and bool(old_result.grounded) == bool(new_result.grounded),
		"%s full safe result must equal old microsteps to 1e-5; old=%s new=%s" % [label, old_result, new_result])


func _gun_part(snapshot: Dictionary, solver: RefCounted) -> Dictionary:
	var ranges: Array = snapshot.part_ranges as Array
	for range_data: Dictionary in ranges:
		if String(range_data.get("anchor", "")) != "gun": continue
		var first: int = int(range_data.start)
		for part: Dictionary in solver.part_bounds:
			if (part.indices as Array).has(first): return part
	return {}


func _reset() -> void:
	await _clear()
	world = Node3D.new()
	root.add_child(world)


func _clear() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _frames(2)
	world = null


func _floor(size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 128
	body.position = Vector3(0.0, -0.1, 0.0)
	world.add_child(body)
	_add_shape(body, size)
	return body


func _box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 128
	body.position = center
	world.add_child(body)
	_add_shape(body, size)
	return body


func _concave(faces: PackedVector3Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 128
	world.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.data = faces
	collision.shape = shape
	body.add_child(collision)
	return body


func _vertical_wall(x: float, min_z: float, max_z: float, min_y: float, max_y: float) -> PackedVector3Array:
	var a := Vector3(x, min_y, min_z)
	var b := Vector3(x, min_y, max_z)
	var c := Vector3(x, max_y, max_z)
	var d := Vector3(x, max_y, min_z)
	return PackedVector3Array([a, b, c, a, c, d, a, c, b, a, d, c])


func _add_shape(body: CollisionObject3D, size: Vector3) -> CollisionShape3D:
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return collision


func _spawn() -> RigidBody3D:
	var tank: RigidBody3D = Tank2.instantiate() as RigidBody3D
	_check(tank != null, "Tank2 must instantiate")
	if tank == null: return null
	tank.position = Vector3(0.0, 2.0, 0.0)
	world.add_child(tank)
	await _frames(2)
	return tank


func _snapshot(tank: RigidBody3D, label: String) -> Dictionary:
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "%s requires true grounded Tank2 snapshot" % label)
	return snapshot if bool(snapshot.get("grounded", false)) else {}


func _old_contact_policy(_index: int, _pose: Transform3D, _rid: RID, _pairs: PackedVector3Array) -> bool:
	return false


func _frames(count: int) -> void:
	for unused: int in count: await physics_frame


func _check(condition: bool, detail: String) -> void:
	if not condition: failures.append(detail)
