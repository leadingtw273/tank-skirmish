## LEA-176：只驗證 _choose_layered 對候選限定 B16 unknown 的選擇語義。
## 真 Tank2 提供當幀 RigidMotion.capture；scripted probe 只替換完整 near 的最終結果，
## 不重寫 candidate loop、capture、score、stats 或 fallback 邏輯。
extends SceneTree

const Tank2 := preload("res://src/actors/rigid_tank/player_rigid_tank.tscn")
const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const DT := 1.0 / 60.0
const SETTLE_TICKS := 180


class ScriptedNearPredictor extends Predictor:
	var outcomes: Array[Dictionary] = []
	var near_calls: Array[Dictionary] = []
	var near_timing_usec: Array[Dictionary] = []
	var far_calls: int = 0

	func _probe_braking(_snapshot: Dictionary, _captured: Dictionary, _radius: float, movement: float, turn: float, _dt: float, _started_usec: int) -> Dictionary:
		var probe_started_usec := Time.get_ticks_usec()
		near_calls.append({"movement": movement, "turn": turn})
		if outcomes.is_empty():
			push_error("scripted near outcomes exhausted")
			return {"safe": false, "budget": true}
		var outcome: Dictionary = outcomes.pop_front() as Dictionary
		var delay_usec := int(outcome.get("delay_usec", 0))
		if delay_usec > 0: OS.delay_usec(delay_usec)
		var probe_completed_usec := Time.get_ticks_usec()
		near_timing_usec.append({"probe_usec": probe_completed_usec - probe_started_usec, "request_elapsed_usec": probe_completed_usec - _started_usec})
		match String(outcome.get("kind", "")):
			"b16_mesh_unknown":
				# Match production _probe_braking evidence: B16 plus an oriented-mesh witness.
				_stats["near_unknown_reason"] = "braking_sweep:B16"
				_stats["near_failure_detail"] = {"braking_unknown": "B16", "mesh_oriented_failure": {"shape_index": 0, "fixture": "scripted"}}
				return {}
			"initial_support":
				_stats["near_unknown_reason"] = "initial_support"
				return {}
			"mixed_support":
				_stats["near_unknown_reason"] = "mixed_support"
				return {}
			"budget":
				return {"safe": false, "budget": true}
			"safe":
				return {"safe": true, "budget": false}
			"unsafe":
				return {"safe": false, "budget": false}
		push_error("unknown scripted near outcome: %s" % outcome)
		return {"safe": false, "budget": true}

	func _probe_ground_motion(_snapshot: Dictionary, _radius: float, _movement: float, _turn: float, _started_usec: int, _trace_candidate: Dictionary, _old_contacts: Dictionary = {}) -> Dictionary:
		far_calls += 1
		return {"safe": true, "budget": false}

	func _score(_final_root: Transform3D, _initial_root: Transform3D, _goal: Vector3, _contacts: Dictionary) -> float:
		return 1.0


var world: Node3D
var failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	await _reset()
	_floor()
	var tank: RigidBody3D = await _spawn()
	if tank == null:
		await _finish()
		return
	await _frames(SETTLE_TICKS)
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	_check(bool(snapshot.get("grounded", false)), "real Tank2 must settle grounded before RigidMotion.capture")
	if bool(snapshot.get("grounded", false)):
		_b16_unknown_tries_next_real_candidate(tank, snapshot)
		_slow_nominal_b16_unknown_stops_before_second_probe(tank, snapshot)
		_b16_unknown_past_soft_returns_legacy(tank, snapshot)
		_all_b16_unknown_returns_legacy(tank, snapshot)
		_b16_then_budget_returns_zero(tank, snapshot)
		_known_unsafe_past_soft_stays_blocked(tank, snapshot)
		_safe_best_past_soft_stays_layered(tank, snapshot)
		_request_wide_support_unknowns_stay_legacy(tank, snapshot, "initial_support")
		_request_wide_support_unknowns_stay_legacy(tank, snapshot, "mixed_support")
	await _finish()


func _b16_unknown_tries_next_real_candidate(tank: RigidBody3D, snapshot: Dictionary) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	var existing: Array[Dictionary] = predictor._candidates(1.0, 0.0, false, false)
	_check(existing.size() >= 2, "Tank2 must expose nominal plus an existing adjustment candidate")
	if existing.size() < 2: return
	predictor.outcomes = [{"kind": "b16_mesh_unknown"}, {"kind": "safe"}]
	var result: Dictionary = _choose_layered(predictor, snapshot)
	var next: Dictionary = existing[1]
	_check(predictor.near_calls.size() >= 2, "candidate-specific B16+mesh unknown must invoke the next existing candidate near probe; calls=%s" % [predictor.near_calls])
	_check(predictor.near_calls.size() >= 2 and _same_command(predictor.near_calls[1], next), "second near probe must preserve the production desired order; expected=%s calls=%s" % [next, predictor.near_calls])
	_check(not result.is_empty() and _same_command(result, next) and bool((result.get("stats", {}) as Dictionary).get("near_verified", false)), "safe next candidate must be selected and near-verified after B16+mesh unknown; result=%s" % result)


