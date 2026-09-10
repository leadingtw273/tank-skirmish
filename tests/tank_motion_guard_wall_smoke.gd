## LEA-173 Task 2 C2：獨立真車矩陣。只使用正式公開控制入口；reset pose 僅用來
## 依真凸形支持範圍放置原場景 CentralOneStory，不會藉此套用受測動作。
extends SceneTree

const PLAYTEST_SCENE := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TANK_SCENES := [preload("res://src/actors/tank/variants/tank1/tank1.tscn"), preload("res://src/actors/tank/variants/tank2/tank2.tscn"), preload("res://src/actors/tank/variants/tank3/tank3.tscn"), preload("res://src/actors/tank/variants/tank4/tank4.tscn")]
const DT := 1.0 / 60.0
const STEPS := 120
const START_YAW := deg_to_rad(6.0)
var failures: Array[String] = []
var evidence: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for index in TANK_SCENES.size():
		await _translation(index)
		await _root_yaw(index)
		await _turret_yaw(index)
		await _gun_pitch(index)
	for line in evidence:
		print(line)
	if failures.is_empty():
		print("C2_WALL_MATRIX PASS: 16/16 authored-building real-tank public-control cases.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _translation(index: int) -> void:
	var tank := await _spawn(index)
	if tank == null: return
	var start_support := _support_min_x(tank, [])
	var wall := _wall_at_face(start_support - 0.20)
	root.add_child(wall)
	await physics_frame
	if _overlap(tank):
		_fail_case(index, "forward", "initial overlap after authored-box placement")
		await _free_pair(tank, wall)
		return
	tank.set_movement_input(1.0)
	var collided := false
	for unused in STEPS:
		await physics_frame
		collided = collided or tank.get_slide_collision_count() > 0
	tank.set_movement_input(0.0)
	var stopped_x := tank.global_position.x
	tank.set_movement_input(-1.0)
	for unused in 120: await physics_frame
	tank.set_movement_input(0.0)
	var exited := tank.global_position.x > stopped_x + 0.02
	_record(index, "forward", "start_support=%.4f stopped_x=%.4f collided=%s reverse_exit=%s overlap=%s" % [start_support, stopped_x, collided, exited, _overlap(tank)])
	if not collided or not exited or _overlap(tank): _fail_case(index, "forward", "expected stop before wall and immediate reverse exit")
	await _free_pair(tank, wall)

func _root_yaw(index: int) -> void:
	var tank := await _spawn(index)
	if tank == null: return
	_set_pose(tank, START_YAW, 0.0, 0.0)
	var root_zero := tank.global_transform.rotated_local(Vector3.UP, -START_YAW)
	var start_transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero.rotated_local(Vector3.UP, START_YAW), 0.0, 0.0)
	var end_transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, 0.0, 0.0)
	var plane := _best_plane(tank, start_transforms, end_transforms, [])
	if bool(plane.get("valid", false)):
		await _rotation_case(index, "rootyaw", tank, plane, func(): _set_pose(tank, START_YAW, 0.0, 0.0), func(): _set_pose(tank, 0.0, 0.0, 0.0), func(): tank.set_turn_input(-1.0), func(): tank.set_turn_input(1.0), &"root")
	else:
		await _rotation_case(index, "rootyaw", tank, _best_plane(tank, end_transforms, start_transforms, []), func(): _set_pose(tank, 0.0, 0.0, 0.0), func(): _set_pose(tank, START_YAW, 0.0, 0.0), func(): tank.set_turn_input(1.0), func(): tank.set_turn_input(-1.0), &"root")

func _turret_yaw(index: int) -> void:
	var tank := await _spawn(index)
	if tank == null: return
	if index == 2:
		await _tank3_turret_80_to_90(tank)
		return
	if index == 3:
		await _tank4_turret_negative_max_to_zero(tank)
		return
	var legal := minf(START_YAW, deg_to_rad(tank.turret_max_yaw_degrees * 0.75))
	_set_pose(tank, 0.0, legal, 0.0)
	var root_zero := tank.global_transform
	var start_transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, legal, 0.0)
	var end_transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, 0.0, 0.0)
	var pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var plane := _best_plane(tank, start_transforms, end_transforms, [&"turret", &"gun"])
	if bool(plane.get("valid", false)):
		await _rotation_case(index, "turretyaw", tank, plane, func(): _set_pose(tank, 0.0, legal, 0.0), func(): _set_pose(tank, 0.0, 0.0, 0.0), func(): tank.aim_turret_at(pivot.global_position + Vector3(-40, 0, 0), DT), func(): tank.aim_turret_at(pivot.global_position + Vector3(-40, 0, 40), DT), &"turret")
	else:
		await _rotation_case(index, "turretyaw", tank, _best_plane(tank, end_transforms, start_transforms, [&"turret", &"gun"]), func(): _set_pose(tank, 0.0, 0.0, 0.0), func(): _set_pose(tank, 0.0, legal, 0.0), func(): tank.aim_turret_at(pivot.global_position + Vector3(-40, 0, 40), DT), func(): tank.aim_turret_at(pivot.global_position + Vector3(-40, 0, 0), DT), &"turret")

