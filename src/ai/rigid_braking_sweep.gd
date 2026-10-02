## 有限平地模型的完整形狀包絡。未知支撐交回既有地形路徑。
extends RefCounted
const Flat := preload("res://src/actors/rigid_tank/rigid_flat_ground_prediction.gd")
const StationSupport := preload("res://src/ai/rigid_station_support_domain.gd")
const MeshSupport := preload("res://src/ai/planar_mesh_support.gd")

static func check(solver: RefCounted, start: Transform3D, poses: Array[Transform3D], reserve: float, peak_vertex_speed: float = INF) -> Dictionary:
	for key in ["braking_unknown", "mesh_support_failure", "mesh_oriented_failure", "station_support_verified", "station_support_failure", "station_envelope", "station_base_reserve", "station_attitude_reserve"]:
		solver.diagnostic.erase(key)
	var profile_started := Time.get_ticks_usec()
	solver.diagnostic["braking_profile"] = {}
	if poses.is_empty() or solver.contact_policy.is_valid() or not solver._snapshot_grounded: return _unknown(solver, "B01")
	if not solver._rigid_pose(start) or not solver.has_support_points: return _unknown(solver, "B02")
	var support: Dictionary = solver._support(start, 0.0)
	var hits: Array = support.get("raw_hits", [])
	if not bool(support.get("supported", false)) or hits.size() != 4: return _unknown(solver, "B03")
	var floor_hit: Dictionary = hits[0].hit
	var body := floor_hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return _unknown(solver, "B04")
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return _unknown(solver, "B05")
	var mixed_support := false
	for sample: Dictionary in hits:
		if sample.hit.rid != floor_hit.rid or int(sample.hit.shape) != int(floor_hit.shape): mixed_support = true
	var plane: Dictionary = solver._box_plane(floor_hit)
	if mixed_support: plane = {}
	if plane.is_empty():
		for sample: Dictionary in hits:
			if (sample.hit.normal as Vector3).distance_to(Vector3.UP) > 0.000001: return _unknown(solver, "B06")
			if absf((sample.hit.position as Vector3).y-(floor_hit.position as Vector3).y) > MeshSupport.HEIGHT_EPS: return _unknown(solver, "B07")
			var sample_body := sample.hit.get("collider") as StaticBody3D
			if sample_body == null or sample_body is AnimatableBody3D: return _unknown(solver, "B08")
			if not sample_body.constant_linear_velocity.is_zero_approx() or not sample_body.constant_angular_velocity.is_zero_approx(): return _unknown(solver, "B09")
		plane = MeshSupport.read(solver, floor_hit, [hits[0]])
	if plane.is_empty() or (plane.normal as Vector3) != Vector3.UP: return _unknown(solver, "B10")
	_profile(solver, "support_plane", profile_started)
	var floor_transform: Transform3D = plane.get("transform", Transform3D.IDENTITY)
	if not solver._rigid_pose(floor_transform): return _unknown(solver, "B11")
	var floor_y: float = plane.point.y
	# Same-level Tank2 mesh calibration includes off-axis suspension relaxation.
	# Enlarge every subsequent support/full-part/oriented envelope; never reduce the base.
	if bool(plane.get("mesh", false)) and str(solver.tank.get("vehicle_id")) == "tank2":
		var extra := StationSupport.attitude_reserve(float(solver.radius), peak_vertex_speed)
		solver.diagnostic["station_base_reserve"] = reserve
		solver.diagnostic["station_attitude_reserve"] = extra
		reserve += extra
	var part_volumes: Array[AABB] = []
	for part: Dictionary in solver.part_bounds:
		part_volumes.append(start * (part.box as AABB))
	var oriented_parts: Array[AABB] = []
	var previous := start
	var maximum_angle := 0.0
	for pose: Transform3D in poses:
		if not solver._reserve(0) or not solver._rigid_pose(pose): return _unknown(solver, "B12")
		# ||R1-R0||F >= 2*sin(theta/2): avoid acos rounding small rotations to zero.
		var difference_squared := (previous.basis.x - pose.basis.x).length_squared() + (previous.basis.y - pose.basis.y).length_squared() + (previous.basis.z - pose.basis.z).length_squared()
		maximum_angle = maxf(maximum_angle, 2.0 * asin(minf(1.0, sqrt(difference_squared) * 0.5)))
		for index in solver.part_bounds.size():
			part_volumes[index] = part_volumes[index].merge(pose * (solver.part_bounds[index].box as AABB))
		previous = pose
	_profile(solver, "pose_bounds", profile_started)
	var volume := AABB()
	for index in part_volumes.size():
		var padding: float = reserve + float(solver.part_bounds[index].radius) * maximum_angle + solver.MARGIN
		part_volumes[index] = part_volumes[index].grow(padding)
		volume = part_volumes[index] if index == 0 else volume.merge(part_volumes[index])
		if not solver.hull_shapes[int(solver.part_bounds[index].indices[0])] and part_volumes[index].position.y <= floor_y + solver.MARGIN:
			return _unknown(solver, "B13")
	# Ground support belongs to the hull/tracks; overhanging gun and turret still
	# participate in every collision query, but do not require road underneath.
	var support_volume := AABB()
	var has_hull := false
	for index in part_volumes.size():
		if not solver.hull_shapes[int(solver.part_bounds[index].indices[0])]: continue
		support_volume = support_volume.merge(part_volumes[index]) if has_hull else part_volumes[index]
		has_hull = true
	if not has_hull: return _unknown(solver, "support_hull_missing")
	var support_points: Array[Vector3] = solver.tank._prediction_support_points
	if support_points.size() != 4: return _unknown(solver, "support_points_missing")
	var ray_bounds := AABB(start * support_points[0], Vector3.ZERO)
	for pose in poses:
		if not solver._reserve(0): return _unknown(solver, "support_budget")
		for point in support_points: ray_bounds = ray_bounds.expand(pose * point)
	ray_bounds = ray_bounds.grow(reserve + float(solver.radius) * maximum_angle + solver.MARGIN)
	support_volume = support_volume.merge(ray_bounds)
	if not bool(plane.get("mesh", false)):
		var inverse := floor_transform.affine_inverse()
		var half: Vector3 = (plane.size as Vector3) * 0.5
		for x in [support_volume.position.x, support_volume.end.x]:
			for z in [support_volume.position.z, support_volume.end.z]:
				var local := inverse * Vector3(x, floor_y, z)
				if absf(local.x) >= half.x - solver.MARGIN or absf(local.z) >= half.z - solver.MARGIN: return _unknown(solver, "B14")
	volume = volume.expand(Vector3(volume.get_center().x, floor_y - solver.MARGIN, volume.get_center().z))
	var hits_limit: int = solver.part_bounds.size() + solver.shapes.size() + 8
	var obstacles: Array = solver._broad_hits(volume, hits_limit)
	if solver.at_cap or obstacles.is_empty() or obstacles.size() >= hits_limit: return _unknown(solver, "B15")
	_profile(solver, "broad_hits", profile_started)
	var plane_shapes: Dictionary = {}
	if bool(plane.get("mesh", false)):
		var combined := {"triangles": [] as Array[PackedVector2Array], "other_bounds": [] as Array[AABB], "other_max_y": [] as Array[float], "other_faces": [] as Array[PackedVector3Array], "minimum_support_height": INF}
		for hit: Dictionary in obstacles:
			var sample_hit := hit.duplicate()
			sample_hit.position = Vector3(0,floor_y,0)
			sample_hit.normal = Vector3.UP
			var patch := MeshSupport.read(solver,sample_hit,[{"hit":sample_hit}])
			if patch.is_empty(): continue
			combined.triangles.append_array(patch.triangles)
			combined.other_bounds.append_array(patch.other_bounds)
			combined.other_max_y.append_array(patch.other_max_y)
			combined.other_faces.append_array(patch.other_faces)
			combined.minimum_support_height = minf(combined.minimum_support_height, patch.minimum_support_height)
			plane_shapes[str(hit.rid.get_id()) + ":" + str(int(hit.shape))] = true
		_profile(solver, "collect_mesh", profile_started)
		var mesh_covered := MeshSupport.covers(solver,combined,support_volume,part_volumes,floor_y)
		_profile(solver, "mesh_coarse", profile_started)
		if not mesh_covered and str(solver.diagnostic.get("mesh_support_failure", {}).get("reason", "")) == "nonplane_intersection":
			oriented_parts = _oriented_parts(solver,start,poses,reserve,maximum_angle)
			_profile(solver, "oriented_bounds", profile_started)
			if not oriented_parts.is_empty():
				mesh_covered = MeshSupport.covers(solver,combined,support_volume,part_volumes,floor_y,start,oriented_parts)
		_profile(solver, "mesh_refined", profile_started)
		if not mesh_covered:
			var failure: Dictionary = solver.diagnostic.get("mesh_support_failure", {})
			if str(failure.get("reason", "")) != "uncovered_rectangle" or not StationSupport.covers(solver,start,poses,reserve,floor_y,combined):
				return _unknown(solver, "B16")
	_profile(solver, "support_certificate", profile_started)
	for hit: Dictionary in obstacles:
		# 只排除同一支撐shape，同RID牆面仍須逐一檢查。
		if bool(plane.get("mesh", false)):
			if plane_shapes.has(str(hit.rid.get_id()) + ":" + str(int(hit.shape))): continue
		elif hit.rid == floor_hit.rid and int(hit.shape) == int(floor_hit.shape): continue
		if not Flat._outside_parts(solver, hit, part_volumes, 0.0):
			var obstacle: Dictionary = solver._box_plane(hit)
			if obstacle.is_empty():
				if oriented_parts.is_empty(): oriented_parts = _oriented_parts(solver,start,poses,reserve,maximum_angle)
				if oriented_parts.is_empty() or not MeshSupport.outside_parts(solver,hit,start,oriented_parts): return _unknown(solver, "B17")
				continue
			var size: Vector3 = obstacle.size
			var obstacle_bounds: AABB = (obstacle.transform as Transform3D) * AABB(-size * 0.5, size)
			# 路肩/階差改變支撐，交原地形求解器，不用平地包絡判成牆。
			if obstacle_bounds.end.y <= floor_y + float(solver.tank.ground_step_height) + 0.01: return _unknown(solver, "B18")
			# 世界 AABB 的空角不是碰撞；同一路徑另以起點座標的完整包絡證明分離。
			if _can_refine(hit, obstacle):
				if oriented_parts.is_empty():
					oriented_parts = _oriented_parts(solver, start, poses, reserve, maximum_angle)
				if _outside_oriented(solver, oriented_parts, start, obstacle): continue
			return {"safe": false}
	if not solver._reserve(0): return _unknown(solver, "B19")
	return {"safe": true}



