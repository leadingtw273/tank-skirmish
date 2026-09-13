## R2 fixed last-seen case after local/direct routes were removed: only shared navmesh may plan it.
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const DT := 1.0 / 60.0
const START := Vector3(57.65064, 0.0, -42.68505)
const LAST_SEEN := Vector3(88.0, 1.039605, -29.05556)
const STOP_DISTANCE := 3.0
const PORTAL_MIN := Vector2(74.0, -32.0)
const PORTAL_MAX := Vector2(84.0, -22.0)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	(scene.get_node("Main/World/Ground") as StaticBody3D).process_mode = Node.PROCESS_MODE_ALWAYS
	(scene.get_node("SightBlockers") as Node3D).process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(scene)
	var map := await _await_navigation(scene)
	if map.is_valid():
		_validate_navmesh_connection(map)
		await _validate_tank_attempt(scene)
	scene.queue_free()
	await physics_frame
	if _failures.is_empty():
		print("ENEMY_NAVMESH_GAP PASS: R2 last-seen portal is navmesh-only and the real Tank1 attempts it safely.")
		quit(0)
		return
	for failure in _failures:
		push_error("ENEMY_NAVMESH_GAP FAIL: %s" % failure)
	quit(1)


func _await_navigation(scene: Node3D) -> RID:
	var region := scene.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var map := scene.get_world_3d().navigation_map
	for unused in 180:
		if region != null and NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 \
				and NavigationServer3D.map_get_closest_point_owner(map, Vector3(43.0, 0.0, -20.0)).is_valid():
			return map
		await physics_frame
	_fail("Navigation map did not become ready for the R2 navmesh-gap case.")
	return RID()


func _validate_navmesh_connection(map: RID) -> void:
	## TankNavigation deliberately flattens last-seen targets before submitting its agent target.
	var nav_goal := Vector3(LAST_SEEN.x, 0.0, LAST_SEEN.z)
	var path := NavigationServer3D.map_get_path(map, START, nav_goal, true, 1)
	var passes_portal := false
	for point in path:
		passes_portal = passes_portal or _in_portal(point)
	print("NAVMESH_GAP_QUERY points=%d portal=%s start=%s goal=%s" % [path.size(), passes_portal, START, LAST_SEEN])
	if path.size() < 2:
		_fail("R2 fixed last-seen endpoints must be connected by the shared navmesh.")
	elif not passes_portal:
		_fail("R2 shared navmesh route must include the x74..84/z-32..-22 portal, not a removed local shortcut.")


func _validate_tank_attempt(scene: Node3D) -> void:
	var tank := TANK1.instantiate() as CharacterBody3D
	tank.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(tank)
	tank.global_position = START
	tank.rotation.y = -PI * 0.5
	tank.set("forward_speed", 0.0)
	await physics_frame
	var driver := TankNavigation.new()
	driver.setup(tank)
	var initial_distance := _xz_distance(tank.stable_world_center(), LAST_SEEN)
	var positive_demand := false
	var moved_toward_goal := false
	var entered_portal := false
	var collided_building := false
	var command: Dictionary = {}
	for unused in 1800:
		command = driver.drive(LAST_SEEN, 2, STOP_DISTANCE, DT)
		if command.get("route") != &"navmesh":
			_fail("R2 command route must remain navmesh after direct/local removal; got %s." % command.get("route"))
			break
		positive_demand = positive_demand or float(command.get("movement", 0.0)) > 0.05
		tank.set_movement_input(float(command.get("movement", 0.0)))
		tank.set_turn_input(float(command.get("turn", 0.0)))
		await physics_frame
		var center: Vector3 = tank.stable_world_center() as Vector3
		moved_toward_goal = moved_toward_goal or _xz_distance(center, LAST_SEEN) < initial_distance - 0.5
		entered_portal = entered_portal or _in_portal(center)
		collided_building = collided_building or _overlaps_sight_blocker(tank)
		if command.get("status") in [&"arrived", &"partial_end", &"no_path", &"stuck"]:
			break
	var distance := _xz_distance(tank.stable_world_center(), LAST_SEEN)
	print("NAVMESH_GAP_DRIVE status=%s route=%s demand=%s toward=%s portal=%s distance=%.3f building_overlap=%s" % [command.get("status"), command.get("route"), positive_demand, moved_toward_goal, entered_portal, distance, collided_building])
	if not positive_demand or not moved_toward_goal:
		_fail("R2 real Tank1 must issue forward navmesh demand and make a safe attempt toward the portal.")
	if collided_building:
		_fail("R2 physical attempt must not overlap an authored SightBlockers collider.")
	if positive_demand and moved_toward_goal and (command.get("status") != &"arrived" or distance > STOP_DISTANCE):
		print("NAVMESH_GAP_NON_WEAKENING: path connected and Tank1 attempted portal but did not reach last-seen; no local/direct fallback is permitted.")
	driver.dispose()
	tank.queue_free()


func _overlaps_sight_blocker(tank: CharacterBody3D) -> bool:
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var shape_index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = transforms[shape_index]
			query.collision_mask = 1
			query.exclude = [tank.get_rid()]
			for hit in tank.get_world_3d().direct_space_state.intersect_shape(query, 16):
				var collider := hit.get("collider") as Node
				if collider != null and str(collider.get_path()).contains("SightBlockers"):
					return true
			shape_index += 1
	return false


func _in_portal(position: Vector3) -> bool:
	return position.x >= PORTAL_MIN.x and position.x <= PORTAL_MAX.x and position.z >= PORTAL_MIN.y and position.z <= PORTAL_MAX.y


func _xz_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x - right.x, left.z - right.z).length()


func _fail(message: String) -> void:
	_failures.append(message)
