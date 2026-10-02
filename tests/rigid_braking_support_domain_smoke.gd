## LEA-177：制動 sweep 的道路覆蓋只約束 hull／履帶與四個支撐柱；砲塔、砲管仍必須參與完整障礙碰撞。
extends SceneTree

const Tank2 := preload("res://src/actors/rigid_tank/player_rigid_tank.tscn")
const Sweep := preload("res://src/ai/rigid_braking_sweep.gd")
const RESERVE := 0.02
const SETTLE_TICKS := 180

var world: Node3D
var failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	await _buried_seam_accepts_gun_overhang_and_rejects_gun_obstacle()
	await _same_rid_floor_wall_rejects()
	await _support_footprint_hole_rejects()
	await _protruding_seam_wall_rejects()
	await _clear()
	for failure: String in failures: push_error(failure)
	print("RIGID_BRAKING_SUPPORT_DOMAIN failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _buried_seam_accepts_gun_overhang_and_rejects_gun_obstacle() -> void:
	await _reset()
	var context: Dictionary = await _seamed_context("buried-seam", 0.0)
	if context.is_empty(): return
	_check(bool(context.get("gun_overhang", false)), "positive fixture requires gun/turret volume outside the hull/support road")
	var result: Dictionary = Sweep.check(context.solver, context.start, context.poses, RESERVE)
	_check(not result.is_empty() and bool(result.get("safe", false)),
		"two-piece static Concave road with buried seam walls must accept hull/tracks despite clear gun overhang; result=%s diagnostic=%s" % [result, context.solver.diagnostic])
	var gun_box: AABB = context.gun_volume as AABB
	_check(_valid_bounds(gun_box), "gun negative requires a real Tank2 gun part volume")
	if not _valid_bounds(gun_box): return
	_add_box(Vector3(0.18, 2.0, 0.35), gun_box.get_center() + Vector3.UP * 0.9)
	await physics_frame
	# The proof cache is synchronous-request local; new geometry needs a new solver.
	context.solver = (context.tank as RigidBody3D).create_ground_motion_query(context.snapshot)
	_test_budget(context.solver)
	result = Sweep.check(context.solver, context.start, context.poses, RESERVE)
	_check(not bool(result.get("safe", false)),
		"thin high obstacle through gun braking volume must never be safe; result=%s" % result)


func _same_rid_floor_wall_rejects() -> void:
	await _reset()
	var context: Dictionary = await _narrow_context("same-rid-wall")
	if context.is_empty(): return
	var gun_box: AABB = context.gun_volume as AABB
	_check(_valid_bounds(gun_box), "same-RID fixture requires gun part volume")
	if not _valid_bounds(gun_box): return
	_add_shape(context.road as StaticBody3D, Vector3(0.18, 2.0, 0.35), gun_box.get_center() + Vector3.UP * 0.9)
	await physics_frame
	var result: Dictionary = Sweep.check(context.solver, context.start, context.poses, RESERVE)
	_check(not bool(result.get("safe", false)),
		"wall on same RID but a different floor shape must never be excluded as road; result=%s" % result)


func _support_footprint_hole_rejects() -> void:
	await _reset()
	var floor: StaticBody3D = _concave_floor(_rectangle(-30.0, 30.0, -30.0, 30.0, 0.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "hole fixture requires grounded pre-hole Tank2")
	if not bool(snapshot.get("grounded", false)): return
	var start: Transform3D = snapshot.root as Transform3D
	var before_solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var before_support: Dictionary = before_solver._support(start, 0.0)
	var points: Array[Vector3] = tank._prediction_support_points
	_check((before_support.get("raw_hits", []) as Array).size() == 4 and points.size() == 4,
		"hole fixture requires four real pre-hole support rays")
	if points.size() != 4: return
	var hole_center: Vector3 = start * points[0]
	var collision: CollisionShape3D = floor.get_node("CollisionShape3D") as CollisionShape3D
	var shape: ConcavePolygonShape3D = collision.shape as ConcavePolygonShape3D
	var hole_faces: PackedVector3Array = _rectangle(-30.0, hole_center.x - 0.18, -30.0, 30.0, 0.0)
	hole_faces.append_array(_rectangle(hole_center.x + 0.18, 30.0, -30.0, 30.0, 0.0))
	shape.data = hole_faces
	await physics_frame
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	_test_budget(solver)
	var support: Dictionary = solver._support(start, 0.0)
	_check((support.get("raw_hits", []) as Array).size() < 4,
		"road hole must remove a true support-ray footprint, not merely an unused road region; support=%s" % support)
	var result: Dictionary = Sweep.check(solver, start, _poses(start), RESERVE)
	_check(not bool(result.get("safe", false)),
		"hole entering a support-ray footprint must never be sweep-safe; result=%s" % result)


func _protruding_seam_wall_rejects() -> void:
	await _reset()
	# 先以埋入接縫取得真正接地 snapshot；再讓同一兩片 Concave 的側壁升過 floor_y。
	# 若一開始就把高牆放在履帶下，剛體會被牆頂抬起，無法量測 sweep 的拒絕語意。
	var context: Dictionary = await _seamed_context("protruding-seam", 0.0)
	if context.is_empty(): return
	var footprint: AABB = context.footprint as AABB
	var roads: Array = context.roads as Array
	_check(roads.size() == 2 and _valid_bounds(footprint), "protruding seam fixture requires two grounded road pieces")
	if roads.size() != 2 or not _valid_bounds(footprint): return
	var seam_x: float = footprint.get_center().x
	var west_collision: CollisionShape3D = (roads[0] as StaticBody3D).get_node("CollisionShape3D") as CollisionShape3D
	var east_collision: CollisionShape3D = (roads[1] as StaticBody3D).get_node("CollisionShape3D") as CollisionShape3D
	(west_collision.shape as ConcavePolygonShape3D).data = _seam_piece(footprint.position.x, seam_x, footprint.position.z, footprint.end.z, seam_x, 1.0)
	(east_collision.shape as ConcavePolygonShape3D).data = _seam_piece(seam_x, footprint.end.x, footprint.position.z, footprint.end.z, seam_x, 1.0)
	await physics_frame
	var solver: RefCounted = (context.tank as RigidBody3D).create_ground_motion_query(context.snapshot as Dictionary)
	_test_budget(solver)
	var result: Dictionary = Sweep.check(solver, context.start, context.poses, RESERVE)
	_check(not bool(result.get("safe", false)),
		"seam side wall with top above floor must never be sweep-safe; result=%s diagnostic=%s" % [result, solver.diagnostic])


func _narrow_context(label: String) -> Dictionary:
	var broad: StaticBody3D = _box_body(Vector3(100.0, 0.2, 80.0), Vector3(0.0, -0.1, 0.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var first_snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(first_snapshot.get("grounded", false)), "%s requires grounded Tank2 on staging floor" % label)
	if not bool(first_snapshot.get("grounded", false)): return {}
	var first_solver: RefCounted = tank.create_ground_motion_query(first_snapshot)
	var start: Transform3D = first_snapshot.root as Transform3D
	var poses: Array[Transform3D] = _poses(start)
	var support_volume: AABB = _hull_support_volume(first_solver, start, poses)
	var gun_volume: AABB = _gun_volume(first_snapshot, first_solver, start, poses)
	_check(_valid_bounds(support_volume) and _valid_bounds(gun_volume), "%s requires hull and gun part ranges" % label)
	if not _valid_bounds(support_volume) or not _valid_bounds(gun_volume): return {}
	var road: StaticBody3D = _box_body(support_volume.size + Vector3(0.2, 0.0, 0.2), Vector3(support_volume.get_center().x, -0.1, support_volume.get_center().z))
	broad.queue_free()
	await _frames(2)
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "%s narrow road must retain true grounded Tank2" % label)
	if not bool(snapshot.get("grounded", false)): return {}
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	_test_budget(solver)
	start = snapshot.root as Transform3D
	poses = _poses(start)
	var road_bounds := AABB(road.global_position - Vector3((road.get_node("CollisionShape3D").shape as BoxShape3D).size.x * 0.5, 0.1, (road.get_node("CollisionShape3D").shape as BoxShape3D).size.z * 0.5), (road.get_node("CollisionShape3D").shape as BoxShape3D).size)
	gun_volume = _gun_volume(snapshot, solver, start, poses)
	var gun_overhang := gun_volume.position.x < road_bounds.position.x - 0.0001 or gun_volume.end.x > road_bounds.end.x + 0.0001 or gun_volume.position.z < road_bounds.position.z - 0.0001 or gun_volume.end.z > road_bounds.end.z + 0.0001
	return {"tank": tank, "road": road, "solver": solver, "start": start, "poses": poses, "gun_volume": gun_volume, "gun_overhang": gun_overhang}


func _seamed_context(label: String, wall_top: float) -> Dictionary:
	var broad: StaticBody3D = _box_body(Vector3(100.0, 0.2, 80.0), Vector3(0.0, -0.1, 0.0))
	var tank: RigidBody3D = await _spawn()
	await _frames(SETTLE_TICKS)
	var first_snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(first_snapshot.get("grounded", false)), "%s requires grounded Tank2 on staging floor" % label)
	if not bool(first_snapshot.get("grounded", false)): return {}
	var first_solver: RefCounted = tank.create_ground_motion_query(first_snapshot)
	var initial_start: Transform3D = first_snapshot.root as Transform3D
	var initial_poses: Array[Transform3D] = _poses(initial_start)
	var footprint: AABB = _hull_support_volume(first_solver, initial_start, initial_poses).grow(0.2)
	var gun_before: AABB = _gun_volume(first_snapshot, first_solver, initial_start, initial_poses)
	_check(_valid_bounds(footprint) and _valid_bounds(gun_before), "%s requires hull/support and gun volumes" % label)
	if not _valid_bounds(footprint) or not _valid_bounds(gun_before): return {}
	var seam_x: float = footprint.get_center().x
	var west := _concave_floor(_seam_piece(footprint.position.x, seam_x, footprint.position.z, footprint.end.z, seam_x, wall_top))
	var east := _concave_floor(_seam_piece(seam_x, footprint.end.x, footprint.position.z, footprint.end.z, seam_x, wall_top))
	broad.queue_free()
	await _frames(2)
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "%s seamed road must retain true grounded Tank2" % label)
	if not bool(snapshot.get("grounded", false)): return {}
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	_test_budget(solver)
	var start: Transform3D = snapshot.root as Transform3D
	var poses: Array[Transform3D] = _poses(start)
	var support: Dictionary = solver._support(start, 0.0)
	_check(bool(support.get("supported", false)) and (support.get("raw_hits", []) as Array).size() == 4,
		"%s seamed road requires all four true support rays; support=%s" % [label, support])
	if not bool(support.get("supported", false)) or (support.get("raw_hits", []) as Array).size() != 4: return {}
	var gun_volume: AABB = _gun_volume(snapshot, solver, start, poses)
	var gun_overhang := gun_volume.position.x < footprint.position.x - 0.0001 or gun_volume.end.x > footprint.end.x + 0.0001 or gun_volume.position.z < footprint.position.z - 0.0001 or gun_volume.end.z > footprint.end.z + 0.0001
	return {"tank": tank, "roads": [west, east], "snapshot": snapshot, "footprint": footprint, "solver": solver, "start": start, "poses": poses, "gun_volume": gun_volume, "gun_overhang": gun_overhang}


