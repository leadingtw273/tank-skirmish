## 將四款可信本機車型在中性 skeleton pose 的實際 mesh 預烘焙為部位凸形資源。
## 執行：Godot --path . --script res://scripts/bake_tank_parts.gd
extends SceneTree

const VARIANTS := [
	{"scene": "res://src/actors/tank/variants/tank1/tank1.tscn", "output": "res://src/actors/tank/variants/tank1/tank1_part_geometry.tres", "upper": "", "stable_center": Vector3(0, 1.519596, 0)},
	{"scene": "res://src/actors/tank/variants/tank2/tank2.tscn", "output": "res://src/actors/tank/variants/tank2/tank2_part_geometry.tres", "upper": "turret", "stable_center": Vector3(0, 1.039605154183, 0)},
	{"scene": "res://src/actors/tank/variants/tank3/tank3.tscn", "output": "res://src/actors/tank/variants/tank3/tank3_part_geometry.tres", "upper": "turret", "stable_center": Vector3(0, 1.673166, 0)},
	{"scene": "res://src/actors/tank/variants/tank4/tank4.tscn", "output": "res://src/actors/tank/variants/tank4/tank4_part_geometry.tres", "upper": "fixed_upper_hull", "stable_center": Vector3(0, 1.34941, 0)},
]
const MAX_CONVEX_SHAPES := TankPartDefinition.MAX_CONVEX_SHAPES
const MAX_SURFACE_POINTS := TankPartDefinition.MAX_SURFACE_POINTS
const TRACK_ENVELOPE_PHASES := [0.0, 0.25, 0.5, 0.75]
## 2026-09-09 核可：輪罩表面的薄肋、小外掛塊、細格柵只顯示，不成為碰撞或瞄準點。
## 依原始三角面與 exact-weld component 順序明列，不依大小猜測其他構件。
const HULL_DECORATION_FILTERS := {
	"tank2": {"triangles": 4272, "components": 49, "omitted_triangles": 448, "ranges": [[5, 8], [15, 34]]},
	"tank3": {"triangles": 4390, "components": 43, "omitted_triangles": 840, "ranges": [[1, 2], [4, 5], [9, 12], [13, 28]]},
	"tank4": {"triangles": 9222, "components": 78, "omitted_triangles": 2048, "ranges": [[4, 11], [13, 20], [22, 22], [24, 64]]},
}
## 經拓撲核對的外壁凸區間；兩車 station 8 都是內孔底部，不是外側轉折。
const AXIAL_GUN_PROFILES := {
	"tank1": {"axis": 0, "triangles": 132, "stations": 10, "sections": [[0, 3], [3, 4], [4, 7], [7, 9]]},
	"tank2": {"axis": 0, "triangles": 156, "stations": 11, "sections": [[0, 3], [3, 4], [4, 7], [7, 9], [9, 10]]},
}
## Tank4 的台階以實際側壁連線分段，不把同平面的大半徑套到前一段直管。
## links 的欄位為 [component, station_a, station_b]；component 2 是已核可封閉的內孔。
const RINGED_GUN_GROUPS := [
	{"components": [7]},
	{"links": [[1, 2, 3]]},
	{"links": [[1, 3, 5]]},
	{"links": [[1, 5, 6]]},
	{"components": [3, 4, 5, 8, 9, 10, 11], "links": [[0, 17, 19], [0, 19, 20]]},
	{"links": [[0, 20, 21]]},
	{"links": [[0, 21, 22]]},
	{"components": [6]},
]
## 固定素材的連通群依最小 source triangle index 排序；每群恰好屬於一個結構。
## 左右行走機構、低車身含平台、主車身、頂部附件、前支座、斜結構分開；天線 c16 僅顯示。
const COMPACT_HULL_GROUPS := [
	[0, 5, 6, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 39, 41, 42, 43, 44, 45, 46],
	[1, 10, 11, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 40, 47, 48, 49, 50, 51, 52],
	[3, 7, 8, 12, 13, 15], [4], [2, 9, 14], [37], [38],
]
var _skin_references: Array[SkinReference] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var selected_variant := ""
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--variant="):
			push_error("Unknown tank bake argument: %s" % argument)
			quit(2)
			return
		selected_variant = argument.trim_prefix("--variant=")
	if not selected_variant.is_empty() and selected_variant not in ["tank1", "tank2", "tank3", "tank4"]:
		push_error("Unknown tank variant: %s" % selected_variant)
		quit(2)
		return
	var success := true
	for contract in VARIANTS:
		if not selected_variant.is_empty() and String(contract.scene).get_file().get_basename() != selected_variant:
			continue
		success = await _bake_variant(contract) and success
	quit(0 if success else 1)


