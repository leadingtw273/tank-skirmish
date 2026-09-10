## LEA-173 R1/R3 regression smoke. 只有 R3 的具名合成反例注入 _contact_records；不冒充真碰撞。
extends "res://tests/tank_contact_response_smoke.gd"

## 覆寫 parent 的 deferred _run；不另排一次 deferred，避免父子初始化語意混淆。
func _run() -> void:
	var failures: Array[String] = []
	for turn in [-1.0, 1.0]:
		var r1 := await _r1_turn_case(turn)
		if not bool(r1.rotated) or not bool(r1.velocity_new_axis) or not bool(r1.actual_new_axis) or not bool(r1.full_empty_speed):
			failures.append("R1 Tank2 turn=%+.0f %s" % [turn, r1])
	var r3_pair_target := await _r3_reinjected_pair_case()
	if not _r3_within_cap(r3_pair_target): failures.append("R3 paired-5deg target-over-speed %s" % r3_pair_target)
	var r3_pair := await _r3_records_case([Vector3.RIGHT, Vector3(cos(deg_to_rad(5.0)), 0.0, sin(deg_to_rad(5.0)))], Vector3(999.0, 0.0, 999.0))
	if not _r3_within_cap(r3_pair): failures.append("R3 paired-5deg prior-over-speed %s" % r3_pair)
	var r3_single := await _r3_records_case([Vector3.RIGHT], Vector3.ZERO)
	if not _r3_within_cap(r3_single): failures.append("R3 single-face %s" % r3_single)
	var empty_exit := await _r3_records_case([Vector3.ZERO], Vector3(999.0, 0.0, 999.0))
	if not bool(empty_exit.exited) or not (empty_exit.slide as Vector3).is_zero_approx(): failures.append("R3 empty-normal exit %s" % empty_exit)
	if failures.is_empty(): print("CONTACT_REVIEW_REGRESSION PASS: R1/R3 production controller paths."); quit(0); return
	for failure in failures: push_error(failure)
	quit(1)

func _r1_turn_case(turn: float) -> Dictionary:
	var tank := TANK_SCENES[1].instantiate() as CharacterBody3D
	root.add_child(tank)
	await physics_frame
	tank.set_manual_turn_active(true)
	tank.set_movement_input(1.0)
	tank.set_turn_input(turn)
	var yaw_before := tank.global_rotation.y
	for unused in 300: await physics_frame
	var new_axis := (tank.transform.basis * Vector3.LEFT).normalized()
	var horizontal_velocity := Vector3(tank.velocity.x, 0.0, tank.velocity.z)
	var real_velocity := tank.get_real_velocity()
	real_velocity.y = 0.0
	var axis_error_rad := horizontal_velocity.normalized().angle_to(new_axis) if horizontal_velocity.length() > 0.01 else INF
	var expected_actual_linear := real_velocity.dot(new_axis)
	var actual_error := absf(float(tank.get_actual_linear_speed()) - expected_actual_linear)
	var speed_cap := float(tank.movement_speed) * 0.35
	var result := {
		"rotated": absf(angle_difference(yaw_before, tank.global_rotation.y)) > 0.01,
		"velocity_new_axis": axis_error_rad < 0.0001,
		"actual_new_axis": actual_error < 0.00001,
		"full_empty_speed": real_velocity.length() > speed_cap + 0.05,
		"axis_error_rad": axis_error_rad,
		"actual_error": actual_error,
		"velocity": horizontal_velocity,
		"new_axis": new_axis,
		"actual": tank.get_actual_linear_speed(),
		"expected_actual": expected_actual_linear,
		"real": real_velocity,
		"35cap": speed_cap,
	}
	tank.queue_free()
	await physics_frame
	return result

