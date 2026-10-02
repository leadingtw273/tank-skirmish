## LEA-176：NorthGable 近角的定向包絡回歸。
## 原世界 AABB 誤擋的完整制動路徑，以及兩端無碰撞但旋轉中段碰撞的負例。
extends SceneTree

const Playtest := preload("res://src/maps/training_ground/training_ground_playtest.tscn")
const Catalog := preload("res://src/actors/tank/tank_catalog.gd")
const Motion := preload("res://src/ai/rigid_motion_prediction.gd")
const BrakingSweep := preload("res://src/ai/rigid_braking_sweep.gd")
const DT := 1.0 / 60.0
const START_XZ := Vector3(73.347244, 0.2, -27.978485)
const START_YAW := 160.534075
const START_VELOCITY := Vector3(0.311857313, 0.0, 0.115014203)
const START_ANGULAR := Vector3(0.0, -0.010969037, 0.0)
const GUN_PITCH := -1.626924
const SETTLE_TICKS := 120

var failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	var scene := Playtest.instantiate() as Node3D
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	(scene.get_node("Main/World/Ground") as StaticBody3D).process_mode = Node.PROCESS_MODE_ALWAYS
	(scene.get_node("SightBlockers") as Node3D).process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(scene)
	var tank := Catalog.instantiate(&"tank2") as RigidBody3D
	_check(tank != null, "TankCatalog.tank2 must be a rigid tank")
	if tank != null:
		tank.process_mode = Node.PROCESS_MODE_ALWAYS
		tank.position = START_XZ + Vector3.UP * 2.0
		tank.rotation.y = deg_to_rad(START_YAW)
		scene.add_child(tank)
		await _frames(SETTLE_TICKS)
		await _prove(tank, scene)
		await _arc_midpoint_negative(tank, scene)
	scene.queue_free()
	await physics_frame
	for failure in failures: push_error(failure)
	print("ORIENTED_SWEEP_PROOF failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _prove(tank: RigidBody3D, scene: Node3D) -> void:
	# 將停滯 pose 重新寫回已接地車身；再等一個 tick 讓 direct state 與 snapshot 同步。
	tank.global_position = Vector3(START_XZ.x, tank.global_position.y, START_XZ.z)
	tank.rotation.y = deg_to_rad(START_YAW)
	tank.linear_velocity = START_VELOCITY
	tank.angular_velocity = START_ANGULAR
	tank.set_movement_input(0.0)
	tank.set_turn_input(0.0)
	var pivot: Node3D = tank.combat_tank.gun_pitch_pivot
	_check(pivot != null, "tank2 requires a gun pitch pivot")
	if pivot == null: return
	pivot.rotation.z = -deg_to_rad(GUN_PITCH)
	tank.call("_sync_rigid_parts")
	await physics_frame
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "fixture requires a settled grounded snapshot")
	_check((snapshot.linear_velocity as Vector3).distance_to(START_VELOCITY) < 0.02 and tank.angular_velocity.distance_to(START_ANGULAR) < 0.02,
		"fixture must retain observed frame-4380 velocity; linear=%s angular=%s" % [snapshot.linear_velocity, tank.angular_velocity])
	_check(absf(rad_to_deg(tank.rotation.y) - START_YAW) < 0.02,
		"fixture yaw drifted before capture; got=%.6f expected=%.6f" % [rad_to_deg(tank.rotation.y), START_YAW])
	_check(absf(rad_to_deg(-pivot.rotation.z) - GUN_PITCH) < 0.001,
		"fixture gun pitch drifted before capture; got=%.6f expected=%.6f" % [rad_to_deg(-pivot.rotation.z), GUN_PITCH])
	if not failures.is_empty(): return
	var captured: Dictionary = Motion.capture(tank, snapshot)
	_check(not captured.is_empty() and int(captured.physics_frame) == Engine.get_physics_frames(), "RigidMotion.capture must use this physics frame")
	if captured.is_empty(): return
	captured.config.braking_feedforward = true
	var run := _braking_path(captured, _radius(snapshot))
	_check(not run.is_empty(), "observed-motion candidate(0,-1) must reach a finite braking tail")
	if run.is_empty(): return
	var path: Array[Transform3D] = run.path
	var reserve: float = float(run.reserve)
	_check(_legacy_aabb_would_reject(tank, snapshot, path, reserve, scene),
		"regression fixture must retain the old padded world-AABB NorthGable rejection")
	_check(_all_path_poses_clear(scene, tank, snapshot, path),
		"every model pose must be narrow-phase clear of all SightBlockers")
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var result: Dictionary = BrakingSweep.check(solver, snapshot.root as Transform3D, path, reserve)
	_check(not result.is_empty() and bool(result.get("safe", false)),
		"oriented proof must clear through new BrakingSweep; result=%s reserve=%.9f path=%d" % [result, reserve, path.size()])
	print("ORIENTED_SWEEP reserve=%.9f poses=%d result=%s failures=%d" % [reserve, path.size(), result, failures.size()])


