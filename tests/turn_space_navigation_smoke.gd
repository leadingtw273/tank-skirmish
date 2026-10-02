## LEA-176: finite navigation lifecycle contract for turn-space hints.
## Uses a local NavigationRegion fixture; it deliberately does not load a game world.
extends SceneTree

const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const TurnSpace := preload("res://src/ai/tank_turn_space.gd")
const DrivingPredictor := preload("res://src/ai/tank_driving_predictor.gd")


class FakeTank extends Node3D:
	var forward_speed := 0.0
	var tank_mass_tonnes := 40.0
	var brake_force_kilonewtons := 100.0
	var movement_speed := 10.0
	var turning_movement_speed_ratio := 1.0
	var reverse_movement_speed := 3.0
	var actual_angular_speed := 1.0

	func stable_world_center() -> Vector3:
		return global_position

	func get_recovery_contacts() -> Array[Dictionary]:
		return []


class SafePredictor extends DrivingPredictor:
	var handoff_result: Dictionary = {"movement": 0.0, "turn": 0.0, "reason": &"near_only"}

	func choose(_movement: float, _turn: float, _goal: Vector3, _delta: float, _allow_reverse := false, _allow_adjustment := true, _continuation: Dictionary = {}) -> Dictionary:
		return {"movement": 0.4, "turn": 0.0, "reason": &"clear", "contact": false, "intervened": false}

	func choose_recovery(_movement: float, _turn: float, _goal: Vector3, _delta: float) -> Dictionary:
		return {"movement": 0.0, "turn": 0.0, "reason": &"clear", "safe": true, "contact": false, "intervened": false}

	func choose_handoff_step(_movement: float, _turn: float, _goal: Vector3, _delta: float) -> Dictionary:
		var result := handoff_result.duplicate(true)
		# Production always reads both command axes in every handoff outcome.
		# Keep deliberately terse case data from becoming a fake-only API.
		result["movement"] = float(result.get("movement", 0.0))
		result["turn"] = float(result.get("turn", 0.0))
		return result


class FakeTurnSpace extends TurnSpace:
	var ready: Array[Dictionary] = []
	var passed: Array[Dictionary] = []
	var resets: Array[Dictionary] = []
	var planned := false
	var captures := 0

	func setup(_tank: Node3D) -> void:
		pass

	func reset(disable: bool = false, reason: StringName = &"") -> void:
		ready.clear()
		planned = false
		resets.append({"disable": disable, "reason": reason})

	func capture(_path: PackedVector3Array, _map: RID) -> void:
		captures += 1
		planned = true

	func step(_deadline_usec: int, _max_queries: int) -> Dictionary:
		return {"elapsed_usec": 0, "query_count": 0}

	func take_next(_position: Vector3) -> Dictionary:
		return ready.pop_front() if not ready.is_empty() else {}

	func note_passed(hint: Dictionary) -> void:
		passed.append(hint.duplicate(true))

	func get_trace() -> Dictionary:
		return {"fake": true, "remaining": ready.size(), "resets": resets.duplicate(true)}

	func has_plan() -> bool:
		return planned

	func is_disabled() -> bool:
		return not resets.is_empty() and bool(resets.back().disable)


class ContractNavigation extends TankNavigation:
	func _navigation_nominal(_position: Vector3, _goal: Vector3, _stop_distance: float, next: Vector3, _path: PackedVector3Array, _index: int, _finished: bool, _reachable: bool, _speed: float, _forward: Vector3) -> Dictionary:
		return {"movement": 0.4, "turn": 0.0, "braking": false, "status": &"moving", "target": next, "continuation": {}}

	func _rejoin_nominal(_stop_distance: float, hold_turn: float, is_hold: bool) -> Dictionary:
		return {"movement": 0.0 if is_hold else 0.4, "turn": hold_turn if is_hold else 0.0, "braking": false, "status": &"holding" if is_hold else &"moving"}


