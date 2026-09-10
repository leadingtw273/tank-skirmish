## LEA-173 Task 2：正式四車與訓練場既有建築的獨立 runtime smoke（僅 /tmp）。
extends SceneTree

const PLAYTEST_SCENE := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TANK_SCENES := [preload("res://src/actors/tank/variants/tank1/tank1.tscn"), preload("res://src/actors/tank/variants/tank2/tank2.tscn"), preload("res://src/actors/tank/variants/tank3/tank3.tscn"), preload("res://src/actors/tank/variants/tank4/tank4.tscn")]
const DT := 1.0 / 60.0
var failures: Array[String] = []
var samples: Dictionary = {&"open_public": [], &"wall_public": [], &"helper": [], &"three_axis_open": [], &"three_axis_near_wall": []}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var building := _clone_building()
	if building == null:
		return _fail("D/Harness: authored CentralOneStory unavailable.")
	root.add_child(building)
	await physics_frame
	await _open_four(building)
	await _wall_tank2(building)
	await _ground_contact_four(building)
	await _other_tank_is_not_pushed(building)
	await _profile_three_axes(building)
	_report()
	if failures.is_empty():
		print("RUNTIME_GUARD PASS: four-tank 60Hz open/fixed/ground/wall/perf matrix.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _open_four(building: StaticBody3D) -> void:
	for index in TANK_SCENES.size():
		var tank := await _spawn(index, building.global_position + Vector3(30.0 + 12.0 * index, 0.0, 28.0))
		if tank == null: continue
		var pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
		var gun := tank.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
		var pos := tank.global_position
		var root_yaw := tank.global_rotation.y
		var turret_yaw := pivot.rotation.y
		var gun_pitch := gun.rotation.z
		tank.set_movement_input(1.0)
		await physics_frame
		tank.set_movement_input(-1.0)
		await physics_frame
		tank.set_movement_input(0.0)
		tank.set_turn_input(1.0)
		await physics_frame
		tank.set_turn_input(0.0)
		_call_and_time(tank, &"open_public", func(): tank.aim_turret_at(pivot.global_position + Vector3(24, 0, 24), DT))
		_call_and_time(tank, &"open_public", func(): tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(18, 8, 0), DT))
		_expect_stats("A%d/root" % (index + 1), tank, &"root", false)
		_expect_stats("A%d/turret" % (index + 1), tank, &"turret", false)
		_expect_stats("A%d/gun" % (index + 1), tank, &"gun", false)
		if tank.global_position.distance_to(pos) < 0.00001: failures.append("A%d open forward/reverse made no movement." % (index + 1))
		if is_equal_approx(root_yaw, tank.global_rotation.y): failures.append("A%d open root yaw made no movement." % (index + 1))
		if is_equal_approx(turret_yaw, pivot.rotation.y): failures.append("A%d legal turret yaw made no movement (including fixed tank)." % (index + 1))
		if is_equal_approx(gun_pitch, gun.rotation.z): failures.append("A%d legal gun pitch made no movement." % (index + 1))
		if _overlap(tank): failures.append("A%d open pose overlaps external body." % (index + 1))
		tank.queue_free()
		await physics_frame

