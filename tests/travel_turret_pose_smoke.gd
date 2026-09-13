## T2/T3：travel policy 與 Tank2 真實 guarded turret yaw。姿態設定只用來建立起點。
extends SceneTree

const TANK2 := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")
const DT := 1.0 / 60.0
const RETRY_GOAL_DISTANCE := 3.0

class SpyVision extends Node:
	var observer: Node3D
	var visible := false
	var point := Vector3.ZERO
	var far_field_of_view_degrees := 20.0
	func can_see(_target: Node3D) -> bool: return visible
	func visible_target_points(_target: Node3D) -> PackedVector3Array: return PackedVector3Array([point]) if visible else PackedVector3Array()
	func target_world_position(_target: Node3D) -> Vector3: return point

var _failures: Array[String] = []

func _init() -> void: call_deferred("_run")
func _run() -> void:
	await _policy_matrix()
	await _tank2_joint_guard(false)
	await _tank2_joint_guard(true)
	if _failures.is_empty():
		print("TRAVEL_TURRET_POSE_SMOKE PASS: T2 policy matrix and Tank2 guarded joint path.")
		quit(0); return
	for failure in _failures: push_error("TRAVEL_TURRET_POSE_SMOKE FAIL: %s" % failure)
	quit(1)

func _policy_matrix() -> void:
	var f := await _fixture()
	var tank: CharacterBody3D = f.tank
	var ai: Node = f.ai
	var vision: SpyVision = f.vision
	var turret := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var gun := tank.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	## visible: existing turret + gun aim remains active.
	vision.visible = true; vision.point = Vector3(-30.0, 8.0, 20.0)
	await _tick(ai)
	if ai.get("_weapon_pose_mode") != &"visible" or is_zero_approx(gun.rotation.z): _fail("visible target must retain ordinary aim/pitch, not travel.")
	## inspection wins over hidden travel.
	vision.visible = false
	ai.call("inspect_hit_position", tank.stable_world_center() + Vector3.FORWARD * 20.0)
	await _tick(ai)
	if ai.get("_weapon_pose_mode") != &"inspection" or (ai.get("_inspection_direction") as Vector3).is_zero_approx(): _fail("hidden inspection must have priority over travel.")
	## hidden, far, no speed: relative yaw returns and pitch/memory do not change.
	ai.set("_inspection_direction", Vector3.ZERO); ai.set("_last_seen_position", Vector3(-40, 0, 0)); ai.set("_has_last_seen_position", true); ai.set("_navigation_generation", 19)
	tank.forward_speed = 0.0; turret.rotation.y = 0.9; gun.rotation.z = -0.21
	var pitch := gun.rotation.z; var memory: Vector3 = ai.get("_last_seen_position") as Vector3
	await _tick(ai)
	var travel_yaw := turret.rotation.y
	if ai.get("_weapon_pose_mode") != &"travel" or absf(travel_yaw) >= 0.9 or not is_equal_approx(gun.rotation.z, pitch) or not (ai.get("_last_seen_position") as Vector3).is_equal_approx(memory): _fail("hidden far speed=0 must travel relative hull while preserving pitch/last_seen.")
	## Hull rotation demands a fresh relative (not fixed-world) travel direction.
	tank.global_rotation.y = 0.55; turret.rotation.y = 0.7
	await _tick(ai)
	if absf(turret.rotation.y) >= 0.7: _fail("travel target must recompute from current hull orientation.")
	## Terminal query is readonly: same goal true; generation/new goal boundary false; following tick last_seen.
	var nav := ai.get("_navigation") as RefCounted
	var terminal_mode: StringName = &"unreached"
	if nav == null: _fail("CombatAI requires real TankNavigation.")
	else:
		nav.set("_generation", 19); nav.set("_terminal", true); nav.set("_attempt_goal", memory)
		var before := [nav.get("_generation"), nav.get("_terminal"), nav.get("_attempt_goal")]
		if not bool(nav.call("is_terminal_for_goal", memory, 19)) or bool(nav.call("is_terminal_for_goal", memory, 20)) or bool(nav.call("is_terminal_for_goal", memory + Vector3.RIGHT * RETRY_GOAL_DISTANCE, 19)) or before != [nav.get("_generation"), nav.get("_terminal"), nav.get("_attempt_goal")]: _fail("terminal query must be readonly with generation/distance retry boundary.")
		await _tick(ai)
		terminal_mode = ai.get("_weapon_pose_mode")
		if ai.get("_weapon_pose_mode") != &"last_seen": _fail("same-goal terminal must use last_seen on following AI frame.")
	ai.call("set_combat_enabled", false)
	if ai.get("_weapon_pose_mode") != &"idle" or bool(ai.get("_has_last_seen_position")) or not is_zero_approx(tank.movement_command) or not is_zero_approx(tank.turn_command): _fail("combat disable must clear travel intent/memory and commands.")
	ai.call("set_target", null)
	if ai.get("_weapon_pose_mode") != &"idle" or bool(ai.get("_has_last_seen_position")): _fail("target replacement must not retain travel state.")
	print("TRAVEL_POLICY_METRIC speed0_yaw=%.3f hull_relative_yaw=%.3f terminal_mode=%s" % [travel_yaw, turret.rotation.y, terminal_mode])
	await _free(f.root)

