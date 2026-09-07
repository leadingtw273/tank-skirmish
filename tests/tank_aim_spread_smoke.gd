extends SceneTree

const TankController := preload("res://src/actors/tank/tank_controller.gd")
const VARIANT_SCENES := [
	"res://src/actors/tank/variants/tank1/tank1.tscn",
	"res://src/actors/tank/variants/tank2/tank2.tscn",
	"res://src/actors/tank/variants/tank3/tank3.tscn",
	"res://src/actors/tank/variants/tank4/tank4.tscn",
]


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var tank := TankController.new()
	var valid := _validate_spread_targets(tank) and _validate_spread_recovery(tank) \
			and _validate_step_invariance(tank) and _validate_seeded_cone_sampling(tank) \
			and await _validate_variant_overrides() and await _validate_turret_turn_measurement()
	tank.free()
	if not valid:
		quit(1)
		return
	print("Tank aim spread smoke validation passed.")
	quit(0)


func _validate_spread_targets(tank: CharacterBody3D) -> bool:
	tank.movement_speed = 10.0
	tank.reverse_movement_speed = 5.0
	tank.turn_speed = 2.0
	if not is_equal_approx(tank.calculate_target_spread_degrees(0.0, 0.0), 0.2):
		return _fail("Stationary tanks must target their base spread.")
	if not is_equal_approx(tank.calculate_target_spread_degrees(5.0, 0.0), 0.95):
		return _fail("Half forward speed must add half the movement spread.")
	if not is_equal_approx(tank.calculate_target_spread_degrees(-5.0, 0.0), 1.7):
		return _fail("Full reverse speed must use the reverse top speed.")
	if not is_equal_approx(tank.calculate_target_spread_degrees(0.0, 2.0), 1.2):
		return _fail("Full turning speed must add the turn spread.")
	tank.turret_turn_speed = 4.0
	if not is_equal_approx(tank.calculate_target_spread_degrees(0.0, 0.0, 4.0), 1.2):
		return _fail("Full turret speed must add the turret-turn spread.")
	if not is_equal_approx(tank.calculate_target_spread_degrees(0.0, 0.0, -2.0), 0.7):
		return _fail("Half turret speed must add half the turret-turn spread symmetrically.")
	if not is_equal_approx(tank.calculate_target_spread_degrees(10.0, 2.0, 4.0), 2.5):
		return _fail("Hull motion and turret motion together must clamp to the cap.")
	if not is_equal_approx(tank.calculate_target_spread_degrees(10.0, 2.0), 2.5):
		return _fail("Moving and turning spread must clamp to the cap.")
	return true


func _validate_spread_recovery(tank: CharacterBody3D) -> bool:
	tank.current_spread_degrees = 0.2
	tank._fire_spread_degrees = 0.0
	tank.update_aim_spread(0.25, 10.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 1.2):
		return _fail("Spread growth must use grow degrees per second and delta.")
	tank.update_aim_spread(0.5, 0.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 0.6):
		return _fail("Stationary recovery must use the stationary recovery degrees per second.")
	tank.current_spread_degrees = 2.5
	tank._fire_spread_degrees = 0.0
	tank.update_aim_spread(0.5, 5.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 2.05):
		return _fail("Moving recovery must use the moving recovery degrees per second.")
	return true


func _validate_step_invariance(tank: CharacterBody3D) -> bool:
	tank.current_spread_degrees = 0.2
	tank._fire_spread_degrees = 0.0
	tank.update_aim_spread(0.35, 10.0, 0.0)
	var one_step: float = tank.get_current_spread_degrees()
	tank.current_spread_degrees = 0.2
	tank._fire_spread_degrees = 0.0
	for index: int in 7:
		tank.update_aim_spread(0.05, 10.0, 0.0)
	if not is_equal_approx(one_step, tank.get_current_spread_degrees()):
		return _fail("Equal simulated time with different physics steps must converge identically.")
	tank.update_aim_spread(10.0, 10.0, 2.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), tank.calculate_target_spread_degrees(10.0, 2.0)):
		return _fail("Spread updates must not overshoot their target.")
	return true


