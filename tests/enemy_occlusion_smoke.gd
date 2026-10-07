extends SceneTree

const Catalog := preload("res://src/actors/tank/tank_catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func building_at(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("occlusion_building")
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.5
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = position
	return body


func expect_model_sources(outline: Node, enemy: Node3D, decoration: MeshInstance3D, initial_models: Array[MeshInstance3D]) -> void:
	var sources: Array = outline.get("_sources")
	var geometry_sources: Array = outline.get("_geometry").get("_sources")
	var effect_count := 0
	for mesh: MeshInstance3D in enemy.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		if mesh.is_in_group(&"effect_mesh"):
			effect_count += 1
			expect(not sources.has(mesh), "effect_mesh excluded from aiming part mask: " + String(mesh.name))
			expect(not geometry_sources.has(mesh), "effect_mesh excluded from geometry detail: " + String(mesh.name))
		elif not initial_models.has(mesh):
			print("POST_CONFIGURE_MESH path=", mesh.get_path(), " captured=", sources.has(mesh))
	for mesh in initial_models:
		expect(sources.has(mesh) and geometry_sources.has(mesh), "actual model source retained: " + String(mesh.name))
	expect(effect_count > 1 and initial_models.size() > 1, "real tank includes both damage FX and model sources")
	expect(sources.has(decoration) and geometry_sources.has(decoration), "unmarked model Quad beneath marked parent remains collected")
	print("MODEL_SOURCE_FILTER effects=", effect_count, " models=", initial_models.size(), " captured=", sources.size())


func run() -> void:
	var main := load("res://src/gameplay_runtime.tscn").instantiate() as Node3D
	main.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(main)
	var occlusion := main.get_node("TankOcclusion")
	var runtime := main.get_node("PlayerRuntime")
	var camera: Camera3D = occlusion.get("camera")
	var enemy := Catalog.instantiate(&"tank2")
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	# Owned fixture distinguishes mesh classification from primitive type and subtree exclusion.
	var effect_fixture := MeshInstance3D.new()
	effect_fixture.name = "EffectFixture"
	effect_fixture.mesh = QuadMesh.new()
	effect_fixture.add_to_group(&"effect_mesh")
	enemy.add_child(effect_fixture)
	var decoration := MeshInstance3D.new()
	decoration.name = "ModelQuadDecoration"
	decoration.mesh = QuadMesh.new()
	effect_fixture.add_child(decoration)
	root.add_child(enemy)
	enemy.global_position = Vector3(0, 0, -12)
	enemy.add_to_group(&"enemy_tank")
	var initial_models: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in enemy.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null and not mesh.is_in_group(&"effect_mesh"):
			initial_models.append(mesh)
	var center: Vector3 = enemy.call("stable_world_center")
	var screen := camera.unproject_position(center)
	var camera_origin := camera.project_ray_origin(screen)
	var camera_wall := building_at(camera_origin.lerp(center, 0.8), Vector3(8, 14, 8))
	await physics_frame
	await physics_frame
	var near_radii := {&"tank1": 80.0, &"tank2": 60.0, &"tank3": 50.0, &"tank4": 40.0}
	var far_radii := {&"tank1": 180.0, &"tank2": 130.0, &"tank3": 100.0, &"tank4": 150.0}
	for vehicle_id in Catalog.IDS:
		var player: Node3D = main.call("replace_player_vehicle", vehicle_id)
		await physics_frame
		var vision: Node = occlusion.get("_vision")
		var state: Dictionary = vision.call("capture_visibility_state")
		expect(vision.get("observer") == player, "vision follows selected " + String(vehicle_id))
		expect(state.near_radius == near_radii[vehicle_id] and state.far_radius == far_radii[vehicle_id], "selected catalog vision settings")
		expect(bool(vision.call("can_see", enemy)), "near enemy has clear player LOS")
		occlusion.call("_process", 0.25)
		expect(occlusion.call("outlined_enemies").has(enemy), "camera wall enables enemy outline")
		if vehicle_id == Catalog.IDS[0]:
			expect_model_sources(occlusion.get("_outlines")[enemy], enemy, decoration, initial_models)
		var player_window: Dictionary = occlusion.call("window_for", player)
		var enemy_window: Dictionary = occlusion.call("window_for", enemy)
		expect(is_equal_approx(player_window.radius_pixels, enemy_window.radius_pixels), "enemy and player share circle radius")
		var wall := building_at(Vector3(0, 10, -2), Vector3(80, 30, 3))
		await physics_frame
		await physics_frame
		expect(not bool(vision.call("can_see", enemy)), "physical building blocks player vision")
		occlusion.call("_process", 0.25)
		expect(occlusion.call("outlined_enemies").is_empty(), "no xray without player LOS")
		wall.queue_free()
		await physics_frame
		await physics_frame
		occlusion.call("_process", 0.25)
		expect(occlusion.call("outlined_enemies").has(enemy), "outline returns after LOS clears")
		camera_wall.global_position.x += 250.0
		await physics_frame
		await physics_frame
		occlusion.call("_process", 0.25)
		expect(occlusion.call("outlined_enemies").is_empty(), "clear camera view needs no outline")
		camera_wall.global_position.x -= 250.0
		await physics_frame
		await physics_frame
		occlusion.call("_process", 0.25)
		runtime.call("set_controlled_tank", null)
		expect(occlusion.call("outlined_enemies").is_empty(), "null player clears overlay")
		runtime.call("set_controlled_tank", player)
		enemy.global_position = Vector3(0, 0, -500)
		await physics_frame
		await physics_frame
		expect(not bool(vision.call("can_see", enemy)), "enemy beyond all catalog ranges")
		occlusion.call("_process", 0.25)
		expect(occlusion.call("outlined_enemies").is_empty(), "out of range does not get outline")
		enemy.global_position = Vector3(0, 0, -12)
		await physics_frame
		await physics_frame
	var player: Node3D = main.call("replace_player_vehicle", &"tank2")
	var vision: Node = occlusion.get("_vision")
	enemy.global_position = player.global_position + Vector3(-60, 0, -60)
	center = enemy.call("stable_world_center")
	player.call("aim_turret_at", center, 10.0)
	camera_wall.global_position = camera.project_ray_origin(camera.unproject_position(center)).lerp(center, 0.8)
	await physics_frame
	await physics_frame
	expect(not occlusion.call("window_for", enemy).is_empty(), "far-cone enemy still has screen window")
	expect(bool(vision.call("can_see", enemy)), "far enemy inside turret cone")
	occlusion.call("_process", 0.25)
	expect(occlusion.call("outlined_enemies").has(enemy), "far cone enables outline")
	var turret := player.call("get_turret_pivot") as Node3D
	var turret_pose := turret.transform
	turret.rotate_y(PI)
	expect(not bool(vision.call("can_see", enemy)), "far enemy outside turret angle")
	occlusion.call("_process", 0.25)
	expect(occlusion.call("outlined_enemies").is_empty(), "outside turret cone disables outline")
	turret.transform = turret_pose
	occlusion.call("_process", 0.25)
	enemy.get_node("HealthComponent").call("apply_damage", 100000.0)
	occlusion.call("_process", 0.25)
	expect(occlusion.call("outlined_enemies").has(enemy), "eligible wreck keeps its outline")
	var wreck_outline: Node = occlusion.get("_outlines")[enemy]
	expect_model_sources(wreck_outline, enemy, decoration, initial_models)
	var line_color: Vector3 = wreck_outline.get("_material").get_shader_parameter(&"line_color")
	expect(line_color.is_equal_approx(Vector3(0.55, 0.55, 0.55)), "wreck body and smoke share neutral gray")
	screen = camera.unproject_position(enemy.call("stable_world_center"))
	expect(wreck_outline.call("pick", screen).is_empty(), "wreck outline cannot become an aim target")
	expect(occlusion.call("resolve_enemy_target", screen).is_empty(), "resolver rejects wreck outline")
	enemy.queue_free()
	await process_frame
	occlusion.call("_process", 0.25)
	expect(occlusion.call("outlined_enemies").is_empty(), "removed wreck clears its outline")
	main.queue_free()
	camera_wall.queue_free()
	await process_frame
	var training := load("res://src/maps/training_ground/training_ground_playtest.tscn").instantiate() as Node3D
	training.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(training)
	var encounter := training.get_node("Encounter")
	expect(encounter.get("enemy").is_in_group(&"enemy_tank"), "training registers actual enemy")
	var previous: Node = encounter.get("enemy")
	encounter.call("_cycle_enemy")
	expect(encounter.get("enemy") != previous and encounter.get("enemy").is_in_group(&"enemy_tank"), "enemy switch registers replacement")
	training.queue_free()
	await process_frame
	print("ENEMY_OCCLUSION ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
