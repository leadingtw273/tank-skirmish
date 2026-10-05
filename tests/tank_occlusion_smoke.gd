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
		expect(untouched.get_surface_override_material(0) == null, "shared-material other building unchanged")
		expect(mesh.material == source and source.albedo_color == Color(0.4, 0.55, 0.7), "shared source unchanged")
		expect(visual.cast_shadow == original_shadow and building.collision_layer == 1, "shadow and collision unchanged")
		var before: Dictionary = occlusion.call("window_for", tank)
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
	main.queue_free()
	building.queue_free()
	other.queue_free()
	await process_frame
	print("TANK_OCCLUSION_PLAYER ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