## 同一個歷史 RED setup：若無 guard，Tank2 砲管在正常 1/60 turret yaw 會進入此建築。
func _wall_tank2(building: StaticBody3D) -> void:
	var tank := await _spawn(1, building.global_position)
	if tank == null: return
	var box := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if box == null or not (box.shape is BoxShape3D):
		failures.append("D/Harness: CentralOneStory must retain BoxShape3D.")
		return
	var center := box.global_position
	var normal := -box.global_transform.basis.x.normalized()
	var clearance := _nearest_clearance(tank, center, normal, (box.shape as BoxShape3D).size.x * 0.5)
	if clearance < 0.0:
		failures.append("B/wall: no non-overlapping Tank2 start beside building.")
		return
	await physics_frame
	var pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var blocked := false
	for frame in 240:
		_call_and_time(tank, &"wall_public", func(): tank.aim_turret_at(center, DT))
		await physics_frame
		var stats := tank.get_motion_guard_attempt_stats(&"turret") as Dictionary
		if String(stats.get("blocked_reason", "")) != "clear" and String(stats.get("blocked_reason", "")) != "no-op":
			blocked = true
			print("RUNTIME_GUARD wall frame=%d clearance=%.4f yaw=%.6f stats=%s" % [frame + 1, clearance, pivot.rotation.y, stats])
			break
	if not blocked:
		failures.append("B/wall: normal Tank2 turret yaw never reported a block against authored building.")
	else:
		_expect_stats("B/wall-turret", tank, &"turret", true)
		if _overlap(tank): failures.append("B/wall: guarded pose overlaps authored building.")
		var before := pivot.rotation.y
		_call_and_time(tank, &"wall_public", func(): tank.aim_turret_at(pivot.global_position + (pivot.global_position - center).normalized() * 40.0, DT))
		await physics_frame
		if is_equal_approx(before, pivot.rotation.y): failures.append("B/wall: immediate opposite turret command did not exit.")
	tank.queue_free()
	await physics_frame

## 每車用其實際 convex world bounds 最低點安排水平 layer-1 地板；頂面只進入
## guard 的 .002 margin，接觸 assert 以 ground RID 為準，不能把「場內有地板」當成接地證據。
func _ground_contact_four(building: StaticBody3D) -> void:
	for index in TANK_SCENES.size():
		var tank := await _spawn(index, building.global_position + Vector3(42 + index * 14, 0, 52))
		if tank == null: continue
		tank.call("_sync_part_collision_shapes")
		var lowest_y: float = tank.part_world_bounds().position.y
		var ground := StaticBody3D.new()
		ground.name = "RuntimeGuardGroundTank%d" % (index + 1)
		ground.collision_layer = 1
		var thickness := 0.2
		var top_y: float = lowest_y + 0.001
		ground.position = Vector3(tank.global_position.x, top_y - thickness * 0.5, tank.global_position.z)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(30, thickness, 30)
		collision.shape = shape
		ground.add_child(collision)
		root.add_child(ground)
		await physics_frame
		if not _touches_rid(tank, ground.get_rid()):
			failures.append("C/Tank%d ground: no initial part-shape contact with floor RID at lowest_y=%.6f top_y=%.6f." % [index + 1, lowest_y, top_y])
		else:
			print("RUNTIME_GUARD ground Tank%d initial_contact=true lowest_y=%.6f top_y=%.6f rid=%d" % [index + 1, lowest_y, top_y, ground.get_rid().get_id()])
		var before := tank.global_rotation.y
		tank.set_turn_input(1.0)
		for unused in 6: await physics_frame
		tank.set_turn_input(0.0)
		_expect_stats("C/Tank%d-ground-root" % (index + 1), tank, &"root", false)
		if is_equal_approx(before, tank.global_rotation.y): failures.append("C/Tank%d ground: contact fully locked normal root yaw." % (index + 1))
		ground.queue_free()
		tank.queue_free()
		await physics_frame

## 旋轉 guard 僅做 query；另一台 CharacterBody3D 不能因新增部位 shape 被施加推力。
func _other_tank_is_not_pushed(building: StaticBody3D) -> void:
	var primary := await _spawn(1, building.global_position + Vector3(52, 0, 32))
	var other := await _spawn(2, building.global_position + Vector3(40, 0, 32))
	if primary == null or other == null: return
	var other_start := other.global_position
	primary.set_movement_input(1.0)
	var collided := false
	for unused in 180:
		await physics_frame
		collided = collided or primary.get_slide_collision_count() > 0
	primary.set_movement_input(0.0)
	if not collided: failures.append("F/other-tank: primary never reached the stationary tank.")
	if other.global_position.distance_to(other_start) > 0.00001:
		failures.append("F/other-tank: stationary tank was pushed by another tank (delta=%f)." % other.global_position.distance_to(other_start))
	if _overlap(primary) or _overlap(other): failures.append("F/other-tank: tank pair ended with external overlap.")
	primary.queue_free()
	other.queue_free()
	await physics_frame