var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _passed_guide_preserves_episode_and_switches()
	await _terrain_phase_records_pass_before_retarget()
	await _passed_final_guide_returns_to_final_goal()
	await _guide_failure_returns_waiting_final_route()
	await _public_cancel_and_hold_preserve_recovery_attempts()
	await _recovery_handoff_resume_gates()
	await _drive_refresh_and_map_change_cancel_through_real_branches()
	for failure: String in failures:
		push_error("TURN_SPACE_NAVIGATION FAIL: %s" % failure)
	print("TURN_SPACE_NAVIGATION failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _passed_guide_preserves_episode_and_switches() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	var tank: FakeTank = fixture.tank
	var agent: NavigationAgent3D = fixture.agent
	nav.set("_generation", 17); nav.set("_goal", Vector3(30, 0, 0)); nav.set("_attempt_goal", Vector3(30, 0, 0))
	(nav.get("_recovery") as RefCounted).set("attempts", 2)
	(nav.get("_terrain_entry") as RefCounted).set("last_entry", Vector3(4, 0, 4))
	nav.set("_guide", {"point": tank.global_position, "arc": 4.0})
	helper.ready.append({"point": Vector3(8, 0, 0), "arc": 12.0})
	nav.call("_advance_guide")
	var guide: Dictionary = nav.get("_guide")
	_check(guide.get("point") == Vector3(8, 0, 0) and helper.passed.size() == 1, "XZ <= .8 must record a pass and switch to the next ready guide.")
	_check(int(nav.get("_generation")) == 17 and nav.get("_goal") == Vector3(30, 0, 0) and nav.get("_attempt_goal") == Vector3(30, 0, 0), "guide switch must preserve final goal, generation, and attempt goal.")
	_check(int((nav.get("_recovery") as RefCounted).get("attempts")) == 2 and (nav.get("_terrain_entry") as RefCounted).get("last_entry") == Vector3(4, 0, 4), "guide switch must preserve Recovery attempts and TerrainEntry.last_entry.")
	_check(agent.target_position == Vector3(8, 0, 0), "next ready guide must become the temporary agent target.")
	await _free_fixture(fixture)


func _terrain_phase_records_pass_before_retarget() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	var tank: FakeTank = fixture.tank
	var agent: NavigationAgent3D = fixture.agent
	nav.set("_goal", Vector3(30, 0, 0)); nav.set("_guide", {"point": tank.global_position, "arc": 4.0})
	helper.ready.append({"point": Vector3(9, 0, 0), "arc": 12.0})
	(nav.get("_terrain_entry") as RefCounted).set("phase", &"cross")
	agent.target_position = Vector3(1, 0, 0)
	nav.call("_advance_guide")
	_check(bool(nav.get("_guide_passed")) and helper.passed.size() == 1 and agent.target_position == Vector3(1, 0, 0), "non-empty TerrainEntry phase must note the pass but defer retargeting.")
	(nav.get("_terrain_entry") as RefCounted).set("phase", &"")
	nav.call("_advance_guide")
	_check((nav.get("_guide") as Dictionary).get("point") == Vector3(9, 0, 0) and agent.target_position == Vector3(9, 0, 0), "after TerrainEntry clears, the deferred next guide must retarget immediately.")
	await _free_fixture(fixture)


func _passed_final_guide_returns_to_final_goal() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var tank: FakeTank = fixture.tank
	var agent: NavigationAgent3D = fixture.agent
	var goal := Vector3(30, 0, 0)
	nav.set("_goal", goal); nav.set("_terminal", false); nav.set("_guide", {"point": tank.global_position, "arc": 4.0})
	nav.call("_advance_guide")
	_check((nav.get("_guide") as Dictionary).is_empty() and agent.target_position == goal and not bool(nav.get("_terminal")), "passing the final guide must restore final target without treating the guide as final arrival.")
	await _free_fixture(fixture)


func _guide_failure_returns_waiting_final_route() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0})
	var command: Dictionary = nav.call("_guide_route_failed")
	_check(command.get("status") == &"waiting_route" and (nav.get("_guide") as Dictionary).is_empty() and bool(nav.get("_guide_disabled")), "guide partial/no-path must disable hints and wait for the existing final route, never finish arrived.")
	_check(not helper.resets.is_empty() and helper.resets.back().reason == &"guide_route_failed", "guide route failure must retain its cancellation reason.")
	await _free_fixture(fixture)


