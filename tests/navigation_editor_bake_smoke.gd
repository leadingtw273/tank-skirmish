## Editor toolbar-equivalent navigation bake regression smoke.
## The test only bakes a duplicate of the authored NavigationMesh: no resource is saved.
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TANK_SCENES := [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	preload("res://src/actors/tank/variants/tank2/tank2.tscn"),
	preload("res://src/actors/tank/variants/tank3/tank3.tscn"),
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]
const SOURCE_GROUP := &"training_navigation_source"
const GROUPS_WITH_CHILDREN := 1
const ROOT_NODE_CHILDREN := 0
const EXTRA_CLEARANCE := 1.0
const EXPECTED_FOUR_TANK_RADIUS := 3.6427174
const EXPECTED_SOURCE_PATHS := ["Main/World/Ground", "SightBlockers"]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var playtest := PLAYTEST.instantiate() as Node3D
	if playtest == null:
		_finish()
		return
	## Keep AI/controllers inert while preserving the authored static source geometry.
	playtest.process_mode = Node.PROCESS_MODE_DISABLED
	var ground := playtest.get_node_or_null("Main/World/Ground") as StaticBody3D
	var blockers := playtest.get_node_or_null("SightBlockers") as Node3D
	if ground != null:
		ground.process_mode = Node.PROCESS_MODE_ALWAYS
	if blockers != null:
		blockers.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(playtest)
	await physics_frame
	await physics_frame

	var before_layers := _collider_layers(playtest)
	_validate_authored_sources(playtest, ground, blockers)
	var region := playtest.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		_fail("Navigation editor smoke requires NavigationRegion3D with an authored NavigationMesh.")
	else:
		var authored := region.navigation_mesh
		var settings := _settings_snapshot(authored)
		var authored_geometry := _canonical_geometry(authored)
		_validate_resource_contract(authored)
		_validate_legacy_root_children_is_empty(region, authored)
		await _validate_group_parse_and_native_bake(region, authored, settings, authored_geometry)
		await _validate_four_tank_radius(authored)

	var after_layers := _collider_layers(playtest)
	if before_layers != after_layers:
		_fail("Navigation parse/bake must not change any CollisionObject3D layer or mask.")
	playtest.queue_free()
	await process_frame
	_finish()


func _validate_authored_sources(playtest: Node3D, ground: StaticBody3D, blockers: Node3D) -> void:
	if ground == null or blockers == null:
		_fail("Authored training ground must expose Ground and SightBlockers source roots.")
		return
	var source_paths: Array[String] = []
	for source in get_nodes_in_group(SOURCE_GROUP):
		source_paths.append(str(playtest.get_path_to(source)))
	source_paths.sort()
	var expected: Array = EXPECTED_SOURCE_PATHS.duplicate()
	expected.sort()
	if source_paths != expected:
		_fail("Navigation source group must contain only Ground and SightBlockers; got %s." % [source_paths])
	var building_bodies := 0
	for row in blockers.get_children():
		for building in row.get_children():
			if building is StaticBody3D:
				building_bodies += 1
	if building_bodies != 9:
		_fail("SightBlockers must contribute exactly the authored nine building StaticBody3D nodes.")
	if not ground is StaticBody3D or playtest.get_node_or_null("Main/World/Targets") == null \
			or playtest.get_node_or_null("Encounter/Enemy") == null:
		_fail("Smoke fixture must retain ground, training targets, and the encounter tank.")
	for forbidden in [playtest.get_node_or_null("Main/World/Targets"), playtest.get_node_or_null("Encounter/Enemy")]:
		if forbidden != null and forbidden.is_in_group(SOURCE_GROUP):
			_fail("Training targets and encounter tanks must not be navigation bake sources.")


func _validate_resource_contract(mesh: NavigationMesh) -> void:
	if mesh.geometry_source_geometry_mode != GROUPS_WITH_CHILDREN:
		_fail("NavigationMesh must use GROUPS_WITH_CHILDREN (1), not ROOT_NODE_CHILDREN.")
	if mesh.geometry_source_group_name != SOURCE_GROUP:
		_fail("NavigationMesh must read the training_navigation_source group.")
	if mesh.get_polygon_count() <= 0 or mesh.get_vertices().is_empty():
		_fail("Authored NavigationMesh must retain non-empty stored geometry before the editor bake.")


func _validate_legacy_root_children_is_empty(region: NavigationRegion3D, authored: NavigationMesh) -> void:
	var legacy := authored.duplicate() as NavigationMesh
	if legacy == null:
		_fail("Could not duplicate NavigationMesh for ROOT_NODE_CHILDREN regression probe.")
		return
	legacy.geometry_source_geometry_mode = ROOT_NODE_CHILDREN
	legacy.geometry_source_group_name = &""
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(legacy, source, region)
	if not source.get_vertices().is_empty():
		_fail("ROOT_NODE_CHILDREN must reproduce the childless NavigationRegion3D empty-source failure.")