func _gun_pitch(index: int) -> void:
	var tank := await _spawn(index)
	if tank == null: return
	if index == 2:
		await _tank3_gun_yaw90_elevation_to_zero(tank)
		return
	var legal := minf(deg_to_rad(6.0), deg_to_rad(tank.gun_max_elevation_degrees * 0.75))
	_set_pose(tank, 0.0, 0.0, legal)
	var root_zero := tank.global_transform
	var start_transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, 0.0, legal)
	var end_transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, 0.0, 0.0)
	var plane := _best_plane(tank, start_transforms, end_transforms, [&"gun"])
	if bool(plane.get("valid", false)):
		await _rotation_case(index, "gunpitch", tank, plane, func(): _set_pose(tank, 0.0, 0.0, legal), func(): _set_pose(tank, 0.0, 0.0, 0.0), func(): tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-40, 0, 0), DT), func(): tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-40, 40, 0), DT), &"gun")
	else:
		await _rotation_case(index, "gunpitch", tank, _best_plane(tank, end_transforms, start_transforms, [&"gun"]), func(): _set_pose(tank, 0.0, 0.0, 0.0), func(): _set_pose(tank, 0.0, 0.0, legal), func(): tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-40, 40, 0), DT), func(): tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-40, 0, 0), DT), &"gun")

## 鎖定 C2 剩餘三格的合法露出姿態；不調整 guard、碰撞形狀或牆面搜尋集合。
func _tank3_turret_80_to_90(tank: CharacterBody3D) -> void:
	var start_yaw := deg_to_rad(80.0)
	var end_yaw := deg_to_rad(90.0)
	var root_zero := tank.global_transform
	var start: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, start_yaw, 0.0)
	var finish: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, end_yaw, 0.0)
	var pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var target80 := func() -> Vector3: return pivot.global_position + Vector3(-cos(start_yaw), 0, sin(start_yaw)) * 40.0
	await _rotation_case(2, "turretyaw", tank, _best_plane(tank, start, finish, [&"turret", &"gun"]), func(): _set_pose(tank, 0.0, start_yaw, 0.0), func(): _set_pose(tank, 0.0, end_yaw, 0.0), func(): tank.aim_turret_at(pivot.global_position + Vector3(0, 0, 40), DT), func(): tank.aim_turret_at(target80.call(), DT), &"turret")

func _tank3_gun_yaw90_elevation_to_zero(tank: CharacterBody3D) -> void:
	var yaw90 := deg_to_rad(90.0)
	var elevation := deg_to_rad(tank.gun_max_elevation_degrees)
	var root_zero := tank.global_transform
	var start: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, yaw90, elevation)
	var finish: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, yaw90, 0.0)
	await _rotation_case(2, "gunpitch", tank, _best_plane(tank, start, finish, [&"gun"]), func(): _set_pose(tank, 0.0, yaw90, elevation), func(): _set_pose(tank, 0.0, yaw90, 0.0), func(): tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(0, 0, 40), DT), func(): tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(0, 40, 40), DT), &"gun")

func _tank4_turret_negative_max_to_zero(tank: CharacterBody3D) -> void:
	var start_yaw := -deg_to_rad(tank.turret_max_yaw_degrees)
	var root_zero := tank.global_transform
	var start: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, start_yaw, 0.0)
	var finish: Array[Transform3D] = tank.candidate_part_shape_world_transforms(root_zero, 0.0, 0.0)
	var pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var target_negative := func() -> Vector3: return pivot.global_position + Vector3(-cos(start_yaw), 0, sin(start_yaw)) * 40.0
	await _rotation_case(3, "turretyaw", tank, _best_plane(tank, start, finish, [&"turret", &"gun"]), func(): _set_pose(tank, 0.0, start_yaw, 0.0), func(): _set_pose(tank, 0.0, 0.0, 0.0), func(): tank.aim_turret_at(pivot.global_position + Vector3(-40, 0, 0), DT), func(): tank.aim_turret_at(target_negative.call(), DT), &"turret")

