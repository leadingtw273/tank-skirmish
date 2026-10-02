## 使用者 2026-09-23 實測掉幀姿態；保留真場景、AI 與碰撞。
extends "res://tests/rigid_training_pursuit_smoke.gd"

const CASES := [
	{"name": "previous-clear", "enemy": Vector3(47.210865, 0.01645, -48.66602), "yaw": -14.879555, "turret": 21.15149, "pitch": -1.594189,
		"player": Vector3(-4.810386, 0.00824, -40.06795), "player_yaw": -142.203569},
	{"name": "observed-budget", "enemy": Vector3(44.851143, 0.01685, -49.37947), "yaw": -12.039794, "turret": 21.534642, "pitch": -1.567306,
		"player": Vector3(-7.559492, 0.00890, -37.90191), "player_yaw": -144.150432},
]

func _run() -> void:
	for fixture: Dictionary in CASES:
		await _case(fixture)
	for failure in _failures: push_error(failure)
	print("RIGID_VISIBLE_COMBAT failures=", _failures.size())
	quit(0 if _failures.is_empty() else 1)

func _case(fixture: Dictionary) -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	root.add_child(scene)
	var ai := scene.get_node("Encounter/CombatAI")
	ai.set_physics_process(false)
	var enemy := scene.get_node("Encounter/Enemy") as RigidBody3D
	var player := scene.get_node("Main/PlayerRuntime").controlled_tank as RigidBody3D
	var region := scene.get_node("NavigationRegion3D") as NavigationRegion3D
	for tick in 120:
		if NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0: break
		await physics_frame
	_apply_initial_pose(enemy, fixture.enemy, deg_to_rad(fixture.yaw), deg_to_rad(fixture.turret))
	_apply_initial_pose(player, fixture.player, deg_to_rad(fixture.player_yaw), 0.0)
	var gun := enemy.combat_tank.gun_pitch_pivot as Node3D
	gun.rotation.z = -deg_to_rad(fixture.pitch)
	enemy.call("_sync_rigid_parts")
	enemy.set_driving_trace_enabled(true)
	ai.set_physics_process(true)
	var elapsed: Array[int] = []
	var visible := 0
	var budget := 0
	var requested := 0
	var last_request := -1
	var total_queries := 0
	var zero_commands := 0
	var layered := 0
	var origin := enemy.global_position
	var initial_yaw := enemy.rotation.y
	var max_distance := 0.0
	var max_yaw := 0.0
	var frame_started := Time.get_ticks_usec()
	var max_frame_usec := 0
	for frame in 240:
		await physics_frame
		var now := Time.get_ticks_usec()
		max_frame_usec = maxi(max_frame_usec, now - frame_started)
		frame_started = now
		var offset := enemy.global_position - origin
		max_distance = maxf(max_distance, Vector2(offset.x, offset.z).length())
		max_yaw = maxf(max_yaw, absf(wrapf(enemy.rotation.y - initial_yaw, -PI, PI)))
		var state: Dictionary = ai.get_driving_trace_state()
		visible += int(bool(state.visible))
		var nav: Dictionary = state.navigation
		var request_frame := int(nav.get("request_frame", -1))
		if request_frame == last_request or request_frame < 0: continue
		last_request = request_frame
		var selected: Dictionary = nav.get("selected", {})
		var stats: Dictionary = selected.get("stats", {})
		if stats.is_empty(): continue
		requested += int(absf(float(nav.requested.get("turn", 0.0))) > 0.001)
		zero_commands += int(is_zero_approx(float(selected.get("movement", 0.0))) and is_zero_approx(float(selected.get("turn", 0.0))))
		layered += int(stats.get("prediction_mode") == &"layered_flat")
		elapsed.append(int(stats.elapsed_usec))
		total_queries += int(stats.query_count)
		budget += int(selected.get("reason") == &"budget")
	if elapsed.is_empty():
		_fail("%s must run real predictions" % fixture.name)
	else:
		elapsed.sort()
		var sum := 0
		for value: int in elapsed: sum += value
		var mean := float(sum) / elapsed.size()
		var p95 := elapsed[mini(elapsed.size() - 1, ceili(elapsed.size() * 0.95) - 1)]
		print("VISIBLE_COMBAT case=%s visible=%d turn_requests=%d samples=%d budget=%d mean_usec=%.1f p95_usec=%d max_usec=%d queries=%d" % [fixture.name, visible, requested, elapsed.size(), budget, mean, p95, elapsed[-1], total_queries])
		print("VISIBLE_PROGRESS case=%s distance=%.3f yaw_degrees=%.2f zero_commands=%d/%d layered=%d max_physics_interval_usec=%d" % [fixture.name, max_distance, rad_to_deg(max_yaw), zero_commands, elapsed.size(), layered, max_frame_usec])
		if max_distance < 2.0 and max_yaw < deg_to_rad(15.0): _fail("%s must actually move 2m or turn 15deg" % fixture.name)
		if zero_commands == elapsed.size(): _fail("%s cannot pass by braking every frame" % fixture.name)
		if visible < 120 or requested < 1 or elapsed.size() < 120: _fail("%s fixture must see target and run turn predictions" % fixture.name)
		if float(budget) / elapsed.size() >= 0.05: _fail("%s budget ratio must be below 5%%" % fixture.name)
		if mean > 6000.0 or p95 > 10000: _fail("%s prediction must leave frame budget: mean<=6ms/p95<=10ms" % fixture.name)
	scene.queue_free()
	await process_frame
	await physics_frame