func _validate_group_parse_and_native_bake(region: NavigationRegion3D, authored: NavigationMesh, settings: Dictionary, authored_geometry: PackedStringArray) -> void:
	var baked := authored.duplicate() as NavigationMesh
	if baked == null:
		_fail("Could not duplicate NavigationMesh for editor-equivalent native bake.")
		return
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(baked, source, region)
	if source.get_vertices().is_empty():
		_fail("GROUPS_WITH_CHILDREN must parse non-empty source vertices from Ground and SightBlockers.")
		return
	region.navigation_mesh = baked
	var finished := [false]
	region.bake_finished.connect(func() -> void: finished[0] = true, CONNECT_ONE_SHOT)
	region.bake_navigation_mesh(false)
	for frame in range(120):
		if finished[0]:
			break
		await process_frame
	if not finished[0]:
		_fail("NavigationRegion3D native bake did not emit bake_finished.")
	baked = region.navigation_mesh
	if baked.get_polygon_count() <= 0 or baked.get_vertices().is_empty():
		_fail("Native editor-equivalent bake must produce non-empty navigation geometry.")
	if _settings_snapshot(baked) != settings:
		_fail("Native bake must preserve authored cell, agent, source-mode, group, and filter settings.")
	if _canonical_geometry(baked) != authored_geometry:
		_fail("Native group bake geometry differs from the stored toolbar-baked vertices/polygons.")


func _validate_four_tank_radius(mesh: NavigationMesh) -> void:
	var envelopes: Array[float] = []
	for tank_scene in TANK_SCENES:
		var tank := tank_scene.instantiate() as CharacterBody3D
		if tank == null:
			_fail("Navigation radius probe could not instantiate a tank variant.")
			return
		tank.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(tank)
		await physics_frame
		envelopes.append(_rotation_envelope_upper_bound(tank))
		tank.queue_free()
		await physics_frame
	if envelopes.size() != TANK_SCENES.size():
		_fail("Navigation radius probe must measure all four tank variants.")
		return
	var required_radius := EXTRA_CLEARANCE
	for envelope in envelopes:
		required_radius = maxf(required_radius, envelope + EXTRA_CLEARANCE)
	if absf(required_radius - EXPECTED_FOUR_TANK_RADIUS) > 0.001:
		_fail("Neutral four-tank envelope drifted: measured %.7f, expected %.7f." % [required_radius, EXPECTED_FOUR_TANK_RADIUS])
	if mesh.agent_radius + 0.0001 < required_radius:
		_fail("NavigationMesh radius %.4f is below four-tank safe minimum %.4f; the test never overwrites the resource." % [mesh.agent_radius, required_radius])
	if absf(mesh.agent_radius - EXPECTED_FOUR_TANK_RADIUS) > 0.001:
		_fail("NavigationMesh radius must be the shared %.7fm four-tank envelope; got %.7f." % [EXPECTED_FOUR_TANK_RADIUS, mesh.agent_radius])


func _rotation_envelope_upper_bound(tank: CharacterBody3D) -> float:
	var stable: Vector3 = tank.stable_world_center()
	## 車頭沿 X、側向為 Z；bake clearance is every neutral collision vertex's maximum
	## absolute Z offset from the stable center, plus the caller's 1m. Use the public
	## candidate API so this remains equivalent to root/zero-yaw/zero-pitch bake contract.
	var transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(tank.global_transform, 0.0, 0.0)
	var shape_index := 0
	var maximum := 0.0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var transform: Transform3D = transforms[shape_index]
			shape_index += 1
			for point in shape.points:
				var world_point: Vector3 = transform * point
				maximum = maxf(maximum, absf(world_point.z - stable.z))
	return maximum


func _settings_snapshot(mesh: NavigationMesh) -> Dictionary:
	return {
		"geometry_parsed_geometry_type": mesh.geometry_parsed_geometry_type,
		"geometry_collision_mask": mesh.geometry_collision_mask,
		"geometry_source_geometry_mode": mesh.geometry_source_geometry_mode,
		"geometry_source_group_name": mesh.geometry_source_group_name,
		"cell_size": mesh.cell_size,
		"cell_height": mesh.cell_height,
		"agent_height": mesh.agent_height,
		"agent_radius": mesh.agent_radius,
		"agent_max_climb": mesh.agent_max_climb,
		"agent_max_slope": mesh.agent_max_slope,
		"filter_baking_aabb": mesh.filter_baking_aabb,
	}


func _canonical_geometry(mesh: NavigationMesh) -> PackedStringArray:
	var vertices := mesh.get_vertices()
	var canonical := PackedStringArray()
	for polygon_index in mesh.get_polygon_count():
		var points := PackedStringArray()
		var polygon := mesh.get_polygon(polygon_index)
		for index in polygon:
			var point: Vector3 = vertices[index]
			points.append("%.4f,%.4f,%.4f" % [point.x, point.y, point.z])
		points.sort()
		canonical.append("|".join(points))
	canonical.sort()
	return canonical


func _collider_layers(node: Node) -> Dictionary:
	var layers := {}
	_collect_collider_layers(node, layers)
	return layers


func _collect_collider_layers(node: Node, layers: Dictionary) -> void:
	if node is CollisionObject3D:
		var collider := node as CollisionObject3D
		layers[str(node.get_path())] = Vector2i(collider.collision_layer, collider.collision_mask)
	for child in node.get_children():
		_collect_collider_layers(child, layers)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("NAVIGATION_EDITOR_BAKE PASS: group parse, native bake, stored geometry, settings, radius, and collider layers.")
		quit(0)
		return
	for failure in _failures:
		push_error("NAVIGATION_EDITOR_BAKE FAIL: %s" % failure)
	quit(1)
