extends "res://tests/rigid_layered_candidate_fallback_smoke.gd"

# Tests the public request boundary: scheduling never reuses a prior result.
class SchedulingPredictor extends Predictor:
	var layered_calls := 0
	var legacy_calls := 0
	var legacy_budget := false
	var contact_present := false
	var near_result: Dictionary = {}

	func _choose_layered(_snapshot: Dictionary, _radius: float, _movement: float, _turn: float, _goal: Vector3, _delta: float, _reverse: bool, _adjustment: bool, _started: int) -> Dictionary:
		layered_calls += 1
		if near_result.is_empty():
			_stats["near_unknown_reason"] = "braking_sweep:B17"
		return near_result

	func _initial_contacts(_space: PhysicsDirectSpaceState3D, _snapshot: Dictionary, _excluded: Array[RID], _started: int) -> Dictionary:
		return {"contacts": {1: {}} if contact_present else {}, "budget": false}

	func _probe(_space: PhysicsDirectSpaceState3D, snapshot: Dictionary, _radius: float, _bounds: Array[Dictionary], _excluded: Array[RID], _contacts: Dictionary, _movement: float, _turn: float, _started: int, _trace: Dictionary = {}) -> Dictionary:
		legacy_calls += 1
		return {"safe": not legacy_budget, "budget": legacy_budget, "final_root": snapshot.root}


func _run() -> void:
	await _reset()
	_floor()
	var tank: RigidBody3D = await _spawn()
	if tank != null:
		await _frames(SETTLE_TICKS)
		_public_scheduling_keeps_fresh_proofs(tank)
	print("RIGID_PREDICTION_SCHEDULING failures=%d" % failures.size())
	await _finish()


func _public_scheduling_keeps_fresh_proofs(tank: RigidBody3D) -> void:
	var predictor := SchedulingPredictor.new()
	predictor.setup(tank)
	var goal := Vector3(-100.0, 0.0, 0.0)
	var first := predictor.choose(1.0, 0.0, goal, DT)
	_check(str(first.reason) == "clear" and predictor.layered_calls == 1 and predictor.legacy_calls == 1, "first unknown must run a fresh legacy proof")
	for call_index in 6:
		predictor.legacy_budget = call_index % 2 == 0
		var result := predictor.choose(1.0, 0.0, goal, DT)
		_check(predictor.layered_calls == 1 and predictor.legacy_calls == call_index + 2, "six retries must each run fresh legacy without optional flat probe")
		_check(str(result.reason) == ("budget" if predictor.legacy_budget else "clear"), "fresh legacy outcome must control every retry; no old safe result")
		_check(not bool(result.stats.near_verified), "terrain retry cannot claim a near certificate")
		if predictor.legacy_budget: _check(is_zero_approx(float(result.movement)), "fresh budget must stop")
	predictor.legacy_budget = false
	predictor.choose(1.0, 0.0, goal, DT)
	_check(predictor.layered_calls == 2, "seventh call must retry the optional flat proof")
	for mode in ["recovery", "handoff", "nominal", "contact", "stop", "reset"]:
		predictor.reset()
		predictor.choose(1.0, 0.0, goal, DT)
		match mode:
			"recovery": predictor.choose_recovery(0.0, 0.0, goal, DT)
			"handoff": predictor.choose_handoff_step(0.0, 0.0, goal, DT)
			"nominal": predictor.choose(1.0, 0.0, goal, DT, false, false)
			"contact":
				predictor.contact_present = true
				predictor.choose(0.0, 0.0, goal, DT, false, false)
				predictor.contact_present = false
			"stop": predictor.choose(0.0, 0.0, goal, DT)
			"reset": predictor.reset()
		var prior := predictor.layered_calls
		predictor.choose(1.0, 0.0, goal, DT)
		_check(predictor.layered_calls == prior + 1, "mode %s must clear optional-probe backoff" % mode)
	for reason in ["blocked", "budget"]:
		predictor.reset()
		predictor.near_result = {"movement":0.0,"turn":0.0,"reason":reason}
		var prior := predictor.layered_calls
		predictor.choose(1.0, 0.0, goal, DT)
		predictor.choose(1.0, 0.0, goal, DT)
		_check(predictor.layered_calls == prior + 2, "known unsafe or hard cap must not arm backoff")
