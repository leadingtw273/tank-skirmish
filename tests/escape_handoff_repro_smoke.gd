## Recorded f2972 recovery handoff: a limited, non-deterministic pose fixture.
## The Tank2 scene, authored blockers, AI, NavigationAgent and controller physics stay live.
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const DT := 1.0 / 60.0
const START := Vector3(41.5591201782227, 0.0, -63.5641975402832)
const PLAYER_START := Vector3(74.1377792358398, 0.0, -75.8793716430664)
const LAST_SEEN := Vector3(52.4104042053223, 1.03960514068604, -87.8649978637695)
const MAX_FRAMES := 1_800 ## Includes 600 physics frames after the safe normal-drive handoff.
const MIN_TURN_RADIANS := deg_to_rad(3.0)
const MIN_ADVANCE_METRES := 0.5
const RETURN_RADIUS_METRES := 0.5
const POST_HANDOFF_FRAMES := 600

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _reproduce_recorded_handoff()
	if _failures.is_empty():
		print("ESCAPE_HANDOFF_REPRO PASS: restored Tank2 escaped without returning to the recorded blocked area or terminal stuck.")
		quit(0)
		return
	for failure in _failures:
		push_error("ESCAPE_HANDOFF_REPRO FAIL: %s" % failure)
	quit(1)


func _reproduce_recorded_handoff() -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	root.add_child(scene)
	await physics_frame
	var enemy := scene.get_node_or_null("Encounter/Enemy") as CharacterBody3D
	var player := scene.get_node_or_null("Main/Tank") as CharacterBody3D
	var ai := scene.get_node_or_null("Encounter/CombatAI") as Node
	if enemy == null or player == null or ai == null or not enemy.scene_file_path.ends_with("tank2.tscn"):
		_fail("author scene must expose its real Tank2 Enemy, player, and CombatAI.")
		await _free(scene)
		return
	## Pause scripts only while applying the one-time recorded initial state.  Collision
	## objects are never disabled, deleted, or replaced; all following movement is live physics.
	_pause_scripts(scene)
	_apply_pose(enemy, START, -0.763230383396149, -1.22139990329742, -0.0283603295683861)
	_apply_pose(player, PLAYER_START, 1.78599977493286, 1.90907824039459, -0.00366183556616306)
	_restore_known_ai_state(ai, enemy)
	enemy.set_driving_trace_enabled(true)
	_resume_ai_and_enemy(ai, enemy)
	await physics_frame
	var restored := ai.get_driving_trace_state() as Dictionary
	if not bool(restored.get("last_seen_valid", false)) or (restored.get("last_seen_position", Vector3.ZERO) as Vector3).distance_to(LAST_SEEN) > 0.01:
		_fail("restore must retain the recorded AI last-seen memory, not replace it with a synthetic predictor target; state=%s." % restored)
		await _free(scene)
		return
	var initial_navigation := restored.get("navigation", {}) as Dictionary
	var initial_recovery := initial_navigation.get("recovery", {}) as Dictionary
	if not _has_recovery_contract(initial_recovery):
		_fail("navigation trace must expose the approved recovery contract before H1 can be measured; recovery=%s." % initial_recovery)
		await _free(scene)
		return
	var initial_handoff_count := int(initial_recovery.get("handoff_count", -1))
	var max_displacement := 0.0
	var escape_heading := Vector3.ZERO
	var advance_origin := Vector3.ZERO
	var max_advance_projection := 0.0
	var max_turn_before_handoff := 0.0
	var handoff_frame := -1
	var handoff_reason := ""
	var handoff_blocked_origin := Vector3.ZERO
	var post_handoff_frames := 0
	var minimum_post_handoff_distance := INF
	var terminal_frames: Array[int] = []
	var start_forward := _forward(enemy)
	var previous_phase := ""
	for frame in MAX_FRAMES:
		await physics_frame
		var state := ai.get_driving_trace_state() as Dictionary
		var nav := state.get("navigation", {}) as Dictionary
		var recovery := nav.get("recovery", {}) as Dictionary
		var phase_key := "%s/%s" % [recovery.get("phase", ""), nav.get("recovery_attempts", -1)]
		if phase_key != previous_phase:
			print("ESCAPE_HANDOFF_PHASE frame=%d state=%s" % [frame, nav])
			previous_phase = phase_key
		if not _has_recovery_contract(recovery):
			_fail("navigation recovery trace contract disappeared during H1; frame=%d recovery=%s." % [frame, recovery])
			break
		var traced_heading := recovery.get("escape_heading", Vector3.ZERO) as Vector3
		if not traced_heading.is_zero_approx():
			escape_heading = traced_heading.normalized()
			advance_origin = recovery.get("advance_origin", advance_origin) as Vector3
		var displacement: float = enemy.stable_world_center().distance_to(START + Vector3.UP * enemy.stable_world_center().y)
		max_displacement = maxf(max_displacement, displacement)
		if not escape_heading.is_zero_approx():
			max_turn_before_handoff = maxf(max_turn_before_handoff, start_forward.angle_to(_forward(enemy))) if handoff_frame < 0 else max_turn_before_handoff
			var true_advance := _horizontal(enemy.stable_world_center() - advance_origin).dot(escape_heading)
			if handoff_frame < 0:
				max_advance_projection = maxf(max_advance_projection, true_advance)
		if bool(nav.get("terminal", false)) and StringName(nav.get("status", &"")) == &"stuck":
			terminal_frames.append(frame)
		if handoff_frame < 0 and int(recovery.get("handoff_count", initial_handoff_count)) > initial_handoff_count:
			handoff_frame = frame
			handoff_reason = String(recovery.get("handoff_reason", ""))
			handoff_blocked_origin = recovery.get("blocked_origin", START) as Vector3
			## H1 normal driving only accepts a fresh nominal-safe handoff.  The trace
			## event is corroborated below by real heading and actual advance position.
			if handoff_reason != "safe_nominal":
				_fail("H1 normal-drive handoff must report safe_nominal, not %s." % handoff_reason)
			var selected := nav.get("selected", {}) as Dictionary
			if bool(nav.get("terminal", true)) or StringName(nav.get("status", &"")) != &"moving" \
					or float(selected.get("movement", 0.0)) <= 0.0:
				_fail("H1 safe_nominal event must be a live non-terminal moving handoff with positive selected movement; nav=%s." % nav)
		if handoff_frame >= 0:
			post_handoff_frames += 1
			minimum_post_handoff_distance = minf(minimum_post_handoff_distance, _horizontal(enemy.stable_world_center() - handoff_blocked_origin).length())
			if post_handoff_frames >= POST_HANDOFF_FRAMES:
				break
	print("ESCAPE_HANDOFF_METRIC max_displacement_m=%.3f turn_deg=%.2f true_advance_m=%.3f handoff_frame=%d reason=%s post_handoff_frames=%d min_post_handoff_distance_m=%.3f terminal_frames=%s forward_speed=%.3f final=%s" % [max_displacement, rad_to_deg(max_turn_before_handoff), max_advance_projection, handoff_frame, handoff_reason, post_handoff_frames, minimum_post_handoff_distance, terminal_frames, float(enemy.forward_speed), ai.get_driving_trace_state()])
	## Preserve the original true-motion baseline: an inert fixture is not evidence of
	## the old regression, while the new H1 must prove turn, forward escape and handoff.
	if max_displacement < 1.5:
		_fail("fixture did not execute the recorded real recovery distance; max_displacement=%.3f." % max_displacement)
	elif handoff_frame < 0:
		_fail("H1 requires a public safe_nominal handoff event after the recorded recovery.")
	elif max_turn_before_handoff <= MIN_TURN_RADIANS:
		_fail("H1 requires >3deg actual Tank2 heading turn before handoff; turn=%.2fdeg." % rad_to_deg(max_turn_before_handoff))
	elif max_advance_projection < MIN_ADVANCE_METRES:
		_fail("H1 requires >=%.1fm actual advance projected along the selected escape heading; advance=%.3fm." % [MIN_ADVANCE_METRES, max_advance_projection])
	elif post_handoff_frames < POST_HANDOFF_FRAMES:
		_fail("H1 requires %d physics frames after safe handoff; observed=%d." % [POST_HANDOFF_FRAMES, post_handoff_frames])
	elif minimum_post_handoff_distance <= RETURN_RADIUS_METRES:
		_fail("H1 forbids returning within %.1fm of blocked origin for the post-handoff window; minimum=%.3fm." % [RETURN_RADIUS_METRES, minimum_post_handoff_distance])
	elif not terminal_frames.is_empty():
		_fail("H1 forbids terminal stuck after safe handoff; terminal_frames=%s." % terminal_frames)
	await _free(scene)


