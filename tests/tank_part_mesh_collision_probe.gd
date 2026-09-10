## 用原生 ConcavePolygonShape3D（實際 baked mesh）與坦克原生凸形，量測相同有限 ray 的第一命中。
## 執行：Godot --path . --script res://tests/tank_part_mesh_collision_probe.gd（需要 GPU skin bake）
extends SceneTree

const VARIANTS := [
	{"id": "tank1", "scene": "res://src/actors/tank/variants/tank1/tank1.tscn"},
	{"id": "tank2", "scene": "res://src/actors/tank/variants/tank2/tank2.tscn"},
	{"id": "tank3", "scene": "res://src/actors/tank/variants/tank3/tank3.tscn"},
	{"id": "tank4", "scene": "res://src/actors/tank/variants/tank4/tank4.tscn"},
]
const TRACK_PHASES := [0.25, 0.5, 0.75]
const TRACK_REFERENCE_PHASES := [0.0, 0.25, 0.5, 0.75]
const GUN_CAP_CONFIGS := {
	"tank1": {"axis": 0, "front": -9.284154892, "front_vertices": 12, "outer_rim": 6, "raw_faces": 132},
	"tank2": {"axis": 0, "front": -7.520068169, "front_vertices": 12, "outer_rim": 6, "raw_faces": 156},
	"tank3": {"axis": 1, "front": -0.821602106, "front_vertices": 14, "outer_rim": 7, "raw_faces": 178},
	"tank4": {"axis": 0, "front": -10.132566452, "front_vertices": 30, "outer_rim": 10, "raw_faces": 516},
}
## 產品裁決的非結構 hull 外掛件；identity 由 local raw face exact-weld component 決定。
const HULL_DECORATION_CONFIGS := {
	"tank2": {"raw_faces": 4272, "components": 49, "removed_faces": 448, "excluded_components": [5, 6, 7, 8, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34]},
	"tank3": {"raw_faces": 4390, "components": 43, "removed_faces": 840, "excluded_components": [1, 2, 4, 5, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28]},
	"tank4": {"raw_faces": 9222, "components": 78, "removed_faces": 2048, "excluded_components": [4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64]},
}
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]
const SOURCE_LAYER := 1 << 20
const CONVEX_LAYER := 1 << 21
const MAX_FIRST_HIT_ERROR := 0.05
const RAY_MARGIN := 1.0
var _skin_references: Array[SkinReference] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var passed := true
	for contract in VARIANTS:
		passed = await _probe_variant(contract) and passed
	quit(0 if passed else 1)


func _probe_variant(contract: Dictionary) -> bool:
	var packed := load(String(contract.scene)) as PackedScene
	var tank := packed.instantiate() as CharacterBody3D if packed != null else null
	if tank == null:
		return _fail("%s could not instantiate." % contract.id)
	root.add_child(tank)
	await physics_frame
	await physics_frame
	_register_skins(tank)
	await process_frame
	await physics_frame
	var valid := true
	var maximum_error := 0.0
	var track_references := await _build_track_references(tank, String(contract.id))
	valid = await _verify_track_formal_shapes(tank, String(contract.id)) and valid
	if track_references.size() != 2:
		valid = false
	if String(contract.id) == "tank1":
		valid = await _probe_tank1_hull_decoration_exclusion(tank) and valid
	elif _has_hull_decoration_exclusion(String(contract.id)):
		valid = _verify_hull_decoration_exclusion(tank, String(contract.id)) and valid

	## 保留既有整車 neutral control：四相位 × 三軸雙向 = 24 對／車。
	for phase in [0.0, 0.25, 0.5, 0.75]:
		_reset_pose(tank)
		_set_track_phase(tank, phase)
		await physics_frame
		var whole_bounds := _all_part_triangles(tank)
		var whole_source := _make_whole_reference_body(tank, track_references, String(contract.id), StringName("whole_neutral"))
		if whole_source == null:
			valid = false
			continue
		var whole := await _compare(tank, String(contract.id), phase, &"whole_neutral", whole_bounds, "", whole_source)
		valid = whole.valid and valid
		maximum_error = maxf(maximum_error, whole.maximum_error)

	## 中性姿態時每個真實 part 的六向對照：每一部位至少需要一個有效命中。
	_reset_pose(tank)
	_set_track_phase(tank, 0.0)
	await physics_frame
	for part in tank.part_geometry.parts:
		var triangles := _part_triangles(tank, part.id)
		var reference: Dictionary = track_references.get(part.id, {})
		var source_triangles := triangles
		if _has_gun_cap(String(contract.id)) and part.id == "gun":
			var gun_reference := _gun_reference_triangles(tank, String(contract.id), &"neutral_gun")
			if not bool(gun_reference.valid):
				valid = false
			else:
				source_triangles = gun_reference.triangles as PackedVector3Array
		if String(contract.id) == "tank3" and part.id == "turret":
			var turret_reference := _tank3_turret_reference_triangles(tank, &"neutral_turret")
			if not bool(turret_reference.valid):
				valid = false
			else:
				source_triangles = turret_reference.triangles as PackedVector3Array
		if _has_hull_decoration_exclusion(String(contract.id)) and part.id == "hull":
			var hull_reference := _hull_reference_triangles(tank, String(contract.id), &"neutral_hull")
			if not bool(hull_reference.valid):
				valid = false
			else:
				source_triangles = hull_reference.triangles as PackedVector3Array
		var neutral := await _compare(tank, String(contract.id), 0.0, StringName("neutral_%s" % part.id), source_triangles, part.id, _make_track_reference_body(reference) if _is_track(part.id) else null, null, false, triangles)
		valid = neutral.valid and valid
		maximum_error = maxf(maximum_error, neutral.maximum_error)
		if _is_track(part.id):
			await _compare(tank, String(contract.id), 0.0, StringName("neutral_%s_raw_triangle" % part.id), triangles, part.id, null, null, true)
		if _has_gun_cap(String(contract.id)) and part.id == "gun":
			await _compare(tank, String(contract.id), 0.0, &"neutral_gun_raw_triangle", triangles, "gun", null, null, true)
		if String(contract.id) == "tank3" and part.id == "turret":
			await _compare(tank, String(contract.id), 0.0, &"neutral_turret_raw_triangle", triangles, "turret", null, null, true)
		if _has_hull_decoration_exclusion(String(contract.id)) and part.id == "hull":
			await _compare(tank, String(contract.id), 0.0, &"neutral_hull_raw_triangle", triangles, "hull", null, null, true)

	## 四車 gun：同時施加可達的非零砲塔 yaw 與砲管 pitch，僅驗 gun 的六向。
	_reset_pose(tank)
	_apply_gun_pose(tank)
	await physics_frame
	var gun_bounds := _part_triangles(tank, "gun")
	var gun_source := gun_bounds
	if _has_gun_cap(String(contract.id)):
		var gun_reference := _gun_reference_triangles(tank, String(contract.id), &"gun_yaw_pitch")
		if not bool(gun_reference.valid):
			valid = false
		else:
			gun_source = gun_reference.triangles as PackedVector3Array
	var gun := await _compare(tank, String(contract.id), 0.0, &"gun_yaw_pitch", gun_source, "gun", null, null, false, gun_bounds)
	valid = gun.valid and valid
	maximum_error = maxf(maximum_error, gun.maximum_error)
	if _has_gun_cap(String(contract.id)):
		await _compare(tank, String(contract.id), 0.0, &"gun_yaw_pitch_raw_triangle", gun_bounds, "gun", null, null, true)

	## 有獨立砲塔的兩車額外驗可達 yaw。
	if tank.part_geometry.part_named("turret") != null:
		_reset_pose(tank)
		_apply_turret_yaw(tank)
		await physics_frame
		var turret_bounds := _part_triangles(tank, "turret")
		var turret_source := turret_bounds
		if String(contract.id) == "tank3":
			var turret_reference := _tank3_turret_reference_triangles(tank, &"turret_yaw")
			if not bool(turret_reference.valid):
				valid = false
			else:
				turret_source = turret_reference.triangles as PackedVector3Array
		var turret := await _compare(tank, String(contract.id), 0.0, &"turret_yaw", turret_source, "turret", null, null, false, turret_bounds)
		valid = turret.valid and valid
		maximum_error = maxf(maximum_error, turret.maximum_error)
		if String(contract.id) == "tank3":
			await _compare(tank, String(contract.id), 0.0, &"turret_yaw_raw_triangle", turret_bounds, "turret", null, null, true)

	## 八條履帶於其餘動畫相位分別驗六向，避免把 skin animation 當靜態資料。
	for phase in TRACK_PHASES:
		_reset_pose(tank)
		_set_track_phase(tank, phase)
		await physics_frame
		for part_id in ["left_track", "right_track"]:
			var triangles := _part_triangles(tank, part_id)
			var reference: Dictionary = track_references.get(part_id, {})
			var track := await _compare(tank, String(contract.id), phase, StringName("track_%s" % part_id), triangles, part_id, _make_track_reference_body(reference))
			valid = track.valid and valid
			maximum_error = maxf(maximum_error, track.maximum_error)
			await _compare(tank, String(contract.id), phase, StringName("track_%s_raw_triangle" % part_id), triangles, part_id, null, null, true)

	print("MESH_CONVEX_PROBE %s ray_pairs=%d max_error=%.6f limit=%.6f" % [contract.id, _case_count(tank), maximum_error, MAX_FIRST_HIT_ERROR])
	tank.queue_free()
	await physics_frame
	return valid or _fail("%s has missing or over-limit native mesh/convex ray pairs." % contract.id)


