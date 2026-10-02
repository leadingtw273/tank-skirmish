## 原有限越障矩陣加上真實 AI 安全檢查；不放寬 frame/penetration 門檻。
extends "res://tests/player_rigid_variants_contact_smoke.gd"

const Predictor := preload("res://src/ai/tank_driving_predictor.gd")

func _run() -> void:
	var names: Array = PLAYER_SCENES.keys()
	if not OS.get_cmdline_user_args().is_empty(): names = [OS.get_cmdline_user_args()[0]]
	for tank_name: String in names:
		current_name = tank_name
		current_player_scene = PLAYER_SCENES[tank_name]
		for height in [0.21, 0.50]:
			for input_value in [1.0, -1.0]: await _step(height, input_value)
		for side in [1.0, -1.0]: await _road(side)
	await _clear()
	for failure in failures: push_error(failure)
	print("RIGID_AI_TERRAIN failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _drive(tank: RigidBody3D, input_value: float, reached: Callable, frame_limit: int) -> Dictionary:
	var predictor := Predictor.new()
	predictor.setup(tank)
	var min_bottom := INF
	var passed := false
	var frames := 0
	var reasons := {}
	for unused in frame_limit:
		tank.set_driving_trace_enabled(unused == 0)
		var goal := tank.global_position - tank.global_basis.x * input_value * 30.0
		var chosen := predictor.choose(input_value, 0.0, goal, 1.0 / 60.0, true, false)
		var reason := String(chosen.get("reason", "missing"))
		if unused == 0: print("AI_TERRAIN_INITIAL ", chosen)
		reasons[reason] = int(reasons.get(reason, 0)) + 1
		tank.set_movement_input(float(chosen.get("movement", 0.0)))
		tank.set_turn_input(float(chosen.get("turn", 0.0)))
		await physics_frame
		frames += 1
		_watch_budget(tank, "ai-drive")
		min_bottom = minf(min_bottom, tank.hull_world_bottom())
		if reached.call():
			passed = true
			break
	tank.set_movement_input(0.0)
	print("AI_TERRAIN ", current_name, " input=", input_value, " frames=", frames, " reached=", passed, " reasons=", reasons)
	return {"reached": passed, "min_bottom": min_bottom, "frames": frames}
