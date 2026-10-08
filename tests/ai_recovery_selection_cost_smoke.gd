## LEA-208：以完整原算法 oracle 驗證三項同義成本修正；不作性能量測。
extends SceneTree

const Tank2 := preload("res://src/actors/rigid_tank/player_rigid_tank.tscn")
const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const Ground := preload("res://src/actors/rigid_tank/rigid_ground_prediction.gd")
const Support := preload("res://src/ai/rigid_motion_support.gd")
const Recovery := preload("res://src/ai/tank_recovery.gd")
var world: Node3D
var failures: Array[String] = []

## 以下保留 b9a03ac 的完整 sample／normal／mean oracle，不共用候選支撐算法。
class OriginalSupport extends RefCounted:

	const MIN_UP_COMPONENT := 0.0001
	const MIN_DIRECTION_LENGTH_SQUARED := 0.000001

	static func sample(space: PhysicsDirectSpaceState3D, pose: Transform3D, local_points: Array[Vector3], excluded: Array[RID], mask: int, step_height: float, snap_distance: float, max_slope_degrees: float) -> Dictionary:
		var indices := PackedInt32Array()
		var positions: Array[Vector3] = []
		var normals: Array[Vector3] = []
		var heights := PackedFloat64Array()
		var query := PhysicsRayQueryParameters3D.new()
		query.collision_mask = mask; query.exclude = excluded; query.collide_with_bodies = true; query.collide_with_areas = false
		var zero_window_floor := INF
		var zero_window_valid := true
		var up := maxf(step_height, 0.0) + 0.02
		var down := maxf(snap_distance, 0.0)
		for index in local_points.size():
			var point := pose * local_points[index]
			query.from = point + Vector3.UP * up; query.to = point + Vector3.DOWN * down
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				zero_window_valid = false
				continue
			var normal := (hit.get("normal", Vector3.ZERO) as Vector3).normalized()
			if normal.y <= MIN_UP_COMPONENT:
				zero_window_valid = false
				continue
			var hit_position: Vector3 = hit.get("position", point)
			# Reuse only four static horizontal first hits strictly below the original
			# step-zero ray origin. The taller motion ray then has the same first hit.
			if not hit.get("collider") is StaticBody3D or normal.y < 0.999999 or hit_position.y >= point.y + 0.019:
				zero_window_valid = false
			zero_window_floor = minf(zero_window_floor, hit_position.y)
			indices.append(index); positions.append(hit.get("position", point) as Vector3); normals.append(normal); heights.append(positions[-1].y-point.y)
		var normal := _normal(indices, positions, normals)
		var height := 0.0
		if not heights.is_empty():
			height = heights[0]
			for value in heights: height = maxf(height, value)
		var cosine := cos(deg_to_rad(clampf(max_slope_degrees, 0.0, 89.999)))
		var steep := indices.size() >= 2 and normal.y < cosine
		if not steep:
			for value in normals:
				if value.y < cosine: steep = true; break
		return {"supported":indices.size() >= 2 and not steep,"too_steep":steep,"normal":normal,"height_delta":height,"step_zero_floor_y":zero_window_floor if zero_window_valid and indices.size() == 4 and not steep else -INF}

	static func _normal(indices: PackedInt32Array, points: Array[Vector3], normals: Array[Vector3]) -> Vector3:
		if indices.is_empty(): return Vector3.UP
		var average := Vector3.ZERO
		for normal in normals: average += normal
		average = Vector3.UP if average.length_squared() < MIN_DIRECTION_LENGTH_SQUARED else average.normalized()
		if indices.size() < 3: return average if average.y >= 0.0 else -average
		var front: Variant = _mean(indices, points, PackedInt32Array([0,2])); var rear: Variant = _mean(indices, points, PackedInt32Array([1,3]))
		var left: Variant = _mean(indices, points, PackedInt32Array([0,1])); var right: Variant = _mean(indices, points, PackedInt32Array([2,3]))
		if front == null or rear == null or left == null or right == null: return average if average.y >= 0.0 else -average
		var plane := ((front as Vector3)-(rear as Vector3)).cross((left as Vector3)-(right as Vector3))
		if plane.length_squared() < MIN_DIRECTION_LENGTH_SQUARED: return average if average.y >= 0.0 else -average
		plane = plane.normalized(); return plane if plane.y >= 0.0 else -plane

	static func _mean(indices: PackedInt32Array, points: Array[Vector3], wanted: PackedInt32Array) -> Variant:
		var total := Vector3.ZERO; var count := 0
		for i in indices.size():
			if wanted.has(indices[i]): total += points[i]; count += 1
		return total / float(count) if count > 0 else null