func _rotation_case(index: int, action: String, tank: CharacterBody3D, plane: Dictionary, reset_start: Callable, reset_end: Callable, forward: Callable, reverse: Callable, stat_kind: StringName) -> void:
	## 牆面法線取同一真凸形頂點的實際水平位移，面位於兩姿態支持面中點；非參數掃描。
	if not bool(plane.get("valid", false)):
		_fail_case(index, action, "geometric premise absent: supports=%s" % plane.get("table", {}))
		tank.queue_free()
		await physics_frame
		return
	var start_support := float(plane.start_support)
	var end_support := float(plane.end_support)
	print("C2_MATRIX oracle Tank%d/%s normal=%s candidate_start=%.6f candidate_end=%.6f center=%s" % [index + 1, action, plane.normal, start_support, end_support, tank.global_position])
	## 兩姿態的 cache 對照在牆尚未加入時完成，避免 endpoint oracle 將真車塞牆後被物理解算推出。
	reset_start.call()
	await physics_frame
	var normal := plane.normal as Vector3
	var actual_start := _support_max_actual(tank, normal, [])
	if absf(actual_start - start_support) > 0.002:
		_fail_case(index, action, "candidate/start sync mismatch %.6f vs %.6f" % [start_support, actual_start])
		tank.queue_free()
		await physics_frame
		return
	reset_end.call()
	await physics_frame
	var actual_end := _support_max_actual(tank, normal, [])
	if absf(actual_end - end_support) > 0.002:
		_fail_case(index, action, "candidate/end sync mismatch %.6f vs %.6f" % [end_support, actual_end])
		tank.queue_free()
		await physics_frame
		return
	reset_start.call()
	await physics_frame
	var pre_wall_position := tank.global_position
	var wall := _wall_at_plane(normal, (start_support + end_support) * 0.5)
	root.add_child(wall)
	await physics_frame
	if tank.global_position.distance_to(pre_wall_position) > 0.00001:
		_fail_case(index, action, "wall setup moved start tank before public command")
		await _free_pair(tank, wall)
		return
	if _overlap(tank):
		_fail_case(index, action, "initial overlap after authored-box placement")
		await _free_pair(tank, wall)
		return
	var endpoint_hits := _candidate_hits_external(tank, plane.end_transforms as Array[Transform3D])
	if not endpoint_hits:
		_fail_case(index, action, "fixture endpoint did not hit authored box despite support-plane placement")
		await _free_pair(tank, wall)
		return
	var blocked := false
	var before := _axis_value(tank, stat_kind)
	for unused in STEPS:
		forward.call()
		await physics_frame
		var stats := tank.get_motion_guard_attempt_stats(stat_kind) as Dictionary
		blocked = blocked or (String(stats.get("blocked_reason", "clear")) != "clear" and String(stats.get("blocked_reason", "")) != "no-op")
		if blocked: break
	var blocked_axis := _axis_value(tank, stat_kind)
	reverse.call()
	await physics_frame
	for unused in 30:
		reverse.call()
		await physics_frame
	var exited := absf(_axis_value(tank, stat_kind) - blocked_axis) > 0.0001
	var stats := tank.get_motion_guard_attempt_stats(stat_kind) as Dictionary
	var final_overlap := _overlap(tank)
	if not blocked or not exited or final_overlap:
		_fail_case(index, action, "expected guard block before insertion then public reverse exit blocked=%s exited=%s overlap=%s axis=%.6f->%.6f stats=%s" % [blocked, exited, final_overlap, before, blocked_axis, stats])
	else:
		_record(index, action, "startclear=true endhit=true support=%.4f->%.4f start=%.5f block=%.5f blocked=%s reverse_exit=%s stats=%s overlap=%s" % [start_support, end_support, before, blocked_axis, blocked, exited, stats, final_overlap])
	await _free_pair(tank, wall)

func _set_pose(tank: CharacterBody3D, root_yaw: float, turret_yaw: float, pitch: float) -> void:
	tank.global_rotation = Vector3(0, root_yaw, 0)
	var pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var gun := tank.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	pivot.rotation.y = turret_yaw
	gun.rotation.z = -pitch
	tank.call("_sync_part_collision_shapes")

func _support_min_x(tank: CharacterBody3D, wanted_anchors: Array[StringName]) -> float:
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var shape_index := 0
	var result := INF
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			if wanted_anchors.is_empty() or part.anchor in wanted_anchors:
				for point in shape.points:
					result = minf(result, (transforms[shape_index] * point).x)
			shape_index += 1
	return result

