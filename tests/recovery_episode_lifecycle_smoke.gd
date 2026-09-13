## E4/E5：以真 CombatAI、TankNavigation、Vision 與 Tank 驗證 episode/stop-goal 生命週期。
extends SceneTree

const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const TANK2 := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const TANK3 := preload("res://src/actors/tank/variants/tank3/tank3.tscn")
const DT := 1.0 / 60.0
const LOCKED_GOAL := Vector3(-60.0, 0.0, 0.0)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_e4_locked_stop_goal_and_hidden_memory()
	await _validate_e5_public_lifecycle_resets()
	await _validate_non_stuck_finishes_preserve_episode()
	if _failures.is_empty():
		print("RECOVERY_EPISODE_LIFECYCLE PASS: E4 stop-goal lock and E5 public reset boundaries hold.")
		quit(0)
		return
	for failure in _failures:
		push_error("RECOVERY_EPISODE_LIFECYCLE FAIL: %s" % failure)
	quit(1)


func _validate_e4_locked_stop_goal_and_hidden_memory() -> void:
	var fixture := await _make_fixture()
	if fixture.is_empty():
		return
	var ai := fixture.ai as Node
	var nav := ai.get("_navigation") as RefCounted
	var target := fixture.target as CharacterBody3D
	var wall := _wall_at(Vector3(-30.0, 1.5, 0.0), Vector3(1.0, 5.0, 200.0))
	fixture.root.add_child(wall)
	await physics_frame
	ai.set("_last_seen_position", LOCKED_GOAL)
	ai.set("_has_last_seen_position", true)
	ai.set("_was_visible", false)
	ai.set("_navigation_generation", 10)
	_initialize_terminal_episode(nav, LOCKED_GOAL, 10)
	_assert_locked(nav, LOCKED_GOAL, "first terminal stop must lock its original goal")

	for probe in [
		{"goal": LOCKED_GOAL + Vector3(2.999, 0.0, 0.0), "generation": 10, "label": "<3m"},
		{"goal": LOCKED_GOAL + Vector3(0.0, 20.0, 0.0), "generation": 10, "label": "y-only"},
		{"goal": LOCKED_GOAL, "generation": 999, "label": "generation-only"},
	]:
		nav.call("drive", probe.goal, probe.generation, 3.0, DT)
		_assert_locked(nav, LOCKED_GOAL, "%s change must not unlock or overwrite the first stop goal" % probe.label)

	## Hidden target may move arbitrarily; CombatAI must continue to submit remembered data only.
	target.global_position = Vector3(-80.0, 0.0, 45.0)
	await _tick(ai)
	var hidden := ai.call("get_driving_trace_state") as Dictionary
	if bool(hidden.get("visible", true)) or (hidden.get("last_seen_position", Vector3.ZERO) as Vector3).distance_to(LOCKED_GOAL) > 0.01:
		_fail("E4 hidden AI must preserve remembered goal instead of reading the moved live player; state=%s." % hidden)
	_assert_locked(nav, LOCKED_GOAL, "hidden live-player movement must not unlock the stop goal")

	## Exactly 3 horizontal metres is the public retry boundary and starts a new event.
	var unlocked := nav.call("drive", LOCKED_GOAL + Vector3(3.0, 50.0, 0.0), 1000, 3.0, DT) as Dictionary
	var unlocked_trace := nav.call("get_driving_trace_state") as Dictionary
	if bool(unlocked_trace.get("terminal", true)) or (unlocked_trace.get("recovery", {}) as Dictionary).get("locked_stop_goal") != null \
			or (unlocked_trace.get("goal", Vector3.ZERO) as Vector3).distance_to(LOCKED_GOAL + Vector3(3.0, 0.0, 0.0)) > 0.01:
		_fail("E4 exactly 3m must unlock into a new goal without retaining the old lock; result=%s trace=%s." % [unlocked, unlocked_trace])
	await _free_fixture(fixture)


func _validate_e5_public_lifecycle_resets() -> void:
	var fixture := await _make_fixture()
	if fixture.is_empty():
		return
	var ai := fixture.ai as Node
	var nav := ai.get("_navigation") as RefCounted
	var original_target := fixture.target as CharacterBody3D
	var recovery := nav.get("_recovery") as RefCounted
	recovery.set("attempts", 2)
	recovery.set("episode_active", true)
	recovery.set("phase", &"normal")
	await _tick(ai)
	_assert_episode(nav, 2, "visible transition")
	var wall := _wall_at(Vector3(-30.0, 1.5, 0.0), Vector3(1.0, 5.0, 30.0))
	fixture.root.add_child(wall)
	await physics_frame
	await _tick(ai)
	_assert_episode(nav, 2, "visible-to-hidden transition")
	## Same-instance delivery is deliberately idempotent and must retain the episode.
	ai.call("set_target", original_target)
	_assert_episode(nav, 2, "same target resend")
	_initialize_terminal_episode(nav, LOCKED_GOAL, 20)
	var replacement := TANK3.instantiate() as CharacterBody3D
	replacement.position = Vector3(-80.0, 0.0, 20.0)
	replacement.set_physics_process(false)
	fixture.root.add_child(replacement)
	ai.call("set_target", replacement)
	_assert_reset(ai, "genuine target replacement")

	_initialize_terminal_episode(ai.get("_navigation") as RefCounted, LOCKED_GOAL, 21)
	ai.call("set_combat_enabled", false)
	_assert_reset(ai, "combat disable")
	ai.call("set_combat_enabled", true)

	## Death uses the real target HealthComponent and normal CombatAI operability gate.
	ai.call("set_target", original_target)
	_initialize_terminal_episode(ai.get("_navigation") as RefCounted, LOCKED_GOAL, 22)
	var health := original_target.get_node("HealthComponent")
	health.call("apply_damage", float(health.get("current_health")))
	await _tick(ai)
	_assert_reset(ai, "target death")

	## Controlled-tank replacement exercises the exported setter used by vehicle switching.
	var replacement_tank := TANK1.instantiate() as CharacterBody3D
	replacement_tank.position = Vector3(0.0, 0.0, 30.0)
	replacement_tank.set_physics_process(false)
	fixture.root.add_child(replacement_tank)
	_initialize_terminal_episode(ai.get("_navigation") as RefCounted, LOCKED_GOAL, 23)
	ai.set("controlled_tank", replacement_tank)
	_assert_reset(ai, "controlled-tank replacement")
	await _free_fixture(fixture)