func _compare(tank: CharacterBody3D, variant_id: String, phase: float, case_id: StringName, triangles: PackedVector3Array, expected_part: String, supplied_source: StaticBody3D = null, supplied_convex: CollisionObject3D = null, advisory: bool = false, bounds_triangles: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	var result := {"valid": true, "maximum_error": 0.0}
	if triangles.is_empty():
		print("MESH_CONVEX_NO_SOURCE %s phase=%.2f case=%s" % [variant_id, phase, case_id])
		result.valid = false
		return result
	var source := supplied_source if supplied_source != null else _make_source_body(triangles)
	var convex: CollisionObject3D = supplied_convex if supplied_convex != null else _make_part_convex_body(tank, expected_part) if not expected_part.is_empty() else tank
	root.add_child(source)
	if convex != tank:
		root.add_child(convex)
	await physics_frame
	var bounds := _triangle_bounds(bounds_triangles if not bounds_triangles.is_empty() else triangles)
	var effective_hits := 0
	for axis in AXES:
		for outward in [axis, -axis]:
			var from: Vector3 = _outside_bounds(bounds, outward)
			var to: Vector3 = from - outward * 100.0
			var source_hit: Dictionary = _ray_hit(tank, from, to, SOURCE_LAYER, source)
			var convex_hit: Dictionary = _ray_hit(tank, from, to, CONVEX_LAYER if convex != tank else tank.collision_layer, convex)
			if source_hit.is_empty() and convex_hit.is_empty():
				print("MESH_CONVEX_%sBOTH_MISS %s phase=%.2f case=%s from=%s to=%s" % ["ADVISORY_" if advisory else "", variant_id, phase, case_id, from, to])
				continue
			if source_hit.is_empty() or convex_hit.is_empty():
				var discrepancy := "FALSE_POSITIVE" if not convex_hit.is_empty() else "FALSE_NEGATIVE"
				print("MESH_CONVEX_%s%s %s phase=%.2f case=%s from=%s to=%s source=%s convex=%s" % ["ADVISORY_" if advisory else "", discrepancy, variant_id, phase, case_id, from, to, source_hit, convex_hit])
				if not advisory:
					result.valid = false
				continue
			effective_hits += 1
			var source_distance := from.distance_to(source_hit.position as Vector3)
			var convex_distance := from.distance_to(convex_hit.position as Vector3)
			var error := absf(source_distance - convex_distance)
			result.maximum_error = maxf(float(result.maximum_error), error)
			var convex_part := expected_part if convex != tank else _part_for_shape(tank, int(convex_hit.get("shape", -1)))
			if error > MAX_FIRST_HIT_ERROR:
				print("MESH_CONVEX_%sERROR %s phase=%.2f case=%s from=%s to=%s source_shape=%s convex_shape=%s convex_part=%s source=%.6f convex=%.6f error=%.6f" % ["ADVISORY_" if advisory else "", variant_id, phase, case_id, from, to, source_hit.get("shape", -1), convex_hit.get("shape", -1), convex_part, source_distance, convex_distance, error])
				if not advisory:
					result.valid = false
	if effective_hits == 0:
		print("MESH_CONVEX_%sNO_EFFECTIVE_HIT %s phase=%.2f case=%s" % ["ADVISORY_" if advisory else "", variant_id, phase, case_id])
		if not advisory:
			result.valid = false
	source.queue_free()
	if convex != tank:
		convex.queue_free()
	await physics_frame
	return result


func _make_source_body(triangles: PackedVector3Array) -> StaticBody3D:
	var source := StaticBody3D.new()
	source.name = "BakedMeshRaySource"
	source.collision_layer = SOURCE_LAYER
	source.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.data = triangles
	collision.shape = shape
	source.add_child(collision)
	return source


## 履帶正式 AC 的 reference：四相位原始 skin baked mesh 的所有 faces，固定在同一個 mesh local frame。
func _build_track_references(tank: CharacterBody3D, variant_id: String) -> Dictionary:
	var references := {}
	for part_id in [&"left_track", &"right_track"]:
		var points := PackedVector3Array()
		var mesh_transform := Transform3D.IDENTITY
		var have_transform := false
		var collected_phases := 0
		for phase in TRACK_REFERENCE_PHASES:
			_reset_pose(tank)
			_set_track_phase(tank, phase)
			await physics_frame
			var instance := _part_mesh_instance(tank, part_id)
			var baked: ArrayMesh = instance.bake_mesh_from_current_skeleton_pose() if instance != null and instance.skin != null else null
			if baked == null:
				print("MESH_CONVEX_NO_TRACK_REFERENCE %s part=%s phase=%.2f" % [variant_id, part_id, phase])
				continue
			if have_transform and not mesh_transform.is_equal_approx(instance.global_transform):
				print("MESH_CONVEX_TRACK_REFERENCE_FRAME_CHANGED %s part=%s phase=%.2f" % [variant_id, part_id, phase])
				continue
			mesh_transform = instance.global_transform
			have_transform = true
			points.append_array(baked.get_faces())
			collected_phases += 1
		if points.is_empty() or not have_transform or collected_phases != TRACK_REFERENCE_PHASES.size():
			print("MESH_CONVEX_INCOMPLETE_TRACK_REFERENCE %s part=%s expected_phases=%d collected_phases=%d" % [variant_id, part_id, TRACK_REFERENCE_PHASES.size(), collected_phases])
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		references[part_id] = {"shape": shape, "transform": mesh_transform}
		print("MESH_CONVEX_TRACK_REFERENCE %s part=%s phases=%d points=%d" % [variant_id, part_id, collected_phases, points.size()])
	return references


func _make_track_reference_body(reference: Dictionary) -> StaticBody3D:
	if reference.is_empty():
		return null
	var shape := reference.get("shape", null) as ConvexPolygonShape3D
	if shape == null:
		return null
	var source := StaticBody3D.new()
	source.name = "TrackPhaseUnionReference"
	source.collision_layer = SOURCE_LAYER
	source.collision_mask = 0
	_add_track_reference_collision(source, reference)
	return source


func _make_whole_reference_body(tank: CharacterBody3D, track_references: Dictionary, variant_id: String, case_id: StringName) -> StaticBody3D:
	var source := StaticBody3D.new()
	source.name = "WholeTankMixedReference"
	source.collision_layer = SOURCE_LAYER
	source.collision_mask = 0
	for part in tank.part_geometry.parts:
		if _is_track(part.id):
			_add_track_reference_collision(source, track_references.get(part.id, {}))
			continue
		var triangles := _part_triangles(tank, part.id)
		if _has_gun_cap(variant_id) and part.id == "gun":
			var gun_reference := _gun_reference_triangles(tank, variant_id, case_id)
			if not bool(gun_reference.valid):
				return null
			triangles = gun_reference.triangles as PackedVector3Array
		if variant_id == "tank3" and part.id == "turret":
			var turret_reference := _tank3_turret_reference_triangles(tank, case_id)
			if not bool(turret_reference.valid):
				return null
			triangles = turret_reference.triangles as PackedVector3Array
		if _has_hull_decoration_exclusion(variant_id) and part.id == "hull":
			var hull_reference := _hull_reference_triangles(tank, variant_id, case_id)
			if not bool(hull_reference.valid):
				return null
			triangles = hull_reference.triangles as PackedVector3Array
		if triangles.is_empty():
			continue
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.data = triangles
		collision.shape = shape
		source.add_child(collision)
	return source


## 炮口封閉只補指定前端平面；外壁仍使用原始 source triangles，絕不改成整枝凸包。
func _gun_reference_triangles(tank: CharacterBody3D, variant_id: String, case_id: StringName) -> Dictionary:
	var config: Dictionary = GUN_CAP_CONFIGS.get(variant_id, {})
	if config.is_empty():
		return _invalid_gun_cap(variant_id, case_id, "no approved cap configuration")
	var gun := _part_mesh_instance(tank, "gun")
	var raw_triangles := _part_triangles(tank, "gun")
	if gun == null or gun.mesh == null or raw_triangles.is_empty():
		return _invalid_gun_cap(variant_id, case_id, "missing gun mesh or source triangles")
	if raw_triangles.size() / 3 != int(config.raw_faces):
		return _invalid_gun_cap(variant_id, case_id, "expected %d raw faces, got %d" % [config.raw_faces, raw_triangles.size() / 3])
	var axis := int(config.axis)
	var front := INF
	var ring := PackedVector3Array()
	for surface in gun.mesh.get_surface_count():
		var arrays := gun.mesh.surface_get_arrays(surface)
		for vertex in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			front = minf(front, vertex[axis])
	if not is_equal_approx(front, float(config.front)):
		return _invalid_gun_cap(variant_id, case_id, "expected front %.9f on axis %d, got %.9f" % [config.front, axis, front])
	for surface in gun.mesh.get_surface_count():
		var arrays := gun.mesh.surface_get_arrays(surface)
		for vertex in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			if is_equal_approx(vertex[axis], front) and not ring.has(vertex):
				ring.append(vertex)
	if ring.size() != int(config.front_vertices):
		return _invalid_gun_cap(variant_id, case_id, "expected %d unique muzzle-plane vertices, got %d" % [config.front_vertices, ring.size()])
	var projected := PackedVector2Array()
	for vertex in ring:
		projected.append(_project_from_axial_plane(vertex, axis))
	var outer_rim := Geometry2D.convex_hull(projected)
	## Godot 回傳封閉 polygon，最後一點與第一點相同；fan 自己負責 wrap，不保留重複端點。
	if outer_rim.size() > 1 and outer_rim[0].is_equal_approx(outer_rim[outer_rim.size() - 1]):
		outer_rim.remove_at(outer_rim.size() - 1)
	if outer_rim.size() != int(config.outer_rim):
		return _invalid_gun_cap(variant_id, case_id, "expected %d outer-rim hull vertices, got %d" % [config.outer_rim, outer_rim.size()])
	var center := Vector2.ZERO
	for point in outer_rim:
		center += point
	center /= outer_rim.size()
	var cap := PackedVector3Array()
	var world_center := gun.global_transform * _restore_to_axial_plane(front, center, axis)
	for index in outer_rim.size():
		var first := outer_rim[index]
		var second := outer_rim[(index + 1) % outer_rim.size()]
		var world_first := gun.global_transform * _restore_to_axial_plane(front, first, axis)
		var world_second := gun.global_transform * _restore_to_axial_plane(front, second, axis)
		cap.append_array(PackedVector3Array([world_center, world_first, world_second, world_center, world_second, world_first]))
	var reference := raw_triangles.duplicate()
	reference.append_array(cap)
	print("MESH_CONVEX_GUN_CAP %s case=%s source_faces=%d cap_faces=%d reference_faces=%d front_axis=%d front_local=%.9f ring_vertices=%d outer_rim=%d" % [variant_id, case_id, raw_triangles.size() / 3, cap.size() / 3, reference.size() / 3, axis, front, ring.size(), outer_rim.size()])
	return {"valid": true, "triangles": reference}


func _project_from_axial_plane(vertex: Vector3, axis: int) -> Vector2:
	match axis:
		0: return Vector2(vertex.y, vertex.z)
		1: return Vector2(vertex.x, vertex.z)
		_: return Vector2(vertex.x, vertex.y)


func _restore_to_axial_plane(axial: float, point: Vector2, axis: int) -> Vector3:
	match axis:
		0: return Vector3(axial, point.x, point.y)
		1: return Vector3(point.x, axial, point.y)
		_: return Vector3(point.x, point.y, axial)


func _has_gun_cap(variant_id: String) -> bool:
	return GUN_CAP_CONFIGS.has(variant_id)


func _invalid_gun_cap(variant_id: String, case_id: StringName, reason: String) -> Dictionary:
	print("MESH_CONVEX_GUN_CAP_INVALID %s case=%s reason=%s" % [variant_id, case_id, reason])
	return {"valid": false, "triangles": PackedVector3Array()}


## Tank3 turret 的 c00 底部是被 hull 遮住的內部接合面；以其原始 boundary 封閉，外表 raw mesh 不變。
func _tank3_turret_reference_triangles(tank: CharacterBody3D, case_id: StringName) -> Dictionary:
	var turret := _part_mesh_instance(tank, "turret")
	var raw_triangles := _part_triangles(tank, "turret")
	if turret == null or turret.mesh == null or raw_triangles.size() / 3 != 392:
		return _invalid_turret_cap(case_id, "expected turret mesh with 392 raw faces")
	var local_triangles := _mesh_triangles(turret.mesh, Transform3D.IDENTITY)
	var components := _triangle_components(local_triangles)
	if components.size() != 4 or components[0].size() != 148:
		return _invalid_turret_cap(case_id, "expected 4 components with c00=148 faces")
	var min_y := INF
	for triangle_index in components[0]:
		for point in _triangle_at(local_triangles, triangle_index):
			min_y = minf(min_y, point.y)
	if not is_equal_approx(min_y, -0.230018288):
		return _invalid_turret_cap(case_id, "expected c00 min local Y=-0.230018288, got %.9f" % min_y)
	var c00_boundary := PackedVector3Array()
	for triangle_index in components[0]:
		for point in _triangle_at(local_triangles, triangle_index):
			if is_equal_approx(point.y, min_y) and not c00_boundary.has(point):
				c00_boundary.append(point)
	var all_min_y_points := PackedVector3Array()
	for triangle_index in local_triangles.size() / 3:
		for point in _triangle_at(local_triangles, triangle_index):
			if is_equal_approx(point.y, min_y) and not all_min_y_points.has(point):
				all_min_y_points.append(point)
	if c00_boundary.size() != 10 or all_min_y_points.size() != c00_boundary.size():
		return _invalid_turret_cap(case_id, "expected exactly 10 c00-only min-Y boundary points, got c00=%d all=%d" % [c00_boundary.size(), all_min_y_points.size()])
	var center_xz := Vector2.ZERO
	for point in c00_boundary:
		center_xz += Vector2(point.x, point.z)
	center_xz /= c00_boundary.size()
	var ordered: Array[Vector3] = []
	for point in c00_boundary:
		ordered.append(point)
	ordered.sort_custom(func(first: Vector3, second: Vector3) -> bool: return atan2(first.z - center_xz.y, first.x - center_xz.x) < atan2(second.z - center_xz.y, second.x - center_xz.x))
	var cap := PackedVector3Array()
	var center := turret.global_transform * Vector3(center_xz.x, min_y, center_xz.y)
	for index in ordered.size():
		var first := turret.global_transform * ordered[index]
		var second := turret.global_transform * ordered[(index + 1) % ordered.size()]
		cap.append_array(PackedVector3Array([center, first, second, center, second, first]))
	var reference := raw_triangles.duplicate()
	reference.append_array(cap)
	print("MESH_CONVEX_TURRET_CAP tank3 case=%s source_faces=%d cap_faces=%d reference_faces=%d components=%d c00_faces=%d boundary=%d plane_local_y=%.9f" % [case_id, raw_triangles.size() / 3, cap.size() / 3, reference.size() / 3, components.size(), components[0].size(), c00_boundary.size(), min_y])
	return {"valid": true, "triangles": reference}


func _invalid_turret_cap(case_id: StringName, reason: String) -> Dictionary:
	print("MESH_CONVEX_TURRET_CAP_INVALID tank3 case=%s reason=%s" % [case_id, reason])
	return {"valid": false, "triangles": PackedVector3Array()}


func _triangle_components(triangles: PackedVector3Array) -> Array:
	var triangle_count := triangles.size() / 3
	var parents := PackedInt32Array()
	parents.resize(triangle_count)
	for index in triangle_count:
		parents[index] = index
	var owner := {}
	for triangle_index in triangle_count:
		for point in _triangle_at(triangles, triangle_index):
			if owner.has(point):
				_union_component(parents, triangle_index, int(owner[point]))
			else:
				owner[point] = triangle_index
	var by_root := {}
	for triangle_index in triangle_count:
		var root_index := _find_component_parent(parents, triangle_index)
		if not by_root.has(root_index):
			by_root[root_index] = PackedInt32Array()
		by_root[root_index].append(triangle_index)
	var components: Array = by_root.values()
	components.sort_custom(func(first: PackedInt32Array, second: PackedInt32Array) -> bool: return first[0] < second[0])
	return components


func _triangle_at(triangles: PackedVector3Array, triangle_index: int) -> PackedVector3Array:
	var offset := triangle_index * 3
	return PackedVector3Array([triangles[offset], triangles[offset + 1], triangles[offset + 2]])


func _find_component_parent(parents: PackedInt32Array, value: int) -> int:
	var current := value
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current


func _union_component(parents: PackedInt32Array, first: int, second: int) -> void:
	var first_root := _find_component_parent(parents, first)
	var second_root := _find_component_parent(parents, second)
	if first_root != second_root:
		parents[second_root] = first_root


## 僅 Tank1 已審核的 hull c16 天線可略過；component 身分一律由 local raw faces exact-weld 決定。
func _tank1_hull_reference_triangles(tank: CharacterBody3D, case_id: StringName) -> Dictionary:
	var hull := _part_mesh_instance(tank, "hull")
	if hull == null or hull.mesh == null:
		return _invalid_hull_decoration(case_id, "missing hull mesh")
	var local_faces := _mesh_triangles(hull.mesh, Transform3D.IDENTITY)
	var world_faces := _part_triangles(tank, "hull")
	var components := _triangle_components(local_faces)
	if local_faces.size() / 3 != 4896 or world_faces.size() != local_faces.size() or components.size() != 53 or components[16].size() != 44:
		return _invalid_hull_decoration(case_id, "expected 4896 faces, 53 components, c16=44 faces; got local=%d world=%d components=%d c16=%d" % [local_faces.size() / 3, world_faces.size() / 3, components.size(), components[16].size()])
	var decoration := PackedVector3Array()
	var filtered := PackedVector3Array()
	for triangle_index in local_faces.size() / 3:
		if _component_contains(components[16], triangle_index):
			decoration.append_array(_triangle_at(world_faces, triangle_index))
		else:
			filtered.append_array(_triangle_at(world_faces, triangle_index))
	if decoration.size() / 3 != 44 or filtered.size() / 3 != 4852:
		return _invalid_hull_decoration(case_id, "component filtering face count mismatch")
	var decoration_bounds := _triangle_bounds(decoration)
	if not _is_tank1_antenna_bounds(decoration_bounds):
		return _invalid_hull_decoration(case_id, "c16 is not the expected tall narrow antenna: %s" % decoration_bounds)
	return {
		"valid": true,
		"triangles": filtered,
		"decoration": decoration,
		"decoration_local_vertices": _component_vertices(local_faces, components[16]),
	}


func _probe_tank1_hull_decoration_exclusion(tank: CharacterBody3D) -> bool:
	var reference := _tank1_hull_reference_triangles(tank, &"antenna_exclusion")
	if not bool(reference.valid):
		return false
	var hull_part: TankPartDefinition = tank.part_geometry.part_named(&"hull")
	if hull_part == null or hull_part.convex_shapes.size() != 7:
		print("MESH_CONVEX_HULL_DECORATION_INVALID tank1 reason=expected 7 formal hull shapes")
		return false
	var decoration_local := reference.decoration_local_vertices as PackedVector3Array
	var world_samples: PackedVector3Array = tank.part_world_surface_points()
	var hull_mesh := _part_mesh_instance(tank, "hull")
	if hull_mesh == null:
		return false
	for sample_index in hull_part.surface_points.size():
		var local_sample: Vector3 = hull_mesh.global_transform.affine_inverse() * world_samples[sample_index]
		if decoration_local.has(local_sample):
			print("MESH_CONVEX_HULL_DECORATION_INVALID tank1 reason=surface sample lands on c16")
			return false
	var decoration := reference.decoration as PackedVector3Array
	var bounds := _triangle_bounds(decoration)
	var from := Vector3(bounds.end.x + 0.2, bounds.get_center().y, bounds.get_center().z)
	var to := Vector3(bounds.position.x - 0.2, bounds.get_center().y, bounds.get_center().z)
	var source := _make_source_body(decoration)
	root.add_child(source)
	await physics_frame
	var raw_hit := _ray_hit(tank, from, to, SOURCE_LAYER, source)
	var formal_hit := _ray_hit(tank, from, to, tank.collision_layer, tank)
	source.queue_free()
	await physics_frame
	if raw_hit.is_empty() or not formal_hit.is_empty():
		print("MESH_CONVEX_HULL_DECORATION_RAY_FAIL tank1 raw=%s formal=%s" % [raw_hit, formal_hit])
		return false
	print("MESH_CONVEX_HULL_DECORATION_EXCLUDED tank1 faces=44 shapes=7 samples=%d from=%s to=%s" % [hull_part.surface_points.size(), from, to])
	return true


func _component_contains(component: PackedInt32Array, triangle_index: int) -> bool:
	return component.has(triangle_index)


func _component_vertices(triangles: PackedVector3Array, component: PackedInt32Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for triangle_index in component:
		for point in _triangle_at(triangles, triangle_index):
			if not result.has(point):
				result.append(point)
	return result


func _is_tank1_antenna_bounds(bounds: AABB) -> bool:
	return bounds.size.x > 0.07 and bounds.size.x < 0.08 and bounds.size.y > 1.2 and bounds.size.y < 1.3 and bounds.size.z > 0.08 and bounds.size.z < 0.09 and bounds.size.y > bounds.size.x * 10.0 and bounds.size.y > bounds.size.z * 10.0


func _invalid_hull_decoration(case_id: StringName, reason: String) -> Dictionary:
	print("MESH_CONVEX_HULL_DECORATION_INVALID tank1 case=%s reason=%s" % [case_id, reason])
	return {"valid": false, "triangles": PackedVector3Array()}


func _has_hull_decoration_exclusion(variant_id: String) -> bool:
	return variant_id == "tank1" or HULL_DECORATION_CONFIGS.has(variant_id)


func _hull_reference_triangles(tank: CharacterBody3D, variant_id: String, case_id: StringName) -> Dictionary:
	if variant_id == "tank1":
		return _tank1_hull_reference_triangles(tank, case_id)
	var config: Dictionary = HULL_DECORATION_CONFIGS.get(variant_id, {})
	if config.is_empty():
		return _invalid_hull_component_exclusion(variant_id, case_id, "no approved decoration configuration")
	var hull := _part_mesh_instance(tank, "hull")
	if hull == null or hull.mesh == null:
		return _invalid_hull_component_exclusion(variant_id, case_id, "missing hull mesh")
	var local_faces := _mesh_triangles(hull.mesh, Transform3D.IDENTITY)
	var world_faces := _part_triangles(tank, "hull")
	var components := _triangle_components(local_faces)
	if local_faces.size() / 3 != int(config.raw_faces) or world_faces.size() != local_faces.size() or components.size() != int(config.components):
		return _invalid_hull_component_exclusion(variant_id, case_id, "expected raw=%d components=%d; got local=%d world=%d components=%d" % [config.raw_faces, config.components, local_faces.size() / 3, world_faces.size() / 3, components.size()])
	var excluded_component_ids: Dictionary = {}
	for component_id in config.excluded_components as Array:
		if int(component_id) < 0 or int(component_id) >= components.size() or excluded_component_ids.has(component_id):
			return _invalid_hull_component_exclusion(variant_id, case_id, "invalid or duplicate component c%02d" % int(component_id))
		excluded_component_ids[component_id] = true
	var excluded := PackedVector3Array()
	var excluded_local_vertices := PackedVector3Array()
	var retained := PackedVector3Array()
	var retained_local_vertices := PackedVector3Array()
	for triangle_index in local_faces.size() / 3:
		var local_triangle := _triangle_at(local_faces, triangle_index)
		if excluded_component_ids.has(_component_id_for_triangle(components, triangle_index)):
			excluded.append_array(_triangle_at(world_faces, triangle_index))
			for point in local_triangle:
				if not excluded_local_vertices.has(point):
					excluded_local_vertices.append(point)
		else:
			retained.append_array(_triangle_at(world_faces, triangle_index))
			for point in local_triangle:
				if not retained_local_vertices.has(point):
					retained_local_vertices.append(point)
	if excluded.size() / 3 != int(config.removed_faces) or retained.size() / 3 != int(config.raw_faces) - int(config.removed_faces):
		return _invalid_hull_component_exclusion(variant_id, case_id, "expected %d removed faces, got %d" % [config.removed_faces, excluded.size() / 3])
	if variant_id == "tank3":
		var roof_cap := _tank3_hull_roof_cap(tank, case_id)
		if roof_cap.is_empty():
			return _invalid_hull_component_exclusion(variant_id, case_id, "could not rebuild approved raw roof-rim cap")
		retained.append_array(roof_cap)
	return {
		"valid": true,
		"triangles": retained,
		"excluded": excluded,
		"excluded_local_vertices": excluded_local_vertices,
		"retained_local_vertices": retained_local_vertices,
	}


## Tank3 hull c00 的遮蔽內部接合穴以原始 roof-rim 建立雙面 fan；不從 collider 或暫存 JSON 取點。
func _tank3_hull_roof_cap(tank: CharacterBody3D, case_id: StringName) -> PackedVector3Array:
	var hull := _part_mesh_instance(tank, "hull")
	if hull == null or hull.mesh == null:
		return PackedVector3Array()
	## local faces only establish raw component provenance; the approved cap thresholds and plane are world-space.
	var local_faces := _mesh_triangles(hull.mesh, Transform3D.IDENTITY)
	var world_faces := _part_triangles(tank, "hull")
	var components := _triangle_components(local_faces)
	if local_faces.size() / 3 != 4390 or world_faces.size() != local_faces.size() or components.size() != 43 or components[0].size() <= 218:
		print("MESH_CONVEX_HULL_ROOF_CAP_INVALID tank3 case=%s local_faces=%d world_faces=%d components=%d" % [case_id, local_faces.size() / 3, world_faces.size() / 3, components.size()])
		return PackedVector3Array()
	var vertices := PackedVector3Array()
	for component_triangle_index in [69, 70, 71, 72, 73, 74, 213, 214, 215, 216, 217, 218]:
		var triangle_id := int(components[0][component_triangle_index])
		for point in _triangle_at(world_faces, triangle_id):
			if point.x > 2.0:
				continue
			if point.x < -1.2 and (point.z < -1.4 or point.z > 1.4):
				continue
			if not vertices.has(point):
				vertices.append(point)
	var projected := PackedVector2Array()
	for vertex in vertices:
		projected.append(Vector2(vertex.x, vertex.z))
	var ring_2d := Geometry2D.convex_hull(projected)
	if ring_2d.size() > 1 and ring_2d[0].is_equal_approx(ring_2d[ring_2d.size() - 1]):
		ring_2d.remove_at(ring_2d.size() - 1)
	if ring_2d.size() != 12:
		print("MESH_CONVEX_HULL_ROOF_CAP_INVALID tank3 case=%s expected_ring=12 actual_ring=%d" % [case_id, ring_2d.size()])
		return PackedVector3Array()
	var roof_triangle := _triangle_at(world_faces, int(components[0][69]))
	var roof_plane := Plane(roof_triangle[0], roof_triangle[1], roof_triangle[2])
	var world_ring := PackedVector3Array()
	for point_2d in ring_2d:
		for vertex in vertices:
			if Vector2(vertex.x, vertex.z).is_equal_approx(point_2d):
				if absf(roof_plane.distance_to(vertex)) >= 0.00001:
					print("MESH_CONVEX_HULL_ROOF_CAP_INVALID tank3 case=%s rim_off_plane=true" % case_id)
					return PackedVector3Array()
				world_ring.append(vertex)
				break
	if world_ring.size() != 12:
		print("MESH_CONVEX_HULL_ROOF_CAP_INVALID tank3 case=%s world_ring=%d" % [case_id, world_ring.size()])
		return PackedVector3Array()
	var center := Vector3.ZERO
	for point in world_ring:
		center += point
	center /= world_ring.size()
	var cap := PackedVector3Array()
	for index in world_ring.size():
		var first := world_ring[index]
		var second := world_ring[(index + 1) % world_ring.size()]
		cap.append_array(PackedVector3Array([center, first, second, center, second, first]))
	print("MESH_CONVEX_HULL_ROOF_CAP tank3 case=%s raw_roof_rim=12 cap_faces=%d" % [case_id, cap.size() / 3])
	return cap


func _verify_hull_decoration_exclusion(tank: CharacterBody3D, variant_id: String) -> bool:
	var reference := _hull_reference_triangles(tank, variant_id, &"decoration_exclusion")
	if not bool(reference.valid):
		return false
	var hull_part: TankPartDefinition = tank.part_geometry.part_named(&"hull")
	if hull_part == null:
		return false
	var world_samples := _part_world_surface_points(tank, &"hull")
	var excluded_world := reference.excluded as PackedVector3Array
	var retained_world := reference.triangles as PackedVector3Array
	if world_samples.size() != hull_part.surface_points.size():
		_invalid_hull_component_exclusion(variant_id, &"decoration_exclusion", "hull sample count mismatch")
		return false
	for sample in world_samples:
		if _contains_approx_vertex(excluded_world, sample) or not _contains_approx_vertex(retained_world, sample):
			_invalid_hull_component_exclusion(variant_id, &"decoration_exclusion", "saved hull sample is not a retained source vertex: %s" % sample)
			return false
	print("MESH_CONVEX_HULL_DECORATION_EXCLUDED %s faces=%d samples=%d" % [variant_id, (reference.excluded as PackedVector3Array).size() / 3, world_samples.size()])
	return true


func _part_world_surface_points(tank: CharacterBody3D, part_id: StringName) -> PackedVector3Array:
	var all_points: PackedVector3Array = tank.part_world_surface_points()
	var offset := 0
	for part in tank.part_geometry.parts:
		if part.id == part_id:
			return all_points.slice(offset, offset + part.surface_points.size())
		offset += part.surface_points.size()
	return PackedVector3Array()


func _component_id_for_triangle(components: Array, triangle_index: int) -> int:
	for component_id in components.size():
		if _component_contains(components[component_id] as PackedInt32Array, triangle_index):
			return component_id
	return -1


func _contains_approx_vertex(vertices: PackedVector3Array, target: Vector3) -> bool:
	for vertex in vertices:
		if vertex.is_equal_approx(target):
			return true
	return false


func _invalid_hull_component_exclusion(variant_id: String, case_id: StringName, reason: String) -> Dictionary:
	print("MESH_CONVEX_HULL_DECORATION_INVALID %s case=%s reason=%s" % [variant_id, case_id, reason])
	return {"valid": false, "triangles": PackedVector3Array()}


func _add_track_reference_collision(parent: Node3D, reference: Dictionary) -> void:
	var shape := reference.get("shape", null) as ConvexPolygonShape3D
	if shape == null:
		return
	var collision := CollisionShape3D.new()
	collision.shape = shape
	## parent 固定為世界原點；保留原始 mesh local frame 到 world 的靜態轉換。
	collision.transform = reference.get("transform", Transform3D.IDENTITY) as Transform3D
	parent.add_child(collision)


func _verify_track_formal_shapes(tank: CharacterBody3D, variant_id: String) -> bool:
	var valid := true
	var baselines := {}
	for phase in TRACK_REFERENCE_PHASES:
		_reset_pose(tank)
		_set_track_phase(tank, phase)
		await physics_frame
		for part_id in [&"left_track", &"right_track"]:
			var part: TankPartDefinition = tank.part_geometry.part_named(part_id)
			if part == null or part.convex_shapes.size() != 1 or not part.convex_shapes[0] is ConvexPolygonShape3D:
				print("MESH_CONVEX_TRACK_FORMAL_SHAPE_INVALID %s part=%s phase=%.2f shape_count=%d" % [variant_id, part_id, phase, part.convex_shapes.size() if part != null else 0])
				valid = false
				continue
			var snapshot := {"transform": _part_shape_world_transform(tank, part_id), "points": part.convex_shapes[0].points}
			if not baselines.has(part_id):
				baselines[part_id] = snapshot
			elif not _track_snapshot_equal(baselines[part_id], snapshot):
				print("MESH_CONVEX_TRACK_FORMAL_SHAPE_CHANGED %s part=%s phase=%.2f" % [variant_id, part_id, phase])
				valid = false
			print("MESH_CONVEX_TRACK_FORMAL_SHAPE %s part=%s phase=%.2f points=%d" % [variant_id, part_id, phase, part.convex_shapes[0].points.size()])
	return valid


func _part_shape_world_transform(tank: CharacterBody3D, part_id: StringName) -> Transform3D:
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for unused in part.convex_shapes:
			if part.id == part_id:
				return transforms[index]
			index += 1
	return Transform3D.IDENTITY


func _track_snapshot_equal(first: Dictionary, second: Dictionary) -> bool:
	var first_transform := first.transform as Transform3D
	var second_transform := second.transform as Transform3D
	if not first_transform.is_equal_approx(second_transform):
		return false
	var first_points := first.points as PackedVector3Array
	var second_points := second.points as PackedVector3Array
	if first_points.size() != second_points.size():
		return false
	for index in first_points.size():
		if not first_points[index].is_equal_approx(second_points[index]):
			return false
	return true


func _is_track(part_id: StringName) -> bool:
	return part_id == &"left_track" or part_id == &"right_track"


func _make_part_convex_body(tank: CharacterBody3D, part_id: String) -> StaticBody3D:
	var convex := StaticBody3D.new()
	convex.name = "PartConvexRaySource_%s" % part_id
	convex.collision_layer = CONVEX_LAYER
	convex.collision_mask = 0
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var shape_index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			if part.id == part_id and shape_index < transforms.size():
				var collision := CollisionShape3D.new()
				collision.shape = shape
				collision.transform = transforms[shape_index]
				convex.add_child(collision)
			shape_index += 1
	return convex


func _ray_hit(tank: CharacterBody3D, from: Vector3, to: Vector3, mask: int, expected: CollisionObject3D) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = tank.get_world_3d().direct_space_state.intersect_ray(query)
	return hit if hit.get("collider", null) == expected else {}


func _reset_pose(tank: CharacterBody3D) -> void:
	tank.global_transform = Transform3D.IDENTITY
	tank.turret_pivot.rotation = Vector3.ZERO
	tank.gun_pitch_pivot.rotation = Vector3.ZERO
	tank.call("_sync_part_collision_shapes")


func _apply_turret_yaw(tank: CharacterBody3D) -> void:
	tank.aim_turret_at(tank.global_position + Vector3.FORWARD * 100.0, 10.0)
	if is_zero_approx(tank.turret_pivot.rotation.y):
		push_error("Turret yaw probe requires a reachable nonzero yaw.")


func _apply_gun_pose(tank: CharacterBody3D) -> void:
	_apply_turret_yaw(tank)
	tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-100.0, 100.0, 0.0), 10.0)
	if is_zero_approx(tank.gun_pitch_pivot.rotation.z):
		push_error("Gun probe requires a reachable nonzero pitch.")