func _validate_seeded_cone_sampling(tank: CharacterBody3D) -> bool:
	var muzzle_direction := Vector3(0.4, 0.3, -0.8).normalized()
	tank.current_spread_degrees = 2.5
	tank._fire_spread_degrees = 0.0
	tank.set_aim_spread_seed(170)
	var first: Vector3 = tank.sample_shot_direction(muzzle_direction)
	var second: Vector3 = tank.sample_shot_direction(muzzle_direction)
	tank.set_aim_spread_seed(170)
	var replay_first: Vector3 = tank.sample_shot_direction(muzzle_direction)
	var replay_second: Vector3 = tank.sample_shot_direction(muzzle_direction)
	var half_angle := deg_to_rad(tank.get_current_spread_degrees())
	if not first.is_normalized() or not second.is_normalized() \
			or first.dot(muzzle_direction) < cos(half_angle) - 0.00001 \
			or second.dot(muzzle_direction) < cos(half_angle) - 0.00001:
		return _fail("Seeded spread directions must remain inside the muzzle cone.")
	if first.is_equal_approx(second) or not first.is_equal_approx(replay_first) \
			or not second.is_equal_approx(replay_second):
		return _fail("Seeded sampling must be repeatable and draw a new direction per shot.")
	tank.current_spread_degrees = 0.0
	tank._fire_spread_degrees = 0.0
	if not tank.sample_shot_direction(muzzle_direction).is_equal_approx(muzzle_direction):
		return _fail("Zero spread must preserve the exact muzzle direction.")
	return true


func _validate_variant_overrides() -> bool:
	var tanks: Array[CharacterBody3D] = []
	for scene_path: String in VARIANT_SCENES:
		var source := FileAccess.get_file_as_string(scene_path)
		for property_name: String in [
			"aim_spread_base_degrees",
			"aim_spread_movement_add_degrees",
			"aim_spread_turn_add_degrees",
			"aim_spread_turret_turn_add_degrees",
			"aim_spread_fire_add_degrees",
			"aim_spread_fire_recovery_degrees_per_second",
			"aim_spread_cap_degrees",
			"aim_spread_grow_degrees_per_second",
			"aim_spread_stationary_recovery_degrees_per_second",
			"aim_spread_moving_recovery_degrees_per_second",
		]:
			if not source.contains("\n%s =" % property_name):
				return _fail("Each tank variant must save an independent %s override." % property_name)
		var packed_scene := load(scene_path) as PackedScene
		var tank := packed_scene.instantiate() as CharacterBody3D if packed_scene != null else null
		if tank == null or not is_equal_approx(tank.aim_spread_base_degrees, 1.0) \
				or not is_equal_approx(tank.aim_spread_turret_turn_add_degrees, 1.0) \
				or not is_equal_approx(tank.aim_spread_fire_add_degrees, 0.3) \
				or not is_equal_approx(tank.aim_spread_fire_recovery_degrees_per_second, 0.2) \
				or not is_equal_approx(tank.aim_spread_cap_degrees, 2.5):
			return _fail("Each tank variant must start with the approved spread values.")
		root.add_child(tank)
		await process_frame
		await process_frame
		var shots: Array = []
		tank.shot_event_fired.connect(func(shot_event: Variant) -> void: shots.append(shot_event))
		tank.set_aim_spread_seed(170)
		if not await _validate_fire_bloom(tank, shots):
			tank.queue_free()
			await process_frame
			return false
		tanks.append(tank)
	if tanks.size() != 4:
		return _fail("All four tank variants must be available for independent tuning.")
	tanks[0].aim_spread_base_degrees = 0.0
	if is_zero_approx(tanks[1].aim_spread_base_degrees):
		return _fail("Changing one variant instance must not alter another variant's spread tuning.")
	tanks[0].aim_spread_fire_add_degrees = 0.0
	if is_zero_approx(tanks[1].aim_spread_fire_add_degrees):
		return _fail("Changing one variant instance must not alter another variant's fire-spread tuning.")
	tanks[0].aim_spread_fire_recovery_degrees_per_second = 0.0
	if is_zero_approx(tanks[1].aim_spread_fire_recovery_degrees_per_second):
		return _fail("Changing one variant instance must not alter another variant's fire-recovery tuning.")
	for tank: CharacterBody3D in tanks:
		tank.queue_free()
	await process_frame
	return true


