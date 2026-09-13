## Recorded f2768 travel posture: a limited pose fixture, not deterministic replay.
## The authored map, live Tank2, Vision, guards, NavigationAgent and recovery stay active.
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const FIXTURE_PATH := "res://tests/fixtures/travel_turret_pose_010203.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _reproduce_recorded_travel_pose()
	if _failures.is_empty():
		print("TRAVEL_TURRET_POSE_REPRO PASS: guarded travel yaw converged while last-seen navigation remained live.")
		quit(0)
		return
	for failure in _failures:
		push_error("TRAVEL_TURRET_POSE_REPRO FAIL: %s" % failure)
	quit(1)


func _reproduce_recorded_travel_pose() -> void:
	var fixture := _load_fixture()
	if fixture.is_empty():
		return
	var scene := PLAYTEST.instantiate() as Node3D
	root.add_child(scene)
	await physics_frame
	var enemy := scene.get_node_or_null("Encounter/Enemy") as CharacterBody3D
	var player := scene.get_node_or_null("Main/Tank") as CharacterBody3D
	var ai := scene.get_node_or_null("Encounter/CombatAI") as Node
	if enemy == null or player == null or ai == null or not enemy.scene_file_path.ends_with("tank2.tscn"):
		_fail("authored scene must expose its live Tank2 Enemy, player and CombatAI.")
		await _free(scene)
		return
	var start := fixture.get("start", {}) as Dictionary
	_pause_scripts(scene)
	_apply_pose(enemy, start.get("enemy", {}) as Dictionary)
	_apply_pose(player, start.get("player", {}) as Dictionary)
	_restore_known_ai_state(ai, enemy, start.get("ai", {}) as Dictionary)
	enemy.set_driving_trace_enabled(true)
	_resume_ai_and_enemy(ai, enemy)
	await physics_frame
	var acceptance := fixture.get("travel_pose_acceptance", {}) as Dictionary
	var observation_frames := int(acceptance.get("observation_frames", 1800))
	var initial_window := int(acceptance.get("initial_window_frames", 180))
	var maximum_travel_yaw := deg_to_rad(float(acceptance.get("maximum_local_yaw_degrees_during_initial_travel", 45.0)))
	var expected_last_seen := _vector(start.get("ai", {}).get("last_seen", []))
	var turret := enemy.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var initial_yaw := absf(turret.rotation.y)
	var minimum_initial_travel_yaw := initial_yaw
	var travel_frames := 0
	var terminal_frame := -1
	var handoff_count := 0
	var maximum_displacement := 0.0
	var first_blockers: Array[String] = []
	var prior_phase := ""
	var checked_memory_frames := 0
	var memory_failure := ""
	var combat_disabled_frame := -1
	var player_depleted_frame := -1
	for frame in observation_frames:
		await physics_frame
		var state := ai.get_driving_trace_state() as Dictionary
		var nav := state.get("navigation", {}) as Dictionary
		var visible := bool(state.get("visible", false))
		var operable := bool(state.get("combat_enabled", false))
		if visible and operable:
			var live_target := ai.get("target") as Node3D
			var vision := ai.get("vision") as Node
			if is_instance_valid(live_target) and is_instance_valid(vision):
				var observed_target := vision.call("target_world_position", live_target) as Vector3
				var visible_memory := state.get("last_seen_position", Vector3.ZERO) as Vector3
				if visible_memory.distance_to(observed_target) <= 0.01:
					expected_last_seen = observed_target
		if operable and not visible and StringName(state.get("weapon_pose_mode", &"")) == &"travel":
			checked_memory_frames += 1
			var remembered := state.get("last_seen_position", Vector3.ZERO) as Vector3
			var nav_goal := nav.get("goal", Vector3.ZERO) as Vector3
			if memory_failure.is_empty() and (not bool(state.get("last_seen_valid", false)) \
					or remembered.distance_to(expected_last_seen) > 0.01 \
					or _horizontal(nav_goal).distance_to(_horizontal(expected_last_seen)) > 0.01):
				memory_failure = "frame=%d remembered=%s expected=%s nav_goal=%s" % [frame, remembered, expected_last_seen, nav_goal]
		if combat_disabled_frame < 0 and not operable:
			combat_disabled_frame = frame
		var live_health := (ai.get("target") as Node3D).get_node_or_null("HealthComponent") if is_instance_valid(ai.get("target")) else null
		if player_depleted_frame < 0 and live_health != null and float(live_health.get("current_health")) <= 0.0:
			player_depleted_frame = frame
		var phase := String(nav.get("recovery_phase", ""))
		if phase != prior_phase:
			print("TRAVEL_TURRET_PHASE frame=%d phase=%s attempts=%d status=%s" % [frame, phase, int(nav.get("attempts", -1)), String(nav.get("status", ""))])
			prior_phase = phase
		var moving_intent := StringName(nav.get("status", &"")) in [&"moving", &"recovering"] and not bool(nav.get("terminal", false))
		if moving_intent and frame < initial_window:
			travel_frames += 1
			minimum_initial_travel_yaw = minf(minimum_initial_travel_yaw, absf(turret.rotation.y))
		var selected := nav.get("selected", {}) as Dictionary
		var stats := selected.get("stats", {}) as Dictionary
		var trace := stats.get("trace", {}) as Dictionary
		for candidate_value in trace.get("candidates", []):
			var candidate := candidate_value as Dictionary
			if candidate.has("first_blocker"):
				var blocker := candidate.get("first_blocker", {}) as Dictionary
				var key := "%s/%s/%s" % [blocker.get("anchor", "unknown"), blocker.get("source", "unknown"), blocker.get("collider_path", "")]
				if key not in first_blockers:
					first_blockers.append(key)
		handoff_count = maxi(handoff_count, int((nav.get("recovery", {}) as Dictionary).get("handoff_count", 0)))
		maximum_displacement = maxf(maximum_displacement, _horizontal(enemy.global_position - _vector(start.get("enemy", {}).get("origin", []))).length())
		if terminal_frame < 0 and bool(nav.get("terminal", false)):
			terminal_frame = frame
	var final_state := ai.get_driving_trace_state() as Dictionary
	print("TRAVEL_TURRET_METRIC initial_yaw_deg=%.2f min_initial_travel_yaw_deg=%.2f travel_frames=%d memory_frames=%d displacement_m=%.3f handoffs=%d terminal_frame=%d player_depleted_frame=%d combat_disabled_frame=%d blockers=%s final=%s" % [rad_to_deg(initial_yaw), rad_to_deg(minimum_initial_travel_yaw), travel_frames, checked_memory_frames, maximum_displacement, handoff_count, terminal_frame, player_depleted_frame, combat_disabled_frame, first_blockers, final_state])
	if checked_memory_frames == 0:
		_fail("fixture must check last-seen memory during at least one operable hidden travel frame.")
	elif not memory_failure.is_empty():
		_fail("travel posture must not overwrite tactical last-seen memory or its navigation goal; %s." % memory_failure)
	elif travel_frames == 0:
		_fail("fixture must expose live pursuit/recovery intent, independent of current speed.")
	elif minimum_initial_travel_yaw > maximum_travel_yaw:
		_fail("while hidden with travel intent, guarded relative yaw must converge toward the hull within the recorded scene allowance; initial=%.2fdeg minimum=%.2fdeg limit=%.2fdeg." % [rad_to_deg(initial_yaw), rad_to_deg(minimum_initial_travel_yaw), rad_to_deg(maximum_travel_yaw)])
	await _free(scene)


