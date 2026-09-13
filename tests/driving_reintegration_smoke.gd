## R3 有限整合合約：deadline 同源、各 recovery gate 接線、normal/rejoin 共用 nominal。
extends SceneTree

const Recovery := preload("res://src/ai/tank_recovery.gd")

var failures: Array[String] = []


func _init() -> void:
	_validate_deadlines()
	_validate_wiring()
	if failures.is_empty():
		print("DRIVING_REINTEGRATION PASS: shared deadlines, recovery safety gates, and shared nominal wiring are present.")
		quit(0)
		return
	for failure in failures: push_error("DRIVING_REINTEGRATION FAIL: %s" % failure)
	quit(1)


func _validate_deadlines() -> void:
	var common := [Vector3.LEFT,Vector3.FORWARD,0.0,0.0,0.0,4.0,15.0]
	var turn := Recovery.escape_transition(&"turning",Recovery.TURN_SECONDS-.05,1.0,
		common[0],common[1],common[2],common[3],common[4],common[5],common[6],.1)
	if not bool(turn.failed): failures.append("turning must fail at the shared 7s deadline")
	var advance := Recovery.escape_transition(&"advancing",Recovery.ESCAPE_SECONDS-.05,1.0,
		common[0],common[1],common[2],common[3],common[4],common[5],common[6],.1)
	if bool(advance.failed) or StringName(advance.phase) != &"escape_settling": failures.append("advance must settle at the shared 2.5s deadline")
	var attempt := Recovery.escape_transition(&"turning",0.0,Recovery.ATTEMPT_SECONDS,
		common[0],common[1],common[2],common[3],common[4],common[5],common[6],0.0)
	if not bool(attempt.failed): failures.append("all escape phases must fail at the shared 16s attempt deadline")


func _validate_wiring() -> void:
	var navigation := FileAccess.get_file_as_string("res://src/ai/tank_navigation.gd")
	var predictor := FileAccess.get_file_as_string("res://src/ai/tank_driving_predictor.gd")
	if navigation.count("_calculate_nominal(") < 3:
		failures.append("normal drive and rejoin must call one shared nominal helper")
	if "_predictor.choose_recovery" not in navigation or "[&\"braking\",&\"reversing\",&\"settling\"]" not in navigation:
		failures.append("braking/reversing/settling must enter the recovery predictor gate")
	if "Recovery.escape_transition" not in predictor:
		failures.append("Predictor profile must use Recovery's shared transition")
	if "profile_start_attempt_elapsed" not in predictor:
		failures.append("prediction trace must distinguish its starting attempt time")
