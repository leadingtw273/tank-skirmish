## LEA-175：原出生點 Tank1 的有限 local 分段近路回歸。
## 真實 Vision / CombatAI 鏈路只觀察公開導航 command，不注入記憶或關閉視野。
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const DirectClearance := preload("res://src/ai/tank_direct_clearance.gd")
const DT := 1.0 / 60.0
const PEEK := Vector3(83.7, 0.0, -21.1)
const HIDE := Vector3(88.0, 0.0, -29.45333)
const EXPECTED_LAST_SEEN := Vector3(88.0, 1.039605, -29.05556)
const STOP_DISTANCE := 3.0
const MIN_CLEARANCE := 1.0
## 此為測試專屬、與建築名稱無關的宅口通過觀察區，不參與 production 候選決策。
const PORTAL_MIN := Vector2(74.0, -32.0)
const PORTAL_MAX := Vector2(84.0, -22.0)

var _failures: Array[String] = []
var _scene: Node3D
var _encounter: Node3D
var _enemy: CharacterBody3D
var _player: CharacterBody3D
var _ai: Node
var _vision: Node
var _gable: StaticBody3D
var _two_story: StaticBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = PLAYTEST.instantiate() as Node3D
	root.add_child(_scene)
	_encounter = _scene.get_node("Encounter") as Node3D
	_player = _scene.get_node("Main/Tank") as CharacterBody3D
	_ai = _encounter.get_node("CombatAI") as Node
	_vision = _encounter.get_node("Vision") as Node
	_gable = _scene.get_node("SightBlockers/BuildingRowA/NorthGable") as StaticBody3D
	_two_story = _scene.get_node("SightBlockers/BuildingRowB/SouthTwoStory") as StaticBody3D
	_ai.set_physics_process(false)
	await _await_navigation()
	if await _cycle_to_tank1():
		_enemy = _encounter.get_node("Enemy") as CharacterBody3D
		await _real_seen_lost_local_route()
		await _fixed_goal_driver_local_route()
		await _clear_and_new_generation_clear_local_state()
		await _query_safety_regressions()
	_scene.queue_free()
	await physics_frame
	if _failures.is_empty():
		print("ENEMY_LOCAL_ROUTE PASS: real Tank1 seen/lost local route, fixed-goal arrival, lifecycle clear.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _await_navigation() -> void:
	var region := _scene.get_node("NavigationRegion3D") as NavigationRegion3D
	var map := _scene.get_world_3d().navigation_map
	for unused in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0:
			return
		await physics_frame
	_fail("Harness navigation map did not become ready.")


func _cycle_to_tank1() -> bool:
	var original := _encounter.get_node("Enemy") as CharacterBody3D
	var original_position := original.global_position
	var combat := _scene.get_node("Main/CombatRuntime") as CombatRuntime
	var switch_target := _scene.get_node("TrainingControls/EnemyTypeSwitch") as StaticBody3D
	for expected in ["tank3", "tank4", "tank1"]:
		var impacts: Array[ImpactEvent] = []
		var callback := func(event: ImpactEvent) -> void: impacts.append(event)
		combat.impact_resolved.connect(callback)
		combat._on_shot_fired(ShotEvent.new(Transform3D(Basis.IDENTITY, switch_target.global_position + Vector3.UP * 5.0), Vector3.DOWN, _player.get_rid()))
		for unused in 60:
			await physics_frame
			if _encounter.get_node("Enemy").scene_file_path.contains(expected):
				break
		if combat.impact_resolved.is_connected(callback):
			combat.impact_resolved.disconnect(callback)
		if not _encounter.get_node("Enemy").scene_file_path.contains(expected):
			_fail("Tank cycle did not reach %s." % expected)
			return false
	var tank1 := _encounter.get_node("Enemy") as CharacterBody3D
	print("CYCLE_TANK1 scene=%s origin=%s actual=%s" % [tank1.scene_file_path, original_position, tank1.global_position])
	if _xz_distance(tank1.global_position, original_position) > 0.05:
		_fail("Tank1 must retain Encounter original spawn; origin=%s actual=%s." % [original_position, tank1.global_position])
	return true


func _real_seen_lost_local_route() -> void:
	_prepare_enemy()
	_player.global_position = PEEK
	_ai.call("set_target", _player)
	_ai.call("set_combat_enabled", true)
	for unused in 60:
		_ai.call("_physics_process", DT)
		await physics_frame
	if not bool(_vision.call("can_see", _player)):
		_fail("R1 setup requires true Vision at PEEK.")
		return
	var observed_seen := _ai.get("_last_seen_position") as Vector3
	if _xz_distance(observed_seen, PEEK) > 0.15:
		_fail("R1 true seen tick must record PEEK; got %s." % observed_seen)
		return
	var loss := await _retreat_until_lost()
	if not bool(loss.get("lost", false)):
		_fail("R1 legal continuous retreat did not transition Vision to lost.")
		return
	var remembered := loss.get("memory", Vector3.ZERO) as Vector3
	if _xz_distance(remembered, EXPECTED_LAST_SEEN) > 0.2:
		_fail("R1 last seen must be ~%s, got %s." % [EXPECTED_LAST_SEEN, remembered])
		return
	var evidence := await _observe_ai_search(remembered, 1200)
	print("R1_REAL route_local=%s portal=%s min_z=%.3f travelled=%.3f reacquired=%s memory_stable=%s status=%s distance=%.3f gable=%.3f two_story=%.3f overlap=%d" % [evidence.local, evidence.portal, evidence.min_z, evidence.travelled, evidence.reacquired, evidence.memory_stable, evidence.status, evidence.distance, evidence.min_gable, evidence.min_two_story, evidence.overlaps])
	if not evidence.local:
		_fail("R1 true seen/lost AI search must expose public route=local at least once.")
	if not evidence.portal and not (evidence.reacquired and evidence.status == &"holding"):
		_fail("R1 must enter the宅口 or reacquire the player and hold under the unchanged combat distance.")
	if evidence.min_z < -50.0:
		_fail("R1 local route must not detour south of z=-50; min_z=%.3f." % evidence.min_z)
	if evidence.travelled >= 60.0:
		_fail("R1 local search must travel <60m, got %.3fm." % evidence.travelled)
	if not evidence.memory_stable:
		_fail("R1 first loss must preserve last-seen until true Vision reacquisition.")
	if evidence.min_gable < MIN_CLEARANCE or evidence.min_two_story < MIN_CLEARANCE or evidence.overlaps != 0:
		_fail("R1 all parts require >=1m XZ clearance and zero overlap; gable=%.3f two_story=%.3f overlap=%d." % [evidence.min_gable, evidence.min_two_story, evidence.overlaps])


func _retreat_until_lost() -> Dictionary:
	var previous := PEEK
	var steps := ceili(previous.distance_to(HIDE) / 0.4)
	for index in range(1, steps + 1):
		_player.global_position = previous.lerp(HIDE, float(index) / float(steps))
		await physics_frame
		var overlaps := _tank_overlap_names(_player)
		if not overlaps.is_empty():
			_fail("R1 retreat step %d overlaps %s." % [index, overlaps])
			return {"lost": false}
		_ai.call("_physics_process", DT)
		if not bool(_vision.call("can_see", _player)):
			var memory := _ai.get("_last_seen_position") as Vector3
			print("R1_LOSS step=%d player=%s memory=%s" % [index, _player.global_position, memory])
			return {"lost": true, "memory": memory}
	return {"lost": false}


func _observe_ai_search(remembered: Vector3, frames: int) -> Dictionary:
	var previous := _enemy.call("stable_world_center") as Vector3
	var travelled := 0.0
	var local := false
	var portal := false
	var reacquired := false
	var memory_stable := true
	var min_z := previous.z
	var min_gable := INF
	var min_two_story := INF
	var overlaps := 0
	var status: StringName = &"idle"
	for unused in frames:
		var clearance := _building_clearances(_enemy)
		min_gable = minf(min_gable, clearance.gable)
		min_two_story = minf(min_two_story, clearance.two_story)
		overlaps += int(clearance.gable <= 0.0) + int(clearance.two_story <= 0.0)
		var visible_before_tick := bool(_vision.call("can_see", _player))
		if visible_before_tick:
			reacquired = true
		_ai.call("_physics_process", DT)
		var navigation := _ai.get("_navigation") as RefCounted
		## 真 AI 沒有公開 command cache；只讀已核可的單一狀態欄位以觀察它實際選到 local。
		local = local or (navigation != null and navigation.get("_shortcut_kind") == &"local")
		if not reacquired and _xz_distance(_ai.get("_last_seen_position") as Vector3, remembered) > 0.1:
			memory_stable = false
		await physics_frame
		var current := _enemy.call("stable_world_center") as Vector3
		travelled += _xz_distance(previous, current)
		previous = current
		min_z = minf(min_z, current.z)
		portal = portal or _in_portal(current)
		status = _ai.get("movement_status") as StringName
		if status in [&"arrived", &"partial_end", &"no_path", &"stuck"]:
			break
	var final_clearance := _building_clearances(_enemy)
	min_gable = minf(min_gable, final_clearance.gable)
	min_two_story = minf(min_two_story, final_clearance.two_story)
	overlaps += int(final_clearance.gable <= 0.0) + int(final_clearance.two_story <= 0.0)
	return {"local": local, "portal": portal, "min_z": min_z, "travelled": travelled, "reacquired": reacquired, "memory_stable": memory_stable, "status": status, "distance": _xz_distance(_enemy.call("stable_world_center"), remembered), "min_gable": min_gable, "min_two_story": min_two_story, "overlaps": overlaps}


func _fixed_goal_driver_local_route() -> void:
	_prepare_enemy()
	_player.global_position = Vector3(-100.0, 0.0, 100.0)
	var driver := TankNavigation.new()
	driver.setup(_enemy)
	var evidence := await _drive_driver(driver, EXPECTED_LAST_SEEN, 10, 1200)
	print("R2_DRIVER route_local=%s status=%s distance=%.3f travelled=%.3f portal=%s min_z=%.3f gable=%.3f two_story=%.3f overlap=%d" % [evidence.local, evidence.status, evidence.distance, evidence.travelled, evidence.portal, evidence.min_z, evidence.min_gable, evidence.min_two_story, evidence.overlaps])
	if not evidence.local:
		_fail("R2 fixed last-seen driver must expose route=local.")
	if evidence.status != &"arrived" or evidence.distance > STOP_DISTANCE:
		_fail("R2 local route must arrive at fixed last-seen within 3m; status=%s distance=%.3f." % [evidence.status, evidence.distance])
	if not evidence.portal or evidence.min_z < -50.0 or evidence.travelled >= 60.0:
		_fail("R2 must traverse the宅口, not the southern detour, within 60m.")
	if not evidence.corner_stopped:
		_fail("R2 must actually stop before advancing from the waypoint to the final leg.")
	if evidence.min_gable < MIN_CLEARANCE or evidence.min_two_story < MIN_CLEARANCE or evidence.overlaps != 0:
		_fail("R2 all parts require >=1m XZ clearance and zero overlap.")
	driver.dispose()


func _clear_and_new_generation_clear_local_state() -> void:
	_prepare_enemy()
	_player.global_position = Vector3(-100.0, 0.0, 100.0)
	var driver := TankNavigation.new()
	driver.setup(_enemy)
	var saw_local := false
	for unused in 180:
		var command := _submit_driver_frame(driver, EXPECTED_LAST_SEEN, 30)
		saw_local = saw_local or command.get("route") == &"local"
		await physics_frame
		if saw_local:
			break
	driver.clear()
	var clear_kind := driver.get("_shortcut_kind") as StringName
	var clear_points := driver.get("_shortcut_points") as Array
	var clear_index := int(driver.get("_shortcut_index"))
	var new_goal := Vector3(43.0, 0.0, -20.0)
	var after_clear := _submit_driver_frame(driver, new_goal, 31)
	for unused in 8:
		await physics_frame
		after_clear = _submit_driver_frame(driver, new_goal, 31)
	print("R3_LIFECYCLE saw_local=%s clear_kind=%s clear_points=%d clear_index=%d after_clear_route=%s status=%s new_goal=%s" % [saw_local, clear_kind, clear_points.size(), clear_index, after_clear.get("route"), after_clear.get("status"), new_goal])
	if not saw_local:
		_fail("R3 precondition requires first generation to select local.")
	if clear_kind != &"none" or not clear_points.is_empty() or clear_index != 0:
		_fail("R3 clear must erase local shortcut state; kind=%s points=%d index=%d." % [clear_kind, clear_points.size(), clear_index])
	if after_clear.get("status") in [&"waiting_map", &"no_path"]:
		_fail("R3 clear/new generation must query the new public goal, got %s." % after_clear.get("status"))
	driver.dispose()


func _drive_driver(driver: RefCounted, goal: Vector3, generation: int, frames: int) -> Dictionary:
	var previous := _enemy.call("stable_world_center") as Vector3
	var travelled := 0.0
	var local := false
	var portal := false
	var min_z := previous.z
	var min_gable := INF
	var min_two_story := INF
	var overlaps := 0
	var command: Dictionary = {}
	var previous_index := 0
	var corner_stopped := false
	for unused in frames:
		var clearance := _building_clearances(_enemy)
		min_gable = minf(min_gable, clearance.gable)
		min_two_story = minf(min_two_story, clearance.two_story)
		overlaps += int(clearance.gable <= 0.0) + int(clearance.two_story <= 0.0)
		command = _submit_driver_frame(driver, goal, generation)
		var current_index := int(driver.get("_shortcut_index"))
		if current_index > previous_index:
			corner_stopped = absf(float(_enemy.get("forward_speed"))) <= 0.1
		previous_index = current_index
		local = local or command.get("route") == &"local"
		await physics_frame
		var current := _enemy.call("stable_world_center") as Vector3
		travelled += _xz_distance(previous, current)
		previous = current
		min_z = minf(min_z, current.z)
		portal = portal or _in_portal(current)
		if command.get("status") in [&"arrived", &"partial_end", &"no_path", &"stuck"]:
			break
	var final_clearance := _building_clearances(_enemy)
	min_gable = minf(min_gable, final_clearance.gable)
	min_two_story = minf(min_two_story, final_clearance.two_story)
	overlaps += int(final_clearance.gable <= 0.0) + int(final_clearance.two_story <= 0.0)
	return {"local": local, "status": command.get("status"), "distance": _xz_distance(_enemy.call("stable_world_center"), goal), "travelled": travelled, "portal": portal, "min_z": min_z, "min_gable": min_gable, "min_two_story": min_two_story, "overlaps": overlaps, "corner_stopped": corner_stopped}


func _query_safety_regressions() -> void:
	_prepare_enemy()
	_player.global_position = Vector3(-100.0, 0.0, 100.0)
	await physics_frame
	var clearance := DirectClearance.new()
	clearance.setup(_enemy)
	var bad_midpoint := Vector3(66.51301, 0.0, -29.93539)
	var unsafe_route := clearance.can_route_via(bad_midpoint, EXPECTED_LAST_SEEN, STOP_DISTANCE)
	if unsafe_route:
		_fail("R4 known midpoint must reject the middle-of-segment SouthTwoStory clearance violation.")
	_enemy.set_physics_process(false)
	_enemy.global_position = Vector3(-200.0, 0.0, -200.0)
	_player.global_position = Vector3(-190.0, 0.0, -200.0)
	await physics_frame
	var open_goal := Vector3(-180.0, 0.0, -200.0)
	var planning_clear := clearance.can_route_via(Vector3(-195.0, 0.0, -196.0), open_goal, 0.0)
	var toward := open_goal - (_enemy.call("stable_world_center") as Vector3)
	toward.y = 0.0
	var forward := _enemy.global_basis * Vector3.LEFT
	forward.y = 0.0
	var angle := atan2(forward.cross(toward).y, forward.dot(toward))
	var execution_clear := clearance.can_travel(open_goal, 0.0, angle)
	if not planning_clear or execution_clear:
		_fail("R4 planning may ignore a movable tank, but execution must still detect it on the same helper.")
	print("R4_QUERY rejected_unsafe_midpoint=%s planning_ignores_vehicle=%s execution_blocks_vehicle=%s" % [not unsafe_route, planning_clear, not execution_clear])


func _prepare_enemy() -> void:
	_enemy.global_position = Vector3(57.65064, 0.0, -42.68505)
	_enemy.rotation.y = -PI / 2.0
	(_enemy.get_node("VisualRecoilPivot/TurretPivot") as Node3D).rotation.y = 0.0
	(_enemy.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D).rotation.z = 0.0
	_enemy.set_movement_input(0.0)
	_enemy.set_turn_input(0.0)
	_enemy.set("forward_speed", 0.0)
	_player.global_position = PEEK
	_player.set_movement_input(0.0)
	_player.set_turn_input(0.0)


func _submit_driver_frame(driver: RefCounted, goal: Vector3, generation: int) -> Dictionary:
	_enemy.aim_turret_at(goal, DT)
	_enemy.aim_gun_pitch_at_target(goal, DT)
	var command: Dictionary = driver.drive(goal, generation, STOP_DISTANCE, DT)
	_enemy.set_movement_input(float(command.get("movement", 0.0)))
	_enemy.set_turn_input(float(command.get("turn", 0.0)))
	return command


func _in_portal(position: Vector3) -> bool:
	return position.x >= PORTAL_MIN.x and position.x <= PORTAL_MAX.x and position.z >= PORTAL_MIN.y and position.z <= PORTAL_MAX.y


func _building_clearances(tank: CharacterBody3D) -> Dictionary:
	return {"gable": _tank_to_box_clearance(tank, _gable), "two_story": _tank_to_box_clearance(tank, _two_story)}


func _tank_to_box_clearance(tank: CharacterBody3D, building: StaticBody3D) -> float:
	var collision := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var box := collision.shape as BoxShape3D if collision != null else null
	if box == null:
		return -INF
	var obstacle := _box_polygon(collision, box)
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var shape_index := 0
	var nearest := INF
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var hull := PackedVector2Array()
			for point in shape.points:
				var world: Vector3 = transforms[shape_index] * point
				hull.append(Vector2(world.x, world.z))
			if hull.size() >= 3:
				nearest = minf(nearest, _polygon_distance(Geometry2D.convex_hull(hull), obstacle))
			shape_index += 1
	return nearest


func _box_polygon(collision: CollisionShape3D, box: BoxShape3D) -> PackedVector2Array:
	var half := box.size * 0.5
	var points := PackedVector2Array()
	for point in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z)]:
		var world: Vector3 = collision.global_transform * point
		points.append(Vector2(world.x, world.z))
	return Geometry2D.convex_hull(points)


