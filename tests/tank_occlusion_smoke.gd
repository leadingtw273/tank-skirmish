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


func expect_activation_transition(main: Node3D, occlusion: Node, camera: Camera3D, building: StaticBody3D) -> void:
	var tank := main.call("replace_player_vehicle", &"tank2") as Node3D
	var pose := building.global_transform
	var center: Vector3 = tank.call("stable_world_center")
	building.global_position = camera.project_ray_origin(camera.unproject_position(center)).lerp(center, 0.7)
	await physics_frame
	await physics_frame
	occlusion.call("_restore_buildings")
	expect(occlusion.call("building_occluders", tank).has(building), "A2 fixture has actual part camera obstruction")
	var visual := building.get_node("Visual") as MeshInstance3D
	var amounts: Array[float] = []
	for unused in 9:
		occlusion.call("_process", 0.02)
		amounts.append(float(occlusion.get("_amounts").get(building, 0.0)))
	expect(amounts[0] > 0.0 and amounts[0] < 1.0, "A2 first contact begins between zero and one")
	for index in range(1, amounts.size()):
		expect(amounts[index] > amounts[index - 1] and amounts[index] - amounts[index - 1] <= 0.112,
			"A2 fade-in is continuous and bounded at frame " + str(index))
	expect(is_equal_approx(amounts[-1], 1.0), "A2 fade-in reaches one at original .18s")
	var replacement := visual.get_surface_override_material(0) as ShaderMaterial
	building.global_position += Vector3(200, 0, 0)
	await physics_frame
	await physics_frame
	amounts.clear()
	for frame in 9:
		occlusion.call("_process", 0.02)
		amounts.append(float(occlusion.get("_amounts").get(building, 0.0)))
		if frame < 8:
			expect(visual.get_surface_override_material(0) == replacement and replacement.next_pass != null,
				"A2 loss retains both passes until amount zero")
			expect(is_equal_approx(float(replacement.get_shader_parameter(&"window_amount")), amounts[-1])
				and is_equal_approx(float(replacement.next_pass.get_shader_parameter(&"window_amount")), amounts[-1]),
				"A2 both passes receive the same exit amount")
	expect(amounts[0] > 0.0 and amounts[0] < 1.0, "A2 first exit frame is a partial fade")
	for index in range(1, amounts.size()):
		expect(amounts[index] < amounts[index - 1] and amounts[index - 1] - amounts[index] <= 0.112,
			"A2 fade-out is continuous and bounded at frame " + str(index))
	expect(is_zero_approx(amounts[-1]) and visual.get_surface_override_material(0) == null
		and not occlusion.get("_fades").has(building), "A2 .18s exit restores material and removes next pass")
	print("ACTIVATION_TIMING exit_amounts=", amounts)
	building.global_transform = pose
	await physics_frame
	await physics_frame


func actual_surface_buildings(occlusion: Node, camera: Camera3D, tank: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var points: PackedVector3Array = tank.call("part_world_surface_points")
	points.append(tank.call("stable_world_center"))
	for point in points:
		var screen := camera.unproject_position(point)
		if camera.is_position_behind(point) or not camera.get_viewport().get_visible_rect().has_point(screen):
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(screen), point, 129, [tank.get_rid()])
		query.hit_from_inside = true
		var hit := tank.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var building: Node3D = occlusion.call("_building_for", hit.collider)
			if building != null and not result.has(building): result.append(building)
	return result


func stop_fixture(node: Node) -> void:
	# Keep collision objects in physics while holding the real map pose still.
	node.set_process(false)
	node.set_physics_process(false)
	if node is RigidBody3D: node.freeze = true
	for child in node.get_children(): stop_fixture(child)


