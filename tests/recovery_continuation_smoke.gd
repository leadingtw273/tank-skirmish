## V4 continuation fail-closed seam；--baseline 載入保存的 pre-F3 Navigation，不改 delivery。
extends SceneTree

const DT := 1.0 / 60.0
const BEFORE_NAV := "/tmp/recovery-continuation-before/tank_navigation.gd"
const DrivingPredictor := preload("res://src/ai/tank_driving_predictor.gd")

class FakeTank extends Node3D:
	var tank_mass_tonnes := 1.0
	var brake_force_kilonewtons := 1.0
	var forward_speed := 0.0
	var reverse_movement_speed := 2.0
	var movement_speed := 7.0
	var actual_angular_speed := 0.0
	func stable_world_center() -> Vector3:
		return global_position


class FakePredictor extends DrivingPredictor:
	var response: Dictionary = {}
	func choose_escape_profile(_forward: Vector3, _candidates: Array[Dictionary], _delta: float, _state: Dictionary = {}) -> Dictionary:
		return response.duplicate(true)


var _failures: Array[String] = []
var _baseline := false


func _init() -> void:
	_baseline = "--baseline" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	print("RECOVERY_CONTINUATION baseline=%s args=%s" % [_baseline, OS.get_cmdline_user_args()])
	var navigation_script: GDScript = (load(BEFORE_NAV) if _baseline else load("res://src/ai/tank_navigation.gd")) as GDScript
	if navigation_script == null:
		_fail("Cannot load Navigation seam source.")
	else:
		_validate_missing_safe(navigation_script)
		_validate_waiting(navigation_script)
		_validate_safe_matrix(navigation_script)
	if _failures.is_empty():
		print("RECOVERY_CONTINUATION PASS: V4 continuation result matrix is fail-closed.")
		quit(0)
		return
	for failure in _failures:
		push_error("RECOVERY_CONTINUATION FAIL: %s" % failure)
	quit(1)


func _make_navigation(navigation_script: GDScript, response: Dictionary, heading: Vector3) -> Dictionary:
	var nav: RefCounted = navigation_script.new() as RefCounted
	var tank := FakeTank.new()
	root.add_child(tank)
	var predictor := FakePredictor.new()
	predictor.response = response
	nav.set("_tank", tank)
	nav.set("_predictor", predictor)
	var recovery: RefCounted = nav.get("_recovery") as RefCounted
	recovery.reset(Vector3.ZERO, Vector3.LEFT)
	recovery.attempts = 1
	recovery.phase = &"turning"
	recovery.escape_heading = heading
	var result: Dictionary = nav.call("_drive_recovery", DT)
	tank.queue_free()
	return {"nav": nav, "result": result}


func _validate_missing_safe(navigation_script: GDScript) -> void:
	var fixture := _make_navigation(navigation_script, {"reason": &"clear", "movement": 1.0, "turn": 1.0}, Vector3.FORWARD)
	var result: Dictionary = fixture.result
	var trace: Dictionary = fixture.nav.get_driving_trace_state()
	var selected: Dictionary = trace.get("selected", {})
	if not is_zero_approx(float(result.get("movement", 0.0))) or not is_zero_approx(float(result.get("turn", 0.0))) \
			or StringName(selected.get("reason", &"")) != &"invalid_continuation_result" or not bool(selected.get("missing_safe", false)):
		_fail("missing safe must fail closed with invalid trace%s; result=%s selected=%s." % [" (saved-before baseline)" if _baseline else "", result, selected])


func _validate_waiting(navigation_script: GDScript) -> void:
	var fixture := _make_navigation(navigation_script, {}, Vector3.ZERO)
	var result: Dictionary = fixture.result
	var selected: Dictionary = (fixture.nav.get_driving_trace_state() as Dictionary).get("selected", {})
	if not is_zero_approx(float(result.get("movement", 0.0))) or not is_zero_approx(float(result.get("turn", 0.0))) \
			or StringName(selected.get("reason", &"")) != &"waiting":
		_fail("zero heading waiting must be 0/0 and non-invalid; result=%s selected=%s." % [result, selected])


func _validate_safe_matrix(navigation_script: GDScript) -> void:
	var safe := _make_navigation(navigation_script, {"safe": true, "reason": &"clear"}, Vector3.FORWARD)
	if is_zero_approx(float((safe.result as Dictionary).get("turn", 0.0))):
		_fail("safe=true must retain original Recovery turn; result=%s." % safe.result)
	for reason in [&"blocked", &"budget"]:
		var blocked := _make_navigation(navigation_script, {"safe": false, "reason": reason, "stats": {"case": reason}}, Vector3.FORWARD)
		var result: Dictionary = blocked.result
		var selected: Dictionary = (blocked.nav.get_driving_trace_state() as Dictionary).get("selected", {})
		if not is_zero_approx(float(result.get("movement", 0.0))) or not is_zero_approx(float(result.get("turn", 0.0))) \
			or StringName(selected.get("reason", &"")) != reason:
			_fail("safe=false %s must remain 0/0 with original diagnostics; result=%s selected=%s." % [reason, result, selected])


func _fail(message: String) -> void:
	_failures.append(message)