func _poses(start: Transform3D) -> Array[Transform3D]:
	return [start, start.translated(-start.basis.x.normalized() * 0.35)]


func _hull_support_volume(solver: RefCounted, start: Transform3D, poses: Array[Transform3D]) -> AABB:
	var result := AABB()
	var found := false
	for part: Dictionary in solver.part_bounds:
		if not solver.hull_shapes[int((part.indices as Array)[0])]: continue
		var volume: AABB = start * (part.box as AABB)
		for pose: Transform3D in poses: volume = volume.merge(pose * (part.box as AABB))
		volume = volume.grow(RESERVE + solver.MARGIN)
		result = result.merge(volume) if found else volume
		found = true
	var points: Array[Vector3] = solver.tank._prediction_support_points
	if points.size() != 4: return AABB()
	var rays := AABB(start * points[0], Vector3.ZERO)
	for pose: Transform3D in poses:
		for point: Vector3 in points: rays = rays.expand(pose * point)
	return result.merge(rays.grow(RESERVE + solver.MARGIN)) if found else AABB()


func _gun_volume(snapshot: Dictionary, solver: RefCounted, start: Transform3D, poses: Array[Transform3D]) -> AABB:
	var result := AABB()
	var found := false
	for range_data: Dictionary in snapshot.part_ranges as Array:
		if String(range_data.get("anchor", "")) != "gun": continue
		var shape_index: int = int(range_data.start)
		for part: Dictionary in solver.part_bounds:
			if not (part.indices as Array).has(shape_index): continue
			var volume: AABB = start * (part.box as AABB)
			for pose: Transform3D in poses: volume = volume.merge(pose * (part.box as AABB))
			result = result.merge(volume.grow(RESERVE + solver.MARGIN)) if found else volume.grow(RESERVE + solver.MARGIN)
			found = true
	return result if found else AABB()