func _public_cancel_and_hold_preserve_recovery_attempts() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	(nav.get("_recovery") as RefCounted).set("attempts", 2)
	nav.set("_goal", Vector3(30, 0, 0)); nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	nav.hold(0.0, 1.0 / 60.0)
	_check(not helper.resets.is_empty() and helper.resets.back().reason == &"hold" and int((nav.get("_recovery") as RefCounted).get("attempts")) == 2, "hold must cancel only this guide plan and retain Recovery attempts.")
	nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	nav.cancel_movement_preserving_budget()
	_check(helper.resets.back().reason == &"cancel" and int((nav.get("_recovery") as RefCounted).get("attempts")) == 2, "movement cancellation must preserve the finite Recovery episode.")
	nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	(nav.get("_recovery") as RefCounted).set("phase", &"braking")
	nav.call("_drive_recovery", 1.0 / 60.0)
	_check(helper.resets.back().reason == &"recovery" and bool(nav.get("_guide_disabled")) and int((nav.get("_recovery") as RefCounted).get("attempts")) == 2, "Recovery handoff must disable rebuilding without granting a new attempt.")
	nav.call("_start_goal", Vector3(30, 0, 0), 31)
	_check(not bool(nav.get("_guide_disabled")) and int((nav.get("_recovery") as RefCounted).get("attempts")) == 2, "only a real new-goal boundary may re-enable planning, without resetting the Recovery episode.")
	await _free_fixture(fixture)


func _recovery_handoff_resume_gates() -> void:
	await _handoff_near_budget_and_blocked_remain_suspended()
	await _handoff_clear_resumes_without_resetting_episode()
	await _safe_hold_and_terminal_never_resume()
	await _non_recovery_disable_never_revives_on_handoff()


func _handoff_near_budget_and_blocked_remain_suspended() -> void:
	for case_data: Dictionary in [
		{"reason": &"near_only", "movement": 0.4},
		{"reason": &"budget", "movement": 0.0},
		{"reason": &"blocked", "movement": 0.0},
	]:
		var fixture := await _fixture()
		if fixture.is_empty(): return
		var nav: ContractNavigation = fixture.nav
		var helper: FakeTurnSpace = fixture.helper
		var predictor: SafePredictor = fixture.predictor
		_predictor_handoff_result(predictor, case_data)
		_arm_recovery_rejoin(nav, helper)
		var output: Dictionary = nav.call("_drive_recovery", 1.0 / 60.0)
		_check(bool(nav.get("_guides_suspended_for_recovery")) and bool(nav.get("_guide_disabled")) and _resume_reset_count(helper) == 0, "%s handoff result must keep Recovery-suspended guides disabled." % case_data.reason)
		_check(StringName(output.get("status", &"")) == &"recovering", "%s handoff result must remain under Recovery ownership." % case_data.reason)
		await _free_fixture(fixture)


func _handoff_clear_resumes_without_resetting_episode() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	var predictor: SafePredictor = fixture.predictor
	_predictor_handoff_result(predictor, {"reason": &"clear", "movement": 0.4, "turn": 0.0})
	var before := _arm_recovery_rejoin(nav, helper)
	var agent: NavigationAgent3D = fixture.agent
	var verified_native_target := Vector3(11, 0, 3)
	nav.set("_rejoin_route_pending", false); agent.target_position = verified_native_target
	var output: Dictionary = nav.call("_drive_recovery", 1.0 / 60.0)
	var recovery: RefCounted = nav.get("_recovery") as RefCounted
	_check(StringName(output.get("status", &"")) == &"moving" and recovery.get("phase") == &"normal" and int(nav.get("_handoff_count")) == 1, "only clear + positive safe_nominal handoff must actually accept Recovery and return moving.")
	_check(not bool(nav.get("_guides_suspended_for_recovery")) and not bool(nav.get("_guide_disabled")) and _resume_reset_count(helper) == 1 and not helper.planned, "accepted safe_nominal handoff must clear only the helper graph for later rebuild.")
	_check(agent.target_position == verified_native_target, "helper resume must not retarget the already verified native handoff route.")
	_check(nav.get("_goal") == before.goal and int(nav.get("_generation")) == int(before.generation) and nav.get("_attempt_goal") == before.attempt_goal, "resuming hints must not change final goal, generation, or attempt goal.")
	_check(int(recovery.get("attempts")) == int(before.attempts) and bool(recovery.get("episode_active")) == bool(before.episode_active) and (nav.get("_terrain_entry") as RefCounted).get("last_entry") == before.last_entry, "accepted handoff must preserve Recovery episode/attempts and TerrainEntry.last_entry.")
	await _free_fixture(fixture)