func _braking_path(captured: Dictionary, radius: float) -> Dictionary:
	var model := Motion.new()
	model.initialize(captured.config, captured.initial)
	var path: Array[Transform3D] = [model.root]
	var tail := INF
	var vertex_speed := model.velocity.length() + radius * absf(model.angular)
	for tick in 900:
		if tick == 0:
			model.step(0.0, -1.0, false, DT)
		else:
			model.step(0.0, 0.0, true, DT)
		path.append(model.root)
		vertex_speed = maxf(vertex_speed, model.velocity.length() + radius * absf(model.angular))
		if tick % 6 == 0:
			tail = model.remaining_vertex_travel(radius, DT)
			if tail <= 0.002: break
	if tail > 0.002: return {}
	return {"path": path, "reserve": 0.01 + 0.08 * vertex_speed + tail}


func _legacy_aabb_would_reject(tank: RigidBody3D, snapshot: Dictionary, path: Array[Transform3D], reserve: float, scene: Node3D) -> bool:
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var parts: Array[AABB] = []
	for part: Dictionary in solver.part_bounds:
		parts.append((snapshot.root as Transform3D) * (part.box as AABB))
	var previous: Transform3D = snapshot.root
	var maximum_angle := 0.0
	for pose in path:
		var difference_squared := (previous.basis.x - pose.basis.x).length_squared() + (previous.basis.y - pose.basis.y).length_squared() + (previous.basis.z - pose.basis.z).length_squared()
		maximum_angle = maxf(maximum_angle, 2.0 * asin(minf(1.0, sqrt(difference_squared) * 0.5)))
		for index in parts.size(): parts[index] = parts[index].merge(pose * (solver.part_bounds[index].box as AABB))
		previous = pose
	for index in parts.size(): parts[index] = parts[index].grow(reserve + float(solver.part_bounds[index].radius) * maximum_angle + solver.MARGIN)
	var obstacle := _world_box(scene.get_node("SightBlockers/BuildingRowA/NorthGable/CollisionShape3D") as CollisionShape3D)
	for part in parts:
		if part.grow(solver.MARGIN).intersects(obstacle): return true
	return false


func _all_path_poses_clear(scene: Node3D, tank: RigidBody3D, snapshot: Dictionary, path: Array[Transform3D]) -> bool:
	var state := scene.get_world_3d().direct_space_state
	var dense: Array[Transform3D] = [path[0]]
	for step in range(1, path.size()):
		for substep in range(1, 5):
			dense.append(path[step-1].interpolate_with(path[step], float(substep)/4.0))
	for pose in dense:
		for index in snapshot.shapes.size():
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = snapshot.shapes[index]
			query.transform = pose * (snapshot.root_local_transforms[index] as Transform3D)
			query.collision_mask = 1
			query.exclude = [tank.get_rid()]
			for hit in state.intersect_shape(query, 32):
				var collider := hit.get("collider") as Node
				if collider != null and str(collider.get_path()).contains("SightBlockers"):
					return false
	return true