func _case_count(tank: CharacterBody3D) -> int:
	var whole: int = 4 * AXES.size() * 2
	var neutral: int = tank.part_geometry.parts.size() * AXES.size() * 2
	var gun: int = AXES.size() * 2
	var turret: int = AXES.size() * 2 if tank.part_geometry.part_named("turret") != null else 0
	var tracks: int = TRACK_PHASES.size() * 2 * AXES.size() * 2
	return whole + neutral + gun + turret + tracks


func _register_skins(tank: Node3D) -> void:
	for child in tank.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.skin == null or mesh.skeleton.is_empty():
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton == null:
			push_error("Skinned probe mesh has no skeleton: %s" % mesh.get_path())
			continue
		skeleton.reset_bone_poses()
		var reference := skeleton.register_skin(mesh.skin)
		if reference != null:
			_skin_references.append(reference)


func _set_track_phase(tank: CharacterBody3D, phase: float) -> void:
	var player: AnimationPlayer = tank.tread_animation_player
	if player == null or tank.tread_forward_animation.is_empty():
		return
	player.play(tank.tread_forward_animation)
	var animation: Animation = player.get_animation(tank.tread_forward_animation)
	if animation != null:
		player.seek(animation.length * phase, true)
	player.pause()


func _all_part_triangles(tank: CharacterBody3D) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	for part in tank.part_geometry.parts:
		triangles.append_array(_part_triangles(tank, part.id))
	return triangles