func _bake_variant(contract: Dictionary) -> bool:
	var packed := load(String(contract.scene)) as PackedScene
	var tank := packed.instantiate() as CharacterBody3D if packed != null else null
	if tank == null:
		push_error("Cannot instantiate tank geometry source: %s" % contract.scene)
		return false
	root.add_child(tank)
	await process_frame
	await process_frame
	_register_neutral_skins(tank)
	await process_frame
	var geometry := TankPartGeometry.new()
	geometry.stable_center = contract.stable_center as Vector3
	var model := tank.get("tank_model") as Node3D
	var turret_pivot := tank.get("turret_pivot") as Node3D
	var gun_pivot := tank.get("gun_pitch_pivot") as Node3D
	var gun := tank.get("tank_gun") as MeshInstance3D
	var hull := _find_mesh_prefix(model, "Tank_body")
	var left_track := _find_mesh_prefix(model, "TrackMesh_L")
	var right_track := _find_mesh_prefix(model, "TrackMesh_R")
	## Tank2/3 的 turret 已在 controller._ready() reparent 到機械 pivot；Tank4 fixed upper 仍留在 model。
	var upper := tank.get("tank_turret") as MeshInstance3D if String(contract.upper) == "turret" else _find_mesh(model, "Tank_Turret") if String(contract.upper) == "fixed_upper_hull" else null
	var parts: Array[Dictionary] = [
		{"id": "hull", "anchor": "hull", "mesh": hull, "anchor_node": model, "gun": false},
		{"id": "left_track", "anchor": "hull", "mesh": left_track, "anchor_node": model, "gun": false},
		{"id": "right_track", "anchor": "hull", "mesh": right_track, "anchor_node": model, "gun": false},
		{"id": "gun", "anchor": "gun", "mesh": gun, "anchor_node": gun_pivot, "gun": true},
	]
	if upper != null:
		parts.append({"id": String(contract.upper), "anchor": "turret" if String(contract.upper) == "turret" else "hull", "mesh": upper, "anchor_node": turret_pivot if String(contract.upper) == "turret" else model, "gun": false})
	var track_envelopes := await _track_envelope_points(tank, [left_track, right_track])
	if track_envelopes.size() != 2:
		tank.queue_free()
		return false
	for part_contract in parts:
		if part_contract.id == "left_track" or part_contract.id == "right_track":
			part_contract["envelope_points"] = track_envelopes[0 if part_contract.id == "left_track" else 1]
		part_contract["compact_hull"] = String(contract.scene).get_file().get_basename() == "tank1" and part_contract.id == "hull"
		part_contract["gun_profile"] = AXIAL_GUN_PROFILES.get(String(contract.scene).get_file().get_basename(), {}) if part_contract.id == "gun" else {}
		part_contract["ringed_gun"] = String(contract.scene).get_file().get_basename() == "tank4" and part_contract.id == "gun"
		part_contract["component_upper"] = String(contract.scene).get_file().get_basename() == "tank4" and part_contract.id == "fixed_upper_hull"
		part_contract["solid_turret"] = String(contract.scene).get_file().get_basename() == "tank3" and part_contract.id == "turret"
		part_contract["component_tank2_turret"] = String(contract.scene).get_file().get_basename() == "tank2" and part_contract.id == "turret"
		part_contract["hull_decoration_filter"] = HULL_DECORATION_FILTERS.get(String(contract.scene).get_file().get_basename(), {}) if part_contract.id == "hull" else {}
		part_contract["partitioned_tank2_hull"] = String(contract.scene).get_file().get_basename() == "tank2" and part_contract.id == "hull"
		part_contract["partitioned_tank3_hull"] = String(contract.scene).get_file().get_basename() == "tank3" and part_contract.id == "hull"
		part_contract["partitioned_destroyer_hull"] = String(contract.scene).get_file().get_basename() == "tank4" and part_contract.id == "hull"
		var part := _bake_part(part_contract)
		if part == null:
			tank.queue_free()
			return false
		geometry.parts.append(part)
	if not geometry.is_valid_geometry():
		push_error("Baked geometry failed its finite part contract: %s" % contract.scene)
		tank.queue_free()
		return false
	var saved := ResourceSaver.save(geometry, String(contract.output))
	tank.queue_free()
	await process_frame
	if saved != OK:
		push_error("Cannot save baked tank geometry: %s" % contract.output)
		return false
	var hull_count := 0
	for part in geometry.parts:
		hull_count += part.convex_shapes.size()
	print("BAKED_TANK_PARTS %s parts=%d hulls=%d" % [contract.output, geometry.parts.size(), hull_count])
	return true


func _bake_part(contract: Dictionary) -> TankPartDefinition:
	var mesh_instance := contract.mesh as MeshInstance3D
	var anchor_node := contract.anchor_node as Node3D
	if mesh_instance == null or anchor_node == null or mesh_instance.mesh == null:
		push_error("Missing mesh or mechanical anchor for baked tank part: %s" % contract.id)
		return null
	var baked_mesh: ArrayMesh = mesh_instance.bake_mesh_from_current_skeleton_pose() if mesh_instance.skin != null else null
	if mesh_instance.skin != null and baked_mesh == null:
		push_error("Skinned tank part must bake from its current skeleton pose: %s" % contract.id)
		return null
	var source_mesh: Mesh = baked_mesh if baked_mesh != null else mesh_instance.mesh
	## Tank2 turret keeps the approved candidate's canonical Mesh.get_faces() provenance.
	if bool(contract.get("component_tank2_turret", false)):
		source_mesh = mesh_instance.mesh
	var decoration_filter: Dictionary = contract.get("hull_decoration_filter", {})
	## Tank4 must partition against raw indexed faces before generic filtering renumbers components.
	if bool(contract.get("partitioned_destroyer_hull", false)):
		return _bake_partitioned_destroyer_hull(source_mesh, mesh_instance, anchor_node, decoration_filter)
	## Tank2 partition uses raw component identities before generic filtering renumbers components.
	if bool(contract.get("partitioned_tank2_hull", false)):
		return _bake_partitioned_tank2_hull(source_mesh, mesh_instance, anchor_node, decoration_filter)
	## Tank3 partition uses raw component identities before generic filtering renumbers components.
	if bool(contract.get("partitioned_tank3_hull", false)):
		return _bake_partitioned_tank3_hull(source_mesh, mesh_instance, anchor_node, decoration_filter)
	if not decoration_filter.is_empty():
		source_mesh = _structural_hull_mesh(source_mesh, decoration_filter)
		if source_mesh == null:
			return null
	if bool(contract.get("compact_hull", false)):
		return _bake_compact_hull(source_mesh, mesh_instance, anchor_node)
	var gun_profile: Dictionary = contract.get("gun_profile", {})
	if not gun_profile.is_empty():
		return _bake_axial_gun(source_mesh, mesh_instance, anchor_node, gun_profile)
	if bool(contract.get("ringed_gun", false)):
		return _bake_ringed_gun(source_mesh, mesh_instance, anchor_node)
	if bool(contract.get("component_upper", false)):
		return _bake_componentwise_upper(source_mesh, mesh_instance, anchor_node)
	if bool(contract.get("solid_turret", false)):
		return _bake_solid_turret(source_mesh, mesh_instance, anchor_node)
	if bool(contract.get("component_tank2_turret", false)):
		return _bake_component_tank2_turret(source_mesh, mesh_instance, anchor_node)
	if contract.has("envelope_points"):
		var part := TankPartDefinition.new()
		part.id = String(contract.id)
		part.anchor = String(contract.anchor)
		part.anchor_transform = anchor_node.global_transform.affine_inverse() * mesh_instance.global_transform
		var shape := ConvexPolygonShape3D.new()
		shape.points = contract.get("envelope_points", source_mesh.get_faces())
		part.convex_shapes.append(shape)
		part.convex_transforms.append(Transform3D.IDENTITY)
		part.surface_points = _surface_samples(source_mesh, bool(contract.gun))
		return part
	## 凸分解是 MeshInstance3D editor helper，不是 ArrayMesh 方法；只在這個離線暫存 node 上呼叫。
	var decomposition_source := MeshInstance3D.new()
	decomposition_source.mesh = source_mesh
	var decomposition_settings := MeshConvexDecompositionSettings.new()
	## Tank3 gun preserves its existing 8-hull authoring ceiling (which produces seven shapes).
	var decomposition_hull_limit := mini(8, MAX_CONVEX_SHAPES) if bool(contract.gun) else MAX_CONVEX_SHAPES
	decomposition_settings.max_convex_hulls = decomposition_hull_limit
	decomposition_settings.max_num_vertices_per_convex_hull = 64
	decomposition_settings.max_concavity = 0.002
	decomposition_settings.resolution = 100000
	if decomposition_settings.max_convex_hulls != decomposition_hull_limit \
			or decomposition_settings.max_num_vertices_per_convex_hull != 64 \
			or not is_equal_approx(decomposition_settings.max_concavity, 0.002) \
			or decomposition_settings.resolution != 100000:
		push_error("Tank convex decomposition settings did not retain their required values.")
		return null
	decomposition_source.create_multiple_convex_collisions(decomposition_settings)
	var collision_body := decomposition_source.get_child(0) as StaticBody3D
	if collision_body == null:
		push_error("Tank part convex decomposition did not create a body: %s" % contract.id)
		return null
	var part := TankPartDefinition.new()
	part.id = String(contract.id)
	part.anchor = String(contract.anchor)
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * mesh_instance.global_transform
	for child in collision_body.get_children():
		var collision := child as CollisionShape3D
		var shape := collision.shape as ConvexPolygonShape3D if collision != null else null
		if shape == null or shape.points.is_empty():
			continue
		part.convex_shapes.append(shape)
		part.convex_transforms.append(collision.transform)
	if part.convex_shapes.is_empty() or part.convex_shapes.size() > MAX_CONVEX_SHAPES:
		push_error("Tank part %s produced %d convex shapes (required 1..%d)." % [part.id, part.convex_shapes.size(), MAX_CONVEX_SHAPES])
		return null
	part.surface_points = _surface_samples(source_mesh, bool(contract.gun))
	if part.surface_points.is_empty() or part.surface_points.size() > MAX_SURFACE_POINTS:
		push_error("Tank part %s did not produce finite surface samples." % part.id)
		return null
	decomposition_source.free()
	return part


