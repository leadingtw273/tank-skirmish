extends SceneTree

const Catalog := preload("res://src/actors/tank/tank_catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func building_at(position: Vector3, mesh: Mesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("occlusion_building")
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 20, 24)
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = position
	return body


func expect_player_outer_windows(occlusion: Node, camera: Camera3D, tank: Node3D, visual: MeshInstance3D) -> void:
	var original_size := camera.size
	var original_radius: float = occlusion.get("window_radius_meters")
	var center: Vector3 = tank.call("stable_world_center")
	for camera_size in [50.0, 100.0]:
		camera.size = camera_size
		var two_meters := camera.unproject_position(center).distance_to(camera.unproject_position(center + camera.global_basis.x.normalized() * 2.0))
		for core_meters in [3.0, 5.0, 9.0]:
			occlusion.set("window_radius_meters", core_meters)
			occlusion.call("_process", 0.25)
			var core: Dictionary = occlusion.call("window_for", tank)
			var outer: Dictionary = occlusion.call("player_fade_window_for", tank)
			expect(core.world_radius == core_meters, "public window remains core radius")
			expect(outer.world_radius == core_meters + 2.0 and outer.core_world_radius == core_meters, "player outer adds exactly 2m")
			expect(is_equal_approx(float(outer.core_radius_pixels), float(core.radius_pixels)), "player retains projected core")
			expect(is_equal_approx(float(outer.radius_pixels) - float(core.radius_pixels), two_meters), "outer ring projects 2m at both camera scales")
			var replacement := visual.get_surface_override_material(0) as ShaderMaterial
			for material in [replacement, replacement.next_pass]:
				expect(is_equal_approx(float(material.get_shader_parameter(&"window_radius_pixels")), float(outer.radius_pixels)), "opaque and soft share player outer radius")
			expect(is_equal_approx(float(replacement.next_pass.get_shader_parameter(&"window_core_radius_pixels")), float(core.radius_pixels)), "soft receives explicit core radius")
			var nearest_material: ShaderMaterial = occlusion.get("_nearest_depth").get("_material")
			expect(is_equal_approx(float(nearest_material.get_shader_parameter(&"window_radius_pixels")), float(outer.radius_pixels)), "nearest-depth uses same player outer radius")
			print("PLAYER_OUTER core_m=", core_meters, " outer_m=", outer.world_radius, " camera_size=", camera_size, " ring_pixels=", float(outer.radius_pixels) - float(core.radius_pixels))
	# Existing five-argument callers reset the optional core and retain the old curve.
	var effect = occlusion.get("_fades")[visual.get_parent()]
	var window: Dictionary = occlusion.call("window_for", tank)
	effect.update_window(window.center, window.radius_pixels, window.viewport_size, 1.0, -INF)
	expect(visual.get_surface_override_material(0).next_pass.get_shader_parameter(&"window_core_radius_pixels") == 0.0, "legacy call clears explicit core")
	occlusion.set("window_radius_meters", original_radius)
	camera.size = original_size
	occlusion.call("_process", 0.25)