func _part_triangles(tank: CharacterBody3D, part_id: String) -> PackedVector3Array:
	var instance := _part_mesh_instance(tank, part_id)
	if instance == null or instance.mesh == null:
		return PackedVector3Array()
	var source: Mesh = instance.bake_mesh_from_current_skeleton_pose() if instance.skin != null else instance.mesh
	return _mesh_triangles(source, instance.global_transform) if source != null else PackedVector3Array()


func _part_mesh_instance(tank: CharacterBody3D, part_id: String) -> MeshInstance3D:
	match part_id:
		"hull": return _find_mesh_prefix(tank.tank_model, "Tank_body")
		"left_track": return _find_mesh_prefix(tank.tank_model, "TrackMesh_L")
		"right_track": return _find_mesh_prefix(tank.tank_model, "TrackMesh_R")
		"gun": return tank.tank_gun
		"turret": return tank.tank_turret as MeshInstance3D
		"fixed_upper_hull": return _find_mesh(tank.tank_model, "Tank_Turret")
	return null


func _mesh_triangles(mesh: Mesh, mesh_transform: Transform3D) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if indices.is_empty():
			for index in range(0, vertices.size() - 2, 3):
				triangles.append_array(PackedVector3Array([mesh_transform * vertices[index], mesh_transform * vertices[index + 1], mesh_transform * vertices[index + 2]]))
		else:
			for index in range(0, indices.size() - 2, 3):
				triangles.append_array(PackedVector3Array([mesh_transform * vertices[indices[index]], mesh_transform * vertices[indices[index + 1]], mesh_transform * vertices[indices[index + 2]]]))
	return triangles