## 僅離線取四個動畫相位的輪廓聯集；執行時仍是一個固定凸形，不逐節更新。
func _track_envelope_points(tank: CharacterBody3D, tracks: Array) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var player: AnimationPlayer = tank.get("tread_animation_player")
	var animation_name: StringName = tank.get("tread_forward_animation")
	if player == null or animation_name.is_empty() or not player.has_animation(animation_name):
		push_error("Track envelope requires the source tread animation.")
		return []
	var animation := player.get_animation(animation_name)
	for phase in TRACK_ENVELOPE_PHASES:
		player.play(animation_name)
		player.seek(animation.length * phase, true)
		player.pause()
		await process_frame
		for index in tracks.size():
			var instance := tracks[index] as MeshInstance3D
			if instance == null or instance.skin == null:
				push_error("Track envelope requires a skinned source mesh.")
				return []
			var mesh := instance.bake_mesh_from_current_skeleton_pose()
			if mesh == null or mesh.get_faces().is_empty():
				push_error("Track envelope source bake was empty.")
				return []
			result[index].append_array(mesh.get_faces())
	player.play(animation_name)
	player.seek(0.0, true)
	player.pause()
	await process_frame
	print("TRACK_ENVELOPE phases=%d left_points=%d right_points=%d" % [TRACK_ENVELOPE_PHASES.size(), result[0].size(), result[1].size()])
	return result


func _bake_compact_hull(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D) -> TankPartDefinition:
	var faces := source.get_faces()
	var components := _source_components(faces)
	if faces.size() != 4896 * 3 or components.size() != 53:
		push_error("Compact hull source topology changed; its authored partition needs revalidation.")
		return null
	var part := TankPartDefinition.new()
	part.id = "hull"
	part.anchor = "hull"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	var covered: Dictionary = {}
	var structural_vertices := PackedVector3Array()
	if components[16].size() != 44:
		push_error("Compact hull antenna topology changed; decoration exclusion needs revalidation.")
		return null
	for group in COMPACT_HULL_GROUPS:
		var points := PackedVector3Array()
		for component_id in group:
			if covered.has(component_id):
				push_error("Compact hull partition contains a duplicate component.")
				return null
			covered[component_id] = true
			for triangle_id in components[component_id]:
				for corner in 3:
					points.append(faces[triangle_id * 3 + corner])
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		structural_vertices.append_array(points)
		part.convex_shapes.append(shape)
		part.convex_transforms.append(Transform3D.IDENTITY)
	if covered.has(16) or covered.size() != components.size() - 1 or part.convex_shapes.size() > MAX_CONVEX_SHAPES:
		push_error("Compact hull partition must cover all non-antenna components within the shape budget.")
		return null
	part.surface_points = _surface_samples_from_vertices(structural_vertices, false)
	print("COMPACT_HULL_PARTITION components=%d triangles=%d hulls=%d" % [covered.size(), faces.size() / 3, part.convex_shapes.size()])
	return part


func _bake_axial_gun(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D, profile: Dictionary) -> TankPartDefinition:
	var faces := source.get_faces()
	var stations: Array[float] = []
	for point in faces:
		if not stations.has(point[int(profile.axis)]):
			stations.append(point[int(profile.axis)])
	stations.sort()
	if faces.size() != int(profile.triangles) * 3 or stations.size() != int(profile.stations):
		push_error("Axial gun source topology changed; its authored sections need revalidation.")
		return null
	var part := TankPartDefinition.new()
	part.id = "gun"
	part.anchor = "gun"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	for section in profile.sections:
		var points := PackedVector3Array()
		for point in faces:
			var coordinate: float = point[int(profile.axis)]
			if coordinate >= stations[section[0]] and coordinate <= stations[section[1]]:
				points.append(point)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		part.convex_shapes.append(shape)
		part.convex_transforms.append(Transform3D.IDENTITY)
	part.surface_points = _surface_samples(source, true)
	print("AXIAL_GUN_SECTIONS stations=%d triangles=%d hulls=%d" % [stations.size(), faces.size() / 3, part.convex_shapes.size()])
	return part


