## 同一靜止 Box 完整覆蓋的平地解析支撐；證明不足就交回完整查詢。
extends RefCounted

static func try_segment(solver: RefCounted, start: Transform3D, states: Array[Dictionary], dt: float) -> Dictionary:
	if states.is_empty() or solver.contact_policy.is_valid() or not solver._snapshot_grounded:
		return {}
	if not solver._rigid_pose(start) or not solver.has_support_points: return {}
	var support: Dictionary = solver._support(start, 0.0)
	var hits: Array = support.get("raw_hits", [])
	if not bool(support.get("supported", false)) or hits.size() != 4: return {}
	var floor_hit: Dictionary = hits[0].hit
	var body := floor_hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return {}
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return {}
	for sample: Dictionary in hits:
		if sample.hit.rid != floor_hit.rid or int(sample.hit.shape) != int(floor_hit.shape): return {}
	var plane: Dictionary = solver._box_plane(floor_hit)
	if plane.is_empty() or (plane.normal as Vector3) != Vector3.UP: return {}
	var floor_transform: Transform3D = plane.transform
	if not solver._rigid_pose(floor_transform): return {}
	var floor_y: float = plane.point.y
	var points: Array[Vector3] = solver.tank._prediction_support_points
	if points.size() != 4: return {}
	var poses: Array[Transform3D] = [start]
	var current := start
	for state: Dictionary in states:
		if not solver._reserve(0): return {}
		var rotated := Transform3D(Basis(Vector3.UP, float(state.angular_speed) * dt) * current.basis, current.origin)
		poses.append(rotated)
		var candidate := rotated.translated(rotated.basis * Vector3.LEFT * float(state.forward_speed) * dt + (state.get("drift", Vector3.ZERO) as Vector3))
		var rise := _height_delta(solver, candidate, points, floor_y)
		if not is_finite(rise) or rise > solver.tank.ground_step_height: return {}
		candidate.origin.y += rise + solver.MARGIN * 2.0
		var raised := rotated
		raised.origin.y = maxf(rotated.origin.y, candidate.origin.y)
		poses.append(raised)
		var across := raised
		across.origin.x = candidate.origin.x
		across.origin.z = candidate.origin.z
		poses.append(across)
		poses.append(candidate)
		candidate.basis = solver.Grounding.aligned_basis(candidate.basis, Vector3.UP, dt, solver.tank.ground_alignment_rate)
		var aligned_rise := _height_delta(solver, candidate, points, floor_y)
		if not is_finite(aligned_rise): return {}
		candidate.origin.y += maxf(aligned_rise, 0.0)
		poses.append(candidate)
		current = candidate
	var volume: AABB = start * solver.full_bounds
	var part_volumes: Array[AABB] = []
	for part: Dictionary in solver.part_bounds:
		part_volumes.append(start * (part.box as AABB))
	var previous := start
	var angle_max := 0.0
	for pose: Transform3D in poses:
		if not solver._reserve(0) or not solver._rigid_pose(pose): return {}
		angle_max = maxf(angle_max, previous.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion()))
		volume = volume.merge(pose * solver.full_bounds)
		for index in solver.part_bounds.size():
			part_volumes[index] = part_volumes[index].merge(pose * (solver.part_bounds[index].box as AABB))
		previous = pose
	# r*theta 包住偏航、俯仰及側傾的中間旋轉，不只驗終點。
	var padding: float = solver.radius * angle_max + solver.MARGIN
	volume = volume.grow(padding)
	for index in solver.part_bounds.size():
		if not solver.hull_shapes[int(solver.part_bounds[index].indices[0])]:
			if part_volumes[index].position.y - padding <= floor_y + solver.MARGIN: return {}
	var inverse := floor_transform.affine_inverse()
	var half: Vector3 = (plane.size as Vector3) * 0.5
	for x in [volume.position.x, volume.end.x]:
		for z in [volume.position.z, volume.end.z]:
			var local := inverse * Vector3(x, floor_y, z)
			if absf(local.x) >= half.x - solver.MARGIN or absf(local.z) >= half.z - solver.MARGIN: return {}
	# 同 RID 其他 shape 不能跟著支撐地板被放行。
	volume = volume.expand(Vector3(volume.get_center().x, floor_y - solver.MARGIN, volume.get_center().z))
	var obstacles: Array = solver._broad_hits(volume, solver.part_bounds.size() + solver.shapes.size() + 8)
	if solver.at_cap or obstacles.is_empty(): return {}
	for hit: Dictionary in obstacles:
		if hit.rid == floor_hit.rid and int(hit.shape) == int(floor_hit.shape): continue
		if not _outside_parts(solver, hit, part_volumes, padding): return {}
	if not solver._reserve(0): return {}
	return {"safe": true, "root": current, "speed": float(states[-1].forward_speed),
		"angular": float(states[-1].angular_speed), "vertical_speed": 0.0, "grounded": true}

static func _outside_parts(solver: RefCounted, hit: Dictionary, parts: Array[AABB], padding: float) -> bool:
	var body := hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return false
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
	var box: Dictionary = solver._box_plane(hit)
	if box.is_empty() or parts.is_empty(): return false
	var size: Vector3 = box.size
	var obstacle: AABB = (box.transform as Transform3D) * AABB(-size * 0.5, size)
	# 各部位包住全部平移路徑，並以 r*theta 補齊取樣間的旋轉掃掠。
	# 只排除整車大框的空白區；任何部位可能接觸都交回完整預測。
	for part: AABB in parts:
		if not solver._reserve(0) or part.grow(padding + solver.MARGIN).intersects(obstacle): return false
	return true

static func _height_delta(solver: RefCounted, pose: Transform3D, points: Array[Vector3], floor_y: float) -> float:
	var highest := -INF
	for point: Vector3 in points:
		var delta := floor_y - (pose * point).y
		# 不命中原四射線範圍以外的地面。
		if delta > solver.tank.ground_step_height + 0.02 or delta < -(solver.tank.ground_snap_distance + solver.tank.ground_step_height): return INF
		highest = maxf(highest, delta)
	return highest
