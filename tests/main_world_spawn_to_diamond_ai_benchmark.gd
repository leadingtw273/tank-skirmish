## LEA-176: real main-world Tank2 spawn -> spawn-side diamond entrance -> origin.
## Temporary native navmesh only; no authored world, vehicle physics, or AI changes.
extends SceneTree

const MAIN := preload("res://src/main.tscn")
const NAV_TEMPLATE := preload("res://src/maps/training_ground/navigation/training_ground_navigation.tres")
const Navigation := preload("res://src/ai/tank_navigation.gd")
const GOAL := Vector3.ZERO
const LIMIT_SECONDS := 90.0
const STOP_DISTANCE := 3.0
const STOP_SPEED := 0.1
const STOP_ANGULAR := 0.02
const GEOMETRY_GROUP := &"mainroute_benchmark_geometry"
var _failures: Array[String] = []
var _building: Node
var _roads: Node
var _ground: Node
var _building_hit: Dictionary = {}
var _terrain_hits := {"ground": 0, "road": 0}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var hz := Engine.physics_ticks_per_second
	if hz != 60:
		push_error("Main-world comparison requires the authored 60 Hz physics setting.")
		quit(1)
		return
	var dt := 1.0 / float(hz)
	var scene := MAIN.instantiate() as Node3D
	root.add_child(scene)
	scene.get_node("PlayerRuntime").set_controls_enabled(false)
	var tank := scene.get_node("PlayerRuntime").get("controlled_tank") as RigidBody3D
	if tank == null or tank.get("vehicle_id") != &"tank2":
		push_error("Main world must provide its original rigid medium Tank2.")
		scene.queue_free()
		quit(1)
		return
	var spawn := tank.global_transform
	var world := scene.get_node("World") as Node3D
	world.process_mode = Node.PROCESS_MODE_ALWAYS
	_building = world.get_node("Buildings")
	_roads = world.get_node("Roads")
	_ground = world.get_node("Ground")
	tank.freeze = true
	world.add_to_group(GEOMETRY_GROUP)
	var region := NavigationRegion3D.new()
	region.name = "BenchmarkNavigation"
	region.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(region)
	var mesh := NAV_TEMPLATE.duplicate(true) as NavigationMesh
	mesh.clear()
	mesh.geometry_source_group_name = GEOMETRY_GROUP
	var map := scene.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
	var geometry := NavigationMeshSourceGeometryData3D.new()
	var bake_started := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(mesh, geometry, region)
	NavigationServer3D.bake_from_source_geometry_data(mesh, geometry)
	region.navigation_mesh = mesh
	for unused in 600:
		await physics_frame
		if NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 and NavigationServer3D.map_get_path(map, spawn.origin, GOAL, true, 1).size() >= 2: break
	var path := NavigationServer3D.map_get_path(map, spawn.origin, GOAL, true, 1)
	var nearest := NavigationServer3D.map_get_closest_point(map, GOAL)
	var path_endpoint_distance := INF if path.is_empty() else _xz(path[path.size()-1]-GOAL).length()
	print("MAIN_ROUTE_PREFLIGHT hz=%d vehicle=%s spawn=%s yaw_degrees=%.3f goal=%s nav_goal=%s polygons=%d path_points=%d path_endpoint_xz_distance=%.6f bake_ms=%d" % [hz,tank.get("vehicle_id"),spawn.origin,rad_to_deg(tank.rotation.y),GOAL,nearest,mesh.get_polygon_count(),path.size(),path_endpoint_distance,Time.get_ticks_msec()-bake_started])
	if path.size() < 2 or _xz(nearest-GOAL).length() > 0.5 or path_endpoint_distance > STOP_DISTANCE:
		_failures.append("The unchanged spawn and fixed center must be connected by the temporary native navmesh.")
	if _overlap(tank): _failures.append("Authored spawn overlaps a building or unknown collider.")
	if not _failures.is_empty():
		_finish(scene, 1)
		return
	# Human controls are disabled through PlayerRuntime; retain all world runtime and tank physics.
	tank.process_mode = Node.PROCESS_MODE_ALWAYS
	tank.freeze = false
	tank.set_movement_input(0.0)
	tank.set_turn_input(0.0)
	for unused in 120: await physics_frame
	var settled_start := tank.global_transform
	var spawn_drift := _xz(settled_start.origin-spawn.origin).length()
	var spawn_turn := absf(wrapf(settled_start.basis.get_euler().y-spawn.basis.get_euler().y,-PI,PI))
	if spawn_drift > 0.1 or spawn_turn > deg_to_rad(1.0):
		_failures.append("Initial settling changed the authored start by >10cm or >1deg; cannot silently rebase.")
	print("MAIN_ROUTE_SETTLE position=%s drift=%.6f yaw_drift_degrees=%.6f mass=%s" % [settled_start.origin,spawn_drift,rad_to_deg(spawn_turn),tank.mass])
	if not _failures.is_empty():
		_finish(scene, 1)
		return
	var driver := Navigation.new()
	driver.setup(tank)
	tank.set_driving_trace_enabled(true)
	var samples: Array[Dictionary] = []
	var elapsed_queries: Array[int] = []
	var reason_counts: Dictionary = {}
	var status_counts: Dictionary = {}
	var phase_counts: Dictionary = {}
	var last_sign := 0.0
	var flips := 0
	var abs_yaw := 0.0
	var net_yaw := 0.0
	var travel := 0.0
	var stationary_ticks := 0
	var longest_stationary_ticks := 0
	var stationary_run := 0
	var stopped_ticks := 0
	var entered_spawn_side := false
	var entrance_seconds := -1.0
	var arrived_seconds := -1.0
	var completed_seconds := -1.0
	var min_distance := INF
	var last_position := tank.global_position
	var ticks := 0
	var command: Dictionary = {}
	var recovery: RefCounted = driver.get("_recovery")
	var max_attempts := 0
	for tick in int(LIMIT_SECONDS * hz):
		command = driver.drive(GOAL, 1, STOP_DISTANCE, dt)
		if command.get("route") != &"navmesh":
			_failures.append("Main-world evaluation must use formal navmesh navigation.")
			break
		tank.set_movement_input(float(command.movement))
		tank.set_turn_input(float(command.turn))
		var stats := driver.get_prediction_stats()
		var reason := String(stats.get("reason", "unknown"))
		var status := String(command.status)
		reason_counts[reason] = int(reason_counts.get(reason,0)) + 1
		status_counts[status] = int(status_counts.get(status,0)) + 1
		var phase := String(recovery.get("phase"))
		phase_counts[phase] = int(phase_counts.get(phase,0)) + 1
		max_attempts = maxi(max_attempts,int(recovery.get("attempts")))
		elapsed_queries.append(int(stats.get("elapsed_usec",0)))
		var turn := float(command.turn)
		if absf(turn) > 0.05:
			var current_sign := signf(turn)
			if last_sign != 0.0 and current_sign != last_sign: flips += 1
			last_sign = current_sign
		await physics_frame
		ticks = tick + 1
		var position := tank.global_position
		travel += _xz(position-last_position).length()
		var yaw_delta := tank.angular_velocity.y * dt
		abs_yaw += absf(yaw_delta)
		net_yaw += yaw_delta
		var speed := _xz(tank.linear_velocity).length()
		stationary_run = stationary_run + 1 if speed <= STOP_SPEED else 0
		stationary_ticks += 1 if speed <= STOP_SPEED else 0
		longest_stationary_ticks = maxi(longest_stationary_ticks,stationary_run)
		var distance := _xz(position-GOAL).length()
		min_distance = minf(min_distance,distance)
		# Require the first entry across the diamond boundary to be on the spawn side.
		if entrance_seconds < 0.0 and absf(position.x)+absf(position.z) <= 48.0:
			entrance_seconds = float(ticks)/hz
			entered_spawn_side = position.x < 0.0 and position.z < 0.0 and last_position.x < 0.0 and last_position.z < 0.0
			if not entered_spawn_side: _failures.append("AI entered the central diamond from a different side than the user's spawn-side entrance.")
		var overlap := _overlap(tank)
		if overlap: _failures.append("Full tank shape overlaps a building or unknown collider.")
		if status == "arrived" and distance <= STOP_DISTANCE:
			if arrived_seconds < 0.0: arrived_seconds = float(ticks)/hz
			stopped_ticks = stopped_ticks + 1 if speed <= STOP_SPEED and absf(tank.angular_velocity.y) <= STOP_ANGULAR else 0
		else: stopped_ticks = 0
		samples.append({"tick":ticks,"seconds":float(ticks)/hz,"position":_vec(position),"distance":distance,"speed":speed,"yaw":tank.rotation.y,"angular_speed":tank.angular_velocity.y,"movement":float(command.movement),"turn":turn,"status":status,"phase":phase,"attempts":recovery.get("attempts"),"reason":reason,"elapsed_usec":stats.get("elapsed_usec",0),"grounded":tank.predictive_driving_snapshot().get("grounded",false),"snapshot_contacts":tank.predictive_driving_snapshot().get("contacts",[]).size(),"navigation":driver.get_driving_trace_state(),"prediction":stats})
		if ticks % hz == 0:
			var trace := driver.get_driving_trace_state()
			print("DETAIL index=%s next=%s requested=%s stats=%s" % [trace.index,trace.route[trace.index] if trace.index >= 0 and trace.index < trace.route.size() else null,trace.requested,stats])
			print("MAIN_ROUTE_TICK t=%.1f position=%s distance=%.2f speed=%.3f status=%s phase=%s attempts=%d reason=%s flips=%d yaw_sum=%.1f" % [float(ticks)/hz,position,distance,speed,status,phase,int(recovery.get("attempts")),reason,flips,rad_to_deg(abs_yaw)])
		last_position = position
		if stopped_ticks >= hz:
			completed_seconds = float(ticks)/hz
			break
		if overlap or not _failures.is_empty(): break
	# A stuck terminal remains running to the fixed 90-second horizon, without resetting its goal.
	if completed_seconds < 0.0: _failures.append("Did not arrive and remain stopped for one second within 90 simulated seconds.")
	if not entered_spawn_side: _failures.append("Did not traverse the spawn-side diamond entrance.")
	elapsed_queries.sort()
	var sum_usec := 0
	for value in elapsed_queries: sum_usec += value
	var result := {"vehicle":"tank2","physics_hz":hz,"limit_seconds":LIMIT_SECONDS,"spawn_transform":var_to_str(spawn),"settled_start_transform":var_to_str(settled_start),"goal":_vec(GOAL),"nav_path":_path_array(path),"nav_path_endpoint_xz_distance":path_endpoint_distance,"nav_polygons":mesh.get_polygon_count(),"nav_agent_radius":mesh.agent_radius,"nav_cell_height":mesh.cell_height,"nav_collision_mask":mesh.geometry_collision_mask,"nav_filter_bounds":var_to_str(mesh.filter_baking_aabb),"ticks":ticks,"elapsed_seconds":float(ticks)/hz,"arrived_seconds":arrived_seconds,"stopped_seconds":completed_seconds,"entrance_seconds":entrance_seconds,"entered_spawn_side":entered_spawn_side,"final_position":_vec(tank.global_position),"min_distance":min_distance,"travel_metres":travel,"turn_sign_flips":flips,"cumulative_yaw_degrees":rad_to_deg(abs_yaw),"net_yaw_degrees":rad_to_deg(net_yaw),"stationary_seconds":float(stationary_ticks)/hz,"longest_stationary_seconds":float(longest_stationary_ticks)/hz,"max_attempts":max_attempts,"reason_counts":reason_counts,"status_counts":status_counts,"phase_counts":phase_counts,"prediction_mean_usec":float(sum_usec)/maxi(1,elapsed_queries.size()),"prediction_p95_usec":elapsed_queries[mini(elapsed_queries.size()-1,ceili(elapsed_queries.size()*0.95)-1)] if not elapsed_queries.is_empty() else 0,"building_or_unknown_hit":_building_hit,"terrain_overlap_samples":_terrain_hits,"failures":_failures,"samples":samples}
	var output := OS.get_environment("LEA176_MAIN_ROUTE_OUTPUT")
	if output.is_empty(): output = "user://lea176-main-world-route-result.json"
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: _failures.append("Cannot write route evidence to %s" % output)
	else: file.store_string(JSON.stringify(result,"  "))
	print("MAIN_ROUTE_RESULT elapsed=%.3f stopped=%.3f entrance=%.3f entered_spawn_side=%s distance=%.3f flips=%d yaw_sum=%.1f stationary=%.3f collision=%s failures=%d output=%s" % [float(ticks)/hz,completed_seconds,entrance_seconds,entered_spawn_side,min_distance,flips,rad_to_deg(abs_yaw),float(stationary_ticks)/hz,not _building_hit.is_empty(),_failures.size(),output])
	driver.dispose()
	_finish(scene,0 if _failures.is_empty() else 1)