## 每輪同時安排下一個 physics root yaw 和兩個同步瞄準入口；public 時間只包三個同步
## 呼叫（await 僅用來更新下一輪 state），並和 helper 內部時間分開列示。
func _profile_three_axes(building: StaticBody3D) -> void:
	var box := building.get_node("CollisionShape3D") as CollisionShape3D
	var normal := -box.global_transform.basis.x.normalized()
	var half := (box.shape as BoxShape3D).size.x * 0.5
	for tank_index in TANK_SCENES.size():
		for profile in [{"name": "open", "position": building.global_position + Vector3(48 + tank_index * 16, 0, 28)}, {"name": "near_wall", "position": box.global_position + normal * (half + 5.0)}]:
			var tank := await _spawn(tank_index, profile.position)
			if tank == null: continue
			if _overlap(tank):
				var support := _nearest_clearance(tank, box.global_position, normal, half)
				if support < 0.0:
					failures.append("E/Tank%d/%s: no supported non-overlap placement." % [tank_index + 1, profile.name])
					tank.queue_free()
					continue
				tank.global_position = box.global_position + normal * (half + support + 1.0)
				tank.call("_sync_part_collision_shapes")
				print("RUNTIME_GUARD profile Tank%d/%s adjusted_support=%.4f" % [tank_index + 1, profile.name, support])
				await physics_frame
			var pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
			var public_usec: Array = []
			var helper_usec: Array = []
			var max_shapes := 0
			var max_substeps := 0
			var max_queries := 0
			for frame in 60:
				var side := 1.0 if frame % 2 == 0 else -1.0
				var started := Time.get_ticks_usec()
				tank.set_turn_input(1.0)
				var legal_turret_target := pivot.global_position + tank.global_transform.basis * Vector3(-20.0, 0.0, 2.0 * side)
				tank.aim_turret_at(legal_turret_target, DT)
				tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + tank.muzzle_global_direction() * 20.0 + Vector3.UP * (3.0 * side), DT)
				public_usec.append(Time.get_ticks_usec() - started)
				await physics_frame
				for kind in [&"root", &"turret", &"gun"]:
					var stats := tank.get_motion_guard_attempt_stats(kind) as Dictionary
					var queries := int(stats.get("query_count", 0))
					if queries > 0:
						helper_usec.append(int(stats.get("elapsed_usec", 0)))
						max_shapes = maxi(max_shapes, int(stats.get("shape_count", 0)))
						max_substeps = maxi(max_substeps, int(stats.get("substeps", 0)))
						max_queries = maxi(max_queries, queries)
					elif String(stats.get("blocked_reason", "")) != "no-op":
						failures.append("E/Tank%d/%s frame=%d %s missing query: %s" % [tank_index + 1, profile.name, frame + 1, kind, stats])
			_print_profile_measurement(tank_index + 1, profile.name, public_usec, helper_usec, max_shapes, max_substeps, max_queries)
			tank.set_turn_input(0.0)
			if _overlap(tank): failures.append("E/Tank%d/%s: three-axis profile ended overlapping external body." % [tank_index + 1, profile.name])
			tank.queue_free()
			await physics_frame

func _print_profile_measurement(tank_number: int, profile: String, public_usec: Array, helper_usec: Array, shape_count: int, substeps: int, queries: int) -> void:
	public_usec.sort()
	helper_usec.sort()
	var public_p95: int = int(public_usec[mini(public_usec.size() - 1, ceili(public_usec.size() * 0.95) - 1)])
	var helper_p95: int = int(helper_usec[mini(helper_usec.size() - 1, ceili(helper_usec.size() * 0.95) - 1)])
	print("RUNTIME_GUARD profile Tank%d/%s public_p95_max_usec=%d/%d helper_p95_max_usec=%d/%d shape_max=%d substeps_max=%d queries_max=%d" % [tank_number, profile, public_p95, public_usec.back(), helper_p95, helper_usec.back(), shape_count, substeps, queries])

