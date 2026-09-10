## LEA-173 H1--H5：只經正式 Tank 公開入口驗證接觸滑動與慢速 yaw。
extends SceneTree

const PLAYTEST_SCENE := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TANK_SCENES := [preload("res://src/actors/tank/variants/tank1/tank1.tscn"), preload("res://src/actors/tank/variants/tank2/tank2.tscn"), preload("res://src/actors/tank/variants/tank3/tank3.tscn"), preload("res://src/actors/tank/variants/tank4/tank4.tscn")]
const PLAYER_CONTROLLER := preload("res://src/player/player_controller.gd")
const DT := 1.0 / 60.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for index in TANK_SCENES.size():
		for angle in [0.0, 10.0]:
			var front := await _case(index, angle)
			if not bool(front.start_clear) or not bool(front.contact) or absf(float(front.yaw_delta)) > 0.002 \
					or (front.slide as Vector3).length() > 0.0001 or float(front.max_window_tangent) > 0.0001 \
					or not bool(front.stable_contact) or not bool(front.exited):
				failures.append("H1 Tank%d %.0fdeg contact=%s yaw=%.6f slide=%s" % [index + 1, angle, front.contact, front.yaw_delta, front.slide])
		var left := await _case(index, 30.0)
		var right := await _case(index, -30.0)
		if not bool(left.contact) or not bool(right.contact) or absf(float(left.tangent)) <= 0.02 or absf(float(right.tangent)) <= 0.02 \
				or is_zero_approx(float(left.yaw_delta)) or is_zero_approx(float(right.yaw_delta)) \
				or signf(float(left.yaw_delta)) == signf(float(right.yaw_delta)) \
				or not bool(left.h2_bounds_ok) or not bool(right.h2_bounds_ok) \
				or not bool(left.h2_consumers_ok) or not bool(right.h2_consumers_ok) \
				or int(left.consumer_check_count) <= 0 or int(right.consumer_check_count) <= 0 \
				or int(left.consumer_nonzero_auto_count) <= 0 or int(right.consumer_nonzero_auto_count) <= 0 \
				or int(left.spread_distinguishable_count) <= 0 or int(right.spread_distinguishable_count) <= 0 \
				or int(left.tread_distinguishable_count) <= 0 or int(right.tread_distinguishable_count) <= 0:
			failures.append("H2 Tank%d left=%s right=%s" % [index + 1, left, right])
		var manual_left := await _manual_case(index, -1.0)
		var manual_right := await _manual_case(index, 1.0)
		if not bool(manual_left.start_clear) or not bool(manual_right.start_clear) \
				or not bool(manual_left.contact) or not bool(manual_right.contact) \
				or not is_zero_approx(float(manual_left.auto_yaw)) or not is_zero_approx(float(manual_right.auto_yaw)) \
				or not bool(manual_left.turned_out) or not bool(manual_right.turned_out) \
				or not bool(manual_left.cleared) or not bool(manual_right.cleared):
			failures.append("H3 Tank%d A=%s D=%s" % [index + 1, manual_left, manual_right])
	var corner := await _corner_case()
	if not bool(corner.start_clear) or not bool(corner.premise) or not bool(corner.both_walls_same_frame) \
			or not bool(corner.contact) or not bool(corner.stopped) or not bool(corner.exited):
		failures.append("H4 %s" % corner)
	var controller_clear := await _controller_clear_case()
	if not bool(controller_clear.switch_old) or not bool(controller_clear.switch_new) or not bool(controller_clear.disabled):
		failures.append("H3 controller clear %s" % controller_clear)
	var pair_a := await _tank_pair_case(1, 3)
	var pair_b := await _tank_pair_case(3, 1)
	if not bool(pair_a.start_clear) or not bool(pair_a.contact) or float(pair_a.other_delta) > 0.00001 \
			or not bool(pair_b.start_clear) or not bool(pair_b.contact) or float(pair_b.other_delta) > 0.00001:
		failures.append("H5 medium-heavy=%s heavy-medium=%s" % [pair_a, pair_b])
	if failures.is_empty():
		print("CONTACT_RESPONSE PASS: H1-H5 fixed real-tank contact matrix.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _case(index: int, angle_degrees: float) -> Dictionary:
	var tank := TANK_SCENES[index].instantiate() as CharacterBody3D
	root.add_child(tank)
	tank.global_rotation.y = deg_to_rad(angle_degrees)
	await physics_frame
	var wall := _wall_at_face(_support_min_x(tank) - 0.10)
	root.add_child(wall)
	await physics_frame
	var start_clear := not _overlap(tank)
	var start := tank.global_position
	var yaw_before := tank.global_rotation.y
	tank.set_movement_input(1.0)
	var contacted := false
	var previous_yaw := yaw_before
	var auto_cap := minf(deg_to_rad(12.0), float(tank.turn_speed) * 0.35)
	var h2_bounds_ok := true
	var max_actual_rate := 0.0
	var max_persistent_base := 0.0
	var max_rate_error := 0.0
	var h2_consumers_ok := true
	var consumer_check_count := 0
	var consumer_nonzero_auto_count := 0
	var spread_distinguishable_count := 0
	var tread_distinguishable_count := 0
	var max_spread_error := 0.0
	var previous_spread: float = float(tank.get_current_spread_degrees())
	for unused in 120:
		await physics_frame
		contacted = contacted or tank.get_slide_collision_count() > 0
		var pose_rate := angle_difference(previous_yaw, tank.global_rotation.y) / DT
		previous_yaw = tank.global_rotation.y
		var actual_spread: float = float(tank.get_current_spread_degrees())
		if absf(angle_degrees) > 10.0 and contacted:
			var frame_stats: Dictionary = tank.get_contact_response_stats()
			var requested_rate := float(frame_stats.auto_yaw_requested) / DT
			var applied_rate := float(frame_stats.auto_yaw_applied) / DT
			var persistent_base := float(tank.angular_speed)
			var reported_rate := float(tank.get_actual_angular_speed())
			max_actual_rate = maxf(max_actual_rate, absf(pose_rate))
			max_persistent_base = maxf(max_persistent_base, absf(persistent_base))
			max_rate_error = maxf(max_rate_error, absf(reported_rate - pose_rate))
			## H2 無手動轉向：每幀總偏轉守上限，且接觸偏轉不能進入持續控制狀態。
			h2_bounds_ok = h2_bounds_ok and absf(pose_rate) <= auto_cap + 0.0001 \
					and absf(requested_rate) <= auto_cap + 0.0001 and absf(applied_rate) <= auto_cap + 0.0001 \
					and absf(persistent_base) <= 0.0001 and absf(reported_rate - pose_rate) <= 0.0001 \
					and absf(reported_rate - persistent_base - applied_rate) <= 0.0001
			## H2 消費端的實際 spread 與播放器必須跟隨本幀總偏航；persistent 僅作反例比較。
			var actual_linear_speed: float = float(tank.get_actual_linear_speed())
			var actual_turret_rate: float = float(tank.get_actual_turret_angular_speed())
			var expected_spread: float = _expected_spread_after_physics(tank, previous_spread, actual_linear_speed, reported_rate, actual_turret_rate)
			var persistent_expected_spread: float = _expected_spread_after_physics(tank, previous_spread, actual_linear_speed, persistent_base, actual_turret_rate)
			var expected_tread: StringName = StringName(tank._tread_animation_for_motion(actual_linear_speed, reported_rate))
			var persistent_tread: StringName = StringName(tank._tread_animation_for_motion(actual_linear_speed, persistent_base))
			var expected_tread_scale: float = float(tank._tread_animation_speed_scale(expected_tread, actual_linear_speed, reported_rate))
			var persistent_tread_scale: float = float(tank._tread_animation_speed_scale(persistent_tread, actual_linear_speed, persistent_base))
			var tread_player: AnimationPlayer = tank.tread_animation_player as AnimationPlayer
			var tread_matches: bool = false
			if tread_player != null:
				var active_tread: StringName = StringName(tank.active_tread_animation)
				var tread_paused: bool = bool(tank.tread_animation_paused)
				var player_animation: StringName = tread_player.current_animation
				tread_matches = tread_paused and not tread_player.is_playing() if expected_tread.is_empty() else \
						active_tread == expected_tread and not tread_paused and tread_player.is_playing() \
						and player_animation == expected_tread and absf(tread_player.speed_scale - expected_tread_scale) <= 0.0001
			consumer_check_count += 1
			max_spread_error = maxf(max_spread_error, absf(actual_spread - expected_spread))
			if absf(applied_rate) > 0.0001:
				consumer_nonzero_auto_count += 1
				spread_distinguishable_count += 1 if absf(expected_spread - persistent_expected_spread) > 0.0001 else 0
				## 車型可以共用同一片段；實際播放倍率也能辨別角速度來源。
				tread_distinguishable_count += 1 if expected_tread != persistent_tread \
						or absf(expected_tread_scale - persistent_tread_scale) > 0.0001 else 0
				h2_consumers_ok = h2_consumers_ok and absf(actual_spread - expected_spread) <= 0.0001 and tread_matches
		previous_spread = actual_spread
		if contacted and absf(angle_degrees) <= 10.0:
			break
	var stable_tangent := 0.0
	var max_window_tangent := 0.0
	var stable_contact := true
	var exited := true
	var stats: Dictionary = tank.get_contact_response_stats()
	if absf(angle_degrees) <= 10.0 and contacted:
		## 首次接觸的 move_and_slide 解算不納入死區漂移；確認接觸後才量固定窗口的真位置。
		for unused in 5: await physics_frame
		for window in 4:
			var stable_start_z := tank.global_position.z
			for unused in 30:
				await physics_frame
				stable_contact = stable_contact and tank.get_slide_collision_count() > 0 and bool(tank.get_contact_response_stats().active)
			var window_tangent := absf(tank.global_position.z - stable_start_z)
			max_window_tangent = maxf(max_window_tangent, window_tangent)
			stable_tangent += window_tangent
		stats = tank.get_contact_response_stats()
		var blocked_position := tank.global_position
		tank.set_movement_input(-1.0)
		for unused in 90: await physics_frame
		exited = tank.global_position.x > blocked_position.x + 0.02
	var result := {"start_clear": start_clear, "contact": contacted, "yaw_delta": tank.global_rotation.y - yaw_before, "tangent": tank.global_position.z - start.z, "stable_tangent": stable_tangent, "max_window_tangent": max_window_tangent, "stable_contact": stable_contact, "exited": exited, "slide": stats.get("slide_velocity", Vector3.ZERO), "stats": stats, "h2_bounds_ok": h2_bounds_ok, "h2_consumers_ok": h2_consumers_ok, "consumer_check_count": consumer_check_count, "consumer_nonzero_auto_count": consumer_nonzero_auto_count, "spread_distinguishable_count": spread_distinguishable_count, "tread_distinguishable_count": tread_distinguishable_count, "auto_cap": auto_cap, "max_actual_rate": max_actual_rate, "max_persistent_base": max_persistent_base, "max_rate_error": max_rate_error, "max_spread_error": max_spread_error}
	print("CONTACT_RESPONSE Tank%d angle=%.0f %s" % [index + 1, angle_degrees, result])
	tank.queue_free()
	wall.queue_free()
	await physics_frame
	return result


func _expected_spread_after_physics(tank: CharacterBody3D, previous_spread: float, actual_linear_speed: float, actual_angular_speed: float, actual_turret_angular_speed: float) -> float:
	## H2 未開火；依前幀實際 spread 與真實速度重建本幀，不能呼叫會寫狀態的 update 方法。
	var cap: float = maxf(float(tank.aim_spread_cap_degrees), 0.0)
	var target: float = float(tank.calculate_target_spread_degrees(actual_linear_speed, actual_angular_speed, actual_turret_angular_speed))
	var expected: float = clampf(previous_spread, 0.0, cap)
	if expected < target:
		return clampf(move_toward(expected, target, maxf(float(tank.aim_spread_grow_degrees_per_second), 0.0) * DT), 0.0, cap)
	var linear_top_speed: float = float(tank.movement_speed) if actual_linear_speed >= 0.0 else float(tank.reverse_movement_speed)
	var speed_ratio: float = 0.0 if linear_top_speed <= 0.0 else clampf(absf(actual_linear_speed) / linear_top_speed, 0.0, 1.0)
	var recovery_rate: float = lerpf(
		maxf(float(tank.aim_spread_stationary_recovery_degrees_per_second), 0.0),
		maxf(float(tank.aim_spread_moving_recovery_degrees_per_second), 0.0),
		speed_ratio,
	)
	return clampf(move_toward(expected, target, recovery_rate * DT), 0.0, cap)


func _support_min_x(tank: CharacterBody3D) -> float:
	var result := INF
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var shape_index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points:
				result = minf(result, (transforms[shape_index] * point).x)
			shape_index += 1
	return result


func _wall_at_face(face_x: float) -> StaticBody3D:
	var scene := PLAYTEST_SCENE.instantiate() as Node3D
	var source := scene.get_node_or_null("SightBlockers/BuildingRowA/CentralOneStory") as StaticBody3D
	var clone := source.duplicate() as StaticBody3D
	var box := clone.get_node("CollisionShape3D") as CollisionShape3D
	var half := (box.shape as BoxShape3D).size.x * 0.5
	clone.position = Vector3(face_x - half, 0, 0)
	scene.free()
	return clone


func _manual_case(index: int, manual_turn: float) -> Dictionary:
	var tank := TANK_SCENES[index].instantiate() as CharacterBody3D
	root.add_child(tank)
	## 每個 A/D case 都是 fresh fixture，並鏡像成該手動方向可安全轉離牆面。
	tank.global_rotation.y = deg_to_rad(45.0 * signf(manual_turn))
	await physics_frame
	var wall := _wall_at_face(_support_min_x(tank) - 0.10)
	root.add_child(wall)
	await physics_frame
	var start_clear := tank.get_slide_collision_count() == 0
	tank.set_movement_input(1.0)
	var contacted := false
	for unused in 90:
		await physics_frame
		contacted = contacted or tank.get_slide_collision_count() > 0
	tank.set_manual_turn_active(true)
	tank.set_turn_input(manual_turn)
	var auto_zero := true
	## 先在 W 仍持續推牆時驗手動來源必壓掉 auto yaw。
	for unused in 5:
		await physics_frame
		auto_zero = auto_zero and is_zero_approx(float(tank.get_contact_response_stats().get("auto_yaw_requested", 0.0)))
	## 再鬆 W（不倒退、不重設姿態），驗證原接觸姿態的安全方向可由 guard 轉出。
	tank.set_movement_input(0.0)
	var start_yaw := tank.global_rotation.y
	for unused in 30: await physics_frame
	var manual_yaw := tank.global_rotation.y - start_yaw
	var stats: Dictionary = tank.get_contact_response_stats()
	tank.clear_contact_response_state()
	var cleared_stats: Dictionary = tank.get_contact_response_stats()
	var result := {"start_clear": start_clear, "contact": contacted, "auto_yaw": 0.0 if auto_zero else stats.get("auto_yaw_requested", 0.0), "manual_yaw": manual_yaw, "turned_out": signf(manual_yaw) == signf(manual_turn) and absf(manual_yaw) > 0.0001, "cleared": not bool(cleared_stats.active) and int(cleared_stats.contact_count) == 0 and String(cleared_stats.reason) == "cleared", "turn": manual_turn}
	print("CONTACT_RESPONSE H3 Tank%d %s" % [index + 1, result])
	tank.queue_free(); wall.queue_free(); await physics_frame
	return result


func _corner_case() -> Dictionary:
	var tank := TANK_SCENES[1].instantiate() as CharacterBody3D
	root.add_child(tank)
	tank.global_rotation.y = deg_to_rad(45.0)
	await physics_frame
	var forward := (tank.transform.basis * Vector3(-1, 0, 0)).normalized()
	var wall_x := _wall_at_plane(tank, Vector3.RIGHT, 0.10)
	var wall_z := _wall_at_plane(tank, Vector3.FORWARD, 0.10)
	root.add_child(wall_x); root.add_child(wall_z)
	await physics_frame
	var start_clear := tank.get_slide_collision_count() == 0
	var no_safe_inward_tangent := forward.dot(Vector3.RIGHT) < 0.0 and forward.dot(Vector3.FORWARD) < 0.0
	tank.set_movement_input(1.0)
	var contacted := false
	var both_walls_same_frame := false
	var observed_normals: Dictionary = {}
	for unused in 120:
		await physics_frame
		contacted = contacted or tank.get_slide_collision_count() > 0
		var frame_rids: Array[RID] = []
		for collision_index in tank.get_slide_collision_count():
			var collision := tank.get_slide_collision(collision_index)
			var rid := collision.get_collider_rid()
			if rid == wall_x.get_rid() or rid == wall_z.get_rid():
				frame_rids.append(rid)
				observed_normals[rid] = collision.get_normal()
		both_walls_same_frame = both_walls_same_frame or (frame_rids.has(wall_x.get_rid()) and frame_rids.has(wall_z.get_rid()))
	var actual_two_face_premise := observed_normals.has(wall_x.get_rid()) and observed_normals.has(wall_z.get_rid()) \
			and forward.dot(observed_normals[wall_x.get_rid()]) < 0.0 and forward.dot(observed_normals[wall_z.get_rid()]) < 0.0 \
			and absf((observed_normals[wall_x.get_rid()] as Vector3).dot(observed_normals[wall_z.get_rid()] as Vector3)) < 0.1
	var stopped := tank.get_real_velocity().length() < 0.05
	var before := tank.global_position
	tank.set_movement_input(-1.0)
	for unused in 90: await physics_frame
	var result := {"start_clear": start_clear, "premise": no_safe_inward_tangent and actual_two_face_premise, "both_walls_same_frame": both_walls_same_frame, "normals": observed_normals, "contact": contacted, "stopped": stopped, "exited": tank.global_position.distance_to(before) > 0.02}
	print("CONTACT_RESPONSE H4 ", result)
	tank.queue_free(); wall_x.queue_free(); wall_z.queue_free(); await physics_frame
	return result


func _controller_clear_case() -> Dictionary:
	var controller := PLAYER_CONTROLLER.new()
	root.add_child(controller)
	controller.set_physics_process(false)
	var old_tank := TANK_SCENES[1].instantiate() as CharacterBody3D
	var new_tank := TANK_SCENES[3].instantiate() as CharacterBody3D
	new_tank.position.z = 50.0
	root.add_child(old_tank); root.add_child(new_tank)
	await physics_frame
	controller.set_controlled_tank(old_tank)
	var old_wall := _wall_at_face(_support_min_x(old_tank) - 0.10)
	root.add_child(old_wall)
	controller.apply_commands(1.0, 0.0, false)
	for unused in 90: await physics_frame
	var old_contact := bool(old_tank.get_contact_response_stats().active)
	controller.set_controlled_tank(new_tank)
	var switch_old := old_contact and String(old_tank.get_contact_response_stats().reason) == "cleared"
	var switch_new := String(new_tank.get_contact_response_stats().reason) == "cleared"
	var new_wall := _wall_at_face(_support_min_x(new_tank) - 0.10)
	new_wall.position.z = 50.0
	root.add_child(new_wall)
	controller.apply_commands(1.0, 0.0, false)
	for unused in 90: await physics_frame
	var new_contact := bool(new_tank.get_contact_response_stats().active)
	controller.set_controls_enabled(false)
	var disabled := new_contact and String(new_tank.get_contact_response_stats().reason) == "cleared"
	var result := {"switch_old": switch_old, "switch_new": switch_new, "disabled": disabled}
	print("CONTACT_RESPONSE H3 controller ", result)
	controller.queue_free(); old_tank.queue_free(); new_tank.queue_free(); old_wall.queue_free(); new_wall.queue_free()
	await physics_frame
	return result


func _tank_pair_case(moving_index: int, other_index: int) -> Dictionary:
	var moving := TANK_SCENES[moving_index].instantiate() as CharacterBody3D
	var other := TANK_SCENES[other_index].instantiate() as CharacterBody3D
	root.add_child(moving)
	moving.global_rotation.y = deg_to_rad(30.0)
	other.position = Vector3(100.0, 0.0, 100.0)
	root.add_child(other)
	await physics_frame
	var direction := (moving.transform.basis * Vector3(-1, 0, 0)).normalized()
	var moving_front := _support_projection(moving, direction, true)
	var other_back := _support_projection(other, direction, false)
	var other_local_back := other_back - direction.dot(other.global_position)
	other.global_position = direction * (moving_front + 0.10 - other_local_back)
	other.call("_sync_part_collision_shapes")
	moving.clear_contact_response_state()
	for unused in 3: await physics_frame
	var start_clear := moving.get_slide_collision_count() == 0 and other.get_slide_collision_count() == 0
	var other_start := other.global_position
	moving.set_movement_input(1.0)
	var contacted := false
	for unused in 180:
		await physics_frame
		for collision_index in moving.get_slide_collision_count():
			contacted = contacted or moving.get_slide_collision(collision_index).get_collider() == other
	var result := {"start_clear": start_clear, "angle": 30.0, "contact": contacted, "other_delta": other.global_position.distance_to(other_start), "moving": moving.global_position, "other": other.global_position}
	print("CONTACT_RESPONSE H5 moving=Tank%d other=Tank%d %s" % [moving_index + 1, other_index + 1, result])
	moving.queue_free(); other.queue_free(); await physics_frame
	return result


func _support_projection(tank: CharacterBody3D, direction: Vector3, maximum: bool) -> float:
	var result := -INF if maximum else INF
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var shape_index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points:
				var projection := direction.dot(transforms[shape_index] * point)
				result = maxf(result, projection) if maximum else minf(result, projection)
			shape_index += 1
	return result


func _wall_at_plane(tank: CharacterBody3D, outward_normal: Vector3, gap: float) -> StaticBody3D:
	var face := _support_projection(tank, outward_normal, false) - gap
	var wall := _wall_at_face(face)
	var box := wall.get_node("CollisionShape3D") as CollisionShape3D
	var half := (box.shape as BoxShape3D).size.x * 0.5
	wall.rotation.y = atan2(-outward_normal.z, outward_normal.x)
	wall.position = outward_normal * (face - half)
	return wall


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
			if not state.intersect_shape(query, 1).is_empty():
				return true
	return false