## 截面分類容許同一匯出平面的浮點噪音；保留原始頂點，不修改幾何位置。
func _bake_ringed_gun(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D) -> TankPartDefinition:
	## get_faces 的三角快取會 weld 此素材的鄰近頂點（12 components 變 8），破壞 authored IDs。
	## 直接讀 surface indices，與已驗證的原始拓撲一致；不改寫任何頂點。
	var faces := _raw_triangle_faces(source)
	var components := _source_components(faces)
	var stations: Array[float] = []
	for point in faces:
		if _ringed_station_index(stations, point.x) == -1:
			stations.append(point.x)
	stations.sort()
	if faces.size() != 516 * 3 or components.size() != 12 or stations.size() != 26:
		push_error("Ringed gun source topology changed; its authored sections need revalidation.")
		return null
	var part := TankPartDefinition.new()
	part.id = "gun"
	part.anchor = "gun"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	for group in RINGED_GUN_GROUPS:
		var points := PackedVector3Array()
		for component_id in group.get("components", []):
			for triangle_id in components[component_id]:
				for corner in 3:
					points.append(faces[triangle_id * 3 + corner])
		for link in group.get("links", []):
			var matched_triangles := 0
			for triangle_id in components[link[0]]:
				var used_stations: Array[int] = []
				for corner in 3:
					var station := _ringed_station_index(stations, faces[triangle_id * 3 + corner].x)
					if not used_stations.has(station):
						used_stations.append(station)
				used_stations.sort()
				if used_stations.size() != 2 or used_stations[0] != link[1] or used_stations[1] != link[2]:
					continue
				matched_triangles += 1
				for corner in 3:
					points.append(faces[triangle_id * 3 + corner])
			if matched_triangles != 20:
				push_error("Ringed gun wall link changed or is missing: %s" % [link])
				return null
		if points.is_empty():
			push_error("Ringed gun section must not be empty.")
			return null
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		part.convex_shapes.append(shape)
		part.convex_transforms.append(Transform3D.IDENTITY)
	part.surface_points = _surface_samples(source, true)
	print("RINGED_GUN_SECTIONS components=%d stations=%d hulls=%d" % [components.size(), stations.size(), part.convex_shapes.size()])
	return part


func _ringed_station_index(stations: Array[float], coordinate: float) -> int:
	for index in stations.size():
		if is_equal_approx(stations[index], coordinate):
			return index
	return -1