func _reset() -> void:
	await _clear()
	world = Node3D.new()
	root.add_child(world)


func _clear() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _frames(2)
	world = null


func _spawn() -> RigidBody3D:
	var tank: RigidBody3D = Tank2.instantiate() as RigidBody3D
	_check(tank != null, "Tank2 must instantiate")
	if tank == null: return null
	tank.position = Vector3(0.0, 2.0, 0.0)
	world.add_child(tank)
	await _frames(2)
	return tank


func _box_body(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 128
	body.position = center
	world.add_child(body)
	_add_shape(body, size)
	return body


func _add_box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := _box_body(size, center)
	return body


func _add_shape(body: StaticBody3D, size: Vector3, global_center: Vector3 = Vector3.INF) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	if global_center.is_finite(): collision.global_position = global_center


func _concave_floor(faces: PackedVector3Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 128
	world.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.data = faces
	collision.shape = shape
	body.add_child(collision)
	return body


func _rectangle(min_x: float, max_x: float, min_z: float, max_z: float, y: float) -> PackedVector3Array:
	var a := Vector3(min_x, y, min_z)
	var b := Vector3(max_x, y, min_z)
	var c := Vector3(max_x, y, max_z)
	var d := Vector3(min_x, y, max_z)
	return PackedVector3Array([a, c, b, a, d, c, a, b, c, a, c, d])


func _seam_piece(min_x: float, max_x: float, min_z: float, max_z: float, seam_x: float, wall_top: float) -> PackedVector3Array:
	var faces: PackedVector3Array = _rectangle(min_x, max_x, min_z, max_z, 0.0)
	# 兩片各有一面接縫側壁；wall_top=0 完全埋於 top surface 以下。
	var low: float = -1.0
	var a := Vector3(seam_x, low, min_z)
	var b := Vector3(seam_x, low, max_z)
	var c := Vector3(seam_x, wall_top, max_z)
	var d := Vector3(seam_x, wall_top, min_z)
	faces.append_array(PackedVector3Array([a, b, c, a, c, d, a, c, b, a, d, c]))
	return faces


func _frames(count: int) -> void:
	for unused: int in count: await physics_frame


func _test_budget(solver: RefCounted) -> void:
	# 僅讓本煙霧隔離幾何結論；正式 near path 仍維持 20ms/4096 限額。
	solver.query_limit = 16384
	solver.deadline_usec = 0


func _valid_bounds(bounds: AABB) -> bool:
	return bounds.size.x > 0.000001 and bounds.size.y > 0.000001 and bounds.size.z > 0.000001


func _check(condition: bool, detail: String) -> void:
	if not condition: failures.append(detail)