func _restore_known_ai_state(ai: Node, enemy: CharacterBody3D, state: Dictionary) -> void:
	var last_seen := _vector(state.get("last_seen", []))
	var generation := int(state.get("generation", 22))
	ai.set("_last_seen_position", last_seen)
	ai.set("_has_last_seen_position", true)
	ai.set("_was_visible", bool(state.get("visible", false)))
	ai.set("_pursuing", bool(state.get("pursuing", false)))
	ai.set("_navigation_generation", generation)
	ai.call("_ensure_navigation")
	var navigation := ai.get("_navigation") as RefCounted
	navigation.set("_generation", generation)
	navigation.set("_goal", _vector(state.get("navigation_goal", [])))
	navigation.set("_attempt_goal", _vector(state.get("navigation_goal", [])))
	navigation.set("_terminal", false)
	navigation.set("_status", &"recovering")
	var recovery := navigation.get("_recovery") as RefCounted
	recovery.set("attempts", int(state.get("attempts", 1)))
	recovery.set("phase", StringName(state.get("recovery_phase", "reversing")))
	recovery.set("blocked_origin", enemy.stable_world_center())
	recovery.set("blocked_forward", enemy.global_basis * Vector3.LEFT)
	recovery.call("reset_progress", enemy.stable_world_center(), enemy.global_basis * Vector3.LEFT)


func _apply_pose(tank: CharacterBody3D, pose: Dictionary) -> void:
	tank.global_transform = Transform3D(Basis(Vector3.UP, float(pose.get("hull_yaw", 0.0))), _vector(pose.get("origin", [])))
	tank.velocity = Vector3.ZERO
	tank.forward_speed = 0.0
	tank.actual_angular_speed = 0.0
	tank.movement_command = 0.0
	tank.turn_command = 0.0
	var turret := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var gun := tank.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	turret.rotation.y = float(pose.get("turret_yaw", 0.0))
	gun.rotation.z = -float(pose.get("gun_pitch", 0.0))
	tank.call("_sync_part_collision_shapes")


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		_fail("cannot open %s." % FIXTURE_PATH)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("fixture must contain one JSON object.")
		return {}
	return parsed as Dictionary


func _vector(value: Variant) -> Vector3:
	var items := value as Array
	return Vector3(float(items[0]), float(items[1]), float(items[2]))


func _pause_scripts(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_pause_scripts(child)


func _resume_ai_and_enemy(ai: Node, enemy: CharacterBody3D) -> void:
	for node in [ai, enemy]:
		node.set_process(true)
		node.set_physics_process(true)


func _horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


func _free(scene: Node) -> void:
	scene.queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