func _validate_non_stuck_finishes_preserve_episode() -> void:
	## These are finite Navigation terminal transitions. E4/E5 above provide the full public wiring;
	## this small table directly guards the common _finish lifecycle shared by all three statuses.
	var fixture := await _make_fixture()
	if fixture.is_empty():
		return
	var nav := (fixture.ai as Node).get("_navigation") as RefCounted
	for status in [&"arrived", &"no_path", &"partial_end"]:
		var recovery := nav.get("_recovery") as RefCounted
		recovery.reset(Vector3.ZERO, Vector3.LEFT)
		recovery.set("attempts", 2)
		recovery.set("episode_active", true)
		nav.call("_finish", status)
		var trace := nav.call("get_driving_trace_state") as Dictionary
		var episode := trace.get("recovery", {}) as Dictionary
		if int(trace.get("attempts", -1)) != 2 or not bool(episode.get("episode_active", false)):
			_fail("finite %s must preserve an unconfirmed episode; trace=%s." % [status, trace])
	await _free_fixture(fixture)


func _initialize_terminal_episode(nav: RefCounted, goal: Vector3, generation: int) -> void:
	## E4 permits one terminal starting snapshot; every transition after this uses real call wiring.
	var recovery := nav.get("_recovery") as RefCounted
	recovery.reset(Vector3.ZERO, Vector3.LEFT)
	recovery.set("attempts", 3)
	recovery.set("episode_active", true)
	recovery.set("phase", &"blocked")
	nav.set("_goal", goal)
	nav.set("_attempt_goal", goal)
	nav.set("_generation", generation)
	nav.set("_terminal", true)
	nav.set("_status", &"stuck")
	nav.set("_locked_stop_goal", goal)
	nav.set("_locked_stop_goal_valid", true)


func _assert_locked(nav: RefCounted, expected: Vector3, context: String) -> void:
	var trace := nav.call("get_driving_trace_state") as Dictionary
	var episode := trace.get("recovery", {}) as Dictionary
	var locked = episode.get("locked_stop_goal")
	if not bool(trace.get("terminal", false)) or StringName(trace.get("status", &"")) != &"stuck" \
			or not locked is Vector3 or (locked as Vector3).distance_to(expected) > 0.01 \
			or int(trace.get("attempts", -1)) != 3 or not bool(episode.get("episode_active", false)):
		_fail("%s; trace=%s." % [context, trace])


func _assert_reset(ai: Node, context: String) -> void:
	var state := ai.call("get_driving_trace_state") as Dictionary
	var nav := state.get("navigation", {}) as Dictionary
	var episode := nav.get("recovery", {}) as Dictionary
	if bool(state.get("last_seen_valid", false)) or int(nav.get("attempts", 0)) != 0 \
			or bool(episode.get("episode_active", false)) or episode.get("locked_stop_goal") != null:
		_fail("E5 %s must fully reset memory, episode and stop lock; state=%s." % [context, state])


func _assert_episode(nav: RefCounted, expected_attempts: int, context: String) -> void:
	var trace := nav.call("get_driving_trace_state") as Dictionary
	var episode := trace.get("recovery", {}) as Dictionary
	if int(trace.get("attempts", -1)) != expected_attempts or not bool(episode.get("episode_active", false)):
		_fail("E5 %s must preserve the active episode; trace=%s." % [context, trace])


func _make_fixture() -> Dictionary:
	var fixture := Node3D.new()
	var region := _open_navigation_region()
	var tank := TANK2.instantiate() as CharacterBody3D
	var target := TANK2.instantiate() as CharacterBody3D
	var vision := TankVision.new()
	var ai := TankCombatAI.new()
	tank.position = Vector3.ZERO
	tank.set_physics_process(false)
	target.position = Vector3(-80.0, 0.0, 0.0)
	target.set_physics_process(false)
	vision.observer = tank
	ai.controlled_tank = tank
	ai.vision = vision
	fixture.add_child(region)
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
	mesh.vertices = PackedVector3Array([Vector3(-160, 0, -160), Vector3(160, 0, -160), Vector3(160, 0, 160), Vector3(-160, 0, 160)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	return region


func _wall_at(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _tick(ai: Node) -> void:
	ai.call("_physics_process", DT)
	await physics_frame


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.root as Node).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