func _slow_nominal_b16_unknown_stops_before_second_probe(tank: RigidBody3D, snapshot: Dictionary) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	predictor.outcomes = [{"kind": "b16_mesh_unknown", "delay_usec": 3500}, {"kind": "safe"}]
	var result: Dictionary = _choose_layered(predictor, snapshot)
	var stats: Dictionary = predictor.get_stats()
	_check(predictor.near_timing_usec.size() >= 1, "slow nominal fixture must record its first near probe timing; timings=%s" % [predictor.near_timing_usec])
	if predictor.near_timing_usec.is_empty(): return
	var first: Dictionary = predictor.near_timing_usec[0]
	var probe_usec := int(first.get("probe_usec", 0))
	var request_elapsed_usec := int(first.get("request_elapsed_usec", 0))
	# A naturally expired old soft window cannot distinguish old from new scheduling.
	_check(request_elapsed_usec < 5500, "slow nominal admission case is inconclusive: first probe already reached the old soft window; request_elapsed=%dus probe=%dus" % [request_elapsed_usec, probe_usec])
	_check(probe_usec >= 3000 and request_elapsed_usec + probe_usec > 5500, "slow nominal admission fixture must measure a >=3ms probe whose observed cost exceeds the next-candidate admission window; request_elapsed=%dus probe=%dus" % [request_elapsed_usec, probe_usec])
	_check(predictor.near_calls.size() == 1 and predictor.far_calls == 0, "slow nominal B16 unknown must return to legacy before the second near probe; calls=%s far_calls=%d timings=%s" % [predictor.near_calls, predictor.far_calls, predictor.near_timing_usec])
	_check(result.is_empty() and not bool(stats.get("near_verified", false)) and String(stats.get("prediction_mode", "")) == "legacy", "slow nominal B16 unknown must return legacy {} without a near certificate; result=%s stats=%s" % [result, stats])


func _b16_unknown_past_soft_returns_legacy(tank: RigidBody3D, snapshot: Dictionary) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	predictor.outcomes = [{"kind": "b16_mesh_unknown"}, {"kind": "safe"}]
	var result: Dictionary = _choose_layered(predictor, snapshot, 6000)
	var stats: Dictionary = predictor.get_stats()
	_check(result.is_empty(), "past the soft window, nominal B16+mesh unknown must return {} for legacy handling; result=%s" % result)
	_check(predictor.near_calls.size() == 1 and predictor.far_calls == 0, "past-soft B16+mesh unknown must complete only the nominal near probe before fallback; near_calls=%s far_calls=%d" % [predictor.near_calls, predictor.far_calls])
	_check(not bool(stats.get("near_verified", false)) and String(stats.get("prediction_mode", "")) == "legacy", "past-soft B16+mesh fallback must not claim a layered certificate; stats=%s" % stats)


func _all_b16_unknown_returns_legacy(tank: RigidBody3D, snapshot: Dictionary) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	var existing: Array[Dictionary] = predictor._candidates(1.0, 0.0, false, false)
	for unused: int in existing.size(): predictor.outcomes.append({"kind": "b16_mesh_unknown"})
	var result: Dictionary = _choose_layered(predictor, snapshot)
	var stats: Dictionary = predictor.get_stats()
	_check(result.is_empty(), "all candidate-specific B16+mesh unknown results must return {} for legacy handling; result=%s" % result)
	_check(predictor.near_calls.size() == existing.size(), "all B16 unknown must inspect every existing desired candidate before legacy fallback; calls=%s expected=%d" % [predictor.near_calls, existing.size()])
	_check(not bool(stats.get("near_verified", false)) and String(stats.get("prediction_mode", "")) == "legacy", "legacy fallback must not claim near_verified; stats=%s" % stats)


func _b16_then_budget_returns_zero(tank: RigidBody3D, snapshot: Dictionary) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	predictor.outcomes = [{"kind": "b16_mesh_unknown"}, {"kind": "budget"}]
	var result: Dictionary = _choose_layered(predictor, snapshot)
	var stats: Dictionary = result.get("stats", {}) as Dictionary
	_check(not result.is_empty() and is_zero_approx(float(result.get("movement", 1.0))) and is_zero_approx(float(result.get("turn", 1.0))) and String(result.get("reason", "")) == "budget", "B16 unknown followed by exhausted budget without a safe candidate must stop; result=%s" % result)
	_check(not bool(stats.get("near_verified", false)) and String(stats.get("prediction_mode", "")) == "legacy", "budget stop before any safe candidate must remain legacy and must not claim near_verified; stats=%s" % stats)


