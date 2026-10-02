## T1 有限可行性矩陣；失敗須保留，不能以此取代人工手感驗收。
extends SceneTree

const Tank := preload("res://src/actors/rigid_tank/contact_tank.gd")
const Road := preload("res://src/world/roads/items/base/Road1/Road1_B__Road1_A.tscn")
var world: Node3D
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("CONTACT_ENGINE ticks=", Engine.physics_ticks_per_second,
		" backend=", ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
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
	print("RIGID_CONTACT failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for unused in count:
		await physics_frame

func _clear() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _frames(2)

func _reset() -> void:
	await _clear()
	world = Node3D.new()
	root.add_child(world)

func _box(size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 128
	body.position = center
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)

func _floor() -> void:
	_box(Vector3(100, 0.2, 80), Vector3(0, -0.1, 0))

func _spawn(position: Vector3, yaw := 0.0) -> RigidBody3D:
	var tank := Tank.new() as RigidBody3D
	tank.position = position
	tank.rotation.y = yaw
	world.add_child(tank)
	await _frames(2)
	return tank

func _expect(label: String, passed: bool, detail: String) -> void:
	print("RIGID_CONTACT ", label, " ", "PASS" if passed else "FAIL", " ", detail)
	if not passed:
		failures.append(label + ": " + detail)

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
		minimum = minf(minimum, tank.position.y)
		maximum = maxf(maximum, tank.position.y)
		minimum_bottom = minf(minimum_bottom, tank.hull_world_bottom())
	var data: Dictionary = tank.telemetry()
	_expect("flat-full-geometry", data.ready and tank.full_shape_count == 30 and tank.source_shape_count == 30,
		"shapes=%s/%s ready=%s" % [tank.full_shape_count, tank.source_shape_count, data.ready])
	_expect("flat-settle", maximum - minimum < 0.03 and minimum_bottom >= -0.02
		and minimum_bottom < 0.20 and data.left_contacts > 0 and data.right_contacts > 0,
		"y_span=%.5f bottom=%.5f contacts=%s/%s N=%.2f" % [maximum-minimum,
		minimum_bottom, data.left_contacts, data.right_contacts, data.total_support_force])

func _air() -> void:
	await _reset()
	var tank := await _spawn(Vector3(0, 8, 0))
	tank.set_movement_input(1.0)
	tank.set_turn_input(1.0)
	var force_free := true
	for unused in 30:
		await physics_frame
		var data: Dictionary = tank.telemetry()
		force_free = force_free and data.left_contacts == 0 and data.right_contacts == 0 \
			and data.applied_force == Vector3.ZERO and data.drive_force == Vector3.ZERO \
			and data.spring_points.size() == 10
	_expect("air-no-ground-force", force_free and tank.position.y < 7.9,
		"force_free=%s position=%s" % [force_free, tank.position])

func _one_side() -> void:
	await _reset()
	# 只在左履帶下放寬台，右側無地面；不是左右都踩地的假單側案例。
	_box(Vector3(30, 0.3, 2.0), Vector3(0, -0.15, 1.9))
	var tank := await _spawn(Vector3(0, 0.10, 0))
	tank.set_movement_input(0.4)
	var saw_single_side := false
	var unsupported_force_free := true
	var peak_roll := 0.0
	var low_y := tank.position.y
	for unused in 100:
		await physics_frame
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
	for unused in frame_limit:
		tank.set_movement_input(input_value)
		await physics_frame
		min_bottom = minf(min_bottom, tank.hull_world_bottom())
		if reached.call():
			passed = true
			break
	tank.set_movement_input(0.0)
	return {"reached": passed, "min_bottom": min_bottom}

func _step(height: float, input_value: float) -> void:
	await _reset()
	_floor()
	_box(Vector3(30, height, 40), Vector3(-15, height * 0.5, 0))
	var tank := await _spawn(Vector3(8, 1, 0), 0.0 if input_value > 0 else PI)
	await _frames(240)
	var outcome := await _drive(tank, input_value, func(): return tank.position.x < -5.0, 720)
	_expect("step-%.2f-input-%s" % [height, input_value], outcome.reached and outcome.min_bottom > -0.03,
		"position=%s reached=%s min_bottom=%.4f" % [tank.position, outcome.reached, outcome.min_bottom])

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
	var reverse := {"reached": false, "min_bottom": 0.0}
	if forward.reached:
		reverse = await _drive(tank, -1.0, func(): return tank.position.x * side > 11.0, 720)
	_expect("road-side-%s" % side, forward.reached and reverse.reached
		and forward.min_bottom > -0.03 and reverse.min_bottom > -0.03,
		"reached=%s final=%s forward=%s reverse=%s min_bottom=%.4f" % [reached,
			tank.position, forward.reached, reverse.reached, minf(forward.min_bottom, reverse.min_bottom)])