func _overlap(tank: RigidBody3D) -> bool:
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	var shapes: Array = snapshot.shapes
	var transforms: Array = snapshot.transforms
	if shapes.is_empty() or shapes.size() != transforms.size():
		_building_hit = {"invalid_shape_snapshot":true}
		return true
	for index in shapes.size():
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shapes[index] as Shape3D
		query.transform = transforms[index] as Transform3D
		query.collision_mask = tank.collision_mask
		query.exclude = [tank.get_rid()]
		var hits := tank.get_world_3d().direct_space_state.intersect_shape(query,64)
		if hits.size() >= 64:
			_building_hit = {"query_results_truncated":true,"shape":index}
			return true
		for hit in hits:
			var collider := hit.get("collider") as Node
			if collider != null and (collider == _ground or _ground.is_ancestor_of(collider)):
				_terrain_hits.ground += 1
			elif collider != null and (collider == _roads or _roads.is_ancestor_of(collider)):
				_terrain_hits.road += 1
			else:
				_building_hit = {"shape":index,"collider":str(collider.get_path()) if collider != null else "unknown","building":collider != null and _building.is_ancestor_of(collider),"position":_vec(tank.global_position)}
				return true
	return false

func _finish(scene: Node3D, code: int) -> void:
	for failure in _failures: push_error(failure)
	scene.queue_free()
	await process_frame
	quit(code)

static func _xz(v: Vector3) -> Vector2: return Vector2(v.x,v.z)
static func _vec(v: Vector3) -> Array: return [v.x,v.y,v.z]
static func _path_array(path: PackedVector3Array) -> Array:
	var result: Array = []
	for point in path: result.append(_vec(point))
	return result
