## Same ground integration, with a complete segment collision proof before acceptance.
extends RefCounted
const MeshSupport := preload("res://src/ai/planar_mesh_support.gd")
const PlanarSupport := preload("res://src/ai/rigid_planar_support_domain.gd")
const ShapeSweep := preload("res://src/ai/rigid_braking_sweep.gd")

static func try_segment(solver: RefCounted, start: Transform3D, states: Array[Dictionary], dt: float, vertical: float, grounded: bool, plane_y: float = INF, floor_heights: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	if states.is_empty() or solver.contact_policy.is_valid(): return {}
	var analytic := is_finite(plane_y) or floor_heights.size() == 4
	if floor_heights.is_empty() and is_finite(plane_y): floor_heights = PackedFloat64Array([plane_y,plane_y,plane_y,plane_y])
	var poses: Array[Transform3D] = [start]
	var ray_poses: Array[Transform3D] = [start]
	var current := start
	for state: Dictionary in states:
		if not solver._reserve(0): return {}
		var rotated := Transform3D(Basis(Vector3.UP, float(state.angular_speed) * dt) * current.basis, current.origin)
		poses.append(rotated)
		var candidate := rotated.translated(rotated.basis * Vector3.LEFT * float(state.forward_speed) * dt + (state.get("drift", Vector3.ZERO) as Vector3))
		ray_poses.append(candidate)
		var support: Dictionary = _plane_support(solver, candidate, floor_heights) if analytic else solver._motion_support(candidate, solver.tank.ground_step_height)
		if support.is_empty(): return {}
		if solver.at_cap: return {}
		grounded = bool(support.get("supported", false)) and not bool(support.get("too_steep", false))
		if grounded:
			var rise: float = float(support.get("height_delta", 0.0)) + solver.MARGIN * 2.0
			if rise > solver.tank.ground_step_height + solver.MARGIN * 2.0: return {}
			candidate.origin.y += rise
			candidate.basis = solver.Grounding.aligned_basis(candidate.basis, support.normal, dt, solver.tank.ground_alignment_rate)
			ray_poses.append(candidate)
			var aligned: Dictionary = _plane_support(solver, candidate, floor_heights) if analytic else solver._motion_support(candidate, solver.tank.ground_step_height)
			if aligned.is_empty(): return {}
			if solver.at_cap: return {}
			candidate.origin.y += maxf(float(aligned.get("height_delta", 0.0)), 0.0)
			vertical = 0.0
		else:
			vertical -= solver.tank.ground_gravity * dt
			candidate.origin.y += vertical * dt
		var raised := rotated
		raised.origin.y = maxf(rotated.origin.y, candidate.origin.y)
		poses.append(raised)
		var across := raised
		across.origin.x = candidate.origin.x
		across.origin.z = candidate.origin.z
		poses.append(across)
		var descent := Vector3(0.0, candidate.origin.y - across.origin.y, 0.0)
		# Match advance() even when cast_motion returns exactly one.
		var landed := across.translated(descent * maxf(0.0, 1.0 - solver.MARGIN / maxf(descent.length(), solver.MARGIN)))
		poses.append(landed)
		# Keep every original pitch sample: its terrain ceiling can be lower than the endpoints.
		var angle := landed.basis.get_rotation_quaternion().angle_to(candidate.basis.get_rotation_quaternion())
		var count := maxi(1, ceili(solver.radius * angle / solver.MAX_ARC))
		var basis_start := landed.basis
		for index in count:
			if not solver._reserve(0): return {}
			landed.basis = basis_start.slerp(candidate.basis, float(index + 1) / count).orthonormalized()
			poses.append(landed)
		current = landed
	if analytic and not PlanarSupport.covers_points(solver, ray_poses, floor_heights): return {}
	if not _clear(solver, poses): return {}
	return {"safe": true, "root": current, "speed": float(states[-1].forward_speed), "angular": float(states[-1].angular_speed), "vertical_speed": vertical, "grounded": grounded}

static func _plane_support(solver: RefCounted, pose: Transform3D, floors: PackedFloat64Array) -> Dictionary:
	var height := -INF
	var points: Array[Vector3] = solver.tank._prediction_support_points
	if points.size() != 4 or floors.size() != 4: return {}
	var positions: Array[Vector3] = []
	for index in 4:
		var point := pose * points[index]
		if not point.is_finite() or not is_finite(floors[index]): return {}
		var delta := floors[index] - point.y
		if delta >= solver.tank.ground_step_height + 0.02 or delta <= -(solver.tank.ground_snap_distance + solver.tank.ground_step_height): return {}
		height = maxf(height, delta)
		positions.append(Vector3(point.x, floors[index], point.z))
	var normals: Array[Vector3] = [Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP]
	var normal: Vector3 = solver.MotionSupport._normal(PackedInt32Array([0,1,2,3]), positions, normals)
	var steep: bool = normal.y < cos(deg_to_rad(clampf(solver.tank.ground_max_slope_degrees,0.0,89.999)))
	return {"supported": not steep, "too_steep": steep, "normal": normal, "height_delta": height}

static func _clear(solver: RefCounted, poses: Array[Transform3D]) -> bool:
	var volumes: Array[AABB] = []
	var local_bounds: Array[AABB] = []
	for part: Dictionary in solver.part_bounds:
		local_bounds.append(part.box as AABB)
		volumes.append(poses[0] * local_bounds[-1])
	var maximum_angle := 0.0
	var ceiling := INF
	var previous := poses[0]
	var first_pose := true
	for pose in poses:
		# Consecutive identical transforms contribute neither a new swept volume
		# nor a different support ceiling/rotation. Retain exact equality only.
		if not first_pose and pose == previous: continue
		first_pose = false
		if not solver._reserve(0) or not solver._rigid_pose(pose): return false
		var difference := (previous.basis.x-pose.basis.x).length_squared() + (previous.basis.y-pose.basis.y).length_squared() + (previous.basis.z-pose.basis.z).length_squared()
		maximum_angle = maxf(maximum_angle, 2.0 * asin(minf(1.0, sqrt(difference)*0.5)))
		ceiling = minf(ceiling, solver._terrain_ceiling(pose))
		for index in volumes.size(): volumes[index] = volumes[index].merge(pose * local_bounds[index])
		previous = pose
	var refined := false
	var oriented_parts: Array[AABB] = []
	var separated_hits: Dictionary = {}
	for index in volumes.size():
		var part: Dictionary = solver.part_bounds[index]
		var volume := volumes[index].grow(float(part.radius)*maximum_angle + solver.MARGIN*2.0)
		var hits: Array = solver._broad_hits(volume, index)
		if solver.at_cap: return false
		var hull: bool = solver.hull_shapes[int(part.indices[0])]
		for hit: Dictionary in hits:
			# This certificate covers all shapes over this complete segment,
			# including non-hull groups that encounter the same native RID/shape.
			var separated_shapes: Dictionary = separated_hits.get(hit.rid, {})
			if separated_shapes.has(int(hit.shape)):
				if not solver._reserve(0): return false
				solver.diagnostic["segment_oriented_cache_hits"] = int(solver.diagnostic.get("segment_oriented_cache_hits", 0)) + 1
				continue
			if hull:
				if not solver._terrain.body_is_traversable(hit.get("collider") as Node3D, ceiling, solver._reserve):
					# Broad hits include cache expansion. Prove separation from the full
					# padded sweep before treating an unrelated building as a blocker.
					if MeshSupport.outside_parts(solver, hit, Transform3D.IDENTITY, [volume]): continue
					# Replace an overlapping grouped box only with a complete proof
					# for all original shapes over the same poses and rotation arcs.
					if oriented_parts.is_empty(): oriented_parts = ShapeSweep._oriented_parts(solver, poses[0], poses, 0.0, maximum_angle)
					if not oriented_parts.is_empty() and MeshSupport.outside_parts(solver, hit, poses[0], oriented_parts):
						separated_shapes[int(hit.shape)] = true
						separated_hits[hit.rid] = separated_shapes
						solver.diagnostic["segment_oriented_separations"] = int(solver.diagnostic.get("segment_oriented_separations", 0)) + 1
						continue
					if solver.at_cap or refined: return false
					refined = true
					var actual_ceiling := INF
					var seen: Dictionary = {}
					for pose in poses:
						if seen.has(pose): continue
						seen[pose] = true
						actual_ceiling = minf(actual_ceiling, solver.refined_terrain_ceiling(pose))
						if solver.at_cap: return false
						# One unchanged minimum already prevents improving this segment.
						if actual_ceiling <= ceiling: return false
					ceiling = actual_ceiling
					if not solver._terrain.body_is_traversable(hit.get("collider") as Node3D, ceiling, solver._reserve): return false
			elif not _below_part(solver, hit, volume.position.y):
				if not MeshSupport.outside_parts(solver, hit, Transform3D.IDENTITY, [volume]): return false
	return solver._reserve(0)

static func _below_part(solver: RefCounted, hit: Dictionary, minimum_y: float) -> bool:
	var body := hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return false
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
	var owner := body.shape_find_owner(int(hit.shape))
	var node := body.shape_owner_get_owner(owner) as CollisionShape3D
	if node == null or node.shape == null: return false
	var local: Dictionary = solver._terrain._local_bounds(node.shape, solver._reserve)
	if local.is_empty() or solver.at_cap: return false
	var world: AABB = node.global_transform * (local.bounds as AABB).grow(maxf(node.shape.margin, solver.MARGIN))
	return world.position.is_finite() and world.size.is_finite() and world.end.y < minimum_y - solver.MARGIN
