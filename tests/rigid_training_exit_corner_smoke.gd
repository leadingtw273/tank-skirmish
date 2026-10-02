## 2026-09-24 F4: Tank2 已出窄口的直角轉彎，靜止重建起點（非完整動態重播）。
## Trace 缺 pending force/Intent；以下是實测位置的靜止起步回歸，不是逐幀重播。
extends "res://tests/rigid_enemy_navmesh_gap_smoke.gd"

const TRACE_GOAL := Vector3(29.17406, 0.0, -20.03056)
const CASES := [
	{"name": "blocked-pivot", "position": Vector3(74.151855, 0.2, -13.986236), "yaw": -55.666284},
	{"name": "post-reverse", "position": Vector3(75.363510, 0.2, -12.318665), "yaw": -28.606724},
]

func _run() -> void:
	for fixture: Dictionary in CASES:
		await _case(fixture)
	for failure in _failures: push_error(failure)
	print("RIGID_TRAINING_EXIT_CORNER cases=%d failures=%d" % [CASES.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _case(fixture: Dictionary) -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	(scene.get_node("Main/World/Ground") as StaticBody3D).process_mode = Node.PROCESS_MODE_ALWAYS
	(scene.get_node("SightBlockers") as Node3D).process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(scene)
	if not (await _await_navigation(scene)).is_valid():
		scene.queue_free()
		await physics_frame
		return
	var tank := Catalog.instantiate(&"tank2") as RigidBody3D
	tank.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(tank)
	tank.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(fixture.yaw))), fixture.position)
	tank.combat_tank.gun_pitch_pivot.rotation.z = -deg_to_rad(-1.136224)
	tank.call("_sync_rigid_parts")
	for unused in 120: await physics_frame
	var driver := TankNavigation.new()
	driver.setup(tank)
	var command: Dictionary = {}
	var crossed := false
	var collision := false
	var frames := 0
	var braking_blocks := 0
	var verified_recovery := 0
	for tick in 3600:
		command = driver.drive(TRACE_GOAL, 4, STOP_DISTANCE, DT)
		if command.get("route") != &"navmesh":
			_fail("%s must retain navmesh routing" % fixture.name)
			break
		tank.set_movement_input(float(command.movement))
		tank.set_turn_input(float(command.turn))
		await physics_frame
		frames += 1
		var stats := driver.get_prediction_stats()
		braking_blocks += 1 if stats.get("reason") == &"braking_blocked" else 0
		verified_recovery += 1 if command.status == &"recovering" and bool(stats.get("near_verified", false)) else 0
		crossed = crossed or (tank.global_position.x > 74.0 and tank.global_position.z > -24.0)
		collision = collision or _overlaps_sight_blocker(tank)
		if collision or command.status in [&"arrived", &"partial_end", &"no_path", &"stuck"]: break
	var distance := _xz_distance(tank.stable_world_center(), TRACE_GOAL)
	print("EXIT_CORNER_GUARD case=%s braking_blocks=%d verified_recovery=%d" % [fixture.name, braking_blocks, verified_recovery])
	print("EXIT_CORNER case=%s status=%s frames=%d crossed=%s distance=%.3f building_overlap=%s position=%s" % [fixture.name, command.get("status"), frames, crossed, distance, collision, tank.global_position])
	if collision: _fail("%s must not overlap any SightBlockers collider" % fixture.name)
	if not crossed or command.get("status") != &"arrived" or distance > STOP_DISTANCE:
		_fail("%s must cross the actual lower portal and arrive within stop distance" % fixture.name)
	driver.dispose()
	scene.queue_free()
	await process_frame
	await physics_frame