func _spawn(index: int, position: Vector3) -> CharacterBody3D:
	var tank := TANK_SCENES[index].instantiate() as CharacterBody3D
	if tank == null:
		failures.append("D/Harness: Tank%d instantiate failed." % (index + 1))
		return null
	root.add_child(tank)
	tank.global_position = position
	tank.global_rotation = Vector3.ZERO
	await physics_frame
	await physics_frame
	return tank

func _clone_building() -> StaticBody3D:
	var scene := PLAYTEST_SCENE.instantiate() as Node3D
	var source := scene.get_node_or_null("SightBlockers/BuildingRowA/CentralOneStory") as StaticBody3D
	var row := scene.get_node_or_null("SightBlockers/BuildingRowA") as Node3D
	if source == null or row == null:
		scene.free()
		return null
	var clone := source.duplicate() as StaticBody3D
	clone.global_transform = row.transform * source.transform
	scene.free()
	return clone

func _nearest_clearance(tank: CharacterBody3D, center: Vector3, normal: Vector3, half: float) -> float:
	for hundredth in 1200:
		var clearance := 12.0 - hundredth * 0.01
		tank.global_position = center + normal * (half + clearance)
		tank.global_rotation = Vector3.ZERO
		tank.call("_sync_part_collision_shapes")
		if not _overlap(tank): continue
		var safe := clearance + 0.01
		tank.global_position = center + normal * (half + safe)
		tank.call("_sync_part_collision_shapes")
		return safe if not _overlap(tank) else -1.0
	return -1.0

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

func _touches_rid(tank: CharacterBody3D, expected_rid: RID) -> bool:
	var state := root.get_world_3d().direct_space_state
	for child in tank.get_children():
		if child is CollisionShape3D and child.shape != null:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = child.global_transform
			query.margin = 0.002
			query.collision_mask = tank.collision_mask
			query.exclude = [tank.get_rid()]
			query.collide_with_bodies = true
			query.collide_with_areas = false
			for hit in state.intersect_shape(query, 32):
				if hit.rid == expected_rid: return true
	return false

func _call_and_time(tank: CharacterBody3D, bucket: StringName, action: Callable) -> void:
	var started := Time.get_ticks_usec()
	action.call()
	(samples[bucket] as Array).append(Time.get_ticks_usec() - started)

func _expect_stats(label: String, tank: CharacterBody3D, kind: StringName, expect_block: bool) -> void:
	if not tank.has_method("get_motion_guard_attempt_stats"):
		failures.append("%s: missing finite guard stats API." % label)
		return
	var stats := tank.get_motion_guard_attempt_stats(kind) as Dictionary
	for key in [&"query_count", &"substeps", &"accepted_substeps", &"shape_count", &"blocked_reason", &"elapsed_usec"]:
		if not stats.has(key):
			failures.append("%s: stats lacks %s." % [label, key])
			return
	(samples[&"helper"] as Array).append(int(stats.elapsed_usec))
	if int(stats.query_count) <= 0 or int(stats.substeps) <= 0 or int(stats.shape_count) <= 0:
		failures.append("%s: non-finite/unexecuted guard stats %s." % [label, stats])
	if expect_block and String(stats.blocked_reason) == "clear": failures.append("%s: expected block, got clear." % label)

func _report() -> void:
	for bucket in samples:
		var values: Array = samples[bucket]
		if values.is_empty(): continue
		values.sort()
		var p95 := mini(values.size() - 1, ceili(values.size() * 0.95) - 1)
		print("RUNTIME_GUARD timing=%s n=%d p95_usec=%d max_usec=%d" % [bucket, values.size(), values[p95], values.back()])

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
