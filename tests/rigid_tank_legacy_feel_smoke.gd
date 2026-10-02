## Frozen 60 Hz main-world Tank2 live reference; compare physical motion, not targets.
extends "res://tests/rigid_tank_contact_smoke.gd"

const Intent := preload("res://src/actors/rigid_tank/tank_drive_intent.gd")

func _spawn(position: Vector3, yaw := 0.0) -> RigidBody3D:
	var tank := await super._spawn(position, yaw)
	tank.driving_feel_enabled = true
	return tank

func _near(label: String, actual: float, expected: float) -> void:
	_expect(label, is_finite(actual) and absf(actual - expected) <= absf(expected) * 0.2,
		"actual=%.5f legacy=%.5f delta=%.1f%%" % [actual, expected, (actual - expected) / expected * 100.0])

func _flat_tank() -> RigidBody3D:
	await _reset()
	_floor()
	var tank := await _spawn(Vector3(20, 1, 0))
	await _frames(240)
	return tank

func _run() -> void:
	await _commands()
	await _linear(false)
	await _linear(true)
	await _turn(false)
	await _turn(true)
	await _air()
	await _clear()
	print("LEGACY_FEEL failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _commands() -> void:
	var donor := Tank.TANK2_SCENE.instantiate()
	var intent := Intent.new()
	intent.configure(donor)
	var exact := true
	var speed := 0.0
	var yaw := 0.0
	for command in [Vector2(1, 0), Vector2(1, 1), Vector2(-1, -1), Vector2.ZERO]:
		for frame in 240:
			var next: Dictionary = donor.predictive_driving_step(speed, yaw, command.x, command.y, 1.0 / 60.0)
			speed = next.forward_speed
			yaw = next.angular_speed
			intent.step(command.x, command.y, speed, 1.0 / 60.0)
			exact = exact and absf(intent.longitudinal - speed) < 0.00001 and absf(intent.steering - yaw) < 0.00001
	_expect("legacy-intent-curves", exact, str(intent.snapshot()))
	var before := intent.snapshot()
	intent.step(1, 1, 0, 0)
	_expect("zero-dt", intent.snapshot() == before, "unchanged")
	donor.free()

func _linear(reverse: bool) -> void:
	var tank := await _flat_tank()
	tank.set_movement_input(1)
	var t90 := -1.0
	var peak_force := 0.0
	for frame in 240:
		await physics_frame
		if t90 < 0 and tank.telemetry().speed >= 5.725135 * 0.9: t90 = (frame + 1) / 60.0
		peak_force = maxf(peak_force, maxf(tank.telemetry().longitudinal_used.left, tank.telemetry().longitudinal_used.right))
	_near("forward-speed", tank.telemetry().speed, 5.725135)
	_near("forward-t90", t90, 1.55)
	var start := tank.position
	tank.set_movement_input(-1 if reverse else 0)
	var stop := -1.0
	var distance := -1.0
	for frame in (360 if reverse else 240):
		await physics_frame
		var speed: float = tank.telemetry().speed
		if stop < 0 and (speed <= 0.0 if reverse else absf(speed) <= 0.05):
			stop = (frame + 1) / 60.0
			distance = tank.position.distance_to(start)
	_near("reverse-zero" if reverse else "release-stop", stop, 1.43333)
	_near("braking-distance", distance, 4.04958)
	if reverse: _near("reverse-speed", tank.telemetry().speed, -2.862625)
	else: _expect("release-rest", absf(tank.telemetry().speed) <= 0.05, str(tank.telemetry().speed))
	_expect("side-cap", peak_force <= 120001.0, str(peak_force))

func _turn(moving: bool) -> void:
	var tank := await _flat_tank()
	tank.set_turn_input(1)
	if moving: tank.set_movement_input(1)
	var t90 := -1.0
	var yaw_total := 0.0
	for frame in (240 if moving else 60):
		await physics_frame
		var yaw_speed := -tank.angular_velocity.y
		yaw_total += yaw_speed / 60.0
		if t90 < 0 and yaw_speed >= 0.36: t90 = (frame + 1) / 60.0
	_near("moving-yaw" if moving else "pivot-yaw", -tank.angular_velocity.y, 0.4)
	if moving:
		_near("moving-turn-speed", tank.telemetry().speed, 2.862592)
		_near("moving-turn-angle", yaw_total, 1.543334)
		return
	_near("pivot-t90", t90, 0.28333)
	_near("pivot-angle", yaw_total, 0.343333)
	tank.set_turn_input(0)
	var stop := -1.0
	for frame in 60:
		await physics_frame
		yaw_total += -tank.angular_velocity.y / 60.0
		if stop < 0 and absf(tank.angular_velocity.y) <= 0.02: stop = (frame + 1) / 60.0
	_near("pivot-stop", stop, 0.25)
	_near("pivot-total-angle", yaw_total, 0.39)
