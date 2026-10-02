## AI-only same-level suspension domain. Does not approve motion or change physics.
extends RefCounted
const MeshSupport := preload("res://src/ai/planar_mesh_support.gd")
const ContactGeometry := preload("res://src/ai/rigid_station_contact_geometry.gd")
# Necessary entry bounds from Tank2 flat and moving-seam calibration, not a safety proof.
# The continuous support certificate AND the unchanged full braking sweep remain required.
const MAX_VERTICAL_SPEED := 0.0145345
const MAX_TILT := 0.00284710
# Moving-seam 35s entry; accepted only with the additional attitude allowance below.
const MAX_OFF_AXIS_SPEED := 0.018627275
# Frozen before 37.5s heldout: calibration max yaw-compensated attitude .01078061 rad.
const ATTITUDE_ALLOWANCE := 0.011

static func attitude_reserve(radius: float, peak_vertex_speed: float = INF) -> float:
	var cap := 2.0 * maxf(radius, 0.0) * sin(ATTITUDE_ALLOWANCE * 0.5)
	# Finite Tank2 calibration + independent seam/low-speed heldouts, not a
	# general suspension bound. Missing speed keeps the larger fixed allowance.
	if not is_finite(peak_vertex_speed) or peak_vertex_speed < 0.0: return cap
	return minf(cap, 0.08 * peak_vertex_speed)

static func covers(solver: RefCounted, start: Transform3D, poses: Array[Transform3D], reserve: float, floor_y: float, plane: Dictionary) -> bool:
	solver.diagnostic.erase("station_support_verified")
	solver.diagnostic["station_support_failure"] = "snapshot_envelope"
	if not solver._reserve(0) or poses.is_empty() or reserve < 0.0: return false
	var all_poses: Array[Transform3D] = [start]
	all_poses.append_array(poses)
	var tank = solver.tank
	solver.diagnostic["station_envelope"] = {"vertical": absf(tank.linear_velocity.y), "off_axis": Vector2(tank.angular_velocity.x,tank.angular_velocity.z).length(), "tilt": acos(clampf(start.basis.y.normalized().y,-1.0,1.0))}
	if str(tank.get("vehicle_id")) != "tank2": return false
	if absf(tank.linear_velocity.y) > MAX_VERTICAL_SPEED or Vector2(tank.angular_velocity.x,tank.angular_velocity.z).length() > MAX_OFF_AXIS_SPEED: return false
	if start.basis.y.normalized().dot(Vector3.UP) < cos(MAX_TILT): return false
	var direct := PhysicsServer3D.body_get_direct_state(tank.get_rid())
	if direct == null or direct.get_contact_count() != 0: return false
	var stations: Array = tank.get("_stations")
	var sphere: SphereShape3D = tank.get("_sphere")
	if stations.size() != 10 or sphere == null or sphere.radius <= MeshSupport.HEIGHT_EPS: return false
	var radius: float = sphere.radius
	var rest: float = tank.SPRING_REST
	var slack: float = MeshSupport.HEIGHT_EPS
	solver.diagnostic["station_support_failure"] = "initial_contacts"
	if not _initial_contacts(solver, start, floor_y): return false
	solver.diagnostic["station_support_failure"] = "pose_domain"
	var maximum_angle := 0.0
	var previous := start
	for pose in all_poses:
		if not solver._reserve(0) or not solver._rigid_pose(pose): return false
		# This extension is for the existing yaw-only model, never a pitched terrain rollout.
		if absf(pose.origin.y-start.origin.y) > slack or absf(pose.basis.y.y-start.basis.y.y) > 0.000001: return false
		var difference := (previous.basis.x-pose.basis.x).length_squared() + (previous.basis.y-pose.basis.y).length_squared() + (previous.basis.z-pose.basis.z).length_squared()
		maximum_angle = maxf(maximum_angle,2.0*asin(minf(1.0,sqrt(difference)*0.5)))
		previous = pose
	var support_bounds := AABB()
	var cast_bounds := AABB()
	var first := true
	solver.diagnostic["station_support_failure"] = "cast_limits"
	for station: Dictionary in stations:
		var local: Vector3 = station.local
		var station_bounds := AABB()
		var station_cast := AABB()
		var max_lever := 0.0
		var minimum_up := 1.0
		var first_pose := true
		for pose in all_poses:
			if not solver._reserve(0): return false
			var up := pose.basis.y.normalized()
			minimum_up = minf(minimum_up,up.y)
			if up.y <= 0.0: return false
			var mount := pose * local
			var travel := (mount.y-floor_y-radius)/up.y
			if travel <= 0.0 or travel+slack/up.y >= rest: return false
			var contact_center := mount-up*travel
			station_bounds = AABB(contact_center,Vector3.ZERO) if first_pose else station_bounds.expand(contact_center)
			station_cast = AABB(mount,Vector3.ZERO) if first_pose else station_cast.expand(mount)
			station_cast = station_cast.expand(mount-up*rest)
			max_lever = maxf(max_lever,(local-Vector3.UP*travel).length())
			first_pose = false
		# A full box contains all interpolated station-center arcs, not only samples.
		# Projection along body-up has norm 1/up.y; include the braking uncertainty.
		var pad := reserve/minimum_up + max_lever*maximum_angle + slack/minimum_up
		station_bounds = station_bounds.grow(pad)
		station_cast = station_cast.grow(radius+float(tank.QUERY_MARGIN)+reserve+(local.length()+rest)*maximum_angle)
		support_bounds = station_bounds if first else support_bounds.merge(station_bounds)
		cast_bounds = station_cast if first else cast_bounds.merge(station_cast)
		first = false
	solver.diagnostic["station_support_failure"] = "cast_environment"
	if not _cast_environment_clear(solver,cast_bounds,floor_y): return false
	var rect := Rect2(Vector2(support_bounds.position.x,support_bounds.position.z),Vector2(support_bounds.size.x,support_bounds.size.z))
	# A superset rectangle covers every station's complete trajectory and uncertainty.
	solver.diagnostic["station_support_failure"] = "continuous_coverage"
	if not ContactGeometry.covers(rect,plane.triangles,radius,slack,Callable(solver,"_reserve").bind(0)): return false
	if not solver._reserve(0): return false
	solver.diagnostic.erase("station_support_failure")
	solver.diagnostic["station_support_verified"] = true
	solver.diagnostic["station_support_height_slack"] = slack
	return true