func _best_plane(tank: CharacterBody3D, start: Array[Transform3D], finish: Array[Transform3D], wanted_anchors: Array[StringName]) -> Dictionary:
	var directions := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	var table := {}
	var best := {"valid": false, "table": table, "end_transforms": finish}
	for normal in directions:
		## 牆面放置必須由整車形狀決定；wanted_anchors 僅描述此次入口的受測部位。
		var start_support := _support_max_candidate(tank, start, [], normal)
		var end_support := _support_max_candidate(tank, finish, [], normal)
		var delta := end_support - start_support
		table[normal] = delta
		if delta >= 0.004 and (not bool(best.valid) or delta > float(best.delta)):
			best = {"valid": true, "table": table, "normal": normal, "start_support": start_support, "end_support": end_support, "delta": delta, "end_transforms": finish}
	return best

func _support_max_candidate(tank: CharacterBody3D, transforms: Array[Transform3D], wanted_anchors: Array[StringName], normal: Vector3) -> float:
	var shape_index := 0
	var result := -INF
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			if wanted_anchors.is_empty() or part.anchor in wanted_anchors:
				for point in shape.points: result = maxf(result, normal.dot(transforms[shape_index] * point))
			shape_index += 1
	return result

func _support_max_actual(tank: CharacterBody3D, normal: Vector3, wanted_anchors: Array[StringName]) -> float:
	return _support_max_candidate(tank, tank.part_shape_world_transforms(), wanted_anchors, normal)

func _anchors_for_kind(kind: StringName) -> Array[StringName]:
	var anchors: Array[StringName] = []
	if kind == &"turret":
		anchors = [&"turret", &"gun"]
	elif kind == &"gun":
		anchors = [&"gun"]
	return anchors

func _candidate_hits_external(tank: CharacterBody3D, transforms: Array[Transform3D]) -> bool:
	var state := root.get_world_3d().direct_space_state
	var shape_index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = transforms[shape_index]
			query.collision_mask = tank.collision_mask
			query.exclude = [tank.get_rid()]
			query.collide_with_bodies = true
			if not state.intersect_shape(query, 1).is_empty(): return true
			shape_index += 1
	return false

func _axis_value(tank: CharacterBody3D, kind: StringName) -> float:
	if kind == &"root": return tank.global_rotation.y
	if kind == &"turret": return (tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D).rotation.y
	return -(tank.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D).rotation.z

func _wall_at_face(face_x: float) -> StaticBody3D:
	var scene := PLAYTEST_SCENE.instantiate() as Node3D
	var source := scene.get_node_or_null("SightBlockers/BuildingRowA/CentralOneStory") as StaticBody3D
	var clone := source.duplicate() as StaticBody3D
	var box := clone.get_node("CollisionShape3D") as CollisionShape3D
	var half := (box.shape as BoxShape3D).size.x * 0.5
	clone.position = Vector3(face_x - half, 0, 0)
	scene.free()
	return clone

func _wall_at_plane(normal: Vector3, face: float) -> StaticBody3D:
	var scene := PLAYTEST_SCENE.instantiate() as Node3D
	var source := scene.get_node_or_null("SightBlockers/BuildingRowA/CentralOneStory") as StaticBody3D
	var clone := source.duplicate() as StaticBody3D
	var box := clone.get_node("CollisionShape3D") as CollisionShape3D
	var half := (box.shape as BoxShape3D).size.x * 0.5
	## support 使用 +normal 的外側面；中心須在 face 的 +normal 一側，不能置入坦克半空間。
	clone.transform = Transform3D(Basis(normal, Vector3.UP, normal.cross(Vector3.UP)), normal * (face + half))
	scene.free()
	return clone

func _spawn(index: int) -> CharacterBody3D:
	var tank := TANK_SCENES[index].instantiate() as CharacterBody3D
	if tank == null:
		_fail_case(index, "spawn", "instantiate failed")
		return null
	root.add_child(tank)
	tank.global_position = Vector3.ZERO
	tank.global_rotation = Vector3.ZERO
	await physics_frame
	await physics_frame
	return tank

func _overlap(tank: CharacterBody3D) -> bool:
	var state := root.get_world_3d().direct_space_state
	for child in tank.get_children():
		if child is CollisionShape3D and child.shape != null:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = child.global_transform
			query.collision_mask = tank.collision_mask
			query.exclude = [tank.get_rid()]
			query.collide_with_bodies = true
			if not state.intersect_shape(query, 1).is_empty(): return true
	return false

func _free_pair(tank: Node, wall: Node) -> void:
	tank.queue_free()
	wall.queue_free()
	await physics_frame

func _record(index: int, action: String, message: String) -> void:
	evidence.append("C2_MATRIX Tank%d/%s PASS %s" % [index + 1, action, message])

func _fail_case(index: int, action: String, message: String) -> void:
	failures.append("C2_MATRIX Tank%d/%s FAIL %s" % [index + 1, action, message])
