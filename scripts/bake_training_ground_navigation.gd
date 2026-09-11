## 固定訓練場導航烘焙：只解析地面與 SightBlockers 的真實 StaticBody3D 碰撞。
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const OUTPUT := "res://src/world/training_ground/training_ground_navigation.tres"
const TANK_SCENES := [preload("res://src/actors/tank/variants/tank1/tank1.tscn"), preload("res://src/actors/tank/variants/tank2/tank2.tscn"), preload("res://src/actors/tank/variants/tank3/tank3.tscn"), preload("res://src/actors/tank/variants/tank4/tank4.tscn")]
const EXTRA_CLEARANCE := 1.0

func _init() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var playtest := PLAYTEST.instantiate() as Node3D
	## 烘焙只讀靜態碰撞；禁止場景 AI／控制器在 await 期間改變幾何姿態。
	playtest.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(playtest)
	await physics_frame
	var envelopes := await _measure_rotation_envelopes()
	if envelopes.is_empty():
		push_error("Navigation bake could not measure tank collision envelopes.")
		quit(1)
		return
	var radius := EXTRA_CLEARANCE
	for envelope in envelopes:
		radius = maxf(radius, envelope + EXTRA_CLEARANCE)
	var mesh := NavigationMesh.new()
	mesh.agent_radius = radius
	mesh.agent_height = 4.0
	mesh.agent_max_climb = 0.5
	mesh.cell_size = 0.25
	mesh.cell_height = 0.1
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 129 ## layer 1 buildings + layer 128 ground
	mesh.filter_baking_aabb = AABB(Vector3(-480.0, -1.0, -472.0), Vector3(960.0, 16.0, 960.0))
	_disable_non_navigation_static_colliders(playtest)
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, playtest)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	var save_error := ResourceSaver.save(mesh, OUTPUT)
	playtest.queue_free()
	if save_error != OK:
		push_error("Navigation bake save failed: %s" % save_error)
		quit(1)
		return
	print("NAV_BAKE native envelopes=%s clearance=%.2f radius=%.4f polygons=%d output=%s" % [envelopes, EXTRA_CLEARANCE, radius, mesh.get_polygon_count(), OUTPUT])
	quit(0)

func _disable_non_navigation_static_colliders(playtest: Node3D) -> void:
	var ground := playtest.get_node_or_null("Main/World/Ground")
	var blockers := playtest.get_node_or_null("SightBlockers")
	for node in _all_static_bodies(playtest):
		var keep := node == ground or (blockers != null and blockers.is_ancestor_of(node))
		if not keep:
			node.collision_layer = 0

func _all_static_bodies(node: Node) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if node is StaticBody3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_all_static_bodies(child))
	return result

func _measure_rotation_envelopes() -> Array[float]:
	var measured: Array[float] = []
	for tank_scene in TANK_SCENES:
		var tank := tank_scene.instantiate() as CharacterBody3D
		## 仍讓 _ready 建立正式碰撞，但不允許 controller 積分位置或砲塔姿態。
		tank.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(tank)
		await physics_frame
		measured.append(_rotation_envelope_upper_bound(tank))
		tank.queue_free()
		await physics_frame
	return measured

func _rotation_envelope_upper_bound(tank: CharacterBody3D) -> float:
	var stable: Vector3 = tank.stable_world_center()
	var turret := tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	var gun_pivot := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var shape_index := 0
	var maximum := 0.0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var transform: Transform3D = transforms[shape_index]
			shape_index += 1
			for point in shape.points:
				var world_point: Vector3 = transform * point
				if part.anchor == &"turret" and turret != null:
					maximum = maxf(maximum, _horizontal_distance(stable, turret.global_position) + _horizontal_distance(turret.global_position, world_point))
				elif part.anchor == &"gun" and turret != null and gun_pivot != null:
					maximum = maxf(maximum, _horizontal_distance(stable, turret.global_position) + _horizontal_distance(turret.global_position, gun_pivot.global_position) + gun_pivot.global_position.distance_to(world_point))
				else:
					maximum = maxf(maximum, _horizontal_distance(stable, world_point))
	return maximum

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