func _non_recovery_disable_never_revives_on_handoff() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	var predictor: SafePredictor = fixture.predictor
	nav.set("_goal", Vector3(30, 0, 0)); nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	nav.call("_cancel_guides", &"guide_route_failed", true)
	var recovery: RefCounted = nav.get("_recovery") as RefCounted
	recovery.set("phase", &"rejoining"); recovery.set("positive_advance", 0.5); recovery.set("attempts", 2)
	_predictor_handoff_result(predictor, {"reason": &"clear", "movement": 0.4, "turn": 0.0})
	nav.call("_drive_recovery", 1.0 / 60.0)
	_check(not bool(nav.get("_guides_suspended_for_recovery")) and bool(nav.get("_guide_disabled")) and _resume_reset_count(helper) == 0, "a non-Recovery guide disable must not be revived by a later successful handoff.")
	await _free_fixture(fixture)
	fixture = await _fixture()
	if fixture.is_empty(): return
	nav = fixture.nav; helper = fixture.helper; predictor = fixture.predictor
	nav.set("_goal", Vector3(30, 0, 0))
	## The helper may reject a plan independently before Navigation has a Recovery suspension.
	helper.reset(true, &"helper_unknown")
	_check(helper.is_disabled() and not bool(nav.get("_guides_suspended_for_recovery")), "fixture requires helper-only disable without a Recovery pending flag.")
	var helper_only_recovery: RefCounted = nav.get("_recovery") as RefCounted
	helper_only_recovery.set("phase", &"rejoining"); helper_only_recovery.set("positive_advance", 0.5); helper_only_recovery.set("attempts", 2)
	_predictor_handoff_result(predictor, {"reason": &"clear", "movement": 0.4, "turn": 0.0})
	var helper_only_output: Dictionary = nav.call("_drive_recovery", 1.0 / 60.0)
	_check(StringName(helper_only_output.get("status", &"")) == &"moving" and helper_only_recovery.get("phase") == &"normal", "helper-only fixture must take the real accepted clear handoff branch.")
	_check(helper.is_disabled() and not bool(nav.get("_guides_suspended_for_recovery")) and _resume_reset_count(helper) == 0, "helper-only disable must not manufacture Recovery pending state or be revived by accepted handoff.")
	await _free_fixture(fixture)


func _safe_hold_and_terminal_never_resume() -> void:
	var fixture := await _fixture()
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	var predictor: SafePredictor = fixture.predictor
	_predictor_handoff_result(predictor, {"reason": &"clear", "movement": 0.4, "turn": 0.0})
	_arm_recovery_rejoin(nav, helper)
	var held: Dictionary = nav.call("_drive_recovery", 1.0 / 60.0, &"safe_hold", 0.0, 0.0)
	_check(StringName(held.get("status", &"")) == &"holding" and bool(nav.get("_guide_disabled")) and bool(nav.get("_guides_suspended_for_recovery")) and _resume_reset_count(helper) == 0, "safe_hold acceptance must not resume recovery-suspended hints.")
	await _free_fixture(fixture)
	fixture = await _fixture()
	if fixture.is_empty(): return
	nav = fixture.nav; helper = fixture.helper
	nav.set("_goal", Vector3(30, 0, 0)); nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	nav.call("_cancel_guides", &"recovery", true)
	(nav.get("_recovery") as RefCounted).set("phase", &"blocked")
	var stuck: Dictionary = nav.call("_drive_recovery", 1.0 / 60.0)
	_check(StringName(stuck.get("status", &"")) == &"stuck" and bool(nav.get("_guide_disabled")) and bool(nav.get("_guides_suspended_for_recovery")) and _resume_reset_count(helper) == 0, "terminal stuck must never resume a suspended helper.")
	await _free_fixture(fixture)


func _arm_recovery_rejoin(nav: ContractNavigation, helper: FakeTurnSpace) -> Dictionary:
	var goal := Vector3(30, 0, 0)
	nav.set("_goal", goal); nav.set("_generation", 47); nav.set("_attempt_goal", goal)
	nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	var recovery: RefCounted = nav.get("_recovery") as RefCounted
	recovery.set("phase", &"rejoining"); recovery.set("positive_advance", 0.5); recovery.set("attempts", 2); recovery.set("episode_active", true)
	(nav.get("_terrain_entry") as RefCounted).set("last_entry", Vector3(4, 0, 4))
	# This is the sole producer of the pending flag: it models the earlier
	# budget/recovery cancellation, then the actual handoff is driven below.
	nav.call("_cancel_guides", &"recovery", true)
	_check(bool(nav.get("_guides_suspended_for_recovery")) and bool(nav.get("_guide_disabled")), "recovery cancellation entry must mark a pending recovery suspension once.")
	return {"goal": goal, "generation": 47, "attempt_goal": goal, "attempts": 2, "episode_active": true, "last_entry": Vector3(4, 0, 4)}


