## LEA-177：路肩接觸 fallback 的有限負例；正例 0.21/0.50m 沿用 rigid_ai_terrain_smoke。
extends SceneTree

const Tank2 := preload("res://src/actors/rigid_tank/player_rigid_tank.tscn")
const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const DT := 1.0 / 60.0
const SETTLE_FRAMES := 180

var _world: Node3D
var _failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	print("RIGID_AI_CURB_BOUNDARY ticks=", Engine.physics_ticks_per_second)
	await _high_wall_is_still_rejected()
	await _side_gun_only_obstacle_is_still_rejected()
	await _floor_and_wall_on_one_rid_are_still_rejected()
	await _clear()
	for failure in _failures:
		push_error(failure)
	print("RIGID_AI_CURB_BOUNDARY failures=", _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _high_wall_is_still_rejected() -> void:
	await _reset()
	_floor()
	_box(Vector3(-3.0, 2.0, 0.0), Vector3(0.5, 4.0, 8.0))
	var tank := await _spawn_tank()
	await _frames(SETTLE_FRAMES)
	_assert_rejected(tank, "high-wall")


func _side_gun_only_obstacle_is_still_rejected() -> void:
	await _reset()
	_floor()
	var tank := await _spawn_tank()
	await _frames(SETTLE_FRAMES)
	# 砲塔轉向 +Z；車身保持原地，這不是移動／速度作弊。
	for unused in 120:
		tank.aim_turret_at(tank.global_position + Vector3(0.0, 0.0, 30.0), DT)
		await physics_frame
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	var gun_index := _outer_gun_shape(snapshot, tank.global_position)
	_check(gun_index >= 0, "gun-only fixture needs a readable outward gun shape; ranges=%s" % [snapshot.get("part_ranges", [])])
	if gun_index < 0: return
	# 將小方塊置於最外側 gun convex 的頂點中心。先以獨立 layer 做幾何證明，
	# 再切回真實 128 layer；不以 floor 的同層 hit 偽造此鑑別力。
	var obstacle := _box(_shape_center(snapshot, gun_index), Vector3(0.18, 0.18, 0.18))
	obstacle.collision_layer = 64
	await physics_frame
	var geometry := _fixture_hits(snapshot, gun_index, 64)
	_check(bool(geometry.gun) and not bool(geometry.hull),
		"gun-only fixture must geometrically hit gun but not hull before predictor; gun=%s hull=%s index=%s" % [geometry.gun, geometry.hull, gun_index])
	obstacle.collision_layer = 128
	await _frames(2)
	_assert_rejected(tank, "side-gun-only")


func _floor_and_wall_on_one_rid_are_still_rejected() -> void:
	await _reset()
	var shared := StaticBody3D.new()
	shared.collision_layer = 128
	_world.add_child(shared)
	_box(Vector3.ZERO, Vector3(100.0, 0.2, 80.0), shared, Vector3(0.0, -0.1, 0.0))
	_box(Vector3.ZERO, Vector3(0.5, 4.0, 8.0), shared, Vector3(-3.0, 2.0, 0.0))
	var tank := await _spawn_tank()
	await _frames(SETTLE_FRAMES)
	_assert_rejected(tank, "shared-rid-floor-wall")


func _assert_rejected(tank: RigidBody3D, label: String) -> void:
	var predictor := Predictor.new()
	predictor.setup(tank)
	var choice: Dictionary = predictor.choose(1.0, 0.0, tank.global_position + Vector3(-30.0, 0.0, 0.0), DT, true, false)
	var rejected := String(choice.get("reason", "")) == "blocked" and is_zero_approx(float(choice.get("movement", 1.0))) and is_zero_approx(float(choice.get("turn", 1.0)))
	_check(rejected, "%s must be blocked with explicit zero command, not a budget timeout; choice=%s stats=%s" % [label, choice, predictor.get_stats()])
	_check(String(choice.get("reason", "")) != "budget", "%s cannot pass/fail by exhausted query budget; choice=%s stats=%s" % [label, choice, predictor.get_stats()])
	print("AI_CURB_BOUNDARY ", label, " choice=", choice, " stats=", predictor.get_stats())


func _fixture_hits(snapshot: Dictionary, gun_index: int, collision_mask: int) -> Dictionary:
	var state := _world.get_world_3d().direct_space_state
	var gun_hit := not _shape_hits(state, snapshot.shapes[gun_index], snapshot.transforms[gun_index], collision_mask).is_empty()
	var hull_hit := false
	for range_data in snapshot.part_ranges:
		if String(range_data.get("anchor", "")) != "hull": continue
		for index in range(int(range_data.start), int(range_data.start) + int(range_data.count)):
			hull_hit = hull_hit or not _shape_hits(state, snapshot.shapes[index], snapshot.transforms[index], collision_mask).is_empty()
	return {"gun": gun_hit, "hull": hull_hit}


func _shape_hits(state: PhysicsDirectSpaceState3D, shape: Shape3D, transform: Transform3D, collision_mask: int) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = transform
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return state.intersect_shape(query, 32)


func _outer_gun_shape(snapshot: Dictionary, hull_center: Vector3) -> int:
	var selected := -1
	var farthest := -INF
	for range_data in snapshot.part_ranges:
		if String(range_data.get("anchor", "")) != "gun": continue
		for index in range(int(range_data.start), int(range_data.start) + int(range_data.count)):
			var distance := hull_center.distance_squared_to(_shape_center(snapshot, index))
			if distance > farthest:
				farthest = distance
				selected = index
	return selected


func _shape_center(snapshot: Dictionary, index: int) -> Vector3:
	var vertices: PackedVector3Array = snapshot.shape_vertices[index]
	var transform: Transform3D = snapshot.transforms[index]
	var center := Vector3.ZERO
	for vertex in vertices:
		center += transform * vertex
	return center / float(vertices.size()) if not vertices.is_empty() else transform.origin


func _reset() -> void:
	await _clear()
	_world = Node3D.new()
	root.add_child(_world)


func _clear() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		await _frames(2)
	_world = null


func _floor() -> void:
	_box(Vector3(0.0, -0.1, 0.0), Vector3(100.0, 0.2, 80.0))


func _box(center: Vector3, size: Vector3, parent: Node3D = _world, local_position: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := parent as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.collision_layer = 128
		body.position = center
		_world.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = local_position
	body.add_child(collision)
	return body


func _spawn_tank() -> RigidBody3D:
	var tank := Tank2.instantiate() as RigidBody3D
	_check(tank != null, "Tank2 must instantiate for AI curb boundary fixture.")
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