func _restore_known_ai_state(ai: Node, enemy: CharacterBody3D) -> void:
	ai.set("_last_seen_position", LAST_SEEN)
	ai.set("_has_last_seen_position", true)
	ai.set("_was_visible", false)
	ai.set("_pursuing", false)
	ai.set("_navigation_generation", 12)
	ai.call("_ensure_navigation")
	var navigation := ai.get("_navigation") as RefCounted
	navigation.set("_generation", 12)
	navigation.set("_goal", LAST_SEEN)
	navigation.set("_attempt_goal", LAST_SEEN)
	navigation.set("_terminal", false)
	navigation.set("_status", &"recovering")
	var recovery := navigation.get("_recovery") as RefCounted
	recovery.set("attempts", 1)
	recovery.set("phase", &"reversing")
	recovery.set("blocked_origin", enemy.stable_world_center())
	recovery.set("blocked_forward", enemy.global_basis * Vector3.LEFT)
	recovery.call("reset_progress", enemy.stable_world_center(), enemy.global_basis * Vector3.LEFT)


func _apply_pose(tank: CharacterBody3D, origin: Vector3, hull_yaw: float, turret_yaw: float, gun_pitch: float) -> void:
	tank.global_transform = Transform3D(Basis(Vector3.UP, hull_yaw), origin)
	tank.velocity = Vector3.ZERO
	tank.forward_speed = 0.0
	tank.actual_angular_speed = 0.0
	tank.movement_command = 0.0
	tank.turn_command = 0.0
	var turret := tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	var gun := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	if turret == null or gun == null:
		_fail("Tank2 must retain authored turret and gun pivots.")
		return
	turret.rotation.y = turret_yaw
	gun.rotation.z = -gun_pitch
	tank.call("_sync_part_collision_shapes")


func _pause_scripts(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_pause_scripts(child)


func _resume_ai_and_enemy(ai: Node, enemy: CharacterBody3D) -> void:
	for node in [ai, enemy]:
		node.set_process(true)
		node.set_physics_process(true)


func _has_recovery_contract(recovery: Dictionary) -> bool:
	return recovery.has_all(["blocked_origin", "escape_heading", "advance_origin", "advance_metres", "phase", "handoff_count", "handoff_reason", "handoff_frame"])


func _forward(tank: CharacterBody3D) -> Vector3:
	return _horizontal(tank.global_basis * Vector3.LEFT).normalized()


func _horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


func _free(scene: Node) -> void:
	scene.queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