func _predictor_handoff_result(predictor: SafePredictor, result: Dictionary) -> void:
	predictor.handoff_result = result.duplicate(true)


func _resume_reset_count(helper: FakeTurnSpace) -> int:
	var count := 0
	for reset: Dictionary in helper.resets:
		if not bool(reset.get("disable", true)):
			count += 1
	return count


func _drive_refresh_and_map_change_cancel_through_real_branches() -> void:
	var fixture := await _fixture(true)
	if fixture.is_empty(): return
	var nav: ContractNavigation = fixture.nav
	var helper: FakeTurnSpace = fixture.helper
	var tank: FakeTank = fixture.tank
	var agent: NavigationAgent3D = fixture.agent
	var goal := Vector3(20, 0, 0)
	# _start_goal is the production episode boundary.  Waiting for its agent path
	# prevents the local async NavigationServer fixture from manufacturing no_path
	# before the refresh branch under test can run.
	nav.call("_start_goal", goal, 9)
	if not await _await_path(agent):
		_check(false, "local fixture must publish a native route before exercising drive refresh")
		await _free_fixture(fixture)
		return
	nav.drive(goal, 9, 0.5, 1.0 / 60.0) # Establish the production map lifecycle.
	if bool(nav.get("_terminal")):
		_check(false, "local fixture route must keep the initial production drive non-terminal")
		await _free_fixture(fixture)
		return
	nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	nav.set("_route_refresh_age", 0.25); nav.set("_last_route_goal", goal)
	var refreshed := goal + Vector3(1.1, 0, 0)
	nav.drive(refreshed, 9, 0.5, 0.0)
	_check(not helper.resets.is_empty() and helper.resets.back().reason == &"goal_refresh" and not bool(nav.get("_guide_disabled")), "same-generation >=1m/.25s refresh must cancel the guide via drive and permit rebuilding for the new final route.")
	nav.set("_guide", {"point": Vector3(8, 0, 0), "arc": 12.0}); helper.planned = true
	var map := tank.get_world_3d().navigation_map
	nav.set("_guide_map_iteration", NavigationServer3D.map_get_iteration_id(map) - 1)
	nav.drive(refreshed, 9, 0.5, 0.0)
	_check(helper.resets.back().reason == &"map_changed", "a changed map iteration must cancel the guide through the production drive branch.")
	await _free_fixture(fixture)


func _fixture(needs_navigation := false) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-10, 0, -10), Vector3(40, 0, -10), Vector3(40, 0, 10), Vector3(-10, 0, 10)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	host.add_child(region)
	var tank := FakeTank.new()
	host.add_child(tank)
	var nav := ContractNavigation.new()
	nav.setup(tank)
	var helper := FakeTurnSpace.new()
	nav.set("_turn_space", helper)
	var predictor := SafePredictor.new()
	predictor.setup(tank)
	nav.set("_predictor", predictor)
	var agent := tank.get_node_or_null("TankNavigationAgent") as NavigationAgent3D
	if agent == null:
		_check(false, "fixture requires TankNavigationAgent")
		await _free_fixture({"host": host, "nav": nav})
		return {}
	if needs_navigation:
		for unused: int in 120:
			if NavigationServer3D.map_get_iteration_id(host.get_world_3d().navigation_map) > 0 and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0:
				break
			await physics_frame
		if NavigationServer3D.map_get_iteration_id(host.get_world_3d().navigation_map) <= 0:
			_check(false, "local NavigationRegion fixture did not become ready")
			await _free_fixture({"host": host, "nav": nav})
			return {}
	return {"host": host, "tank": tank, "nav": nav, "helper": helper, "predictor": predictor, "agent": agent}


func _await_path(agent: NavigationAgent3D) -> bool:
	for unused: int in 60:
		agent.get_next_path_position()
		if not agent.get_current_navigation_path().is_empty():
			return true
		await physics_frame
	return false


func _free_fixture(fixture: Dictionary) -> void:
	var nav := fixture.get("nav") as ContractNavigation
	if nav != null:
		nav.dispose()
	var host := fixture.get("host") as Node3D
	if is_instance_valid(host):
		host.queue_free()
	await process_frame


func _check(condition: bool, detail: String) -> void:
	if not condition:
		failures.append(detail)