func _triangle_bounds(triangles: PackedVector3Array) -> AABB:
	if triangles.is_empty():
		return AABB()
	var minimum := triangles[0]
	var maximum := minimum
	for point in triangles:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)


func _outside_bounds(bounds: AABB, direction: Vector3) -> Vector3:
	var center := bounds.get_center()
	var extent := bounds.size * 0.5
	return center + direction * (absf(direction.x) * extent.x + absf(direction.y) * extent.y + absf(direction.z) * extent.z + RAY_MARGIN)


func _part_for_shape(tank: CharacterBody3D, shape_index: int) -> String:
	var index := 0
	for part in tank.part_geometry.parts:
		for unused in part.convex_shapes:
			if index == shape_index:
				return part.id
			index += 1
	return "unknown"


func _find_mesh_prefix(root_node: Node, prefix: String) -> MeshInstance3D:
	if root_node != null:
		for child in root_node.find_children("*", "MeshInstance3D", true, false):
			if String(child.name).begins_with(prefix):
				return child as MeshInstance3D
	return null


func _find_mesh(root_node: Node, accepted_name: String) -> MeshInstance3D:
	if root_node != null:
		for child in root_node.find_children("*", "MeshInstance3D", true, false):
			if child.name == accepted_name:
				return child as MeshInstance3D
	return null


func _fail(message: String) -> bool:
	push_error(message)
	return false
