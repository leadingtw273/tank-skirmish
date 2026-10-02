extends "res://tests/player_rigid_integration_smoke.gd"
const Variants := preload("res://tests/player_rigid_variants_contact_smoke.gd")

func _run() -> void:
	for name: String in Variants.PLAYER_SCENES:
		await _reset()
		_floor()
		var scene: PackedScene = Variants.PLAYER_SCENES[name]
		var runtime := Runtime.instantiate()
		runtime.startup_player_scene = scene
		world.add_child(runtime)
		runtime.player_runtime.set_controls_enabled(false)
		await _frames(180)
		var tank = runtime.player_spawn_group.get_node("Tank")
		var donor: Node = tank.combat_tank
		var expected_health: float = {"Tank1": 80.0, "Tank2": 100.0, "Tank3": 120.0, "Tank4": 60.0}[name]
		_expect(name + " health-config", tank.get_node("HealthComponent").maximum_health == expected_health, "existing variant health")
		var active_bodies := 1
		for node in tank.find_children("*", "PhysicsBody3D", true, false):
			if node.collision_layer != 0 or node.collision_mask != 0: active_bodies += 1
		_expect(name + " owners/bindings", active_bodies == 1
			and tank.find_children("*", "HealthComponent", true, false).size() == 1
			and not donor.tread_animation_player.active
			and runtime.player_runtime.controlled_tank == tank
			and runtime.combat_runtime.get_registered_shot_sources() == [tank]
			and runtime.track_contact_effects == tank.get_node("TrackContactEffects"), "single owners and runtime wired")
		var points_match := true
		for index in 4:
			points_match = points_match and tank.get_node("TrackContactEffects").contact_points[index].global_position.is_equal_approx(donor.get_node("TrackContactEffects").contact_points[index].global_position)
		_expect(name + " contact-points", points_match and runtime.surface_effects._emitters.size() == 4, "variant markers")
		shots.clear()
		tank.shot_event_fired.connect(func(event): shots.append(event))
		tank.request_fire()
		tank.request_fire()
		_expect(name + " fire/cooldown", shots.size() == 1 and runtime.combat_runtime.projectiles.get_child_count() == 1
			and shots[0].shooter_rid == tank.get_rid(), "one projectile; root excluded")
		await _frames(3)
		_expect(name + " recoil/self-hit", tank.recoil_application_count == 1
			and tank.get_node("HealthComponent").current_health == expected_health and donor.visual_recoil_tween == null, "one impulse and no self damage")
		var shooter := StaticBody3D.new()
		shooter.collision_layer = 0
		world.add_child(shooter)
		var center: Vector3 = tank.global_position + Vector3.UP
		runtime.combat_runtime._on_shot_fired(Shot.new(Transform3D(Basis.IDENTITY, center + Vector3(20, 0, 0)), Vector3.LEFT, shooter.get_rid(), expected_health))
		await _frames(60)
		_expect(name + " projectile/death", tank.get_node("HealthComponent").current_health == 0.0 and tank._damage_visuals(donor)._is_depleted, "real projectile hit")
		tank.set_movement_input(1.0)
		tank.set_turn_input(1.0)
		tank.request_fire()
		_expect(name + " dead-gates", tank._movement_input == 0.0 and tank._turn_input == 0.0 and shots.size() == 1, "no new input/shot")
		var next = runtime.replace_player_tank(scene)
		_expect(name + " replace", next != null and tank.is_in_group("player_wreck"), "rigid wreck replaced")
	await _clear()
	print("FOUR_RUNTIME failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