func _arc_midpoint_negative(tank: RigidBody3D, scene: Node3D) -> void:
	# 端點皆不碰，但將砲管外側 convex 旋到 90° 時必撞；不能被 endpoint OBB 分離略過。
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	var gun := _outer_gun_shape(snapshot, tank.global_position)
	_check(gun >= 0, "arc negative requires a gun convex")
	if gun < 0: return
	var start: Transform3D = snapshot.root
	var middle := start
	middle.basis = Basis(Vector3.UP, PI * 0.5) * start.basis
	var finish := start
	finish.basis = Basis(Vector3.UP, PI) * start.basis
	var obstacle := StaticBody3D.new()
	obstacle.name = "ArcMidpointOnly"
	obstacle.collision_layer = 1
	obstacle.process_mode = Node.PROCESS_MODE_ALWAYS
	obstacle.position = _shape_vertex(snapshot, gun, middle)
	scene.add_child(obstacle)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	collision.shape = box
	obstacle.add_child(collision)
	await physics_frame
	_check(not _shape_hits(scene, tank, snapshot, start, gun, obstacle) and not _shape_hits(scene, tank, snapshot, finish, gun, obstacle),
		"arc negative endpoints must each clear the midpoint-only obstacle")
	_check(_shape_hits(scene, tank, snapshot, middle, gun, obstacle),
		"arc negative midpoint must truly collide with the gun convex")
	var endpoints: Array[Transform3D] = [start, finish]
	var solver: RefCounted = tank.create_ground_motion_query(snapshot)
	var parts: Array[AABB] = BrakingSweep._oriented_parts(solver, start, endpoints, 0.01, PI)
	var obstacle_data := {"size": box.size, "transform": collision.global_transform}
	_check(not BrakingSweep._outside_oriented(solver, parts, start, obstacle_data),
		"arc midpoint collision must not be separated by endpoint OBB refinement")
	obstacle.queue_free()
	await physics_frame


func _outer_gun_shape(snapshot: Dictionary, center: Vector3) -> int:
	var chosen := -1
	var farthest := -INF
	for part in snapshot.part_ranges:
		if String(part.anchor) != "gun": continue
		for index in range(int(part.start), int(part.start) + int(part.count)):
			var distance := center.distance_squared_to(_shape_center(snapshot, index, snapshot.root))
			if distance > farthest:
				farthest = distance
				chosen = index
	return chosen


func _shape_center(snapshot: Dictionary, index: int, root_pose: Transform3D) -> Vector3:
	var local: Transform3D = root_pose * (snapshot.root_local_transforms[index] as Transform3D)
	var result := Vector3.ZERO
	var vertices: PackedVector3Array = snapshot.shape_vertices[index]
	for point in vertices: result += local * point
	return result / float(vertices.size()) if not vertices.is_empty() else local.origin


func _shape_vertex(snapshot: Dictionary, index: int, root_pose: Transform3D) -> Vector3:
	var local: Transform3D = root_pose * (snapshot.root_local_transforms[index] as Transform3D)
	var selected := local.origin
	var farthest := -INF
	for point in snapshot.shape_vertices[index]:
		var world: Vector3 = local * point
		var distance := world.distance_squared_to(root_pose.origin)
		if distance > farthest:
			farthest = distance
			selected = world
	return selected


func _shape_hits(scene: Node3D, tank: RigidBody3D, snapshot: Dictionary, pose: Transform3D, index: int, obstacle: StaticBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = snapshot.shapes[index]
	query.transform = pose * (snapshot.root_local_transforms[index] as Transform3D)
	query.collision_mask = 1
	query.exclude = [tank.get_rid()]
	for hit in scene.get_world_3d().direct_space_state.intersect_shape(query, 32):
		if hit.get("rid") == obstacle.get_rid(): return true
	return false


func _world_box(collision: CollisionShape3D) -> AABB:
	var box := collision.shape as BoxShape3D
	var half := box.size * 0.5
	var result := AABB(collision.global_transform * Vector3(-half.x, -half.y, -half.z), Vector3.ZERO)
	for x in [-half.x, half.x]:
		for y in [-half.y, half.y]:
			for z in [-half.z, half.z]: result = result.expand(collision.global_transform * Vector3(x, y, z))
	return result


func _radius(snapshot: Dictionary) -> float:
	var radius := 0.0
	for index in snapshot.shape_vertices.size():
		var local: Transform3D = snapshot.root_local_transforms[index]
		for point in snapshot.shape_vertices[index]: radius = maxf(radius, (local * point).length())
	return radius


func _frames(count: int) -> void:
	for unused in count: await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