func _raw_triangle_faces(source: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array and not (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			for index in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
				faces.append(vertices[index])
		else:
			faces.append_array(vertices)
	return faces


## 僅建立烘焙輸入，不改可見 MeshInstance3D 或素材。
func _structural_hull_mesh(source: Mesh, profile: Dictionary) -> ArrayMesh:
	var faces := _raw_triangle_faces(source)
	var components := _source_components(faces)
	if faces.size() != int(profile.triangles) * 3 or components.size() != int(profile.components):
		push_error("Hull decoration source topology changed; exclusions need revalidation.")
		return null
	var retained := PackedVector3Array()
	var omitted_triangles := 0
	for component_id in components.size():
		var is_decoration := false
		for interval in profile.ranges:
			if component_id >= int(interval[0]) and component_id <= int(interval[1]):
				is_decoration = true
				break
		if is_decoration:
			omitted_triangles += components[component_id].size()
			continue
		for triangle_id in components[component_id]:
			for corner in 3:
				retained.append(faces[triangle_id * 3 + corner])
	if omitted_triangles != int(profile.omitted_triangles) or retained.is_empty():
		push_error("Hull decoration triangle count changed; refusing to remove unverified geometry.")
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = retained
	var structural_mesh := ArrayMesh.new()
	structural_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	print("STRUCTURAL_HULL source_triangles=%d omitted_triangles=%d retained_triangles=%d" % [faces.size() / 3, omitted_triangles, retained.size() / 3])
	return structural_mesh


func _bake_partitioned_tank2_hull(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D, profile: Dictionary) -> TankPartDefinition:
	var raw := _raw_triangle_faces(source)
	var components := _source_components(raw)
	if raw.size() != 4272 * 3 or components.size() != 49:
		return null
	var structural := _structural_hull_mesh(source, profile)
	if structural == null or _raw_triangle_faces(structural).size() != 3824 * 3:
		return null
	var part := TankPartDefinition.new()
	part.id = "hull"; part.anchor = "hull"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	var mesh_to_world := instance.global_transform
	var world_to_mesh := mesh_to_world.affine_inverse()
	for bounds in [[-INF, -0.793183207511902], [-0.793183207511902, 2.12868547439575], [2.12868547439575, INF]]:
		var ids: Array = []
		for triangle_id_value in components[4]:
			var triangle_id := int(triangle_id_value)
			var lo := INF; var hi := -INF
			for corner in 3:
				var point: Vector3 = mesh_to_world * raw[triangle_id * 3 + corner]
				lo = minf(lo, point.x); hi = maxf(hi, point.x)
			if hi > float(bounds[0]) + 0.00001 and lo < float(bounds[1]) - 0.00001:
				ids.append(triangle_id)
		if not _append_tank2_direct_shape(part, _tank2_clipped_points(raw, ids, mesh_to_world, world_to_mesh, float(bounds[0]), float(bounds[1]))): return null
	var covered := {4: true}
	for spec in [[[9,10,11,12],1], [[0,1],3], [[13,35,37,38,39,40,41,42],1], [[2,3],3], [[14,36,43,44,45,46,47,48],1]]:
		var ids: Array = spec[0]
		for id_value in ids:
			var id := int(id_value)
			if id < 0 or id >= components.size() or covered.has(id): return null
			covered[id] = true
		if not _append_tank2_decomposition(part, _component_points(raw, components, ids), int(spec[1])): return null
	if covered.size() != 25 or part.convex_shapes.size() != 12: return null
	part.surface_points = _surface_samples(structural, false)
	return part

func _append_tank2_direct_shape(part: TankPartDefinition, points: PackedVector3Array) -> bool:
	if points.size() < 4: return false
	var shape := ConvexPolygonShape3D.new(); shape.points = points
	part.convex_shapes.append(shape); part.convex_transforms.append(Transform3D.IDENTITY)
	return true

func _tank2_clipped_points(raw: PackedVector3Array, ids: Array, mesh_to_world: Transform3D, world_to_mesh: Transform3D, lo: float, hi: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for id_value in ids:
		var polygon := PackedVector3Array()
		for corner in 3: polygon.append(mesh_to_world * raw[int(id_value) * 3 + corner])
		if not is_inf(lo): polygon = _tank3_clip_polygon(polygon, 0, lo, 1)
		if not is_inf(hi): polygon = _tank3_clip_polygon(polygon, 0, hi, -1)
		if polygon.size() >= 3 and _tank3_polygon_double_area(polygon) > 0.00000001:
			for point in polygon: points.append(world_to_mesh * point)
	return points

func _append_tank2_decomposition(part: TankPartDefinition, points: PackedVector3Array, max_hulls: int) -> bool:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var temp := MeshInstance3D.new(); temp.mesh = mesh
	var settings := MeshConvexDecompositionSettings.new()
	settings.max_convex_hulls = max_hulls; settings.max_num_vertices_per_convex_hull = 64; settings.max_concavity = 0.002; settings.resolution = 100000
	temp.create_multiple_convex_collisions(settings)
	var body := temp.get_child(0) as StaticBody3D
	if body == null: return false
	var before := part.convex_shapes.size()
	for child in body.get_children():
		var collision := child as CollisionShape3D
		if collision != null and collision.shape is ConvexPolygonShape3D:
			part.convex_shapes.append(collision.shape); part.convex_transforms.append(collision.transform)
	temp.free()
	return part.convex_shapes.size() - before == max_hulls

func _bake_component_tank2_turret(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D) -> TankPartDefinition:
	var faces := source.get_faces(); var components := _tank2_turret_components(faces)
	if faces.size() != 1212 * 3 or components.size() != 11: return null
	var part := TankPartDefinition.new(); part.id = "turret"; part.anchor = "turret"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	for component in components:
		var points := PackedVector3Array()
		for triangle_id in component:
			for corner in 3: points.append(faces[int(triangle_id) * 3 + corner])
		if not _append_tank3_partition_shape(part, points): return null
	if part.convex_shapes.size() != 11: return null
	part.surface_points = _surface_samples(source, false); return part

func _tank2_turret_components(faces: PackedVector3Array) -> Array:
	var parents := PackedInt32Array(); parents.resize(faces.size() / 3)
	for index in parents.size(): parents[index] = index
	var owner := {}
	for triangle_index in parents.size():
		for corner in 3:
			var point := faces[triangle_index * 3 + corner]
			if owner.has(point):
				var first := _tank2_turret_root(parents, triangle_index); var second := _tank2_turret_root(parents, int(owner[point]))
				if first != second: parents[second] = first
			else: owner[point] = triangle_index
	var groups := {}
	for triangle_index in parents.size():
		var root_id := _tank2_turret_root(parents, triangle_index)
		if not groups.has(root_id): groups[root_id] = []
		groups[root_id].append(triangle_index)
	var keys: Array = groups.keys(); keys.sort(); var result: Array = []
	for key in keys: result.append(groups[key])
	return result

func _tank2_turret_root(parents: PackedInt32Array, value: int) -> int:
	var current := value
	while parents[current] != current: parents[current] = parents[parents[current]]; current = parents[current]
	return current

func _bake_partitioned_tank3_hull(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D, profile: Dictionary) -> TankPartDefinition:
	var raw_faces := _raw_triangle_faces(source)
	var components := _source_components(raw_faces)
	if raw_faces.size() != 4390 * 3 or components.size() != 43:
		push_error("Tank3 hull source topology changed; its locked partition needs revalidation.")
		return null
	var structural_mesh := _structural_hull_mesh(source, profile)
	if structural_mesh == null or _raw_triangle_faces(structural_mesh).size() != 3550 * 3:
		push_error("Tank3 hull structural sample source changed; expected 3550 retained triangles.")
		return null
	var part := TankPartDefinition.new()
	part.id = "hull"
	part.anchor = "hull"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	var mesh_to_world := instance.global_transform
	var world_to_mesh := mesh_to_world.affine_inverse()
	var inner_z := [-1.48891258239746, 1.42210280895233]
	var fender_x := [-INF, -1.7181361913681, -1.21164643764496, 2.51380848884583, INF]
	var c00 := components[0]
	var center_ids: Array = []
	for triangle_id_value in c00:
		var triangle_id := int(triangle_id_value)
		var min_z := INF
		var max_z := -INF
		for corner in 3:
			var world_point: Vector3 = mesh_to_world * raw_faces[triangle_id * 3 + corner]
			min_z = minf(min_z, world_point.z)
			max_z = maxf(max_z, world_point.z)
		if max_z > float(inner_z[0]) + 0.00001 and min_z < float(inner_z[1]) - 0.00001:
			center_ids.append(triangle_id)
	if not _append_tank3_partition_shape(part, _tank3_clipped_world_points(raw_faces, center_ids, mesh_to_world, world_to_mesh, [[2, inner_z[0], 1], [2, inner_z[1], -1]])):
		return null
	for side in [-1, 1]:
		var boundary := float(inner_z[0 if side == -1 else 1])
		var outside_ids: Array = []
		for triangle_id_value in c00:
			var triangle_id := int(triangle_id_value)
			var has_strict_side := false
			for corner in 3:
				var world_point: Vector3 = mesh_to_world * raw_faces[triangle_id * 3 + corner]
				if (world_point.z - boundary) * side > 0.00001:
					has_strict_side = true
			if has_strict_side:
				outside_ids.append(triangle_id)
		for section in fender_x.size() - 1:
			var x_planes := [[0, fender_x[section], 1], [0, fender_x[section + 1], -1]]
			if section != 2:
				var ordinary_planes: Array = [[2, boundary, side]]
				ordinary_planes.append_array(x_planes)
				if not _append_tank3_partition_shape(part, _tank3_clipped_world_points(raw_faces, outside_ids, mesh_to_world, world_to_mesh, ordinary_planes)):
					return null
				continue
			var fold_z := -2.50380373001099 if side == -1 else 2.43699383735657
			var inner_side := 1 if side == -1 else -1
			var outer_side := -1 if side == -1 else 1
			var inner_ids := _tank3_strict_side_triangle_ids(raw_faces, outside_ids, mesh_to_world, 2, fold_z, inner_side)
			var outer_ids := _tank3_strict_side_triangle_ids(raw_faces, outside_ids, mesh_to_world, 2, fold_z, outer_side)
			var inner_planes: Array = [[2, boundary, side], [2, fold_z, inner_side]]
			inner_planes.append_array(x_planes)
			var outer_planes: Array = [[2, fold_z, outer_side]]
			outer_planes.append_array(x_planes)
			if not _append_tank3_partition_shape(part, _tank3_clipped_world_points(raw_faces, inner_ids, mesh_to_world, world_to_mesh, inner_planes)):
				return null
			if not _append_tank3_partition_shape(part, _tank3_clipped_world_points(raw_faces, outer_ids, mesh_to_world, world_to_mesh, outer_planes)):
				return null
	for component_group in [[7, 29, 31, 32, 33, 34, 35, 36], [8, 30, 37, 38, 39, 40, 41, 42], [3], [6]]:
		if not _append_tank3_partition_shape(part, _component_points(raw_faces, components, component_group)):
			return null
	if part.convex_shapes.size() != 15:
		push_error("Tank3 hull must produce exactly 15 identity-transform collision shapes.")
		return null
	part.surface_points = _surface_samples(structural_mesh, false)
	if part.surface_points.is_empty() or part.surface_points.size() > MAX_SURFACE_POINTS:
		push_error("Tank3 hull did not produce finite structural surface samples.")
		return null
	print("TANK3_HULL_PARTITION source_triangles=%d components=%d retained_triangles=%d hulls=%d omitted_ribs=4 middle_wing_cells=4" % [raw_faces.size() / 3, components.size(), _raw_triangle_faces(structural_mesh).size() / 3, part.convex_shapes.size()])
	return part


func _component_points(raw_faces: PackedVector3Array, components: Array, component_group: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for component_id_value in component_group:
		var component_id := int(component_id_value)
		if component_id < 0 or component_id >= components.size():
			return PackedVector3Array()
		for triangle_id_value in components[component_id]:
			var triangle_id := int(triangle_id_value)
			for corner in 3:
				points.append(raw_faces[triangle_id * 3 + corner])
	return points


func _append_tank3_partition_shape(part: TankPartDefinition, points: PackedVector3Array) -> bool:
	if points.size() < 4:
		push_error("Tank3 hull partition cell is empty or degenerate.")
		return false
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	part.convex_shapes.append(shape)
	part.convex_transforms.append(Transform3D.IDENTITY)
	return true


func _tank3_clipped_world_points(raw_faces: PackedVector3Array, source_triangle_ids: Array, mesh_to_world: Transform3D, world_to_mesh: Transform3D, planes: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for triangle_id_value in source_triangle_ids:
		var triangle_id := int(triangle_id_value)
		var polygon := PackedVector3Array()
		for corner in 3:
			polygon.append(mesh_to_world * raw_faces[triangle_id * 3 + corner])
		for plane in planes:
			polygon = _tank3_clip_polygon(polygon, int(plane[0]), float(plane[1]), int(plane[2]))
		if polygon.size() < 3 or _tank3_polygon_double_area(polygon) <= 0.00000001:
			continue
		for world_point in polygon:
			points.append(world_to_mesh * world_point)
	return points


func _tank3_strict_side_triangle_ids(raw_faces: PackedVector3Array, source_triangle_ids: Array, mesh_to_world: Transform3D, axis: int, boundary: float, side: int) -> Array:
	var selected: Array = []
	for triangle_id_value in source_triangle_ids:
		var triangle_id := int(triangle_id_value)
		for corner in 3:
			var world_point: Vector3 = mesh_to_world * raw_faces[triangle_id * 3 + corner]
			if (world_point[axis] - boundary) * side > 0.00001:
				selected.append(triangle_id)
				break
	return selected


func _tank3_clip_polygon(polygon: PackedVector3Array, axis: int, boundary: float, side: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous := polygon[polygon.size() - 1]
	var previous_distance: float = (previous[axis] - boundary) * side
	for current in polygon:
		var distance: float = (current[axis] - boundary) * side
		if (distance >= 0.0) != (previous_distance >= 0.0):
			result.append(previous.lerp(current, previous_distance / (previous_distance - distance)))
		if distance >= 0.0:
			result.append(current)
		previous = current
		previous_distance = distance
	return result


func _tank3_polygon_double_area(polygon: PackedVector3Array) -> float:
	var area := 0.0
	for index in range(1, polygon.size() - 1):
		area += (polygon[index] - polygon[0]).cross(polygon[index + 1] - polygon[0]).length()
	return area


## Tank4 destroyer hull: 11 locked collision cells in mesh local coordinates.
## The raw component order is provenance: never feed this source through _structural_hull_mesh first.
func _bake_partitioned_destroyer_hull(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D, profile: Dictionary) -> TankPartDefinition:
	var raw_faces := _raw_triangle_faces(source)
	var components := _source_components(raw_faces)
	if raw_faces.size() != 9222 * 3 or components.size() != 78:
		push_error("Tank4 destroyer hull source topology changed; its locked partition needs revalidation.")
		return null
	var c00: Array = components[0]
	if c00.size() != 482:
		push_error("Tank4 destroyer hull c00 provenance changed; refusing to infer a replacement partition.")
		return null
	var body_ids: Array = []
	var plus_frame_ids: Array = []
	var minus_frame_ids: Array = []
	for raw_triangle_id_value in c00:
		var raw_triangle_id := int(raw_triangle_id_value)
		if raw_triangle_id <= 75 or (raw_triangle_id >= 98 and raw_triangle_id <= 125):
			body_ids.append(raw_triangle_id)
		elif raw_triangle_id >= 1616 and raw_triangle_id <= 1804:
			plus_frame_ids.append(raw_triangle_id)
		elif raw_triangle_id >= 2293 and raw_triangle_id <= 2481:
			minus_frame_ids.append(raw_triangle_id)
		else:
			push_error("Tank4 destroyer hull c00 contains an unrecognized source triangle provenance.")
			return null
	if body_ids.size() != 104 or plus_frame_ids.size() != 189 or minus_frame_ids.size() != 189:
		push_error("Tank4 destroyer hull c00 provenance counts changed; refusing the locked 11-cell recipe.")
		return null
	if components[1].size() != 36 or components[12].size() != 100 or components[65].size() != 204:
		push_error("Tank4 destroyer hull cover provenance changed; c01/c12/c65 must remain direct structural cells.")
		return null
	var part := TankPartDefinition.new()
	part.id = "hull"
	part.anchor = "hull"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	var world_to_mesh := instance.global_transform.affine_inverse()
	if not _append_tank4_partition_shape(part, _tank4_clipped_world_points(raw_faces, body_ids, instance.global_transform, world_to_mesh, -1.41022336483002, -1, 0.0)):
		return null
	if not _append_tank4_partition_shape(part, _tank4_clipped_world_points(raw_faces, body_ids, instance.global_transform, world_to_mesh, -1.41022336483002, 1, 0.0)):
		return null
	if not _append_tank4_partition_shape(part, _tank4_clipped_world_points(raw_faces, plus_frame_ids, instance.global_transform, world_to_mesh, -1.48736214637756, -1, -0.04308032989502)):
		return null
	if not _append_tank4_partition_shape(part, _tank4_clipped_world_points(raw_faces, plus_frame_ids, instance.global_transform, world_to_mesh, -1.48736214637756, 1, -0.04308032989502)):
		return null
	if not _append_tank4_partition_shape(part, _tank4_clipped_world_points(raw_faces, minus_frame_ids, instance.global_transform, world_to_mesh, -1.48736214637756, -1, 0.04308021068573)):
		return null
	if not _append_tank4_partition_shape(part, _tank4_clipped_world_points(raw_faces, minus_frame_ids, instance.global_transform, world_to_mesh, -1.48736214637756, 1, 0.04308021068573)):
		return null
	## c66–77 輪組完全包含於對應履帶凸形，由履帶承擔碰撞，不重複建立四個 hull 凸形。
	## 原始結構 reference 與表面取樣仍保留輪組，不將輪組改列裝飾。
	for component_group in [[1], [12], [65], [2, 21], [3, 23]]:
		if not _append_tank4_partition_shape(part, _tank4_component_points(raw_faces, components, component_group)):
			return null
	if part.convex_shapes.size() != 11 or part.convex_transforms.size() != 11 or part.convex_shapes.size() > MAX_CONVEX_SHAPES:
		push_error("Tank4 destroyer hull must produce exactly 11 identity-transform collision shapes.")
		return null
	var structural_mesh := _structural_hull_mesh(source, profile)
	if structural_mesh == null or _raw_triangle_faces(structural_mesh).size() != 7174 * 3:
		push_error("Tank4 destroyer hull structural sample source changed; expected 7174 retained triangles.")
		return null
	part.surface_points = _surface_samples(structural_mesh, false)
	if part.surface_points.is_empty() or part.surface_points.size() > MAX_SURFACE_POINTS:
		push_error("Tank4 destroyer hull did not produce finite structural surface samples.")
		return null
	print("TANK4_DESTROYER_HULL_PARTITION source_triangles=%d components=%d retained_triangles=%d hulls=%d" % [raw_faces.size() / 3, components.size(), _raw_triangle_faces(structural_mesh).size() / 3, part.convex_shapes.size()])
	return part


func _append_tank4_partition_shape(part: TankPartDefinition, points: PackedVector3Array) -> bool:
	if points.size() < 4:
		push_error("Tank4 destroyer hull partition cell is empty or degenerate.")
		return false
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	part.convex_shapes.append(shape)
	part.convex_transforms.append(Transform3D.IDENTITY)
	return true


func _tank4_component_points(raw_faces: PackedVector3Array, components: Array, component_group: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for component_id_value in component_group:
		var component_id := int(component_id_value)
		if component_id < 0 or component_id >= components.size():
			return PackedVector3Array()
		for raw_triangle_id_value in components[component_id]:
			var raw_triangle_id := int(raw_triangle_id_value)
			for corner in 3:
				points.append(raw_faces[raw_triangle_id * 3 + corner])
	return points


## Select by source triangle ID before clipping: faces lying entirely on the cut plane do not leak into either cell.
func _tank4_clipped_world_points(raw_faces: PackedVector3Array, source_triangle_ids: Array, mesh_to_world: Transform3D, world_to_mesh: Transform3D, cut_x: float, side: int, world_z_shift: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for raw_triangle_id_value in source_triangle_ids:
		var raw_triangle_id := int(raw_triangle_id_value)
		var triangle := PackedVector3Array()
		var has_strict_side := false
		for corner in 3:
			var world_point: Vector3 = mesh_to_world * raw_faces[raw_triangle_id * 3 + corner]
			triangle.append(world_point)
			if (world_point.x - cut_x) * side > 0.0:
				has_strict_side = true
		if not has_strict_side:
			continue
		var polygon := _tank4_clip_polygon(triangle, cut_x, side)
		if polygon.size() < 3 or _tank4_polygon_double_area(polygon) <= 0.00000001:
			continue
		for world_point in polygon:
			points.append(world_to_mesh * (world_point + Vector3(0.0, 0.0, world_z_shift)))
	return points


func _tank4_clip_polygon(polygon: PackedVector3Array, cut_x: float, side: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous := polygon[polygon.size() - 1]
	var previous_distance: float = (previous.x - cut_x) * side
	for current in polygon:
		var distance: float = (current.x - cut_x) * side
		if (distance >= 0.0) != (previous_distance >= 0.0):
			result.append(previous.lerp(current, previous_distance / (previous_distance - distance)))
		if distance >= 0.0:
			result.append(current)
		previous = current
		previous_distance = distance
	return result


func _tank4_polygon_double_area(polygon: PackedVector3Array) -> float:
	var area := 0.0
	for index in range(1, polygon.size() - 1):
		area += (polygon[index] - polygon[0]).cross(polygon[index + 1] - polygon[0]).length()
	return area
## Tank3 砲塔底部接合空洞已核可封實；四個實際構件各自保留外輪廓。
func _bake_solid_turret(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D) -> TankPartDefinition:
	var faces := _raw_triangle_faces(source)
	var components := _source_components(faces)
	if faces.size() != 392 * 3 or components.size() != 4:
		push_error("Solid turret source topology changed; its component partition needs revalidation.")
		return null
	var part := TankPartDefinition.new()
	part.id = "turret"
	part.anchor = "turret"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	for component in components:
		var points := PackedVector3Array()
		for triangle_id in component:
			for corner in 3:
				points.append(faces[triangle_id * 3 + corner])
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		part.convex_shapes.append(shape)
		part.convex_transforms.append(Transform3D.IDENTITY)
	part.surface_points = _surface_samples(source, false)
	print("SOLID_TURRET components=%d hulls=%d" % [components.size(), part.convex_shapes.size()])
	return part


## Tank4 上方結構與支架分開分解，避免一個分解輸入跨越兩者的空隙。
func _bake_componentwise_upper(source: Mesh, instance: MeshInstance3D, anchor_node: Node3D) -> TankPartDefinition:
	var faces := _raw_triangle_faces(source)
	var components := _source_components(faces)
	if faces.size() != 80 * 3 or components.size() != 2:
		push_error("Fixed upper source topology changed; component decomposition needs revalidation.")
		return null
	var part := TankPartDefinition.new()
	part.id = "fixed_upper_hull"
	part.anchor = "hull"
	part.anchor_transform = anchor_node.global_transform.affine_inverse() * instance.global_transform
	for component in components:
		var vertices := PackedVector3Array()
		for triangle_id in component:
			for corner in 3:
				vertices.append(faces[triangle_id * 3 + corner])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var temporary := MeshInstance3D.new()
		temporary.mesh = mesh
		var settings := MeshConvexDecompositionSettings.new()
		settings.max_convex_hulls = MAX_CONVEX_SHAPES
		settings.max_num_vertices_per_convex_hull = 64
		settings.max_concavity = 0.002
		settings.resolution = 100000
		temporary.create_multiple_convex_collisions(settings)
		var body := temporary.get_child(0) as StaticBody3D if temporary.get_child_count() > 0 else null
		if body == null or body.get_child_count() == 0:
			push_error("Fixed upper component decomposition produced no collision shapes.")
			temporary.free()
			return null
		for child in body.get_children():
			var collision := child as CollisionShape3D
			if collision == null or not collision.shape is ConvexPolygonShape3D:
				push_error("Fixed upper component decomposition produced an invalid shape.")
				temporary.free()
				return null
			part.convex_shapes.append(collision.shape as ConvexPolygonShape3D)
			part.convex_transforms.append(collision.transform)
		temporary.free()
	if part.convex_shapes.size() > MAX_CONVEX_SHAPES:
		push_error("Fixed upper component decomposition exceeded the part shape budget.")
		return null
	part.surface_points = _surface_samples(source, false)
	print("COMPONENT_UPPER components=%d hulls=%d" % [components.size(), part.convex_shapes.size()])
	return part


## 離線只按完全相同位置 weld；不以任意 epsilon 合併模型間的真實空隙。
func _source_components(faces: PackedVector3Array) -> Array[Array]:
	var parents := PackedInt32Array()
	parents.resize(faces.size() / 3)
	for index in parents.size():
		parents[index] = index
	var vertex_owner: Dictionary = {}
	for triangle_id in parents.size():
		for corner in 3:
			var point := faces[triangle_id * 3 + corner]
			if vertex_owner.has(point):
				var first := _component_root(parents, triangle_id)
				var second := _component_root(parents, int(vertex_owner[point]))
				parents[maxi(first, second)] = mini(first, second)
			else:
				vertex_owner[point] = triangle_id
	var groups: Dictionary = {}
	for triangle_id in parents.size():
		var root_id := _component_root(parents, triangle_id)
		if not groups.has(root_id):
			groups[root_id] = []
		groups[root_id].append(triangle_id)
	var component_ids: Array = groups.keys()
	component_ids.sort()
	var result: Array[Array] = []
	for component_id in component_ids:
		result.append(groups[component_id])
	return result


func _component_root(parents: PackedInt32Array, value: int) -> int:
	var current := value
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current


func _register_neutral_skins(tank: Node3D) -> void:
	## bake_mesh_from_current_skeleton_pose 只接受已註冊 Skin；明確重設 rest pose，避免履帶動畫殘留。
	for mesh_instance in tank.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_instance as MeshInstance3D
		if mesh.skin == null or mesh.skeleton.is_empty():
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton == null:
			push_error("Skinned tank part has no resolvable Skeleton3D: %s" % mesh.get_path())
			continue
		skeleton.reset_bone_poses()
		var reference := skeleton.register_skin(mesh.skin)
		if reference != null:
			_skin_references.append(reference)


func _surface_samples(mesh: Mesh, is_gun: bool) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vertices.append_array(surface_vertices)
	return _surface_samples_from_vertices(vertices, is_gun)


func _surface_samples_from_vertices(vertices: PackedVector3Array, is_gun: bool) -> PackedVector3Array:
	if vertices.is_empty():
		return PackedVector3Array()
	var selected: Array[Vector3] = []
	var directions := [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]
	if is_gun:
		directions = [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for direction in directions:
		var best := vertices[0]
		var best_dot := best.dot(direction)
		for vertex in vertices:
			var value := vertex.dot(direction)
			if value > best_dot:
				best = vertex
				best_dot = value
		_append_unique(selected, best)
	var stride: int = maxi(1, vertices.size() / MAX_SURFACE_POINTS)
	for index in range(0, vertices.size(), stride):
		_append_unique(selected, vertices[index])
		if selected.size() >= MAX_SURFACE_POINTS:
			break
	selected.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x or (is_equal_approx(a.x, b.x) and (a.y < b.y or (is_equal_approx(a.y, b.y) and a.z < b.z))))
	var samples := PackedVector3Array()
	for point in selected:
		if samples.size() >= MAX_SURFACE_POINTS:
			break
		samples.append(point)
	return samples


func _append_unique(points: Array[Vector3], candidate: Vector3) -> void:
	for point in points:
		if point.is_equal_approx(candidate):
			return
	points.append(candidate)


func _find_mesh_prefix(root_node: Node, prefix: String) -> MeshInstance3D:
	if root_node == null:
		return null
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		if String(child.name).begins_with(prefix):
			return child as MeshInstance3D
	return null


func _find_mesh(root_node: Node, accepted_name: String) -> MeshInstance3D:
	if root_node == null:
		return null
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		if child.name == accepted_name:
			return child as MeshInstance3D
	return null
