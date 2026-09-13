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
	var envelopes := await _measure_forward_half_widths()
	if envelopes.is_empty():
		push_error("Navigation bake could not measure forward-facing tank collision widths.")
		quit(1)
		return
	var radius := EXTRA_CLEARANCE
	for envelope in envelopes:
		radius = maxf(radius, envelope + EXTRA_CLEARANCE)
	var region := playtest.get_node("NavigationRegion3D") as NavigationRegion3D
	## 與編輯器工具列共用已儲存資源：來源群組、半徑和所有烘焙參數只有一份。
	var mesh := region.navigation_mesh.duplicate() as NavigationMesh
	if mesh.agent_radius + 0.0001 < radius:
		push_error("NavigationMesh Agent Radius %.4f is smaller than the measured forward-width radius %.4f. Update the shared resource before baking." % [mesh.agent_radius, radius])
		playtest.queue_free()
		quit(1)
		return
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, region)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	if mesh.get_polygon_count() == 0:
		push_error("Navigation bake produced no polygons; the saved resource was not overwritten. Check the shared source group.")
		playtest.queue_free()
		quit(1)
		return
	var save_error := ResourceSaver.save(mesh, OUTPUT)
	playtest.queue_free()
	if save_error != OK:
		push_error("Navigation bake save failed: %s" % save_error)
		quit(1)
		return
	print("NAV_BAKE forward_half_widths=%s clearance=%.2f radius=%.4f polygons=%d output=%s" % [envelopes, EXTRA_CLEARANCE, mesh.agent_radius, mesh.get_polygon_count(), OUTPUT])
	quit(0)

func _measure_forward_half_widths() -> Array[float]:
	var measured: Array[float] = []
	for tank_scene in TANK_SCENES:
		var tank := tank_scene.instantiate() as CharacterBody3D
		## 仍讓 _ready 建立正式碰撞，但不允許 controller 積分位置或砲塔姿態。
		tank.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(tank)
		await physics_frame
		measured.append(_forward_half_width(tank))
		tank.queue_free()
		await physics_frame
	return measured

func _forward_half_width(tank: CharacterBody3D) -> float:
	var stable: Vector3 = tank.stable_world_center()
	## 本專案車頭為 local -X；砲塔／砲管回正後取全部碰撞頂點的橫向界限。
	var lateral := tank.global_transform.basis.z.normalized()
	var transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(tank.global_transform, 0.0, 0.0)
	var shape_index := 0
	var maximum := 0.0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var transform: Transform3D = transforms[shape_index]
			shape_index += 1
			for point in shape.points:
				var world_point: Vector3 = transform * point
				maximum = maxf(maximum, absf((world_point - stable).dot(lateral)))
	return maximum