func run() -> void:
	var main := load("res://src/gameplay_runtime.tscn").instantiate() as Node3D
	main.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(main)
	var runtime := main.get_node("PlayerRuntime")
	var occlusion := main.get_node("TankOcclusion")
	var camera: Camera3D = occlusion.get("camera")
	var tank: Node3D = runtime.get("controlled_tank")
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.4, 0.55, 0.7)
	source.cull_mode = BaseMaterial3D.CULL_DISABLED
	source.roughness = 0.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3(24, 20, 24)
	mesh.material = source
	var center: Vector3 = tank.call("stable_world_center")
	var screen := camera.unproject_position(center)
	var ray_start := camera.project_ray_origin(screen)
	var building := building_at(ray_start.lerp(center, 0.7), mesh)
	var other := building_at(Vector3(-150, 10, -150), mesh)
	var visual := building.get_node("Visual") as MeshInstance3D
	var untouched := other.get_node("Visual") as MeshInstance3D
	var original_shadow := visual.cast_shadow
	await physics_frame
	await physics_frame
	for vehicle_id in Catalog.IDS:
		tank = main.call("replace_player_vehicle", vehicle_id) as Node3D
		await physics_frame
		expect(occlusion.get("controlled_tank") == tank, "occlusion follows " + String(vehicle_id))
		occlusion.call("_process", 0.25)
		expect(occlusion.call("faded_buildings").has(building), "camera building fades for " + String(vehicle_id))
		expect(visual.get_surface_override_material(0) is ShaderMaterial, "per-instance surface override")
		var replacement := visual.get_surface_override_material(0) as ShaderMaterial
		expect(replacement.next_pass is ShaderMaterial, "continuous transparent next pass")
		expect(replacement.get_shader_parameter(&"window_amount") == 1.0, "persistent window uses spatial gradient")
		expect(untouched.get_surface_override_material(0) == null, "shared-material other building unchanged")
		expect(mesh.material == source and source.albedo_color == Color(0.4, 0.55, 0.7), "shared source unchanged")
		expect(visual.cast_shadow == original_shadow and building.collision_layer == 1, "shadow and collision unchanged")
		var before: Dictionary = occlusion.call("window_for", tank)
		expect(before.world_radius == 5.0, "shared default world radius is 5m")
		if vehicle_id == Catalog.IDS[0]:
			expect_player_outer_windows(occlusion, camera, tank, visual)
		var foreground_depth := camera.to_local(tank.call("stable_world_center")).z
		for point in tank.call("part_world_surface_points"):
			foreground_depth = minf(foreground_depth, camera.to_local(point).z)
		expect(is_equal_approx(float(replacement.get_shader_parameter(&"foreground_depth")), foreground_depth), "foreground includes farthest actual tank part")
		expect(replacement.next_pass.get_shader_parameter(&"foreground_depth") == replacement.get_shader_parameter(&"foreground_depth"), "both passes share foreground plane")
		camera.size *= 0.5
		var zoomed: Dictionary = occlusion.call("window_for", tank)
		expect(is_equal_approx(float(zoomed.radius_pixels), float(before.radius_pixels) * 2.0), "world radius follows zoom")
		camera.size *= 2.0
		var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(screen), center, 129, [tank.get_rid()])
		var hit := tank.get_world_3d().direct_space_state.intersect_ray(query)
		expect(hit.get("collider") == building, "faded building still blocks physical ray")
		runtime.call("set_controlled_tank", null)
		expect(visual.get_surface_override_material(0) == null, "null binding restores original override")
		runtime.call("set_controlled_tank", tank)
		occlusion.call("_process", 0.25)
		building.global_position.x += 200.0
		await physics_frame
		await physics_frame
		occlusion.call("_process", 0.25)
		expect(visual.get_surface_override_material(0) == null, "leaving occlusion restores building")
		building.global_position.x -= 200.0
		await physics_frame
		await physics_frame
		occlusion.call("_process", 0.25)
		tank.get_node("HealthComponent").call("apply_damage", 100000.0)
		occlusion.call("_process", 0.25)
		expect(visual.get_surface_override_material(0) == null, "dead player no longer opens window")
	# A thin foreground building enters the persistent aperture before any
	# body ray hits it. Its transparent material must already be installed.
	tank = main.call("replace_player_vehicle", &"tank2") as Node3D
	building.global_position.x += 200.0
	center = tank.call("stable_world_center")
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.5, 0.5, 0.5)
	edge_mesh.material = source
	var edge := building_at(center + camera.global_basis.z * 12.0 + camera.global_basis.x * 6.7, edge_mesh)
	(edge.get_child(1) as CollisionShape3D).shape = BoxShape3D.new()
	((edge.get_child(1) as CollisionShape3D).shape as BoxShape3D).size = edge_mesh.size
	var edge_visual := edge.get_node("Visual") as MeshInstance3D
	var behind := building_at(center - camera.global_basis.z * 12.0, edge_mesh)
	var behind_visual := behind.get_node("Visual") as MeshInstance3D
	await physics_frame
	await physics_frame
	expect(not occlusion.call("building_occluders", tank).has(edge), "window edge enters before any tank occlusion ray")
	occlusion.call("_process", 0.001)
	expect(occlusion.call("faded_buildings").has(edge), "new outer ring intersection activates without body ray or timer")
	expect(behind_visual.get_surface_override_material(0) == null, "building behind tank depth stays opaque")
	edge.global_position += camera.global_basis.x * 2.0
	occlusion.call("_process", 0.001)
	expect(edge_visual.get_surface_override_material(0) == null, "moving outside window immediately restores both passes")
	edge.global_position -= camera.global_basis.x * 2.0
	occlusion.call("_process", 0.001)
	expect(edge_visual.get_surface_override_material(0) is ShaderMaterial, "candidate cache follows moving building")
	main.queue_free()
	building.queue_free()
	other.queue_free()
	await process_frame
	expect(edge_visual.get_surface_override_material(0) == null, "scene exit restores surviving building next pass")
	edge.queue_free()
	behind.queue_free()
	await process_frame
	print("TANK_OCCLUSION_PLAYER ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