func expect_training_positions() -> void:
	# Reuse the twelve real training poses of the original regression evidence.
	root.size = Vector2i(960, 580)
	root.content_scale_size = Vector2i(1920, 1160)
	await process_frame
	var training := load("res://src/maps/training_ground/training_ground_playtest.tscn").instantiate() as Node3D
	root.add_child(training)
	var main := training.get_node("Main")
	var tank := main.call("replace_player_vehicle", &"tank1") as Node3D
	stop_fixture(training)
	var occlusion := main.get_node("TankOcclusion")
	var rig: Node3D = main.get("player_runtime").get("camera_controller")
	var camera: Camera3D = rig.get("camera")
	camera.size = 35.0
	rig.global_position = Vector3(42, 0, -1) + (rig.get("follow_target_offset") as Vector3) + Vector3(-8, 0, -21)
	var samples := [["start", 42, -1, -PI/2], ["away", 44, 1, -PI/2], ["outside", 46, 3, -PI/2],
		["south-corner", 42, 3, -PI/2], ["corner", 40, 5, -PI/2], ["south-wall", 37, 5, -PI/2],
		["south-mid", 34, 5, -PI/2], ["south-west", 31, 5, -PI/2], ["east-wall", 42, -4, -PI/2],
		["east-north", 42, -8, -PI/2], ["east-back", 42, -12, -PI/2], ["start-turn", 42, -1, 0.0]]
	var exposed := 0
	var obstructed := 0
	for sample in samples:
		tank.global_position = Vector3(sample[1], 0.01, sample[2])
		tank.global_rotation = Vector3(0, sample[3], 0)
		tank.get("turret_pivot").rotation = Vector3.ZERO
		tank.call("_sync_rigid_parts")
		await physics_frame
		await physics_frame
		var actual := actual_surface_buildings(occlusion, camera, tank)
		for unused in 12: occlusion.call("_process", 1.0 / 60.0)
		var faded: Array = occlusion.call("faded_buildings")
		if actual.is_empty():
			exposed += 1
			expect(faded.is_empty(), "A1 actual all-part rays zero stays opaque: " + str(sample[0]))
			for candidate in get_nodes_in_group("occlusion_building"):
				for child in candidate.find_children("*", "MeshInstance3D", true, false):
					if child.mesh != null:
						for surface in child.mesh.get_surface_count():
							expect(not (child.get_surface_override_material(surface) is ShaderMaterial),
								"A1 exposed training material restored: " + str(sample[0]))
		else:
			obstructed += 1
			expect(not faded.is_empty(), "A1 actual part obstruction activates: " + str(sample[0]))
			for building in faded: expect(actual.has(building), "A1 no unrelated side building: " + str(sample[0]))
		print("TRAINING_ACTIVATION ", sample[0], " actual=", actual.size(), " faded=", faded.size())
	expect(exposed > 0 and obstructed > 0, "A1 twelve real positions cover exposure and actual obstruction")
	training.queue_free()
	await process_frame


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


func expect_player_wreck_flow(main: Node3D, occlusion: Node, camera: Camera3D, building: StaticBody3D, source: Material) -> void:
	var wreck := main.call("replace_player_vehicle", &"tank2") as Node3D
	# Isolate this finite tank2 fixture from wrecks retained by the original catalog loop.
	for previous: Node3D in get_nodes_in_group(&"player_wreck"):
		previous.global_position += Vector3(500, 0, 0)
	var center: Vector3 = wreck.call("stable_world_center")
	var building_pose := building.global_transform
	building.global_position = camera.project_ray_origin(camera.unproject_position(center)).lerp(center, 0.7)
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	expect(occlusion.call("faded_buildings").has(building), "live tank2 retains original player fade")
	var spawn_pose := wreck.global_transform
	wreck.get_node("HealthComponent").call("apply_damage", 100000.0)
	occlusion.call("_process", 0.25)
	var line: Node = occlusion.get("_player_wreck_outlines").get(wreck)
	expect(line != null and bool(line.get("active")), "controlled dead tank2 has its own active outline")
	expect(building.get_node("Visual").get_surface_override_material(0) == null, "controlled death restores building material")
	if line == null:
		return
	var core: Dictionary = occlusion.call("window_for", wreck)
	var color: Vector3 = line.get("_material").get_shader_parameter(&"line_color")
	expect(color.is_equal_approx(Vector3(0.55, 0.55, 0.55)), "player wreck reuses neutral body and smoke color")
	expect(core.world_radius == 5.0 and is_equal_approx(float(line.get("_radius")), float(core.radius_pixels)), "player wreck uses core 5m rather than outer 7m")
	var sources: Array = line.get("_sources")
	expect(not sources.is_empty() and sources == line.get("_geometry").get("_sources"), "player wreck retains real shared model and geometry sources")
	for mesh: MeshInstance3D in sources:
		expect(not mesh.is_in_group(&"effect_mesh"), "player wreck excludes FX mesh")
	expect(line.call("pick", core.center).is_empty() and occlusion.call("resolve_enemy_target", core.center).is_empty(), "player wreck is never an enemy aim target")
	# Public runtime entry tests real replacement/binding/group order, not the training 3s timer.
	var observer := main.call("respawn_player_vehicle", &"tank2", spawn_pose) as Node3D
	expect(observer != null and wreck.is_in_group(&"player_wreck") and not wreck.is_in_group(&"enemy_tank"), "public respawn retains only player wreck classification")
	expect(occlusion.get("_player_wreck_outlines").is_empty(), "respawn binding clears owned old renderers before next frame")
	if observer == null:
		return
	observer.global_position = wreck.global_position + Vector3(0, 0, 12)
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	line = occlusion.get("_player_wreck_outlines").get(wreck)
	expect(line != null and bool(line.get("active")), "new live observer can see eligible retained player wreck")
	expect(occlusion.call("player_fade_window_for", observer).world_radius == 7.0, "respawned live player retains 5m plus 2m fade window")
	expect(not occlusion.call("outlined_enemies").has(wreck), "retained player wreck stays outside enemy resolver dictionary")
	if line == null:
		return
	building.global_position.x += 250.0
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	expect(not bool(line.get("active")), "unoccluded retained wreck has no xray")
	building.global_position.x -= 250.0
	observer.global_position = wreck.global_position + Vector3(0, 0, 500)
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	expect(not bool(line.get("active")), "retained wreck beyond current observer range is hidden")
	observer.global_position = wreck.global_position + Vector3(0, 0, 80)
	observer.call("aim_turret_at", wreck.call("stable_world_center"), 10.0)
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	expect(bool(line.get("active")), "retained wreck inside current far cone returns")
	var turret := observer.call("get_turret_pivot") as Node3D
	var turret_pose := turret.transform
	turret.rotate_y(PI)
	occlusion.call("_process", 0.25)
	expect(not bool(line.get("active")), "retained wreck outside current far cone is hidden")
	turret.transform = turret_pose
	observer.global_position = wreck.global_position + Vector3(0, 0, 12)
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	expect(bool(line.get("active")), "retained wreck recovers when qualified again")
	var enemy := Catalog.instantiate(&"tank2")
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(enemy)
	enemy.global_position = observer.global_position + Vector3(12, 0, -12)
	enemy.add_to_group(&"enemy_tank")
	var enemy_center: Vector3 = enemy.call("stable_world_center")
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(8, 14, 8)
	wall_mesh.material = source
	var enemy_wall := building_at(camera.project_ray_origin(camera.unproject_position(enemy_center)).lerp(enemy_center, 0.7), wall_mesh)
	((enemy_wall.get_child(1) as CollisionShape3D).shape as BoxShape3D).size = wall_mesh.size
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	expect(occlusion.call("outlined_enemies").has(enemy), "live observer retains qualified real enemy outline")
	observer.get_node("HealthComponent").call("apply_damage", 100000.0)
	occlusion.call("_process", 0.25)
	var dead_candidates: Dictionary = occlusion.get("_player_wreck_outlines")
	expect(dead_candidates.size() == 1 and dead_candidates.has(observer), "dead observer renders only its controlled wreck, never old wrecks")
	expect(occlusion.call("outlined_enemies").is_empty(), "dead observer clears previously visible enemy information")
	var replacement := main.call("respawn_player_vehicle", &"tank2", spawn_pose) as Node3D
	replacement.global_position = wreck.global_position + Vector3(0, 0, 12)
	await physics_frame
	await physics_frame
	occlusion.call("_process", 0.25)
	var removed_id := wreck.get_instance_id()
	wreck.queue_free()
	await process_frame
	occlusion.call("_process", 0.25)
	for remaining: Node3D in occlusion.get("_player_wreck_outlines"):
		expect(remaining.get_instance_id() != removed_id, "removed retained wreck clears its owned renderer")
	var runtime := main.get_node("PlayerRuntime")
	runtime.call("set_controlled_tank", null)
	expect(occlusion.get("_player_wreck_outlines").is_empty(), "null binding clears every player wreck renderer")
	runtime.call("set_controlled_tank", replacement)
	main.call("replace_player_vehicle", &"tank2")
	expect(occlusion.get("_player_wreck_outlines").is_empty(), "vehicle replacement clears owned player wreck renderers")
	enemy.queue_free()
	enemy_wall.queue_free()
	building.global_transform = building_pose
	await process_frame
	print("PLAYER_WRECK_FIXTURE public_respawn_entry_only=true normal_three_second_timer_tested=false")


