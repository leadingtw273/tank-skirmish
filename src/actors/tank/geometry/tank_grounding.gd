## LEA-176：候選履帶支撐面查詢與車身接地姿態；不移動節點或略過任何碰撞。
class_name TankGrounding
extends RefCounted

const MIN_UP_COMPONENT := 0.0001
const MIN_DIRECTION_LENGTH_SQUARED := 0.000001


## 從候選姿態的履帶接觸點向下有限取樣。
## local_points 的固定順序為 LeftFront、LeftRear、RightFront、RightRear；前三個以上的
## 命中以該前後／左右配置解算平面，兩點時改採命中法線平均，避免虛構完整平面。
static func sample_support(
	space: PhysicsDirectSpaceState3D,
	pose: Transform3D,
	local_points: Array[Vector3],
	excluded: Array[RID],
	mask: int,
	step_height: float = 0.5,
	snap_distance: float = 0.15,
	max_slope_degrees: float = 35.0,
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var raw_hits: Array = []
	var query_start_offset := maxf(step_height, 0.0) + 0.02
	var query_end_offset := maxf(snap_distance, 0.0)
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for index in local_points.size():
		var local_point := local_points[index]
		var point := pose * local_point
		## 起點只高過目前履帶點一個受限跨階窗口；不從任意高處尋找地板。
		query.from = point + Vector3.UP * query_start_offset
		query.to = point + Vector3.DOWN * query_end_offset
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var position := hit.get("position", point) as Vector3
		var hit_normal := (hit.get("normal", Vector3.ZERO) as Vector3).normalized()
		var height_delta := position.y - point.y
		raw_hits.append({
			"sample_index": index,
			"local_point": local_point,
			"world_point": point,
			"height_delta": height_delta,
			"hit": hit,
		})
		## 向下射線仍可能命中垂直面；那不是承托履帶的候選。
		if hit_normal.y <= MIN_UP_COMPONENT:
			continue
		candidates.append({
			"sample_index": index,
			"position": position,
			"normal": hit_normal,
			"height_delta": height_delta,
			"rid": hit.get("rid", RID()) as RID,
		})

	var points: Array = []
	for candidate in candidates:
		points.append(candidate.position as Vector3)
	var normal := _candidate_normal(candidates)
	var height_delta := 0.0
	if not candidates.is_empty():
		height_delta = float(candidates[0].height_delta)
		for candidate in candidates:
			## 用最高命中相對於自身履帶點的差，避免跨階時任一履帶沉入地面。
			height_delta = maxf(height_delta, float(candidate.height_delta))
	var max_slope_cosine := cos(deg_to_rad(clampf(max_slope_degrees, 0.0, 89.999)))
	var too_steep := candidates.size() >= 2 and normal.y < max_slope_cosine
	if not too_steep:
		for candidate in candidates:
			if (candidate.normal as Vector3).y < max_slope_cosine:
				too_steep = true
				break
	var supported := candidates.size() >= 2 and not too_steep
	var support_rids: Array[RID] = []
	if supported:
		for candidate in candidates:
			var rid := candidate.rid as RID
			if rid.is_valid() and not support_rids.has(rid):
				support_rids.append(rid)
	return {
		"supported": supported,
		"normal": normal,
		"height_delta": height_delta,
		"points": points,
		"too_steep": too_steep,
		"support_rids": support_rids,
		"raw_hits": raw_hits,
	}


## 只平順地旋轉正交 Basis；車頭本地 -X 的水平偏航會被保留。
static func aligned_basis(current: Basis, normal: Vector3, delta: float, rate: float = 8.0) -> Basis:
	var up := normal.normalized()
	if up.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return current.orthonormalized()
	var heading := -current.x
	heading.y = 0.0
	if heading.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		heading = -current.z
		heading.y = 0.0
	if heading.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	var forward := heading.slide(up)
	if forward.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		forward = up.cross(Vector3.RIGHT)
	if forward.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		forward = up.cross(Vector3.FORWARD)
	forward = forward.normalized()
	var right := -forward
	var back := right.cross(up).normalized()
	var target := Basis(right, up, back).orthonormalized()
	var weight := clampf(maxf(delta, 0.0) * maxf(rate, 0.0), 0.0, 1.0)
	return current.orthonormalized().slerp(target, weight).orthonormalized()


static func _candidate_normal(candidates: Array[Dictionary]) -> Vector3:
	if candidates.is_empty():
		return Vector3.UP
	var averaged_normals := Vector3.ZERO
	for candidate in candidates:
		averaged_normals += candidate.normal as Vector3
	if averaged_normals.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		averaged_normals = Vector3.UP
	averaged_normals = averaged_normals.normalized()
	if candidates.size() < 3:
		return averaged_normals if averaged_normals.y >= 0.0 else -averaged_normals
	var front: Variant = _mean_position(candidates, [0, 2])
	var rear: Variant = _mean_position(candidates, [1, 3])
	var left: Variant = _mean_position(candidates, [0, 1])
	var right: Variant = _mean_position(candidates, [2, 3])
	if front == null or rear == null or left == null or right == null:
		return averaged_normals if averaged_normals.y >= 0.0 else -averaged_normals
	var forward_span := (front as Vector3) - (rear as Vector3)
	var left_span := (left as Vector3) - (right as Vector3)
	var plane_normal := forward_span.cross(left_span)
	if plane_normal.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return averaged_normals if averaged_normals.y >= 0.0 else -averaged_normals
	plane_normal = plane_normal.normalized()
	return plane_normal if plane_normal.y >= 0.0 else -plane_normal


static func _mean_position(candidates: Array[Dictionary], indices: Array[int]) -> Variant:
	var total := Vector3.ZERO
	var count := 0
	for candidate in candidates:
		if indices.has(int(candidate.sample_index)):
			total += candidate.position as Vector3
			count += 1
	return total / float(count) if count > 0 else null
