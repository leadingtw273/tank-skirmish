## F2 V1-V3：真 CombatAI / Navigation / Tank wiring 下，可見性切換保留 active recovery；明確取消仍清除。
extends SceneTree

const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const TANK2 := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const DT := 1.0 / 60.0
const FAR_GOAL := Vector3(-60.0, 0.0, 0.0)

class ControlledVision extends Node:
	var observer: Node3D
	var visible := true
	var far_field_of_view_degrees := 90.0

	func can_see(_target: Node3D) -> bool:
		return visible

	func visible_target_points(target: Node3D) -> PackedVector3Array:
		return PackedVector3Array([target.call("stable_world_center") as Vector3]) if visible else PackedVector3Array()

	func target_world_position(target: Node3D) -> Vector3:
		return target.call("stable_world_center") as Vector3


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for direction in [&"visible_to_hidden", &"hidden_to_visible"]:
		for phase in [&"braking", &"reversing", &"turning"]:
			await _validate_visibility_transition(direction, phase)
	await _validate_near_goal_and_followup_updates()
	await _validate_explicit_cancellation_boundaries()
	if _failures.is_empty():
		print("RECOVERY_VISIBILITY_CONTINUATION PASS: V1-V3 visibility continuation and cancellation boundaries hold.")
		quit(0)
		return
	for failure in _failures:
		push_error("RECOVERY_VISIBILITY_CONTINUATION FAIL: %s" % failure)
	quit(1)


func _validate_visibility_transition(direction: StringName, phase: StringName) -> void:
	var fixture := await _make_fixture()
	var ai := fixture.ai as Node
	var vision := fixture.vision as ControlledVision
	var nav := ai.get("_navigation") as RefCounted
	_initialize_ai_goal(ai, FAR_GOAL, direction == &"visible_to_hidden")
	vision.visible = direction == &"hidden_to_visible"
	_initialize_action(nav, phase)
	var before := _action_snapshot(nav)
	await _tick(ai)
	var after := _action_snapshot(nav)
	if StringName(after.phase) != phase or int(after.attempts) != int(before.attempts) \
			or (after.heading as Vector3).distance_to(before.heading as Vector3) > 0.001 \
			or float(after.phase_elapsed) + 0.0001 < float(before.phase_elapsed) \
			or float(after.attempt_elapsed) + 0.0001 < float(before.attempt_elapsed):
		_fail("V1 %s %s must preserve phase/timers/heading/attempt; before=%s after=%s" % [direction, phase, before, after])
	var state := ai.call("get_driving_trace_state") as Dictionary
	if StringName(state.get("status", &"")) != &"recovering":
		_fail("V1 %s %s next public AI step must continue recovery; state=%s" % [direction, phase, state])
	print("V1_METRIC direction=%s phase=%s before=%s after=%s status=%s" % [direction, phase, before, after, state.get("status")])
	await _free_fixture(fixture)


func _validate_near_goal_and_followup_updates() -> void:
	var fixture := await _make_fixture()
	var ai := fixture.ai as Node
	var vision := fixture.vision as ControlledVision
	var nav := ai.get("_navigation") as RefCounted
	var near_goal := Vector3(-0.5, 0.0, 0.0)
	_initialize_ai_goal(ai, near_goal, true)
	vision.visible = false
	_initialize_action(nav, &"reversing")
	await _tick(ai)
	var first := nav.call("get_driving_trace_state") as Dictionary
	if StringName(first.get("status", &"")) != &"recovering" or bool(first.get("terminal", true)):
		_fail("V2 goal inside stop distance must not arrive before active recovery; trace=%s" % first)
	var first_generation := int(first.get("generation", -1))
	var updated_goal := Vector3(-8.0, 0.0, 5.0)
	var command := nav.call("drive", updated_goal, first_generation + 1, 3.0, DT) as Dictionary
	var after := _action_snapshot(nav)
	var trace := nav.call("get_driving_trace_state") as Dictionary
	if StringName(command.get("status", &"")) != &"recovering" or StringName(after.phase) != &"reversing" \
			or int(after.attempts) != 2 or (trace.get("goal", Vector3.ZERO) as Vector3).distance_to(updated_goal) > 0.01:
		_fail("V2 later goal update must retain the same action and make latest goal authoritative; command=%s trace=%s" % [command, trace])
	print("V2_METRIC near_status=%s near_terminal=%s update_status=%s phase=%s attempts=%s latest_goal=%s" % [
		first.get("status"), first.get("terminal"), command.get("status"), after.phase, after.attempts, trace.get("goal")])
	await _free_fixture(fixture)


