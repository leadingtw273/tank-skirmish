## Allocation-light equivalent of TankGrounding.sample_support for motion prediction.
extends RefCounted

const MIN_UP_COMPONENT := 0.0001
const MIN_DIRECTION_LENGTH_SQUARED := 0.000001

static func sample(space: PhysicsDirectSpaceState3D, pose: Transform3D, local_points: Array[Vector3], excluded: Array[RID], mask: int, step_height: float, snap_distance: float, max_slope_degrees: float, reusable_query: PhysicsRayQueryParameters3D = null) -> Dictionary:
	var indices := PackedInt32Array()
	var positions: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var heights := PackedFloat64Array()
	var query := reusable_query if reusable_query != null else PhysicsRayQueryParameters3D.new()
	query.collision_mask = mask; query.exclude = excluded; query.collide_with_bodies = true; query.collide_with_areas = false
	query.hit_back_faces = true; query.hit_from_inside = false
	var zero_window_floor := INF
	var zero_window_valid := true
	var up := maxf(step_height, 0.0) + 0.02
	var down := maxf(snap_distance, 0.0)
	for index in local_points.size():
		var point := pose * local_points[index]
		query.from = point + Vector3.UP * up; query.to = point + Vector3.DOWN * down
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			zero_window_valid = false
			continue
		var normal := (hit.get("normal", Vector3.ZERO) as Vector3).normalized()
		if normal.y <= MIN_UP_COMPONENT:
			zero_window_valid = false
			continue
		var hit_position: Vector3 = hit.get("position", point)
		# Reuse only four static horizontal first hits strictly below the original
		# step-zero ray origin. The taller motion ray then has the same first hit.
		if not hit.get("collider") is StaticBody3D or normal.y < 0.999999 or hit_position.y >= point.y + 0.019:
			zero_window_valid = false
		zero_window_floor = minf(zero_window_floor, hit_position.y)
		indices.append(index); positions.append(hit.get("position", point) as Vector3); normals.append(normal); heights.append(positions[-1].y-point.y)
	var normal := _normal(indices, positions, normals)
	var height := 0.0
	if not heights.is_empty():
		height = heights[0]
		for value in heights: height = maxf(height, value)
	var cosine := cos(deg_to_rad(clampf(max_slope_degrees, 0.0, 89.999)))
	var steep := indices.size() >= 2 and normal.y < cosine
	if not steep:
		for value in normals:
			if value.y < cosine: steep = true; break
	return {"supported":indices.size() >= 2 and not steep,"too_steep":steep,"normal":normal,"height_delta":height,"step_zero_floor_y":zero_window_floor if zero_window_valid and indices.size() == 4 and not steep else -INF}

static func _normal(indices: PackedInt32Array, points: Array[Vector3], normals: Array[Vector3]) -> Vector3:
	if indices.is_empty(): return Vector3.UP
	var average := Vector3.ZERO
	for normal in normals: average += normal
	average = Vector3.UP if average.length_squared() < MIN_DIRECTION_LENGTH_SQUARED else average.normalized()
	if indices.size() < 3: return average if average.y >= 0.0 else -average
	var front: Variant = _mean(indices, points, PackedInt32Array([0,2])); var rear: Variant = _mean(indices, points, PackedInt32Array([1,3]))
	var left: Variant = _mean(indices, points, PackedInt32Array([0,1])); var right: Variant = _mean(indices, points, PackedInt32Array([2,3]))
	if front == null or rear == null or left == null or right == null: return average if average.y >= 0.0 else -average
	var plane := ((front as Vector3)-(rear as Vector3)).cross((left as Vector3)-(right as Vector3))
	if plane.length_squared() < MIN_DIRECTION_LENGTH_SQUARED: return average if average.y >= 0.0 else -average
	plane = plane.normalized(); return plane if plane.y >= 0.0 else -plane

static func _mean(indices: PackedInt32Array, points: Array[Vector3], wanted: PackedInt32Array) -> Variant:
	var total := Vector3.ZERO; var count := 0
	for i in indices.size():
		if wanted.has(indices[i]): total += points[i]; count += 1
	return total / float(count) if count > 0 else null
