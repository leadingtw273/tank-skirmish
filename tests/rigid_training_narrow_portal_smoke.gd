## 使用者 F4 session 2026-09-23T10-20-21-246845：Tank2 下方窄口不得以「曾前進」冒稱通過。
## Trace 缺 pending force/Intent；以下是實测位置的靜止起步回歸，不是逐幀重播。
extends "res://tests/rigid_enemy_navmesh_gap_smoke.gd"

const TRACE_GOAL := Vector3(77.183815, 0.0, -10.611977)
const CASES := [
	{"name": "approach", "position": Vector3(70.675499, 0.2, -29.317780), "yaw": 132.250153},
	{"name": "stalled-turn", "position": Vector3(73.415283, 0.2, -27.950188), "yaw": 160.404588},
]

func _run() -> void:
	for fixture: Dictionary in CASES:
		await _case(fixture)
	for failure in _failures: push_error(failure)
	print("RIGID_TRAINING_NARROW_PORTAL cases=%d failures=%d" % [CASES.size(), _failures.size()])
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
	tank.combat_tank.gun_pitch_pivot.rotation.z = -deg_to_rad(-1.626924)
	tank.call("_sync_rigid_parts")
	for unused in 120: await physics_frame
	var driver := TankNavigation.new()
	driver.setup(tank)
	var command: Dictionary = {}
	var crossed := false
	var collision := false
	var frames := 0
	for tick in 3600:
		command = driver.drive(TRACE_GOAL, 4, STOP_DISTANCE, DT)
		if command.get("route") != &"navmesh":
			_fail("%s must retain navmesh routing" % fixture.name)
			break
		tank.set_movement_input(float(command.movement))
		tank.set_turn_input(float(command.turn))
		await physics_frame
		frames += 1
		crossed = crossed or (tank.global_position.x > 74.0 and tank.global_position.z > -24.0)
		collision = collision or _overlaps_sight_blocker(tank)
		if collision or command.status in [&"arrived", &"partial_end", &"no_path", &"stuck"]: break
	var distance := _xz_distance(tank.stable_world_center(), TRACE_GOAL)
	print("NARROW_PORTAL case=%s status=%s frames=%d crossed=%s distance=%.3f building_overlap=%s position=%s" % [fixture.name, command.get("status"), frames, crossed, distance, collision, tank.global_position])
	if collision: _fail("%s must not overlap any SightBlockers collider" % fixture.name)
	if not crossed or command.get("status") != &"arrived" or distance > STOP_DISTANCE:
		_fail("%s must cross the actual lower portal and arrive within stop distance" % fixture.name)
	driver.dispose()
	scene.queue_free()
	await process_frame
	await physics_frame
