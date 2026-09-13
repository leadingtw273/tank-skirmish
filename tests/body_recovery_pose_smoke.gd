## 兩個已記錄砲塔/砲管姿態下的 body-only recovery 合約。
## 僅測試；不重播 trace，也不主張安全候選必定完成整段追擊。
extends SceneTree

const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const DT := 1.0 / 60.0
const MAX_EXECUTION_FRAMES := 120

const CASES := [
	{
		"label": "reverse_f4604", "kind": "reverse", "frame": 4604,
		"requested": Vector2(-0.52399998, 0.0),
		"enemy_root": Transform3D(Basis(Vector3.UP, 3.02348136901855), Vector3(72.9678955078125, 0.0, -81.4386367797852)),
		"enemy_turret": -1.83570396900177, "enemy_pitch": -0.0412773303687572,
		"enemy_speed": 0.0333333333333331, "enemy_angular": 0.0,
		"player_root": Transform3D(Basis(Vector3.UP, 1.5098522901535), Vector3(53.402587890625, 0.0, -51.5303077697754)),
		"player_turret": 2.54795503616333, "player_pitch": -0.0237586926668882,
		"goal": Vector3(65.7923431396484, 0.0, -64.0484619140625),
	},
	{
		"label": "terminal_f4906", "kind": "turn", "frame": 4906,
		"requested": Vector2(0.0, -1.0),
		"enemy_root": Transform3D(Basis(Vector3.UP, 2.98051881790161), Vector3(73.166618347168, 0.0, -81.4106140136719)),
		"enemy_turret": -1.80296683311462, "enemy_pitch": -0.0411513410508633,
		"enemy_speed": 0.1, "enemy_angular": -0.016,
		"player_root": Transform3D(Basis(Vector3.UP, 1.5098522901535), Vector3(53.402587890625, 0.0, -51.5303077697754)),
		"player_turret": 2.54370093345642, "player_pitch": -0.0208977330476046,
		"goal": Vector3(65.7923431396484, 0.0, -64.0484619140625),
	},
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for data in CASES:
		await _validate_pose_case(data)
	await _validate_clear_command_passthrough()
	await _validate_navigation_recovery_integration(CASES[0])
	if _failures.is_empty():
		print("BODY_RECOVERY_POSE PASS: recorded gun#14 blocks; body-only recovery is safe and makes short progress.")
		quit(0)
		return
	for failure in _failures:
		push_error("BODY_RECOVERY_POSE FAIL: %s" % failure)
	quit(1)


func _validate_pose_case(data: Dictionary) -> void:
	var fixture := await _fixture(data, true)
	if fixture.is_empty():
		return
	var tank := fixture.tank as CharacterBody3D
	var predictor := Predictor.new()
	predictor.setup(tank)
	var requested: Vector2 = data.requested
	var baseline: Dictionary = predictor.choose(requested.x, requested.y, data.goal, DT, false, false)
	var blocker := _first_blocker(predictor.get_stats())
	if StringName(baseline.get("reason", &"")) != &"blocked" or blocker.get("part_id", "") != "gun" or int(blocker.get("shape_index", -1)) != 14:
		_fail("%s frame=%d must reproduce its original nominal request as gun#14 blocked; result=%s blocker=%s." % [data.label, data.frame, baseline, blocker])
		await _free_fixture(fixture)
		return
	if not predictor.has_method(&"choose_recovery"):
		_fail("%s requires Predictor.choose_recovery(movement, turn, goal, delta); API is missing." % data.label)
		await _free_fixture(fixture)
		return
	var choice: Dictionary = predictor.call(&"choose_recovery", requested.x, requested.y, data.goal, DT)
	if not _is_safe_nonzero(choice) or not _choice_is_nominally_clear(predictor, choice, data.goal):
		_fail("%s choose_recovery must return a safe non-zero body-only alternative; choice=%s." % [data.label, choice])
		await _free_fixture(fixture)
		return
	if data.kind == "reverse" and absf(float(choice.get("movement", 0.0))) <= 0.01:
		_fail("%s recovery candidate must retain a non-zero movement axis for short physical displacement; choice=%s." % [data.label, choice])
	if data.kind == "turn" and absf(float(choice.get("turn", 0.0))) <= 0.01:
		_fail("%s recovery candidate must retain a non-zero body turn axis for short physical heading progress; choice=%s." % [data.label, choice])
	var stopped: Dictionary = predictor.call(&"choose_recovery", 0.0, 0.0, data.goal, DT)
	if not is_zero_approx(float(stopped.get("movement", NAN))) or not is_zero_approx(float(stopped.get("turn", NAN))):
		_fail("%s choose_recovery(0, 0) must not invent motion; result=%s." % [data.label, stopped])
	else:
		await _execute_with_per_frame_query(data, fixture, predictor, choice)
	await _free_fixture(fixture)


func _validate_navigation_recovery_integration(data: Dictionary) -> void:
	var fixture := await _fixture(data, true)
	if fixture.is_empty():
		return
	var tank := fixture.tank as CharacterBody3D
	var driver := TankNavigation.new()
	driver.setup(tank)
	## fixture 不依賴 navmesh ready；直接讓已 setup 的真 navigation 進入其 recovery entrypoint。
	driver.set("_goal", data.goal)
	var recovery := driver.get("_recovery") as RefCounted
	if recovery == null:
		_fail("TankNavigation must own its real recovery instance.")
	else:
		recovery.set("phase", &"reversing")
		recovery.call("reset_progress", tank.stable_world_center(), tank.global_basis * Vector3.LEFT)
		var start: Vector3 = tank.stable_world_center()
		var max_distance := 0.0
		var saw_safe_alternative := false
		for frame in MAX_EXECUTION_FRAMES:
			var command: Dictionary = driver.call(&"_drive_recovery", DT)
			var selected: Dictionary = driver.get_driving_trace_state().get("selected", {}) as Dictionary
			if _is_safe_nonzero(selected):
				var nominal := Predictor.new()
				nominal.setup(tank)
				saw_safe_alternative = _choice_is_nominally_clear(nominal, selected, data.goal)
			tank.set_movement_input(float(command.get("movement", 0.0)))
			tank.set_turn_input(float(command.get("turn", 0.0)))
			await physics_frame
			max_distance = maxf(max_distance, tank.stable_world_center().distance_to(start))
		tank.set_movement_input(0.0)
		tank.set_turn_input(0.0)
		print("BODY_RECOVERY_INTEGRATION label=%s distance=%.3f safe_alternative=%s final_phase=%s" % [data.label, max_distance, saw_safe_alternative, recovery.get("phase")])
		if not saw_safe_alternative or max_distance < 0.2:
			_fail("TankNavigation reversing phase must execute a nominally-clear choose_recovery alternative through real physics; distance=%.3f safe_alternative=%s final_phase=%s." % [max_distance, saw_safe_alternative, recovery.get("phase")])
	driver.dispose()
	await _free_fixture(fixture)


func _execute_with_per_frame_query(data: Dictionary, fixture: Dictionary, predictor: RefCounted, choice: Dictionary) -> void:
	var tank := fixture.tank as CharacterBody3D
	var start: Vector3 = tank.stable_world_center()
	var start_forward: Vector3 = _forward(tank)
	var max_distance := 0.0
	var max_angle := 0.0
	var requested: Vector2 = data.requested
	for frame in MAX_EXECUTION_FRAMES:
		## 每個 physics frame 以原 recovery request 重選，並用獨立 nominal probe 驗證選出的當幀 body command。
		var current: Dictionary = predictor.call(&"choose_recovery", requested.x, requested.y, data.goal, DT)
		if _is_safe_nonzero(current) and not _choice_is_nominally_clear(predictor, current, data.goal):
			_fail("%s selected unsafe body candidate at frame=%d; result=%s." % [data.label, frame, current])
			break
		tank.set_movement_input(float(current.get("movement", 0.0)))
		tank.set_turn_input(float(current.get("turn", 0.0)))
		await physics_frame
		max_distance = maxf(max_distance, tank.stable_world_center().distance_to(start))
		max_angle = maxf(max_angle, start_forward.angle_to(_forward(tank)))
	tank.set_movement_input(0.0)
	tank.set_turn_input(0.0)
	if data.kind == "reverse" and max_distance < 0.2:
		_fail("%s safe recovery only made %.3fm in %d real physics frames; needs >=0.2m short-range progress." % [data.label, max_distance, MAX_EXECUTION_FRAMES])
	if data.kind == "turn" and rad_to_deg(max_angle) < 3.0:
		_fail("%s safe recovery only changed heading %.2fdeg in %d real physics frames; needs >=3deg short-range progress." % [data.label, rad_to_deg(max_angle), MAX_EXECUTION_FRAMES])
	print("BODY_RECOVERY_EXECUTION label=%s distance=%.3f heading=%.2f final_position=%s" % [data.label, max_distance, rad_to_deg(max_angle), tank.stable_world_center()])


func _validate_clear_command_passthrough() -> void:
	var world := Node3D.new()
	var ground := StaticBody3D.new()
	ground.position = Vector3(0.0, -0.5, 0.0)
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(220.0, 1.0, 220.0)
	ground_shape.shape = box
	ground.add_child(ground_shape)
	var tank := TANK1.instantiate() as CharacterBody3D
	world.add_child(ground)
	world.add_child(tank)
	root.add_child(world)
	for unused in 3:
		await physics_frame
	var predictor := Predictor.new()
	predictor.setup(tank)
	var movement := 0.4
	var turn := -0.2
	var goal: Vector3 = tank.stable_world_center() + Vector3.LEFT * 20.0
	var nominal := predictor.choose(movement, turn, goal, DT, false, false)
	if StringName(nominal.get("reason", &"")) != &"clear":
		_fail("Open fixture nominal command must be clear before testing recovery passthrough; result=%s." % nominal)
	elif not predictor.has_method(&"choose_recovery"):
		_fail("Open fixture requires Predictor.choose_recovery API.")
	else:
		var selected: Dictionary = predictor.call(&"choose_recovery", movement, turn, goal, DT)
		if not is_equal_approx(float(selected.get("movement", NAN)), movement) or not is_equal_approx(float(selected.get("turn", NAN)), turn):
			_fail("choose_recovery must preserve an already-clear movement/turn exactly; selected=%s nominal=%s." % [selected, nominal])
	world.queue_free()
	await physics_frame


func _fixture(data: Dictionary, live_tank: bool) -> Dictionary:
	var scene := PLAYTEST.instantiate() as Node3D
	root.add_child(scene)
	await physics_frame
	var tank := scene.get_node_or_null("Encounter/Enemy") as CharacterBody3D
	var player := scene.get_node_or_null("Main/Tank") as CharacterBody3D
	if tank == null or player == null:
		_fail("%s fixture requires Encounter/Enemy and Main/Tank." % data.label)
		scene.queue_free()
		await physics_frame
		return {}
	_freeze_tree(scene)
	_apply_pose(tank, data.enemy_root, float(data.enemy_turret), float(data.enemy_pitch), float(data.enemy_speed), float(data.enemy_angular))
	_apply_pose(player, data.player_root, float(data.player_turret), float(data.player_pitch), 0.0, 0.0)
	if live_tank:
		tank.process_mode = Node.PROCESS_MODE_ALWAYS
		tank.set_process(true)
		tank.set_physics_process(true)
	await physics_frame
	await physics_frame
	tank.call(&"set_driving_trace_enabled", true)
	return {"scene": scene, "tank": tank}


func _freeze_tree(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze_tree(child)


func _apply_pose(tank: CharacterBody3D, root_transform: Transform3D, turret_yaw: float, gun_pitch: float, forward_speed: float, angular_speed: float) -> void:
	tank.global_transform = root_transform
	tank.velocity = Vector3.ZERO
	tank.forward_speed = forward_speed
	tank.angular_speed = angular_speed
	tank.actual_angular_speed = angular_speed
	tank.movement_command = 0.0
	tank.turn_command = 0.0
	var turret := tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	var gun := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	if turret == null or gun == null:
		_fail("%s is missing turret or gun pivot." % tank.name)
		return
	turret.rotation.y = turret_yaw
	gun.rotation.z = -gun_pitch
	tank.call(&"_sync_part_collision_shapes")


func _first_blocker(stats: Dictionary) -> Dictionary:
	var trace: Dictionary = stats.get("trace", {}) as Dictionary
	var candidates: Array = trace.get("candidates", []) as Array
	return candidates[0].get("first_blocker", {}) as Dictionary if not candidates.is_empty() else {}


func _is_safe_nonzero(choice: Dictionary) -> bool:
	var stats: Dictionary = choice.get("stats", {}) as Dictionary
	return not bool(stats.get("at_cap", false)) and (not is_zero_approx(float(choice.get("movement", 0.0))) or not is_zero_approx(float(choice.get("turn", 0.0))))


func _choice_is_nominally_clear(predictor: RefCounted, choice: Dictionary, goal: Vector3) -> bool:
	var selected_stats: Dictionary = choice.get("stats", {}) as Dictionary
	if bool(selected_stats.get("at_cap", false)):
		return false
	var nominal: Dictionary = predictor.choose(float(choice.get("movement", 0.0)), float(choice.get("turn", 0.0)), goal, DT, true, false)
	var nominal_stats: Dictionary = nominal.get("stats", {}) as Dictionary
	return StringName(nominal.get("reason", &"")) == &"clear" and not bool(nominal_stats.get("at_cap", false))


func _forward(tank: CharacterBody3D) -> Vector3:
	return (tank.global_basis * Vector3.LEFT).slide(Vector3.UP).normalized()


func _free_fixture(fixture: Dictionary) -> void:
	var scene := fixture.get("scene") as Node
	if is_instance_valid(scene):
		scene.queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