func _validate_fire_bloom(tank: CharacterBody3D, shots: Array) -> bool:
	var original_base: float = tank.aim_spread_base_degrees
	var original_stationary_recovery: float = tank.aim_spread_stationary_recovery_degrees_per_second
	var original_moving_recovery: float = tank.aim_spread_moving_recovery_degrees_per_second
	var original_fire_interval: float = tank.fire_interval_seconds
	var original_fire_add: float = tank.aim_spread_fire_add_degrees
	var original_fire_recovery: float = tank.aim_spread_fire_recovery_degrees_per_second
	## 固定此數學案例的增量；四車試玩值另由上方配置測試驗證。
	tank.aim_spread_fire_add_degrees = 0.2
	var original_current_spread: float = tank.current_spread_degrees
	var original_fire_spread: float = tank._fire_spread_degrees
	tank.aim_spread_base_degrees = 0.0
	tank.aim_spread_stationary_recovery_degrees_per_second = 0.0
	tank.aim_spread_moving_recovery_degrees_per_second = 0.0
	tank.aim_spread_fire_recovery_degrees_per_second = 0.0
	tank.fire_interval_seconds = 0.01
	tank.current_spread_degrees = 0.0
	tank._fire_spread_degrees = 0.0
	var muzzle_direction: Vector3 = tank.muzzle_global_direction()
	tank.request_fire()
	var first_direction: Vector3 = shots[0].direction if shots.size() == 1 else Vector3.ZERO
	if shots.size() != 1 or not first_direction.is_equal_approx(muzzle_direction) \
			or not is_equal_approx(tank.get_current_spread_degrees(), 0.2):
		return _fail("A successful zero-spread shot must use its pre-fire cone, then add 0.2 degrees.")
	tank.request_fire()
	if shots.size() != 1 or not is_equal_approx(tank.get_current_spread_degrees(), 0.2):
		return _fail("Reload-rejected fire requests must not emit shots or add spread.")
	await create_timer(0.1, false, true).timeout
	var second_pre_fire_spread: float = tank.get_current_spread_degrees()
	tank.request_fire()
	var second_direction: Vector3 = shots[1].direction if shots.size() == 2 else Vector3.ZERO
	if shots.size() != 2 or second_direction.dot(muzzle_direction) < cos(deg_to_rad(second_pre_fire_spread)) - 0.00001 \
			or not is_equal_approx(tank.get_current_spread_degrees(), 0.4):
		return _fail("The next successful shot must use its pre-fire cone, then accumulate fire spread.")
	await create_timer(0.1, false, true).timeout
	tank.current_spread_degrees = 2.5
	tank._fire_spread_degrees = 0.0
	tank.request_fire()
	if shots.size() != 3 or tank.get_current_spread_degrees() > 2.5 or not is_zero_approx(tank._fire_spread_degrees):
		return _fail("Successful fire spread must not exceed its cap or retain hidden overflow.")
	await create_timer(0.1, false, true).timeout
	tank.current_spread_degrees = 0.7
	tank._fire_spread_degrees = 0.0
	tank.aim_spread_fire_add_degrees = 0.0
	tank.request_fire()
	if shots.size() != 4 or not is_equal_approx(tank.get_current_spread_degrees(), 0.7):
		return _fail("A zero fire-spread increment must preserve existing behavior.")
	tank.aim_spread_stationary_recovery_degrees_per_second = 1.2
	tank.update_aim_spread(0.5, 0.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 0.1):
		return _fail("Motion-only spread must retain the existing stationary recovery path.")

	tank.aim_spread_base_degrees = 1.0
	tank.aim_spread_fire_add_degrees = 0.2
	tank.aim_spread_fire_recovery_degrees_per_second = 0.4
	tank.aim_spread_stationary_recovery_degrees_per_second = 0.0
	tank.aim_spread_moving_recovery_degrees_per_second = 0.0
	tank.current_spread_degrees = 1.0
	tank._fire_spread_degrees = 0.0
	await create_timer(0.1, false, true).timeout
	tank.request_fire()
	if shots.size() != 5 or not is_equal_approx(tank.get_current_spread_degrees(), 1.2):
		return _fail("A stationary base-1 tank must add 0.2 degrees after a successful shot.")
	tank.update_aim_spread(0.25, 0.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 1.1):
		return _fail("Fire spread must recover independently at 0.4 degrees per second.")
	tank.update_aim_spread(0.25, 0.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 1.0):
		return _fail("A 0.2-degree fire increment must recover in about 0.5 seconds at the configured test rate.")
	tank.aim_spread_fire_recovery_degrees_per_second = 0.2
	await create_timer(0.1, false, true).timeout
	tank.request_fire()
	tank.update_aim_spread(1.0, 0.0, 0.0)
	if shots.size() != 6 or not is_equal_approx(tank.get_current_spread_degrees(), 1.0):
		return _fail("A 0.2-degree fire increment must recover in one second at 0.2 degrees per second.")
	tank.aim_spread_fire_recovery_degrees_per_second = 0.0
	await create_timer(0.1, false, true).timeout
	tank.request_fire()
	tank.update_aim_spread(1.0, 0.0, 0.0)
	if shots.size() != 7 or not is_equal_approx(tank.get_current_spread_degrees(), 1.2):
		return _fail("Zero fire recovery must retain the accepted fire spread until retuned.")
	tank.aim_spread_fire_recovery_degrees_per_second = 0.2
	tank.update_aim_spread(1.0, 0.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 1.0):
		return _fail("Retuning fire recovery must resume recovery of retained fire spread.")

	tank.aim_spread_stationary_recovery_degrees_per_second = 1.2
	tank.aim_spread_fire_recovery_degrees_per_second = 0.4
	tank.aim_spread_base_degrees = 0.0
	tank.current_spread_degrees = 2.5
	tank._fire_spread_degrees = 0.2
	tank.update_aim_spread(0.5, 0.0, 0.0, tank.turret_turn_speed)
	if not is_equal_approx(tank.get_current_spread_degrees(), 1.7) or not is_zero_approx(tank._fire_spread_degrees):
		return _fail("Turret-motion recovery and fire recovery must both apply without sharing a rate.")
	tank.aim_spread_base_degrees = original_base
	tank.aim_spread_stationary_recovery_degrees_per_second = original_stationary_recovery
	tank.aim_spread_moving_recovery_degrees_per_second = original_moving_recovery
	tank.fire_interval_seconds = original_fire_interval
	tank.aim_spread_fire_add_degrees = original_fire_add
	tank.aim_spread_fire_recovery_degrees_per_second = original_fire_recovery
	tank.current_spread_degrees = original_current_spread
	tank._fire_spread_degrees = original_fire_spread
	return true


