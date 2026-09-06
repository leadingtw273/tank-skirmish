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
			and await _validate_variant_overrides()
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
	if not is_equal_approx(tank.calculate_target_spread_degrees(10.0, 2.0), 2.5):
		return _fail("Moving and turning spread must clamp to the cap.")
	return true


func _validate_spread_recovery(tank: CharacterBody3D) -> bool:
	tank.current_spread_degrees = 0.2
	tank.update_aim_spread(0.25, 10.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 1.2):
		return _fail("Spread growth must use grow degrees per second and delta.")
	tank.update_aim_spread(0.5, 0.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 0.6):
		return _fail("Stationary recovery must use the stationary recovery degrees per second.")
	tank.current_spread_degrees = 2.5
	tank.update_aim_spread(0.5, 5.0, 0.0)
	if not is_equal_approx(tank.get_current_spread_degrees(), 2.05):
		return _fail("Moving recovery must use the moving recovery degrees per second.")
	return true


func _validate_step_invariance(tank: CharacterBody3D) -> bool:
	tank.current_spread_degrees = 0.2
	tank.update_aim_spread(0.35, 10.0, 0.0)
	var one_step: float = tank.get_current_spread_degrees()
	tank.current_spread_degrees = 0.2
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
			"aim_spread_cap_degrees",
			"aim_spread_grow_degrees_per_second",
			"aim_spread_stationary_recovery_degrees_per_second",
			"aim_spread_moving_recovery_degrees_per_second",
		]:
			if not source.contains("\n%s =" % property_name):
				return _fail("Each tank variant must save an independent %s override." % property_name)
		var packed_scene := load(scene_path) as PackedScene
		var tank := packed_scene.instantiate() as CharacterBody3D if packed_scene != null else null
		if tank == null or not is_equal_approx(tank.aim_spread_base_degrees, 0.2) \
				or not is_equal_approx(tank.aim_spread_cap_degrees, 2.5):
			return _fail("Each tank variant must start with the approved spread values.")
		root.add_child(tank)
		await process_frame
		await process_frame
		var shots: Array = []
		tank.shot_event_fired.connect(func(shot_event: Variant) -> void: shots.append(shot_event))
		tank.set_aim_spread_seed(170)
		tank.request_fire()
		var muzzle_direction: Vector3 = tank.muzzle_global_direction()
		var cone_limit := cos(deg_to_rad(tank.get_current_spread_degrees()))
		var shot_direction: Vector3 = shots[0].direction if shots.size() == 1 else Vector3.ZERO
		if shots.size() != 1 or shot_direction.dot(muzzle_direction) < cone_limit - 0.00001:
			tank.queue_free()
			await process_frame
			return _fail("Each tank variant must emit one sampled ShotEvent inside its own muzzle cone.")
		tanks.append(tank)
	if tanks.size() != 4:
		return _fail("All four tank variants must be available for independent tuning.")
	tanks[0].aim_spread_base_degrees = 0.0
	if is_zero_approx(tanks[1].aim_spread_base_degrees):
		return _fail("Changing one variant instance must not alter another variant's spread tuning.")
	for tank: CharacterBody3D in tanks:
		tank.queue_free()
	await process_frame
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
