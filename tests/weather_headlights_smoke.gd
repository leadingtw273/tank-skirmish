## 主圖四車車燈的錨點、朝向、換車、死亡與卸載；不替代視覺審查。
extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _expect(label: String, passed: bool) -> void:
	print("WEATHER_HEADLIGHTS ", label, " PASS" if passed else " FAIL")
	if not passed:
		failures.append(label)

func _frames(count: int) -> void:
	for unused: int in count:
		await physics_frame

func _track_inner_limits(tank: Node3D) -> Vector2:
	# 履帶是蒙皮網格，raw Mesh AABB 不能代表實際兩側；使用已烘焙的四相位碰撞包絡。
	var donor: Node3D = tank.get("combat_tank")
	var geometry: Resource = donor.get("part_geometry")
	var limits := Vector2(-INF, INF)
	for id: StringName in [&"left_track", &"right_track"]:
		var part: Resource = geometry.call("part_named", id)
		var anchor: Transform3D = donor.call("_current_anchor_transform", part.get("anchor"))
		var frame: Transform3D = tank.global_transform.affine_inverse() * anchor * part.get("anchor_transform")
		var shapes: Array = part.get("convex_shapes")
		var transforms: Array = part.get("convex_transforms")
		for i: int in shapes.size():
			for point: Vector3 in shapes[i].points:
				var z: float = (frame * transforms[i] * point).z
				if id == &"left_track": limits.y = minf(limits.y, z)
				else: limits.x = maxf(limits.x, z)
	return limits

func _run() -> void:
	var main := load("res://src/main.tscn").instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	var runtime := main.get_node("PlayerRuntime")
	runtime.call("set_controls_enabled", false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process(false)
	await _frames(180)
	var weather := main.get_node("World/MainWeather")
	var previous_lights: Array[WeakRef] = []
	var tank: Node3D
	for id: StringName in [&"tank1", &"tank2", &"tank3", &"tank4"]:
		tank = main.call("replace_player_vehicle", id) as Node3D
		for previous: WeakRef in previous_lights:
			_expect(str(id) + "-old-hidden", not previous.get_ref().visible)
		await _frames(2)
		for previous: WeakRef in previous_lights:
			_expect(str(id) + "-old-freed", previous.get_ref() == null)
		previous_lights.clear()
		var lights: Array = weather.get("player_headlights")
		_expect(str(id) + "-two-variant-anchors", lights.size() == 2 and tank.get_node("Headlights").get_child_count() == 2)
		var track_limits := _track_inner_limits(tank)
		for light: SpotLight3D in lights:
			var direction := -light.global_basis.z
			_expect(str(id) + "-forward-down-shadow", direction.dot(-tank.global_basis.x * cos(deg_to_rad(16.0)) + Vector3.DOWN * sin(deg_to_rad(16.0))) > 0.9999 and light.shadow_enabled and light.spot_range >= 15.0 and light.spot_range <= 20.0)
			_expect(str(id) + "-warm-soft-auxiliary", light.light_color.is_equal_approx(Color(1,.85,.65)) and light.light_energy < 6.0 and light.spot_angle == 42.0 and is_equal_approx(light.spot_angle_attenuation,0.6))
			var anchor := light.get_parent() as Marker3D
			_expect(str(id) + "-inside-track-inner-boundaries", is_finite(track_limits.x) and is_finite(track_limits.y) and track_limits.x < -0.8 and track_limits.y > 0.8 and anchor.position.z > track_limits.x + 0.15 and anchor.position.z < track_limits.y - 0.15)
			var query := PhysicsRayQueryParameters3D.create(anchor.global_position, anchor.global_position + tank.global_basis.x * 2.0, 1)
			query.hit_from_inside = true
			var hit := tank.get_world_3d().direct_space_state.intersect_ray(query)
			_expect(str(id) + "-outside-front-surface", not hit.is_empty() and hit.collider == tank and hit.normal.length() > 0.5)
			var before := light.global_position
			tank.global_position += Vector3(3, 0, 2)
			_expect(str(id) + "-follows-hull", light.global_position.distance_to(before + Vector3(3, 0, 2)) < 0.001)
			tank.global_position -= Vector3(3, 0, 2)
			previous_lights.append(weakref(light))
		var original_basis := tank.basis
		tank.rotate_y(0.7)
		_expect(str(id) + "-turns-with-hull", lights.all(func(light: SpotLight3D): return (-light.global_basis.z).dot(-tank.global_basis.x * cos(deg_to_rad(16.0)) + Vector3.DOWN * sin(deg_to_rad(16.0))) > 0.9999))
		tank.basis = original_basis
	var road_lights := 0
	var shadows := 0
	for lamp in weather.get("lamps"):
		road_lights += int(lamp.light.visible)
		shadows += int(lamp.light.shadow_enabled)
	_expect("all-roads-budget-shadowed-plus-two-headlights", weather.get("lamps").size() == 117 and road_lights == weather.visible_candidates and shadows == road_lights and weather.get("player_headlights").size() == 2)
	(tank.get_node("HealthComponent") as HealthComponent).apply_damage(100000.0)
	_expect("death-hides-before-wreck-free", is_instance_valid(tank) and weather.get("player_headlights").is_empty() and previous_lights.all(func(ref: WeakRef): return not ref.get_ref().visible))
	await _frames(2)
	_expect("death-frees-lights", previous_lights.all(func(ref: WeakRef): return ref.get_ref() == null))
	runtime.call("set_controlled_tank", null)
	runtime.call("set_controlled_tank", tank)
	_expect("dead-car-never-relit", weather.get("player_headlights").is_empty())
	tank = main.call("replace_player_vehicle", &"tank2") as Node3D
	previous_lights.clear()
	for light: SpotLight3D in weather.get("player_headlights"):
		previous_lights.append(weakref(light))
	weather.queue_free()
	await _frames(2)
	_expect("map-unload-cleans-car-children", previous_lights.all(func(ref: WeakRef): return ref.get_ref() == null))
	main.queue_free()
	await _frames(2)
	print("WEATHER_HEADLIGHTS failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
