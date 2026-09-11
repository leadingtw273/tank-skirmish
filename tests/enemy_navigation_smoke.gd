## LEA-175 Task 1/2：導航地圖、保守通道與純輸入需求的 headless smoke。
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const TANK2 := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const NAV_RADIUS := 6.1790233
const TANK_SCENES := [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	TANK2,
	preload("res://src/actors/tank/variants/tank3/tank3.tscn"),
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var region := scene.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		_fail("Playtest must expose a NavigationRegion3D and its navigation mesh.")
	else:
		var map := scene.get_world_3d().navigation_map
		for tick in 120:
			if NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 and NavigationServer3D.map_get_closest_point_owner(map, Vector3(43, 0, -20)).is_valid():
				break
			await physics_frame
		if NavigationServer3D.map_get_iteration_id(map) <= 0:
			_fail("Navigation map did not become ready.")
		else:
			_validate_conservative_bake(region.navigation_mesh)
			_validate_training_route(map)
			_validate_narrow_gap(map)
			## Driver is exercised against the same ready map below; it only returns demands.
			await _validate_driver(scene)
			await _validate_four_tank_driving()
			await _validate_partial_endpoint()
	scene.queue_free()
	await physics_frame
	if _failures.is_empty():
		print("ENEMY_NAVIGATION PASS: map readiness, building detour, narrow gap, terminal states, and pure commands.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _validate_conservative_bake(mesh: NavigationMesh) -> void:
	if mesh.agent_radius < NAV_RADIUS - 0.001:
		_fail("Navigation mesh radius must retain the measured 6.1790233m four-tank envelope.")
	if mesh.get_polygon_count() <= 0:
		_fail("Navigation mesh has no traversable polygons.")


func _validate_training_route(map: RID) -> void:
	## Row A CentralOneStory sits at about (59.4, -20.1); endpoints are on its two sides.
	var start := Vector3(43.0, 0.0, -20.0)
	var goal := Vector3(76.0, 0.0, -20.0)
	print("NAV_ROUTE training_query start=%s goal=%s" % [start, goal])
	var path := NavigationServer3D.map_get_path(map, start, goal, true, 1)
	if path.size() < 2:
		_fail("Training-ground enemy-to-player route has no path.")
		return
	var path_distance := _path_distance(path)
	var direct_distance := _horizontal_distance(start, goal)
	print("NAV_ROUTE training points=%d direct=%.2f path=%.2f start=%s goal=%s" % [path.size(), direct_distance, path_distance, start, goal])
	if path_distance <= direct_distance + 0.5:
		_fail("Expected an authored-building detour, but route is indistinguishable from a straight line.")


func _validate_narrow_gap(map: RID) -> void:
	## Central and north buildings in Row A leave a physical gap narrower than 2 * 6.1790233m.
	var from := Vector3(57.0, 0.0, -2.0)
	var to := Vector3(57.0, 0.0, -26.0)
	var path := NavigationServer3D.map_get_path(map, from, to, true, 1)
	if path.size() > 1 and _path_distance(path) <= _horizontal_distance(from, to) + 2.0:
		_fail("A passage narrower than the conservative envelope was treated as directly traversable.")
	else:
		print("NAV_ROUTE narrow points=%d direct=%.2f path=%.2f" % [path.size(), _horizontal_distance(from, to), _path_distance(path)])


func _validate_driver(scene: Node3D) -> void:
	## Do not attach a second agent to Encounter/Enemy: CombatAI owns that live tank.
	var enemy := TANK2.instantiate() as CharacterBody3D
	enemy.name = "NavigationSmokeTank"
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(enemy)
	enemy.global_position = Vector3(-120.0, 0.0, 120.0)
	await physics_frame
	var driver := TankNavigation.new()
	driver.setup(enemy)
	var agent := enemy.get_node_or_null("TankNavigationAgent") as NavigationAgent3D
	if agent != null:
		agent.process_mode = Node.PROCESS_MODE_ALWAYS
	await physics_frame
	var preserved_movement := 0.37
	var preserved_turn := -0.22
	enemy.set_movement_input(preserved_movement)
	enemy.set_turn_input(preserved_turn)
	var goal: Vector3 = enemy.stable_world_center() + Vector3(30.0, 0.0, 0.0)
	var command := driver.drive(goal, 1, 3.0, 1.0 / 60.0)
	if not (command.get("movement", -1.0) is float) or float(command.movement) < 0.0:
		_fail("Driver movement must be a non-negative numeric demand.")
	if not is_equal_approx(enemy.movement_command, preserved_movement) or not is_equal_approx(enemy.turn_command, preserved_turn):
		_fail("Driver directly wrote tank movement or turn state.")
	var arrived := driver.drive(enemy.stable_world_center(), 2, 3.0, 1.0 / 60.0)
	if arrived.status != &"arrived" or float(arrived.movement) != 0.0:
		_fail("Driver must distinguish direct-distance arrival and stop without reverse movement.")
	var blocked_goal := Vector3(59.4, 0.0, -20.1)
	var partial := driver.drive(blocked_goal, 3, 0.1, 1.0 / 60.0)
	for unused in 4:
		await physics_frame
		partial = driver.drive(blocked_goal, 3, 0.1, 1.0 / 60.0)
	if partial.status == &"arrived":
		_fail("A blocked interior goal must not be reported as arrived.")
	if partial.status not in [&"moving", &"partial_end", &"no_path", &"stuck"]:
		_fail("Driver returned an invalid blocked-goal state: %s" % partial.status)
	driver.dispose()
	enemy.queue_free()
	await physics_frame


## A8：讓四台正式坦克各自用真物理駛過原場景建築，不只驗路徑線段。
func _validate_four_tank_driving() -> void:
	var start := Vector3(43, 0, -20)
	var goal := Vector3(76, 0, -20)
	for model in TANK_SCENES.size():
		var tank := TANK_SCENES[model].instantiate() as CharacterBody3D
		tank.position = start
		root.add_child(tank)
		var driver := TankNavigation.new()
		driver.setup(tank)
		await physics_frame
		var command: Dictionary
		var furthest_from_line := 0.0
		for tick in 5400:
			command = driver.drive(goal, 1, 3.0, 1.0 / 60.0)
			tank.call("set_movement_input", command.movement)
			if is_zero_approx(float(command.turn)):
				tank.call("stop_hull_aim_turn")
			else:
				tank.call("set_turn_input", command.turn)
			await physics_frame
			furthest_from_line = maxf(furthest_from_line, absf(tank.global_position.z - start.z))
			if command.status in [&"arrived", &"partial_end", &"no_path", &"stuck"]:
				break
		var distance := _horizontal_distance(tank.call("stable_world_center"), goal)
		print("NAV_DRIVE Tank%d status=%s distance=%.3f detour=%.3f position=%s" % [model + 1, command.get("status"), distance, furthest_from_line, tank.global_position])
		if command.get("status") != &"arrived" or distance > 3.0 or furthest_from_line < 5.0:
			_fail("A8 Tank%d must physically drive around the authored building and reach within3m, got %s at %.3fm." % [model + 1, command.get("status"), distance])
		driver.dispose()
		tank.queue_free()
		await process_frame
		await physics_frame


func _validate_partial_endpoint() -> void:
	var tank := TANK2.instantiate() as CharacterBody3D
	tank.position = Vector3(43, 0, -20)
	root.add_child(tank)
	var driver := TankNavigation.new()
	driver.setup(tank)
	await physics_frame
	var goal := Vector3(59.4, 0, -20.1)
	var command: Dictionary
	for tick in 3600:
		command = driver.drive(goal, 1, 3.0, 1.0 / 60.0)
		tank.call("set_movement_input", command.movement)
		if is_zero_approx(float(command.turn)):
			tank.call("stop_hull_aim_turn")
		else:
			tank.call("set_turn_input", command.turn)
		await physics_frame
		if command.status in [&"arrived", &"partial_end", &"no_path", &"stuck"]:
			break
	var stopped := tank.global_position
	var distance := _horizontal_distance(tank.call("stable_world_center"), goal)
	print("NAV_PARTIAL status=%s distance=%.3f position=%s" % [command.get("status"), distance, stopped])
	if command.get("status") != &"partial_end" or distance <= 3.0 or float(command.movement) != 0.0:
		_fail("A9 must stop at the safe partial endpoint, distinct from arrival at the original goal.")
	for tick in 300:
		command = driver.drive(goal, 1, 3.0, 1.0 / 60.0)
		if command.status != &"partial_end" or float(command.movement) != 0.0 or _horizontal_distance(stopped, tank.global_position) > 0.1:
			_fail("A9 partial endpoint must remain stopped for five seconds without retrying the same goal.")
			break
		await physics_frame
	driver.dispose()
	tank.queue_free()
	await process_frame
	await physics_frame


func _path_distance(path: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += _horizontal_distance(path[index - 1], path[index])
	return total


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _fail(message: String) -> void:
	_failures.append(message)