## R3 test-double 僅注入上一幀接觸 records；rotation guard 與 _physics_process/move_and_slide 均為正式實作。
func _r3_records_case(normals: Array[Vector3], prior_slide: Vector3) -> Dictionary:
	var tank := TANK_SCENES[1].instantiate() as CharacterBody3D
	root.add_child(tank)
	tank.global_rotation.y = deg_to_rad(45.0)
	await physics_frame
	tank.set_manual_turn_active(true)
	tank.set_movement_input(1.0)
	tank.set_turn_input(0.0)
	tank.set("_contact_slide_velocity", prior_slide)
	_inject_contact_records(tank, normals)
	await physics_frame
	var cap := float(tank.movement_speed) * 0.35
	var velocity := Vector3(tank.velocity.x, 0.0, tank.velocity.z)
	var real := tank.get_real_velocity()
	real.y = 0.0
	var stats: Dictionary = tank.get_contact_response_stats()
	var result := {
		"cap": cap,
		"velocity": velocity,
		"real": real,
		"slide": stats.get("slide_velocity", Vector3.ZERO),
		"normals": normals,
		"reason": stats.get("reason", ""),
		"exited": String(stats.get("reason", "")) == "no-active-contact",
	}
	tank.queue_free()
	await physics_frame
	return result

## 從零開始，有限 150 physics frames 每幀重新注入上一幀 records；覆蓋未限聚合 target 的累積路徑。
func _r3_reinjected_pair_case() -> Dictionary:
	var normals: Array[Vector3] = [Vector3.RIGHT, Vector3(cos(deg_to_rad(5.0)), 0.0, sin(deg_to_rad(5.0)))]
	var tank := TANK_SCENES[1].instantiate() as CharacterBody3D
	root.add_child(tank)
	tank.global_rotation.y = deg_to_rad(45.0)
	await physics_frame
	tank.set_manual_turn_active(true)
	tank.set_movement_input(1.0)
	tank.set_turn_input(0.0)
	var cap := float(tank.movement_speed) * 0.35
	var max_velocity := 0.0
	var max_real := 0.0
	var max_slide := 0.0
	var no_inward := true
	for unused in 150:
		_inject_contact_records(tank, normals)
		await physics_frame
		var velocity := Vector3(tank.velocity.x, 0.0, tank.velocity.z)
		var real := tank.get_real_velocity()
		real.y = 0.0
		var slide := tank.get_contact_response_stats().get("slide_velocity", Vector3.ZERO) as Vector3
		max_velocity = maxf(max_velocity, velocity.length())
		max_real = maxf(max_real, real.length())
		max_slide = maxf(max_slide, slide.length())
		for normal in normals:
			no_inward = no_inward and velocity.dot(normal) >= -0.0001 and real.dot(normal) >= -0.0001 and slide.dot(normal) >= -0.0001
	var result := {"cap": cap, "velocity": Vector3(max_velocity, 0.0, 0.0), "real": Vector3(max_real, 0.0, 0.0), "slide": Vector3(max_slide, 0.0, 0.0), "normals": [], "all_frames_ok": no_inward, "max_velocity": max_velocity, "max_real": max_real, "max_slide": max_slide}
	tank.queue_free()
	await physics_frame
	return result

func _inject_contact_records(tank: CharacterBody3D, normals: Array[Vector3]) -> void:
	var records: Array[Dictionary] = []
	for normal in normals:
		records.append({"position": tank.stable_world_center(), "normal": normal, "rid": RID()})
	tank.set("_contact_records", records)
	tank.set("_contact_frames_since_contact", 0)

func _r3_within_cap(result: Dictionary) -> bool:
	if not bool(result.get("all_frames_ok", true)): return false
	var cap := float(result.cap) + 0.0001
	var velocity := result.velocity as Vector3
	var real := result.real as Vector3
	var slide := result.slide as Vector3
	if velocity.length() > cap or real.length() > cap or slide.length() > cap: return false
	for normal in result.normals:
		if (normal as Vector3).length() > 0.0001 and (velocity.dot(normal as Vector3) < -0.0001 or real.dot(normal as Vector3) < -0.0001 or slide.dot(normal as Vector3) < -0.0001): return false
	return true
