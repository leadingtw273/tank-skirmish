## 綠圈斜開口捷徑：正式 Tank2 的完整物理 smoke，不以輸入 probe 取代 driver 證據。
extends SceneTree

const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const DirectClearance := preload("res://src/ai/tank_direct_clearance.gd")
const TANK_SCENES: Array[PackedScene] = [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	preload("res://src/actors/tank/variants/tank2/tank2.tscn"),
	preload("res://src/actors/tank/variants/tank3/tank3.tscn"),
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]
const DT := 1.0 / 60.0
const START := Vector3(64.6, 0.0, -35.7)
const GOAL := Vector3(83.7, 0.0, -21.1)
const STOP_DISTANCE := 3.0
const MIN_CLEARANCE := 1.0

var _failures: Array[String] = []
var _scene: Node3D
var _gable: StaticBody3D
var _two_story: StaticBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = PLAYTEST.instantiate() as Node3D
	root.add_child(_scene)
	_gable = _scene.get_node("SightBlockers/BuildingRowA/NorthGable") as StaticBody3D
	_two_story = _scene.get_node("SightBlockers/BuildingRowB/SouthTwoStory") as StaticBody3D
	var ai := _scene.get_node_or_null("Encounter/CombatAI") as Node
	if ai != null:
		ai.set_physics_process(false)
	await _await_navigation()
	await _g1_tank2_uses_safe_direct_shortcut()
	await _g2_blocker_refuses_direct_shortcut()
	await _g3_all_tanks_measure_full_geometry()
	await _lifecycle_clear_requeries_new_goal()
	await _g4_ai_last_seen_uses_direct_gap()
	_scene.queue_free()
	await physics_frame
	if _failures.is_empty():
		print("ENEMY_GAP_SHORTCUT PASS: G1 physical direct route, G2 blocker fallback, G3 all-part gate evidence, G4 real AI last-seen, lifecycle clear.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _await_navigation() -> void:
	var region := _scene.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var map := _scene.get_world_3d().navigation_map
	for unused in 120:
		if region != null and NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0:
			return
		await physics_frame
	_fail("Harness navigation map did not become ready.")


## G1：Encounter 的 Tank2 原始 -pi/2 車頭，必先安全原地轉正，後再實體穿過開口。
func _g1_tank2_uses_safe_direct_shortcut() -> void:
	var tank := _scene.get_node("Encounter/Enemy") as CharacterBody3D
	if tank == null:
		_fail("G1 Encounter/Enemy Tank2 is missing.")
		return
	tank.global_position = START
	tank.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
	tank.set("forward_speed", 0.0)
	await physics_frame
	var driver := TankNavigation.new()
	driver.setup(tank)
	await physics_frame
	var evidence := await _drive_gap(tank, driver, 1, 900)
	print("G1_DIRECT route_direct=%s status=%s distance=%.3f travelled=%.3f min_gable=%.3f min_two_story=%.3f overlap=%d reverse=%s" % [evidence.direct, evidence.status, evidence.distance, evidence.travelled, evidence.min_gable, evidence.min_two_story, evidence.overlaps, evidence.reverse])
	if not evidence.direct:
		_fail("G1 safe Tank2 gap must expose at least one route=direct command.")
	if evidence.status != &"arrived" or evidence.distance > STOP_DISTANCE:
		_fail("G1 Tank2 must physically arrive within 3m; status=%s distance=%.3f." % [evidence.status, evidence.distance])
	if evidence.travelled >= 40.0:
		_fail("G1 direct gap path must stay below 40m, got %.3fm (98m detour regression)." % evidence.travelled)
	if evidence.min_gable < MIN_CLEARANCE or evidence.min_two_story < MIN_CLEARANCE or evidence.overlaps != 0:
		_fail("G1 every frame including initial pose requires >=1m XZ building clearance and zero overlap; gable=%.3f two_story=%.3f overlap=%d." % [evidence.min_gable, evidence.min_two_story, evidence.overlaps])
	if evidence.reverse:
		_fail("G1 driver submitted reverse movement.")
	driver.dispose()


## G2：真實 Box blocker 放在相同線段時，不得把捷徑標成 direct；不縮車身通關。
func _g2_blocker_refuses_direct_shortcut() -> void:
	var tank := _scene.get_node("Encounter/Enemy") as CharacterBody3D
	tank.global_position = START
	tank.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
	tank.set_movement_input(0.0)
	tank.set_turn_input(0.0)
	tank.set("forward_speed", 0.0)
	var blocker := _blocker_at(Vector3(74.0, 3.0, -28.0), Vector3(3.0, 8.0, 7.0))
	_scene.add_child(blocker)
	await physics_frame
	var driver := TankNavigation.new()
	driver.setup(tank)
	var direct := false
	var reverse := false
	var progressed := false
	for unused in 120:
		var command := _submit_driver_frame(tank, driver, GOAL, 1)
		direct = direct or command.get("route") == &"direct"
		reverse = reverse or float(command.get("movement", 0.0)) < -0.0001
		await physics_frame
		progressed = progressed or _xz_distance(tank.global_position, START) > 0.5
	print("G2_BLOCKER direct=%s reverse=%s progressed=%s status=%s" % [direct, reverse, progressed, driver.drive(GOAL, 1, STOP_DISTANCE, DT).get("status")])
	if direct:
		_fail("G2 blocker must keep first 120 driver ticks on navmesh, never route=direct.")
	if reverse:
		_fail("G2 blocker case submitted reverse movement.")
	if not progressed:
		_fail("G2 rejected shortcut must make real forward progress along the fallback route.")
	driver.dispose()
	blocker.queue_free()
	await physics_frame


## G3：四台正式車以完整 part_geometry（固定與旋轉砲塔、含 gun）實際呼叫 helper gate。
func _g3_all_tanks_measure_full_geometry() -> void:
	## 將原敵車移出量測點，不能讓同位置的另一台車污染 gate 證據。
	var original := _scene.get_node("Encounter/Enemy") as CharacterBody3D
	original.set_movement_input(0.0)
	original.stop_hull_aim_turn()
	original.set("forward_speed", 0.0)
	original.global_position = Vector3(-120, 0, 120)
	await physics_frame
	for index in TANK_SCENES.size():
		var tank := TANK_SCENES[index].instantiate() as CharacterBody3D
		_scene.add_child(tank)
		tank.global_position = START
		tank.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
		await physics_frame
		var clearance := DirectClearance.new()
		clearance.setup(tank)
		var fixed := clearance.can_travel(GOAL, STOP_DISTANCE, 0.0, true)
		var fixed_parts := _part_shape_count(tank)
		var gun_shapes := _gun_shape_count(tank)
		tank.aim_turret_at(GOAL, 1.0)
		tank.aim_gun_pitch_at_target(GOAL + Vector3(0.0, 8.0, 0.0), 1.0)
		await physics_frame
		var aimed := clearance.can_travel(GOAL, STOP_DISTANCE)
		var turn := clearance.can_turn(_heading_error(tank, GOAL))
		print("G3_GATE Tank%d all_convex=%d gun_convex=%d fixed=%s aimed=%s turn=%s" % [index + 1, fixed_parts, gun_shapes, fixed, aimed, turn])
		if fixed_parts <= 0 or gun_shapes <= 0:
			_fail("G3 Tank%d gate evidence lacks complete convex geometry or gun shapes." % (index + 1))
		tank.queue_free()
		await physics_frame


func _lifecycle_clear_requeries_new_goal() -> void:
	var tank := _scene.get_node("Encounter/Enemy") as CharacterBody3D
	tank.global_position = START
	tank.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
	await physics_frame
	var driver := TankNavigation.new()
	driver.setup(tank)
	var first := driver.drive(GOAL, 1, STOP_DISTANCE, DT)
	driver.clear()
	var new_goal := Vector3(43.0, 0.0, -20.0)
	var second := driver.drive(new_goal, 2, STOP_DISTANCE, DT)
	for unused in 8:
		await physics_frame
		second = driver.drive(new_goal, 2, STOP_DISTANCE, DT)
	print("LIFECYCLE_CLEAR first_route=%s second_status=%s second_route=%s new_goal=%s" % [first.get("route"), second.get("status"), second.get("route"), new_goal])
	if second.get("status") in [&"waiting_map", &"no_path"]:
		_fail("Lifecycle clear/new generation must query the new destination, got %s." % second.get("status"))
	driver.dispose()


## G4：不注入記憶；由正式 Encounter AI 先真實目擊，再失視回查原 last-seen 點。
func _g4_ai_last_seen_uses_direct_gap() -> void:
	var enemy := _scene.get_node("Encounter/Enemy") as CharacterBody3D
	var ai := _scene.get_node("Encounter/CombatAI") as Node
	var vision := _scene.get_node("Encounter/Vision") as Node
	var player := _scene.get_node("Main/Tank") as CharacterBody3D
	if enemy == null or ai == null or vision == null or player == null:
		_fail("G4 requires original Encounter/Enemy, CombatAI, Vision, and Main/Tank.")
		return
	enemy.global_position = START
	enemy.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
	enemy.set_movement_input(0.0)
	enemy.set_turn_input(0.0)
	enemy.set("forward_speed", 0.0)
	player.global_position = GOAL
	player.set_movement_input(0.0)
	player.set_turn_input(0.0)
	ai.call("set_target", player)
	ai.call("set_combat_enabled", true)
	await physics_frame
	## 先以正常 AI tick 取得 memory；不可直接寫 _last_seen_position。
	ai.call("_physics_process", DT)
	var remembered := ai.get("_last_seen_position") as Vector3
	var has_memory := bool(ai.get("_has_last_seen_position"))
	if not has_memory or _xz_distance(remembered, GOAL) > 0.1:
		_fail("G4 first real visible AI tick must capture GOAL as last-seen; has=%s remembered=%s." % [has_memory, remembered])
		return
	var hidden_position := Vector3(-100.0, 0.0, 100.0)
	enemy.set("vision_near_radius", 0.0)
	enemy.set("vision_far_radius", 0.0)
	player.global_position = hidden_position
	await physics_frame
	var previous := enemy.call("stable_world_center") as Vector3
	var travelled := 0.0
	var direct := false
	var min_gable := INF
	var min_two_story := INF
	var overlaps := 0
	var memory_changed := false
	var status: StringName = &"idle"
	for unused in 900:
		var frame_clearance := _building_clearances(enemy)
		min_gable = minf(min_gable, frame_clearance.gable)
		min_two_story = minf(min_two_story, frame_clearance.two_story)
		overlaps += int(frame_clearance.gable <= 0.0) + int(frame_clearance.two_story <= 0.0)
		ai.call("_physics_process", DT)
		var navigation: RefCounted = ai.get("_navigation") as RefCounted
		direct = direct or (navigation != null and navigation.get("_shortcut_kind") == &"direct")
		memory_changed = memory_changed or _xz_distance(ai.get("_last_seen_position") as Vector3, remembered) > 0.1
		status = ai.get("movement_status")
		await physics_frame
		var current := enemy.call("stable_world_center") as Vector3
		travelled += _xz_distance(previous, current)
		previous = current
		if status in [&"arrived", &"partial_end", &"no_path", &"stuck"]:
			break
	var distance := _xz_distance(enemy.call("stable_world_center"), GOAL)
	print("G4_AI_LAST_SEEN direct=%s status=%s distance=%.3f travelled=%.3f memory_changed=%s min_gable=%.3f min_two_story=%.3f overlap=%d hidden=%s" % [direct, status, distance, travelled, memory_changed, min_gable, min_two_story, overlaps, hidden_position])
	if not direct:
		_fail("G4 true AI last-seen search must activate its navigation direct shortcut.")
	if status != &"arrived" or distance > STOP_DISTANCE or travelled >= 40.0:
		_fail("G4 AI must reach original GOAL within 3m via <40m route; status=%s distance=%.3f travelled=%.3f." % [status, distance, travelled])
	if memory_changed:
		_fail("G4 hidden player position must not replace AI last-seen memory.")
	if min_gable < MIN_CLEARANCE or min_two_story < MIN_CLEARANCE or overlaps != 0:
		_fail("G4 every frame requires >=1m XZ building clearance and zero overlap; gable=%.3f two_story=%.3f overlap=%d." % [min_gable, min_two_story, overlaps])
	## 測試隔離：恢復 target 與 vision 範圍，避免 scene teardown 前殘留人工失視狀態。
	enemy.set("vision_near_radius", 50.0)
	enemy.set("vision_far_radius", 150.0)
	player.global_position = GOAL


func _drive_gap(tank: CharacterBody3D, driver: RefCounted, generation: int, frames: int) -> Dictionary:
	var previous := tank.call("stable_world_center") as Vector3
	var travelled := 0.0
	var direct := false
	var reverse := false
	var overlaps := 0
	var min_gable := INF
	var min_two_story := INF
	var command: Dictionary = {}
	for unused in frames:
		var frame_clearance := _building_clearances(tank)
		min_gable = minf(min_gable, frame_clearance.gable)
		min_two_story = minf(min_two_story, frame_clearance.two_story)
		overlaps += int(frame_clearance.gable <= 0.0) + int(frame_clearance.two_story <= 0.0)
		command = _submit_driver_frame(tank, driver, GOAL, generation)
		direct = direct or command.get("route") == &"direct"
		reverse = reverse or float(command.get("movement", 0.0)) < -0.0001
		await physics_frame
		var current := tank.call("stable_world_center") as Vector3
		travelled += _xz_distance(previous, current)
		previous = current
		if command.get("status") in [&"arrived", &"partial_end", &"no_path", &"stuck"]:
			break
	return {"direct": direct, "status": command.get("status"), "distance": _xz_distance(tank.call("stable_world_center"), GOAL), "travelled": travelled, "min_gable": min_gable, "min_two_story": min_two_story, "overlaps": overlaps, "reverse": reverse}


func _submit_driver_frame(tank: CharacterBody3D, driver: RefCounted, goal: Vector3, generation: int) -> Dictionary:
	tank.aim_turret_at(goal, DT)
	tank.aim_gun_pitch_at_target(goal, DT)
	var command: Dictionary = driver.drive(goal, generation, STOP_DISTANCE, DT)
	tank.set_movement_input(float(command.get("movement", 0.0)))
	tank.set_turn_input(float(command.get("turn", 0.0)))
	return command


func _blocker_at(position: Vector3, size: Vector3) -> StaticBody3D:
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	## 尚未加入 SceneTree 時 global_position 是 off-tree transform；明確寫 local position。
	blocker.position = position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	blocker.add_child(collision)
	return blocker


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


func _part_shape_count(tank: CharacterBody3D) -> int:
	var count := 0
	for part in tank.part_geometry.parts:
		count += part.convex_shapes.size()
	return count


func _gun_shape_count(tank: CharacterBody3D) -> int:
	var count := 0
	for part in tank.part_geometry.parts:
		if part.anchor == &"gun":
			count += part.convex_shapes.size()
	return count


func _heading_error(tank: CharacterBody3D, goal: Vector3) -> float:
	var forward := tank.global_transform.basis * Vector3.LEFT
	forward.y = 0.0
	var direction := goal - (tank.call("stable_world_center") as Vector3)
	direction.y = 0.0
	return atan2(forward.cross(direction).y, forward.dot(direction))


func _xz_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x - right.x, left.z - right.z).length()


func _fail(message: String) -> void:
	_failures.append(message)
