## 四款完整玩家剛體入口共用原接觸矩陣；門檻、障礙與每段 deadline 不變。
extends "res://tests/rigid_tank_contact_smoke.gd"

const PLAYER_SCENES := {
	"Tank1": preload("res://src/actors/rigid_tank/variants/tank1.tscn"),
	"Tank2": preload("res://src/actors/rigid_tank/player_rigid_tank.tscn"),
	"Tank3": preload("res://src/actors/rigid_tank/variants/tank3.tscn"),
	"Tank4": preload("res://src/actors/rigid_tank/variants/tank4.tscn"),
}
const EXPECTED := {
	"Tank1": {"mass": 36000.0, "drive": 115200.0, "brake": 90000.0},
	"Tank2": {"mass": 60000.0, "drive": 120000.0, "brake": 120000.0},
	"Tank3": {"mass": 84000.0, "drive": 134400.0, "brake": 165000.0},
	"Tank4": {"mass": 52000.0, "drive": 158400.0, "brake": 110000.0},
}

var current_name := ""
var current_player_scene: PackedScene
var budget_failure_keys: Dictionary = {}


func _run() -> void:
	print("RIGID_VARIANTS_CONTACT ticks=", Engine.physics_ticks_per_second,
		" backend=", ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
	for tank_name: String in PLAYER_SCENES:
		current_name = tank_name
		current_player_scene = PLAYER_SCENES[tank_name]
		budget_failure_keys.clear()
		await _flat()
		await _air()
		await _one_side()
		for height in [0.21, 0.50]:
			for input_value in [1.0, -1.0]:
				await _step(height, input_value)
		for side in [1.0, -1.0]:
			await _road(side)
	await _clear()
	for failure in failures:
		push_error(failure)
	print("RIGID_VARIANTS_CONTACT failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _expect(label: String, passed: bool, detail: String) -> void:
	super._expect("%s-%s" % [current_name, label], passed, detail)


func _spawn(position: Vector3, yaw := 0.0) -> RigidBody3D:
	var tank := current_player_scene.instantiate() as RigidBody3D
	tank.position = position
	tank.rotation.y = yaw
	world.add_child(tank)
	await _frames(2)
	return tank


func _flat() -> void:
	await _reset()
	_floor()
	var tank := await _spawn(Vector3(0, 1, 0))
	await _frames(240)
	var minimum := INF
	var maximum := -INF
	var minimum_bottom := INF
	for unused in 120:
		await physics_frame
		_watch_budget(tank, "flat")
		minimum = minf(minimum, tank.position.y)
		maximum = maxf(maximum, tank.position.y)
		minimum_bottom = minf(minimum_bottom, tank.hull_world_bottom())
	var data: Dictionary = tank.telemetry()
	var donor := tank.combat_tank as CharacterBody3D
	var snapshot: Dictionary = donor.predictive_driving_snapshot()
	var shapes: Array = snapshot.get("shapes", [])
	var transforms: Array = donor.part_shape_world_transforms()
	var expected: Dictionary = EXPECTED[current_name]
	var shape_mapping: bool = shapes.size() == transforms.size() and tank.collision_shapes.size() == shapes.size()
	for index in shapes.size():
		var collision := tank.collision_shapes[index] as CollisionShape3D
		shape_mapping = shape_mapping and collision != null and collision.shape == shapes[index] \
			and collision.global_transform.is_equal_approx(transforms[index])
	var station_count := 10.0
	var expected_k := tank.mass * 9.81 / (station_count * 0.15)
	var expected_c := 0.7 * 2.0 * sqrt(expected_k * tank.mass / station_count)
	_expect("flat-source-and-geometry", data.ready and tank.full_shape_count == shapes.size()
		and tank.source_shape_count == shapes.size() and tank.mass == float(expected.mass)
		and tank.side_drive_force_limit == float(expected.drive)
		and tank.side_brake_force_limit == float(expected.brake) and shape_mapping
		and is_equal_approx(tank._spring_k, expected_k) and is_equal_approx(tank._damper_c, expected_c),
		"donor=%s shapes=%s/%s mass=%.0f drive=%.0f brake=%.0f map=%s k=%.2f c=%.2f" % [
			donor.scene_file_path, tank.full_shape_count, shapes.size(), tank.mass,
			tank.side_drive_force_limit, tank.side_brake_force_limit, shape_mapping,
			tank._spring_k, tank._damper_c])
	_expect("flat-settle", maximum - minimum < 0.03 and minimum_bottom >= -0.02
		and minimum_bottom < 0.20 and data.left_contacts > 0 and data.right_contacts > 0,
		"y_span=%.5f bottom=%.5f contacts=%s/%s N=%.2f" % [maximum - minimum,
			minimum_bottom, data.left_contacts, data.right_contacts, data.total_support_force])


func _air() -> void:
	await _reset()
	var tank := await _spawn(Vector3(0, 8, 0))
	tank.set_movement_input(1.0)
	tank.set_turn_input(1.0)
	var force_free := true
	for unused in 30:
		await physics_frame
		_watch_budget(tank, "air")
		var data: Dictionary = tank.telemetry()
		force_free = force_free and data.left_contacts == 0 and data.right_contacts == 0 \
			and data.applied_force == Vector3.ZERO and data.drive_force == Vector3.ZERO \
			and data.spring_points.size() == 10
	_expect("air-no-ground-force", force_free and tank.position.y < 7.9,
		"force_free=%s position=%s" % [force_free, tank.position])


func _one_side() -> void:
	await _reset()
	_box(Vector3(30, 0.3, 2.0), Vector3(0, -0.15, 1.9))
	var tank := await _spawn(Vector3(0, 0.10, 0))
	tank.set_movement_input(0.4)
	var saw_single_side := false
	var unsupported_force_free := true
	var peak_roll := 0.0
	var low_y := tank.position.y
	for unused in 100:
		await physics_frame
		_watch_budget(tank, "one-side")
		var data: Dictionary = tank.telemetry()
		unsupported_force_free = unsupported_force_free and data.spring_points.size() == 10
		if data.left_contacts > 0 and data.right_contacts == 0:
			saw_single_side = true
		for station in data.spring_points:
			if not station.contact:
				unsupported_force_free = unsupported_force_free and station.normal_load == 0.0 \
					and station.traction == Vector3.ZERO
		peak_roll = maxf(peak_roll, absf(tank.basis.y.z))
		low_y = minf(low_y, tank.position.y)
	_expect("single-side-contact-evidence", saw_single_side and unsupported_force_free
		and (peak_roll > 0.02 or low_y < 0.05),
		"single=%s unsupported_zero=%s peak_roll=%.4f lowest_y=%.4f" % [
			saw_single_side, unsupported_force_free, peak_roll, low_y])


func _drive(tank: RigidBody3D, input_value: float, reached: Callable, frame_limit: int) -> Dictionary:
	var min_bottom := INF
	var passed := false
	var frames := 0
	for unused in frame_limit:
		tank.set_movement_input(input_value)
		await physics_frame
		frames += 1
		_watch_budget(tank, "drive-%+.1f" % input_value)
		min_bottom = minf(min_bottom, tank.hull_world_bottom())
		if reached.call():
			passed = true
			break
	tank.set_movement_input(0.0)
	print("RIGID_VARIANTS_CONTACT ", current_name, " drive input=", input_value,
		" frames=", frames, "/", frame_limit, " reached=", passed, " min_bottom=", min_bottom)
	return {"reached": passed, "min_bottom": min_bottom, "frames": frames}


func _step(height: float, input_value: float) -> void:
	await _reset()
	_floor()
	_box(Vector3(30, height, 40), Vector3(-15, height * 0.5, 0))
	var tank := await _spawn(Vector3(8, 1, 0), 0.0 if input_value > 0 else PI)
	await _frames(240)
	var outcome := await _drive(tank, input_value, func(): return tank.position.x < -5.0, 720)
	_expect("step-%.2f-input-%s" % [height, input_value], outcome.reached and outcome.min_bottom > -0.03,
		"position=%s reached=%s frames=%s/720 min_bottom=%.4f" % [tank.position,
			outcome.reached, outcome.frames, outcome.min_bottom])


func _road(side: float) -> void:
	await _reset()
	_floor()
	var road := Road.instantiate() as Node3D
	road.position.y = 0.03
	world.add_child(road)
	var tank := await _spawn(Vector3(side * 12, 1, 0), 0.0 if side > 0 else PI)
	await _frames(240)
	var forward := await _drive(tank, 1.0, func(): return tank.position.x * side < 0.5, 720)
	var reached := tank.position
	var reverse := {"reached": false, "min_bottom": 0.0, "frames": 0}
	if forward.reached:
		reverse = await _drive(tank, -1.0, func(): return tank.position.x * side > 11.0, 720)
	_expect("road-side-%s" % side, forward.reached and reverse.reached
		and forward.min_bottom > -0.03 and reverse.min_bottom > -0.03,
		"reached=%s final=%s forward=%s/%s reverse=%s/%s min_bottom=%.4f" % [reached,
			tank.position, forward.reached, forward.frames, reverse.reached, reverse.frames,
			minf(forward.min_bottom, reverse.min_bottom)])


func _watch_budget(tank: RigidBody3D, segment: String) -> void:
	var data: Dictionary = tank.telemetry()
	var budgets: Dictionary = data.side_budget_used
	var drive: Dictionary = data.drive_used
	var brake: Dictionary = data.brake_used
	for side in ["left", "right"]:
		var used := float(budgets[side])
		var drive_used := float(drive[side])
		var brake_used := float(brake[side])
		var drive_limit := float(data.side_drive_limit)
		var brake_limit := float(data.side_brake_limit)
		var passed := used <= 1.0 + 0.000001 and drive_used <= drive_limit + 0.000001 \
			and brake_used <= brake_limit + 0.000001
		var key := "%s-%s-%s" % [segment, side, "budget"]
		if not passed and not budget_failure_keys.has(key):
			budget_failure_keys[key] = true
			_expect("%s-%s-budget" % [segment, side], false,
				"used=%.8f drive=%.3f/%.3f brake=%.3f/%.3f" % [used, drive_used,
					drive_limit, brake_used, brake_limit])