## 保留原 provider 的 cache／reserve／ceiling 處理，只連接上方原 sample oracle。
class OriginalGround extends "res://src/actors/rigid_tank/rigid_ground_prediction.gd":
	func _motion_support(pose: Transform3D, step_height: float) -> Dictionary:
		var full: Dictionary = _support_cache.get(step_height, {})
		if full.has(pose): return full[pose]
		if _motion_support_cache.has(pose): return _motion_support_cache[pose]
		if not _reserve(4): return {}
		var result := OriginalSupport.sample(space, pose, tank._prediction_support_points, excluded,
			tank.collision_mask, step_height, tank.ground_snap_distance + tank.ground_step_height, tank.ground_max_slope_degrees)
		_motion_support_cache[pose] = result
		var floor_y: float = result.get("step_zero_floor_y", -INF)
		if is_finite(floor_y) and bool(result.get("supported", false)):
			var ceiling: float = floor_y + tank.ground_step_height + TERRAIN_HEIGHT_TOLERANCE
			_exact_ceiling_cache[pose] = ceiling
			_ceiling_cache[pose] = ceiling
		return result

class ComparingGround extends "res://src/actors/rigid_tank/rigid_ground_prediction.gd":
	var comparisons := 0
	var same := true
	func predictive_driving_step(speed: float, angular: float, movement: float, turn: float, delta: float) -> Dictionary:
		var direct: Dictionary = tank.predictive_driving_step(speed, angular, movement, turn, delta)
		var cached := super.predictive_driving_step(speed, angular, movement, turn, delta)
		comparisons += 1
		## 只比較模型輸出；後續 ground segment 加入的 drift 不屬於此契約。
		same = same and direct.forward_speed == cached.forward_speed and direct.angular_speed == cached.angular_speed
		return cached