static func _unknown(solver: RefCounted, reason: String) -> Dictionary:
	solver.diagnostic["braking_unknown"] = reason
	return {}

## 僅細化靜止、正交 Box；不替動態／未知支撐建立安全證明。
static func _can_refine(hit: Dictionary, obstacle: Dictionary) -> bool:
	var body := hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return false
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
	var basis: Basis = (obstacle.transform as Transform3D).basis
	for i in 3:
		for j in range(i + 1, 3):
			if absf(basis[i].normalized().dot(basis[j].normalized())) > 0.00001: return false
	return true

## Transform3D * AABB 包住所有八頂點；radius 從 root 到真形狀頂點計算，補齊相鄰 pose 間的旋轉。
static func _oriented_parts(solver: RefCounted, start: Transform3D, poses: Array[Transform3D], reserve: float, angle: float) -> Array[AABB]:
	var result: Array[AABB] = []
	if solver.bounds.is_empty() or solver.bounds.size() != solver.shapes.size() or solver.bounds.size() != solver.shape_radii.size(): return []
	# Preserve all 30 collider pieces; grouping them by part introduces empty corners.
	for index: int in solver.bounds.size():
		var shape_box: AABB = solver.bounds[index]
		if not shape_box.position.is_finite() or not shape_box.size.is_finite() or shape_box.size.x < 0.0 or shape_box.size.y < 0.0 or shape_box.size.z < 0.0: return []
		if not is_finite(float(solver.shape_radii[index])) or float(solver.shape_radii[index]) < 0.0: return []
		result.append(shape_box)
	var inverse := start.affine_inverse()
	var previous := start
	var first := true
	for pose: Transform3D in poses:
		if not solver._reserve(0): return []
		# Exact consecutive duplicates add no volume; every input still checks budget.
		if not first and pose == previous: continue
		first = false
		previous = pose
		var local := inverse * pose
		for index in result.size(): result[index] = result[index].merge(local * (solver.bounds[index] as AABB))
	for index in result.size():
		# 原 world part grow 與 Flat._outside_parts 各加一次 MARGIN，兩次都保留。
		result[index] = result[index].grow(reserve + float(solver.shape_radii[index]) * angle + 2.0 * solver.MARGIN)
	return result