func _polygon_distance(first: PackedVector2Array, second: PackedVector2Array) -> float:
	if not Geometry2D.intersect_polygons(first, second).is_empty() or Geometry2D.is_point_in_polygon(first[0], second) or Geometry2D.is_point_in_polygon(second[0], first):
		return 0.0
	var nearest := INF
	for point in first:
		for index in second.size():
			nearest = minf(nearest, _point_segment_distance(point, second[index], second[(index + 1) % second.size()]))
	for point in second:
		for index in first.size():
			nearest = minf(nearest, _point_segment_distance(point, first[index], first[(index + 1) % first.size()]))
	return nearest


func _point_segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var axis := end - start
	var ratio := clampf((point - start).dot(axis) / maxf(axis.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(start.lerp(end, ratio))


func _tank_overlap_names(tank: CharacterBody3D) -> Array[String]:
	var names: Array[String] = []
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = transforms[index]
			query.collision_mask = 1
			query.exclude = [tank.get_rid()]
			for hit in tank.get_world_3d().direct_space_state.intersect_shape(query, 8):
				var collider := hit.get("collider") as Node
				var name := str(collider.get_path()) if collider != null else "<null>"
				if not names.has(name):
					names.append(name)
			index += 1
	return names


func _xz_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x - right.x, left.z - right.z).length()


func _fail(message: String) -> void:
	_failures.append(message)