static func _initial_contacts(solver: RefCounted, pose: Transform3D, floor_y: float) -> bool:
	var cache: Dictionary = solver._station_support_cache
	var key := [pose,floor_y]
	if cache.has(key): return bool(cache[key])
	cache[key] = false
	var tank = solver.tank
	var up := pose.basis.y.normalized()
	for station: Dictionary in tank.get("_stations"):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = tank.get("_sphere")
		query.transform = Transform3D(Basis.IDENTITY,pose*(station.local as Vector3))
		query.motion = -up*float(tank.SPRING_REST)
		query.margin = float(tank.QUERY_MARGIN)
		query.collision_mask = tank.collision_mask
		query.exclude = [tank.get_rid()]
		if not solver._reserve(): return false
		if not solver.space.intersect_shape(query,1).is_empty(): return false
		if not solver._reserve(): return false
		var fractions: PackedFloat32Array = solver.space.cast_motion(query)
		if fractions.size() < 2 or float(fractions[1]) >= 1.0: return false
		query.transform.origin += query.motion*minf(float(fractions[1])+0.0001,1.0)
		if not solver._reserve(): return false
		var hit: Dictionary = solver.space.get_rest_info(query)
		if hit.is_empty(): return false
		var body := instance_from_id(int(hit.get("collider_id",0))) as StaticBody3D
		if body == null or body is AnimatableBody3D: return false
		if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
		if (hit.normal as Vector3).distance_to(Vector3.UP)>0.000001 or absf((hit.point as Vector3).y-floor_y)>MeshSupport.HEIGHT_EPS: return false
	cache[key] = true
	return true

static func _cast_environment_clear(solver: RefCounted, volume: AABB, floor_y: float) -> bool:
	var hits: Array = solver._broad_hits(volume,10007)
	if solver.at_cap or hits.is_empty(): return false
	for hit: Dictionary in hits:
		if not solver._reserve(0): return false
		var body := hit.get("collider") as StaticBody3D
		if body == null or body is AnimatableBody3D: return false
		if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
		var sample := hit.duplicate()
		sample.position = Vector3(0,floor_y,0)
		sample.normal = Vector3.UP
		var patch := MeshSupport.read(solver,sample,[{"hit":sample}])
		if not patch.is_empty():
			for index: int in patch.other_bounds.size():
				var bounds: AABB = patch.other_bounds[index]
				if float(patch.other_max_y[index]) <= float(patch.minimum_support_height): continue
				if volume.intersects(bounds.grow(MeshSupport.HEIGHT_EPS)): return false
			continue
		var node := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as CollisionShape3D
		if node == null: return false
		var local: Dictionary = solver._terrain._local_bounds(node.shape,solver._reserve)
		if local.is_empty(): return false
		var bounds: AABB = node.global_transform*(local.bounds as AABB)
		if bounds.end.y <= floor_y: continue
		if not MeshSupport.outside_parts(solver,hit,Transform3D.IDENTITY,[volume]): return false
	return solver._reserve(0)