## 沿候選軸直接投影兩個 box 的支撐半徑；非均勻 scale 保留在 basis。
static func _separated(a: AABB, transform_a: Transform3D, b: AABB, transform_b: Transform3D) -> bool:
	var offset := transform_b * b.get_center() - transform_a * a.get_center()
	var axes: Array[Vector3] = [transform_a.basis.x, transform_a.basis.y, transform_a.basis.z, transform_b.basis.x, transform_b.basis.y, transform_b.basis.z]
	for i in 3:
		for j in 3: axes.append(transform_a.basis[i].cross(transform_b.basis[j]))
	for axis in axes:
		if axis.length_squared() < 0.00000001: continue
		axis = axis.normalized()
		var radius_a := 0.0
		var radius_b := 0.0
		for i in 3:
			radius_a += absf(axis.dot(transform_a.basis[i])) * a.size[i] * 0.5
			radius_b += absf(axis.dot(transform_b.basis[i])) * b.size[i] * 0.5
		if absf(offset.dot(axis)) > radius_a + radius_b + 0.0001: return true
	return false

static func _outside_oriented(solver: RefCounted, parts: Array[AABB], start: Transform3D, obstacle: Dictionary) -> bool:
	if parts.is_empty(): return false
	var size: Vector3 = obstacle.size
	for part in parts:
		if not solver._reserve(0): return false
		if not _separated(part, start, AABB(-size*0.5,size), obstacle.transform as Transform3D): return false
	return true

static func _profile(solver: RefCounted, phase: String, started: int) -> void:
	solver.diagnostic.braking_profile[phase] = Time.get_ticks_usec() - started