func _validate_explicit_cancellation_boundaries() -> void:
	var fixture := await _make_fixture()
	var ai := fixture.ai as Node
	var vision := fixture.vision as ControlledVision
	var nav := ai.get("_navigation") as RefCounted
	_initialize_ai_goal(ai, FAR_GOAL, false)
	vision.visible = false
	_initialize_action(nav, &"turning")
	## Hit point is behind the current turret, so the real inspection public entry accepts it.
	var center := (fixture.tank as Node).call("stable_world_center") as Vector3
	ai.call("inspect_hit_position", center + Vector3(60.0, 0.0, 0.0))
	_assert_action_cancelled(nav, "V3 inspection")
	print("V3_METRIC boundary=inspection action=%s" % [_action_snapshot(nav)])

	_initialize_action(nav, &"reversing")
	ai.call("set_combat_enabled", false)
	_assert_full_reset(ai, "V3 combat disable")
	print("V3_METRIC boundary=combat_disable state=%s" % [ai.call("get_driving_trace_state")])
	ai.call("set_combat_enabled", true)

	_initialize_action(ai.get("_navigation") as RefCounted, &"braking")
	var replacement := TANK1.instantiate() as CharacterBody3D
	replacement.set_physics_process(false)
	fixture.root.add_child(replacement)
	ai.set("controlled_tank", replacement)
	_assert_full_reset(ai, "V3 controlled-tank replacement")
	print("V3_METRIC boundary=tank_replacement state=%s" % [ai.call("get_driving_trace_state")])
	await _free_fixture(fixture)


func _initialize_ai_goal(ai: Node, goal: Vector3, was_visible: bool) -> void:
	ai.set("_last_seen_position", goal)
	ai.set("_has_last_seen_position", true)
	ai.set("_was_visible", was_visible)
	ai.set("_pursuing", true)
	ai.set("_navigation_generation", 20)
	var nav := ai.get("_navigation") as RefCounted
	nav.call("drive", goal, 20, 3.0, DT)


func _initialize_action(nav: RefCounted, phase: StringName) -> void:
	## V1 permits finite state initialization; every tested transition then enters through public CombatAI/Navigation calls.
	var recovery := nav.get("_recovery") as RefCounted
	recovery.reset(Vector3.ZERO, Vector3.LEFT)
	recovery.set("episode_active", true)
	recovery.set("attempts", 2)
	recovery.set("phase", phase)
	recovery.set("blocked_origin", Vector3.ZERO)
	recovery.set("blocked_forward", Vector3.LEFT)
	recovery.set("escape_heading", Vector3(0.0, 0.0, -1.0))
	recovery.set("_elapsed", 0.4)
	recovery.set("_attempt_elapsed", 1.2)
	if phase == &"braking":
		(nav.get("_tank") as Node).set("forward_speed", 1.0)
	else:
		(nav.get("_tank") as Node).set("forward_speed", 0.0)


func _action_snapshot(nav: RefCounted) -> Dictionary:
	var recovery := nav.get("_recovery") as RefCounted
	return {"phase": recovery.get("phase"), "attempts": recovery.get("attempts"),
		"heading": recovery.get("escape_heading"), "phase_elapsed": recovery.get("_elapsed"),
		"attempt_elapsed": recovery.get("_attempt_elapsed")}


func _assert_action_cancelled(nav: RefCounted, context: String) -> void:
	var action := _action_snapshot(nav)
	if StringName(action.phase) != &"normal" or int(action.attempts) != 2:
		_fail("%s must cancel action while preserving the active episode budget; action=%s" % [context, action])


func _assert_full_reset(ai: Node, context: String) -> void:
	var state := ai.call("get_driving_trace_state") as Dictionary
	var nav := state.get("navigation", {}) as Dictionary
	if bool(state.get("last_seen_valid", false)) or int(nav.get("attempts", 0)) != 0 \
			or StringName(nav.get("recovery_phase", &"normal")) != &"normal":
		_fail("%s must clear target memory, action and budget; state=%s" % [context, state])


func _make_fixture() -> Dictionary:
	var fixture := Node3D.new()
	var tank := TANK2.instantiate() as CharacterBody3D
	var target := TANK2.instantiate() as CharacterBody3D
	var vision := ControlledVision.new()
	var ai := TankCombatAI.new()
	tank.set_physics_process(false)
	target.position = FAR_GOAL
	target.set_physics_process(false)
	vision.observer = tank
	ai.controlled_tank = tank
	ai.vision = vision
	fixture.add_child(_open_navigation_region())
	fixture.add_child(tank)
	fixture.add_child(target)
	fixture.add_child(vision)
	fixture.add_child(ai)
	root.add_child(fixture)
	ai.set_physics_process(false)
	ai.call("set_target", target)
	ai.call("set_combat_enabled", true)
	for unused in 4:
		await physics_frame
	ai.call("_ensure_navigation")
	return {"root": fixture, "tank": tank, "target": target, "vision": vision, "ai": ai}


func _open_navigation_region() -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(100, 0, -100), Vector3(100, 0, 100), Vector3(-100, 0, 100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	return region


func _tick(ai: Node) -> void:
	ai.call("_physics_process", DT)
	await physics_frame


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.root as Node).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