func _known_unsafe_past_soft_stays_blocked(tank: RigidBody3D, snapshot: Dictionary) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	var existing: Array[Dictionary] = predictor._candidates(1.0, 0.0, false, false)
	for unused: int in existing.size(): predictor.outcomes.append({"kind": "unsafe"})
	var result: Dictionary = _choose_layered(predictor, snapshot, 6000)
	var stats: Dictionary = predictor.get_stats()
	_check(not result.is_empty() and is_zero_approx(float(result.get("movement", 1.0))) and is_zero_approx(float(result.get("turn", 1.0))) and String(result.get("reason", "")) == "blocked", "known unsafe candidates past the soft window must stop as blocked; result=%s" % result)
	_check(predictor.near_calls.size() == existing.size() and String(stats.get("prediction_mode", "")) == "layered_flat", "known unsafe must remain layered and inspect every desired candidate; calls=%s expected=%d stats=%s" % [predictor.near_calls, existing.size(), stats])


func _safe_best_past_soft_stays_layered(tank: RigidBody3D, snapshot: Dictionary) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	predictor.outcomes = [{"kind": "safe"}]
	var result: Dictionary = _choose_layered(predictor, snapshot, 6000)
	var stats: Dictionary = predictor.get_stats()
	_check(not result.is_empty() and _same_command(result, {"movement": 1.0, "turn": 0.0}) and bool(stats.get("near_verified", false)), "a nominal safe candidate past the soft window must remain selected and near-verified; result=%s stats=%s" % [result, stats])
	_check(predictor.near_calls.size() == 1 and predictor.far_calls == 0 and String(stats.get("prediction_mode", "")) == "layered_flat" and String(stats.get("far_status", "")) == "unknown", "past-soft safe best must keep the layered result without a far probe; calls=%s far_calls=%d stats=%s" % [predictor.near_calls, predictor.far_calls, stats])


func _request_wide_support_unknowns_stay_legacy(tank: RigidBody3D, snapshot: Dictionary, kind: String) -> void:
	var predictor: ScriptedNearPredictor = _predictor(tank)
	predictor.outcomes = [{"kind": kind}, {"kind": "safe"}]
	var result: Dictionary = _choose_layered(predictor, snapshot)
	var stats: Dictionary = predictor.get_stats()
	_check(result.is_empty() and predictor.near_calls.size() == 1, "%s must immediately return {} for existing request-wide legacy handling; result=%s calls=%s" % [kind, result, predictor.near_calls])
	_check(not bool(stats.get("near_verified", false)) and String(stats.get("prediction_mode", "")) == "legacy", "%s legacy fallback must not claim near_verified; stats=%s" % [kind, stats])


func _choose_layered(predictor: ScriptedNearPredictor, snapshot: Dictionary, elapsed_usec: int = 0) -> Dictionary:
	# The 6ms cases are beyond FAR_WORK_USEC but remain well inside the 20ms request cap.
	var started_usec := Time.get_ticks_usec() - elapsed_usec
	return predictor._choose_layered(snapshot, 1.0, 1.0, 0.0, Vector3(-100.0, 0.0, 0.0), DT, false, true, started_usec)


func _predictor(tank: RigidBody3D) -> ScriptedNearPredictor:
	var predictor: ScriptedNearPredictor = ScriptedNearPredictor.new()
	predictor.setup(tank)
	return predictor


func _same_command(actual: Dictionary, expected: Dictionary) -> bool:
	return is_equal_approx(float(actual.get("movement", INF)), float(expected.get("movement", -INF))) and is_equal_approx(float(actual.get("turn", INF)), float(expected.get("turn", -INF)))


func _floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Tank2CaptureFloor"
	body.collision_layer = 128
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 0.2, 200.0)
	collision.shape = shape
	body.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(collision)
	world.add_child(body)


func _spawn() -> RigidBody3D:
	var tank := Tank2.instantiate() as RigidBody3D
	_check(tank != null, "Tank2 must instantiate as the real rigid vehicle")
	if tank == null: return null
	tank.position = Vector3(0.0, 2.0, 0.0)
	world.add_child(tank)
	await _frames(2)
	return tank


func _reset() -> void:
	await _clear()
	world = Node3D.new()
	root.add_child(world)


func _finish() -> void:
	await _clear()
	for failure: String in failures: push_error(failure)
	print("RIGID_LAYERED_CANDIDATE_FALLBACK failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _clear() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _frames(2)
	world = null


func _frames(count: int) -> void:
	for unused: int in count: await physics_frame


func _check(condition: bool, detail: String) -> void:
	if not condition: failures.append(detail)
