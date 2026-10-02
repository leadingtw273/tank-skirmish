extends "res://tests/rigid_tank_contact_smoke.gd"

const PlayerTank := preload("res://src/actors/rigid_tank/player_rigid_tank.tscn")
const Runtime := preload("res://src/gameplay_runtime.tscn")
const Shot := preload("res://src/combat/shot_event.gd")
var shots: Array = []

func _run() -> void:
	await _ownership_and_combat()
	await _impulse_case(0.0, false)
	await _impulse_case(PI / 2.0, true)
	await _committed_shot_on_death()
	await _wall_guard()
	await _clear()
	print("PLAYER_RIGID_INTEGRATION failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _player(position: Vector3) -> RigidBody3D:
	var tank := PlayerTank.instantiate() as RigidBody3D
	tank.position = position
	world.add_child(tank)
	await _frames(3)
	return tank

func _ownership_and_combat() -> void:
	await _reset()
	_floor()
	var runtime := Runtime.instantiate()
	runtime.startup_player_scene = PlayerTank
	world.add_child(runtime)
	runtime.player_runtime.set_controls_enabled(false)
	await _frames(180)
	var tank := runtime.player_spawn_group.get_node("Tank") as RigidBody3D
	var donor: CharacterBody3D = tank.combat_tank
	var health := tank.get_node("HealthComponent")
	var bodies := 1
	for node in tank.find_children("*", "PhysicsBody3D", true, false):
		if node.collision_layer != 0 or node.collision_mask != 0: bodies += 1
	_expect("unique-owners", bodies == 1 and tank.find_children("*", "HealthComponent", true, false).size() == 1
		and donor.transform.is_equal_approx(Transform3D.IDENTITY) and not donor.tread_animation_player.active,
		"active_bodies=%d donor=%s" % [bodies, donor.transform])
	_expect("bindings", runtime.player_runtime.controlled_tank == tank
		and runtime.combat_runtime.get_registered_shot_sources() == [tank]
		and runtime.track_contact_effects == tank.get_node("TrackContactEffects"), "player/combat/contact")
	var donor_pose := donor.transform
	_expect("dust-idle", runtime.surface_effects._emitters.size() == 4
		and not donor.get_node("TrackContactEffects").is_physics_processing(), "four stable emitters; donor reporter off")
	tank.set_turn_input(1.0)
	await _frames(60)
	_expect("left-command", tank.angular_velocity.dot(tank.global_basis.y) > 0.1, str(tank.angular_velocity))
	var active_dust := 0
	for emitter in runtime.surface_effects._emitters.values():
		if emitter.emission_intensity > 0.0: active_dust += 1
	_expect("dust-turn", active_dust == 4 and runtime.surface_effects._emitters.size() == 4, str(active_dust))
	tank.set_turn_input(0.0)
	await _frames(180)
	var stopped_dust := true
	for emitter in runtime.surface_effects._emitters.values():
		stopped_dust = stopped_dust and is_zero_approx(emitter.emission_intensity)
	_expect("dust-stop", stopped_dust, "no continuing emissions")
	_expect("donor-no-motion", donor.transform.is_equal_approx(donor_pose), str(donor.transform))
	var target: Vector3 = tank.global_position + Vector3(-30, 5, -30)
	for unused in 90:
		tank.aim_turret_at(target, 1.0 / 60.0)
		tank.aim_gun_pitch_at_target(target, 1.0 / 60.0)
		await physics_frame
	var transforms: Array = donor.part_shape_world_transforms()
	var matching := true
	for i in transforms.size():
		matching = matching and (tank.get_node("Tank2Convex%02d" % i) as CollisionShape3D).global_transform.is_equal_approx(transforms[i])
	_expect("aim-collision-sync", matching and absf(tank.turret_pivot.rotation.y) > 0.1
		and tank.mass == 60000.0 and tank.center_of_mass.is_equal_approx(donor.part_geometry.stable_center), str(tank.turret_pivot.rotation))
	shots.clear()
	tank.shot_event_fired.connect(func(event): shots.append(event))
	tank.request_fire()
	tank.request_fire()
	_expect("camera-recoil", runtime.player_runtime.camera_controller._shake_elapsed_seconds == 0.0
		and runtime.player_runtime.camera_controller.camera_shake_pivot.position.length() > 0.0, "existing shot feedback retained")
	_expect("one-projectile", shots.size() == 1 and runtime.combat_runtime.projectiles.get_child_count() == 1
		and shots[0].shooter_rid == tank.get_rid(), "shots=%d" % shots.size())
	await _frames(30)
	tank.request_fire()
	_expect("cooldown-block", shots.size() == 1 and tank.recoil_application_count == 1, str(shots.size()))
	await _frames(32)
	tank.request_fire()
	await _frames(2)
	_expect("cooldown-rearm", shots.size() == 2 and tank.recoil_application_count == 2
		and health.current_health == 100.0 and donor.visual_recoil_tween == null,
		"shots=%d impulses=%d health=%s" % [shots.size(), tank.recoil_application_count, health.current_health])
	# 真投射物朝車殼中央射入，走 CombatRuntime → 根 DamageReceiver → 唯一 health。
	var shooter := StaticBody3D.new()
	shooter.collision_layer = 0
	world.add_child(shooter)
	var center: Vector3 = tank.global_position + Vector3.UP
	runtime.combat_runtime._on_shot_fired(Shot.new(Transform3D(Basis.IDENTITY, center + Vector3(20, 0, 0)), Vector3.LEFT, shooter.get_rid(), 100.0))
	await _frames(30)
	_expect("projectile-damage", health.current_health == 0.0 and donor.get_node("Tank2DamageVisuals")._is_depleted,
		"health=%s" % health.current_health)
	tank.set_movement_input(1.0)
	tank.set_turn_input(1.0)
	tank.request_fire()
	await _frames(5)
	_expect("death-input-gate", shots.size() == 2 and tank._movement_input == 0.0 and tank._turn_input == 0.0, str(shots.size()))
	var replacement = runtime.replace_player_tank(PlayerTank)
	_expect("rigid-wreck-replacement", replacement != null and tank.is_in_group("player_wreck"), "no CharacterBody cast")

func _impulse_case(yaw: float, sleep_first: bool) -> void:
	await _reset()
	var tank := await _player(Vector3(0, 30, 0))
	tank.gravity_scale = 0.0
	tank.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	tank.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	tank.linear_damp = 0.0
	tank.angular_damp = 0.0
	tank.combat_tank.turret_pivot.rotation.y = yaw
	tank._sync_rigid_parts()
	await _frames(3)
	tank.linear_velocity = Vector3.ZERO # 測試初始條件，產品程式不直接改速度。
	tank.angular_velocity = Vector3.ZERO
	await _frames(2)
	if sleep_first:
		tank.sleeping = true
		await _frames(2)
	var state := PhysicsServer3D.body_get_direct_state(tank.get_rid())
	var inverse_tensor := state.inverse_inertia_tensor
	var com: Vector3 = state.transform.origin + state.center_of_mass
	var muzzle: Transform3D = tank.combat_tank.muzzle_point.global_transform
	var impulse: Vector3 = muzzle.basis.x.normalized() * tank.recoil_impulse
	var expected_v: Vector3 = impulse / tank.mass
	var expected_w: Vector3 = inverse_tensor * (muzzle.origin - com).cross(impulse)
	tank.request_fire()
	await _frames(3)
	_expect("impulse-%s" % yaw, tank.linear_velocity.distance_to(expected_v) < 0.002
		and tank.angular_velocity.distance_to(expected_w) < 0.002 and tank.recoil_application_count == 1,
		"v=%s expected=%s w=%s expected=%s" % [tank.linear_velocity, expected_v, tank.angular_velocity, expected_w])
	_expect("no-fake-recoil", tank.combat_tank.visual_recoil_tween == null
		and tank.combat_tank.visual_recoil_pivot.position == tank.combat_tank.visual_recoil_rest_local_position, "pivot remains at rest")

func _wall_guard() -> void:
	await _reset()
	_floor()
	var tank := await _player(Vector3(0, 0.1, 0))
	await _frames(180)
	# 先前 -5m 的牆在砲口極限之外，未形成碰撞；此處讓目標確實穿過牆面。
	_box(Vector3(30, 8, 1), Vector3(0, 4, -3.5))
	var wall := world.get_child(world.get_child_count() - 1)
	await _frames(2)
	_expect("wall-start-clear", not _overlaps_wall(tank, wall), "initial hull/gun do not overlap wall")
	var saw_block := false
	for unused in 120:
		tank.aim_turret_at(Vector3(-20, 2, -30), 1.0 / 60.0)
		var stats: Dictionary = tank.combat_tank.get_motion_guard_attempt_stats(&"turret")
		saw_block = saw_block or (String(stats.get("blocked_reason", "")) not in ["", "clear", "no-op"])
		await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 3, 0), Vector3(0, 3, -10), 129, [tank.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	_expect("wall-no-penetration", not _overlaps_wall(tank, wall), "all 30 shapes remain outside wall")
	_expect("wall-not-self", saw_block and not hit.is_empty() and hit.rid != tank.get_rid(), "yaw=%s blocked=%s muzzle=%s stats=%s" % [tank.turret_pivot.rotation.y, saw_block, tank.muzzle_global_position(), tank.combat_tank.get_motion_guard_attempt_stats(&"turret")])

func _overlaps_wall(tank: RigidBody3D, wall: Node) -> bool:
	for i in tank.full_shape_count:
		var shape := tank.get_node("Tank2Convex%02d" % i) as CollisionShape3D
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.margin = 0.0
		query.exclude = [tank.get_rid()]
		for hit in world.get_world_3d().direct_space_state.intersect_shape(query, 32):
			if hit.collider == wall: return true
	return false

func _committed_shot_on_death() -> void:
	await _reset()
	var tank := await _player(Vector3(0, 30, 0))
	var fired: Array = []
	tank.shot_event_fired.connect(func(event): fired.append(event))
	tank.request_fire()
	tank.get_node("HealthComponent").apply_damage(100.0)
	tank.request_fire()
	await _frames(3)
	_expect("committed-shot-survives-death", fired.size() == 1 and tank.recoil_application_count == 1,
		"shots=%d impulses=%d" % [fired.size(), tank.recoil_application_count])