func _tank2_joint_guard(with_wall: bool) -> void:
	var world := Node3D.new(); var tank := TANK2.instantiate() as CharacterBody3D
	world.add_child(_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))); world.add_child(tank); root.add_child(world)
	for unused in 3: await physics_frame
	var turret := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D; var gun := tank.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	var start_yaw := 0.9; turret.rotation.y = start_yaw; gun.rotation.z = -0.19; tank.call("_sync_part_collision_shapes"); await physics_frame
	var pitch := gun.rotation.z
	if with_wall:
		var plane := _best_guard_plane(tank, start_yaw, 0.0)
		if not bool(plane.get("valid", false)): _fail("Tank2 wall fixture needs a real changing shape support plane."); await _free(world); return
		world.add_child(_wall_at_plane(plane.normal, (float(plane.start) + float(plane.finish)) * 0.5)); await physics_frame
		if _overlap(tank): _fail("Tank2 wall fixture must start clear."); await _free(world); return
	var blocked := false
	for frame in 120:
		var forward := tank.global_basis * Vector3.LEFT
		tank.aim_turret_at(turret.global_position + forward.normalized() * 100.0, DT); await physics_frame
		var stats: Dictionary = tank.get_motion_guard_attempt_stats(&"turret") as Dictionary
		blocked = blocked or (String(stats.get("blocked_reason", "clear")) not in ["clear", "no-op"])
	var final_yaw := turret.rotation.y; var overlap := _overlap(tank)
	print("TRAVEL_TANK2_GUARD_METRIC wall=%s start=%.3f final=%.3f blocked=%s overlap=%s pitch=%.3f" % [with_wall, start_yaw, final_yaw, blocked, overlap, gun.rotation.z])
	if not is_equal_approx(gun.rotation.z, pitch): _fail("travel yaw must preserve Tank2 pitch (wall=%s)." % with_wall)
	if with_wall and (not blocked or absf(final_yaw) < 0.0001 or overlap): _fail("wall sweep must guard-limit and not insert Tank2 shapes; blocked=%s yaw=%.3f overlap=%s." % [blocked, final_yaw, overlap])
	if not with_wall and (absf(final_yaw) >= absf(start_yaw) or overlap): _fail("unobstructed guarded yaw must converge without overlap.")
	await _free(world)

func _fixture() -> Dictionary:
	var node := Node3D.new(); var tank := TANK2.instantiate() as CharacterBody3D; var target := TANK2.instantiate() as CharacterBody3D; var vision := SpyVision.new(); var ai := TankCombatAI.new()
	target.position = Vector3(-30, 0, 20); target.set_physics_process(false); vision.observer = tank; ai.controlled_tank = tank; ai.vision = vision
	node.add_child(_box(Vector3(0, -0.5, 0), Vector3(160, 1, 160))); node.add_child(tank); node.add_child(target); node.add_child(vision); node.add_child(ai); root.add_child(node)
	ai.set_physics_process(false); ai.call("set_target", target); ai.call("set_combat_enabled", true)
	for unused in 4: await physics_frame
	return {"root": node, "tank": tank, "target": target, "vision": vision, "ai": ai}

func _tick(ai: Node) -> void: ai.call("_physics_process", DT); await physics_frame
func _best_guard_plane(tank: CharacterBody3D, start_yaw: float, end_yaw: float) -> Dictionary:
	var start: Array[Transform3D] = tank.candidate_part_shape_world_transforms(tank.global_transform, start_yaw, 0.19); var finish: Array[Transform3D] = tank.candidate_part_shape_world_transforms(tank.global_transform, end_yaw, 0.19); var best := {"valid": false}
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var a := _support(tank, start, normal); var b := _support(tank, finish, normal)
		if b - a > 0.01 and (not bool(best.get("valid", false)) or b - a > float(best.delta)): best = {"valid": true, "normal": normal, "start": a, "finish": b, "delta": b - a}
	return best
func _support(tank: CharacterBody3D, transforms: Array, normal: Vector3) -> float:
	var i := 0; var result := -INF
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points: result = maxf(result, normal.dot(transforms[i] * point))
			i += 1
	return result
func _overlap(tank: CharacterBody3D) -> bool:
	var space := tank.get_world_3d().direct_space_state
	for child in tank.get_children():
		if not child is CollisionShape3D or child.shape == null: continue
		var query := PhysicsShapeQueryParameters3D.new(); query.shape = child.shape; query.transform = child.global_transform; query.exclude = [tank.get_rid()]; query.collision_mask = tank.collision_mask
		if not space.intersect_shape(query, 1).is_empty(): return true
	return false
func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new(); body.position = position; var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = size; collision.shape = shape; body.add_child(collision); return body
func _wall_at_plane(normal: Vector3, support: float) -> StaticBody3D:
	return _box(normal * (support + 0.2), Vector3(0.4 if absf(normal.x) > 0.5 else 12.0, 5.0, 0.4 if absf(normal.z) > 0.5 else 12.0))
func _free(node: Node) -> void: node.queue_free(); await physics_frame
func _fail(message: String) -> void: _failures.append(message)