func _validate_turret_turn_measurement() -> bool:
	for scene_path: String in [VARIANT_SCENES[0], VARIANT_SCENES[1]]:
		var packed_scene := load(scene_path) as PackedScene
		var tank := packed_scene.instantiate() as CharacterBody3D if packed_scene != null else null
		if tank == null:
			return _fail("Turret-speed validation requires a loadable tank variant.")
		root.add_child(tank)
		await process_frame
		await process_frame
		var delta := 0.1
		tank.aim_turret_at(Vector3(0.0, 0.0, -100.0), delta)
		if not is_equal_approx(absf(tank.get_actual_turret_angular_speed()), tank.turret_turn_speed):
			tank.queue_free()
			await process_frame
			return _fail("Full and limited turret branches must measure their local yaw speed.")
		tank.turret_pivot.rotation.y = 0.0
		tank.aim_turret_at(Vector3(0.0, 0.0, 100.0), delta)
		if not is_equal_approx(absf(tank.get_actual_turret_angular_speed()), tank.turret_turn_speed):
			tank.queue_free()
			await process_frame
			return _fail("Turret speed must be symmetric when aiming left or right.")
		tank.aim_turret_at(tank.turret_pivot.global_position, delta)
		if not is_zero_approx(tank.get_actual_turret_angular_speed()):
			tank.queue_free()
			await process_frame
			return _fail("Turret dead-zone aiming must clear measured turret speed.")
		tank.turret_pivot.rotation.y = 0.0
		tank.global_rotation.y += 0.5
		var aligned_target: Vector3 = tank.turret_pivot.global_position - tank.turret_pivot.global_transform.basis.x * 100.0
		tank.aim_turret_at(aligned_target, delta)
		if not is_zero_approx(tank.get_actual_turret_angular_speed()):
			tank.queue_free()
			await process_frame
			return _fail("Hull world rotation without local pivot rotation must not create turret speed.")
		tank.aim_turret_at(aligned_target, 0.0)
		if not is_zero_approx(tank.get_actual_turret_angular_speed()):
			tank.queue_free()
			await process_frame
			return _fail("Zero delta must not produce turret angular speed.")
		tank.queue_free()
		await process_frame
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