func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 128
	floor.position.y = -0.1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	collision.shape = box
	floor.add_child(collision)
	world.add_child(floor)
	var tank := Tank2.instantiate() as RigidBody3D
	tank.position = Vector3(0, 2, 0)
	world.add_child(tank)
	for unused in 180: await physics_frame
	tank.freeze = true
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "fixture requires true grounded Tank2")
	var before := tank.global_transform
	var shapes: Array = snapshot.shapes
	var transforms: Array = snapshot.transforms
	var pose: Transform3D = snapshot.root
	var predictor := Predictor.new()
	predictor.setup(tank)
	var radius: float = predictor._snapshot_radius(shapes, transforms, pose)
	_check(radius == _original_radius(shapes, transforms, pose), "typed radius must exactly equal the original world vertex algorithm")
	var shifted := pose.translated(Vector3(17, -2, 9))
	_check(predictor._snapshot_radius(shapes, transforms, shifted) == _original_radius(shapes, transforms, shifted), "radius must retain world origin arithmetic")
	_check(predictor._snapshot_radius([], [], pose) == _original_radius([], [], pose), "radius initial value/+0.01 must remain")
	_check(predictor._snapshot_radius([BoxShape3D.new()], [pose], pose) == 1000.0, "non-convex fallback must remain")
	_support_equivalence(tank, floor, snapshot)
	_driving_equivalence(tank, snapshot, predictor, radius)
	_check(tank.global_transform == before, "synchronous oracle checks must not move the true Tank2")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("AI_RECOVERY_SELECTION_COST failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _support_equivalence(tank: RigidBody3D, floor: StaticBody3D, snapshot: Dictionary) -> void:
	var pose: Transform3D = snapshot.root
	var points: Array[Vector3] = tank._prediction_support_points
	var reusable := PhysicsRayQueryParameters3D.new()
	var defaults := PhysicsRayQueryParameters3D.new()
	var own: Array[RID] = [tank.get_rid()]
	var omit_floor: Array[RID] = [tank.get_rid(), floor.get_rid()]
	var cases: Array = [
		[pose, 128, own], [pose.translated(Vector3(2, 0, 3)), 129, own],
		[pose.translated(Vector3(0, 1, 0)), 128, own], [pose, 0, own], [pose, 128, omit_floor],
	]
	for inputs: Array in cases:
		var current: Transform3D = inputs[0]
		var excluded: Array[RID] = inputs[2]
		var mask: int = inputs[1]
		## 污染所有非位置旗標；每次 sample 必須恢復 fresh 物件的原設定。
		reusable.collision_mask = 0
		reusable.exclude = omit_floor
		reusable.collide_with_bodies = false
		reusable.collide_with_areas = true
		reusable.hit_back_faces = false
		reusable.hit_from_inside = true
		reusable.from = Vector3.ONE * 500
		reusable.to = -Vector3.ONE * 500
		var original := OriginalSupport.sample(tank.get_world_3d().direct_space_state, current, points, excluded, mask, tank.ground_step_height, tank.ground_snap_distance + tank.ground_step_height, tank.ground_max_slope_degrees)
		var direct := Support.sample(tank.get_world_3d().direct_space_state, current, points, excluded, mask, tank.ground_step_height, tank.ground_snap_distance + tank.ground_step_height, tank.ground_max_slope_degrees)
		var reused := Support.sample(tank.get_world_3d().direct_space_state, current, points, excluded, mask, tank.ground_step_height, tank.ground_snap_distance + tank.ground_step_height, tank.ground_max_slope_degrees, reusable)
		_check(original == direct and original == reused, "fresh/reused support must exactly equal all original fields for pose/mask/exclude")
		_check(reusable.collision_mask == mask and reusable.exclude == excluded and reusable.collide_with_bodies == defaults.collide_with_bodies and reusable.collide_with_areas == defaults.collide_with_areas and reusable.hit_back_faces == defaults.hit_back_faces and reusable.hit_from_inside == defaults.hit_from_inside, "all ray flags must reset to original defaults")
		var last := current * points[-1]
		_check(reusable.from == last + Vector3.UP * (maxf(tank.ground_step_height, 0.0) + 0.02) and reusable.to == last + Vector3.DOWN * maxf(tank.ground_snap_distance + tank.ground_step_height, 0.0), "every ray must replace from/to")
	var old := OriginalGround.new()
	var candidate := Ground.new()
	old.setup(tank, snapshot)
	candidate.setup(tank, snapshot)
	_check(candidate._motion_support_ray != old._motion_support_ray, "providers must own distinct query parameter objects")
	for current: Transform3D in [pose, pose.translated(Vector3(2, 0, 3))]:
		var original: Dictionary = old._motion_support(current, tank.ground_step_height)
		var reused: Dictionary = candidate._motion_support(current, tank.ground_step_height)
		_check(original == reused and old.queries == candidate.queries, "provider support fields and reserve count must remain exact")
	_check(old.queries == 8 and candidate.queries == 8, "two new support poses must retain four reserved rays each")
	print("AI_RECOVERY_SUPPORT cases=", cases.size(), " provider_queries=", candidate.queries)

func _driving_equivalence(tank: RigidBody3D, snapshot: Dictionary, predictor: RefCounted, radius: float) -> void:
	var provider := ComparingGround.new()
	provider.setup(tank, snapshot)
	var forward: Vector3 = -(snapshot.root as Transform3D).basis.x
	forward.y = 0.0
	forward = forward.normalized()
	var heading := forward.rotated(Vector3.UP, Recovery.ESCAPE_ANGLE).normalized()
	var action: Dictionary = Recovery.escape_transition(&"turning", 0.0, 0.1, forward, heading, float(snapshot.forward_speed), float(snapshot.angular_speed), 0.0, tank.brake_force_kilonewtons / tank.tank_mass_tonnes, tank.movement_speed, 0.1)
	var cases: Array = [
		[snapshot.forward_speed, snapshot.angular_speed, action.movement, action.turn, 0.1],
		[0.0, 0.0, 0.0, 0.0, 0.1], [0.0, 0.0, 0.0, 1.0, 0.1], [0.0, 0.0, 0.0, -1.0, 0.1],
		[1.5, 0.0, 1.0, 0.0, 0.1], [-1.5, 0.0, -1.0, 0.0, 0.1],
		[1.5, 0.2, -1.0, -0.4, 1.0 / 60.0], [0.0, -0.2, 0.0, 0.4, 0.1 / 8.0],
	]
	for inputs: Array in cases:
		provider.predictive_driving_step(inputs[0], inputs[1], inputs[2], inputs[3], inputs[4])
	_check(provider.same and provider.comparisons == 8, "eight driving inputs must exactly match both raw model fields")
	var captured := snapshot.duplicate()
	captured.ground_motion_query = provider
	var excluded: Array[RID] = []
	var started := Time.get_ticks_usec()
	var profile: Dictionary = predictor._probe_profile(tank.get_world_3d().direct_space_state, captured, radius, provider.prediction_bounds(), excluded, {}, heading, started, 10.0, {}, {"phase": &"selecting_escape"})
	_check(provider.same and provider.comparisons > 8, "actual selecting_escape heading inputs must match direct driving outputs in the same query")
	print("AI_RECOVERY_DRIVING matrix=8 profile_model_calls=", provider.comparisons - 8, " exact=", provider.same, " phase=", profile.get("phase"))
	captured.erase("ground_motion_query")

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _original_radius(shapes: Array, transforms: Array, root: Transform3D) -> float:
	var radius := 0.1
	for index in shapes.size():
		var convex := shapes[index] as ConvexPolygonShape3D
		if convex == null:
			return 1000.0
		for point in convex.points:
			radius = maxf(radius, root.origin.distance_to((transforms[index] as Transform3D) * point))
	return radius + 0.01
