## Prove the actual four downward ray columns, independently of hull collision clearance.
extends RefCounted
const MeshSupport := preload("res://src/ai/planar_mesh_support.gd")

static func covers(solver: RefCounted, poses: Array[Transform3D], floor_y: float) -> bool:
	return covers_points(solver, poses, PackedFloat64Array([floor_y,floor_y,floor_y,floor_y]))

static func covers_points(solver: RefCounted, poses: Array[Transform3D], floors: PackedFloat64Array) -> bool:
	var points: Array[Vector3] = solver.tank._prediction_support_points
	if poses.is_empty() or points.size() != 4 or floors.size() != 4: return false
	for index in 4:
		if not is_finite(floors[index]) or not points[index].is_finite(): return false
		var world := poses[0] * points[index]
		var column := AABB(Vector3(world.x, floors[index], world.z), Vector3.ZERO)
		for pose in poses:
			if not solver._reserve(0) or not solver._rigid_pose(pose): return false
			var point := pose * points[index]
			column = column.expand(Vector3(point.x, point.y + solver.tank.ground_step_height + 0.02, point.z))
		if not _covers_column(solver, column.grow(solver.MARGIN), floors[index], index): return false
	return solver._reserve(0)

static func _covers_column(solver: RefCounted, column: AABB, floor_y: float, index: int) -> bool:
	var combined := {"triangles": [] as Array[PackedVector2Array], "other_bounds": [] as Array[AABB], "other_max_y": [] as Array[float], "other_faces": [] as Array[PackedVector3Array], "minimum_support_height": INF}
	var hits: Array = solver._broad_hits(column, solver.part_bounds.size()+solver.shapes.size()+20+index)
	if solver.at_cap or hits.is_empty(): return false
	for hit: Dictionary in hits:
		var body := hit.get("collider") as StaticBody3D
		if body == null or body is AnimatableBody3D: return false
		if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
		var node := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as CollisionShape3D
		if node == null or node.shape == null: return false
		# Analytic support needs native UP normals, not merely two-sided collision coverage.
		if node.shape is ConcavePolygonShape3D and node.shape.backface_collision: return false
		var sample := hit.duplicate()
		sample.position = Vector3(0, floor_y, 0)
		sample.normal = Vector3.UP
		var cache_key := [hit.rid, int(hit.shape), floor_y]
		if not solver._planar_mesh_cache.has(cache_key):
			var read_patch := MeshSupport.read(solver, sample, [{"hit": sample}])
			if solver.at_cap: return false
			solver._planar_mesh_cache[cache_key] = read_patch
		var patch: Dictionary = solver._planar_mesh_cache[cache_key]
		if not patch.is_empty():
			for key in ["triangles", "other_bounds", "other_max_y", "other_faces"]:
				if not patch.get(key) is Array: return false
			if patch.other_max_y.size() != patch.other_bounds.size() or patch.other_faces.size() != patch.other_bounds.size(): return false
			var minimum_height: float = patch.get("minimum_support_height", NAN)
			if not is_finite(minimum_height): return false
			combined.triangles.append_array(patch.triangles)
			combined.other_bounds.append_array(patch.other_bounds)
			combined.other_max_y.append_array(patch.other_max_y)
			combined.other_faces.append_array(patch.other_faces)
			combined.minimum_support_height = minf(float(combined.minimum_support_height), minimum_height)
			continue
		var plane: Dictionary = solver._box_plane(hit)
		if not plane.is_empty() and (plane.normal as Vector3) == Vector3.UP and absf((plane.point as Vector3).y-floor_y) <= MeshSupport.HEIGHT_EPS:
			var transform: Transform3D = plane.transform
			if not solver._rigid_pose(transform): return false
			var half: Vector3 = (plane.size as Vector3)*0.5
			var a := transform * Vector3(-half.x, half.y, -half.z)
			var b := transform * Vector3(half.x, half.y, -half.z)
			var c := transform * Vector3(half.x, half.y, half.z)
			var d := transform * Vector3(-half.x, half.y, half.z)
			combined.minimum_support_height = minf(float(combined.minimum_support_height), minf(minf(a.y, b.y), minf(c.y, d.y)))
			combined.triangles.append(PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)]))
			combined.triangles.append(PackedVector2Array([Vector2(a.x,a.z),Vector2(c.x,c.z),Vector2(d.x,d.z)]))
			continue
		var local: Dictionary = solver._terrain._local_bounds(node.shape, solver._reserve)
		if local.is_empty() or solver.at_cap: return false
		var obstacle: AABB = node.global_transform * (local.bounds as AABB).grow(maxf(node.shape.margin,solver.MARGIN))
		if not obstacle.position.is_finite() or not obstacle.size.is_finite(): return false
		if column.intersects(obstacle): return false
	# The actual first-hit floor is known for this foot. Preserve exact face
	# heights so buried tile sides do not masquerade as blockers at the column's
	# padded lower boundary. Full column coverage and the later body sweep remain.
	if not MeshSupport.covers(solver, combined, column, [column], floor_y): return false
	return solver._reserve(0)