func run() -> void:
	# Formal canvas_items configuration: render 1280x720, logical 1920x1080.
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_factor = 1.0
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.scaling_3d_scale = 1.0
	await process_frame
	expect(root.size == Vector2i(1280, 720) and root.get_visible_rect().size.is_equal_approx(Vector2(1920, 1080)), "formal canvas_items window fixture")
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
			var nearest_viewport: SubViewport = occlusion.get("_nearest_depth").get("_viewport")
			expect(nearest_viewport.size == Vector2i(1280, 720), "nearest capture uses actual 1280x720 render grid")
			print("NEAREST_CAPTURE window=", root.size, " logical=", root.get_visible_rect().size, " capture=", nearest_viewport.size)
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
	await expect_activation_transition(main, occlusion, camera, building)
	await expect_player_wreck_flow(main, occlusion, camera, building, source)
	# 本輪明示取代舊 P2 的預先啟動：外環交窗但沒有部件實遮擋，必須保持 opaque。
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
	expect(not occlusion.call("faded_buildings").has(edge) and edge_visual.get_surface_override_material(0) == null,
		"A1 outer ring intersection alone stays opaque without actual part obstruction")
	expect(behind_visual.get_surface_override_material(0) == null, "building behind tank depth stays opaque")
	edge.global_position += camera.global_basis.x * 2.0
	occlusion.call("_process", 0.001)
	expect(edge_visual.get_surface_override_material(0) == null, "moving outside window immediately restores both passes")
	edge.global_position -= camera.global_basis.x * 2.0
	occlusion.call("_process", 0.001)
	expect(edge_visual.get_surface_override_material(0) == null, "A1 moving side candidate stays opaque without part obstruction")
	main.queue_free()
	building.queue_free()
	other.queue_free()
	await process_frame
	expect(edge_visual.get_surface_override_material(0) == null, "scene exit restores surviving building next pass")
	edge.queue_free()
	behind.queue_free()
	await process_frame
	await expect_training_positions()
	print("TANK_OCCLUSION_PLAYER ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
