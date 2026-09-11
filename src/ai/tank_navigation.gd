## 將原生導航路線轉成坦克車身的「需求」，不直接寫入任何載具控制欄位。
extends RefCounted

const DirectClearance := preload("res://src/ai/tank_direct_clearance.gd")
const LocalRouteSearch := preload("res://src/ai/tank_local_route_search.gd")
const WAYPOINT_DISTANCE := DirectClearance.WAYPOINT_TOLERANCE
const AGENT_NAME := &"TankNavigationAgent"
const MAP_READY_ITERATION := 0
const GOAL_REFRESH_SECONDS := 0.25
const GOAL_REFRESH_DISTANCE := 1.0
const TURN_IN_PLACE_RADIANS := deg_to_rad(32.0)
const STUCK_SECONDS := 3.0
const STUCK_PROGRESS_METRES := 0.5
const DIRECT_ALIGNMENT_RADIANS := deg_to_rad(1.0)
const SHORTCUT_SAVING_METRES := 2.0

var _tank: Node3D
var _agent: NavigationAgent3D
var _generation := -1
var _goal := Vector3.ZERO
var _last_route_goal := Vector3.ZERO
var _route_refresh_age := INF
var _status: StringName = &"waiting_map"
var _terminal := false
var _stuck_elapsed := 0.0
var _stuck_origin := Vector3.ZERO
var _clearance: RefCounted
var _shortcut_kind: StringName = &"none"
var _shortcut_points: Array[Vector3] = []
var _shortcut_index := 0
var _local_search: RefCounted
var _local_pending := false
var _local_started := false
var _guard_rejoin := false
var _shortcut_aligning := false
var _shortcut_braking := false
var _shortcut_checked := false
var _shortcut_checked_goal := Vector3.ZERO


func setup(tank: Node3D) -> void:
	dispose()
	_tank = tank
	if _tank == null:
		return
	_agent = NavigationAgent3D.new()
	_agent.name = AGENT_NAME
	_agent.avoidance_enabled = false
	_agent.path_desired_distance = 1.0
	_agent.target_desired_distance = 0.5
	_tank.add_child(_agent)
	_agent.set_navigation_map(_tank.get_world_3d().navigation_map)
	_clearance = DirectClearance.new()
	_clearance.setup(_tank)
	_local_search = LocalRouteSearch.new()
	clear()


func dispose() -> void:
	if is_instance_valid(_agent):
		_agent.queue_free()
	_agent = null
	_clearance = null
	_local_search = null
	_tank = null
	clear()


func clear() -> void:
	_generation = -1
	_goal = Vector3.ZERO
	_last_route_goal = Vector3.ZERO
	_route_refresh_age = INF
	_status = &"waiting_map"
	_terminal = false
	_stuck_elapsed = 0.0
	_stuck_origin = Vector3.ZERO
	_reset_shortcut_route()


func drive(goal: Vector3, generation: int, stop_distance: float, delta: float) -> Dictionary:
	if _tank == null or not is_instance_valid(_agent):
		return _command(0.0, 0.0, &"waiting_map")
	var map := _tank.get_world_3d().navigation_map
	if map.is_valid() and _agent.get_navigation_map() != map:
		_agent.set_navigation_map(map)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= MAP_READY_ITERATION:
		_status = &"waiting_map"
		return _command(0.0, 0.0, _status)
	## 地圖可能先同步空集合；所屬區域尚未完成首輪同步時不能鎖死成無路。
	for region in NavigationServer3D.map_get_regions(map):
		if NavigationServer3D.region_get_enabled(region) and NavigationServer3D.region_get_iteration_id(region) == 0:
			return _command(0.0, 0.0, &"waiting_map")
	var horizontal_goal := _horizontal(goal)
	if generation != _generation:
		_generation = generation
		_goal = horizontal_goal
		_last_route_goal = horizontal_goal
		_route_refresh_age = 0.0
		_terminal = false
		_status = &"moving"
		_reset_stuck()
		_reset_shortcut_route()
		_agent.target_position = horizontal_goal
	elif _terminal:
		return _command(0.0, 0.0, _status)
	else:
		_route_refresh_age += maxf(delta, 0.0)
		_goal = horizontal_goal
		if _route_refresh_age >= GOAL_REFRESH_SECONDS and _last_route_goal.distance_to(horizontal_goal) >= GOAL_REFRESH_DISTANCE:
			_last_route_goal = horizontal_goal
			_route_refresh_age = 0.0
			_agent.target_position = horizontal_goal
			_reset_stuck()
	var position := _horizontal(_stable_center())
	var direct_distance := _horizontal_distance(position, horizontal_goal)
	var speed := absf(float(_tank.get("forward_speed")))
	if direct_distance <= maxf(stop_distance, 0.0):
		return _finish(&"arrived") if speed <= 0.1 else _command(0.0, 0.0, &"moving")
	var next := _agent.get_next_path_position()
	## 世界原點是合法路徑點；無路由空路徑判定，不能把零座標當哨兵。
	var path := _agent.get_current_navigation_path()
	if path.is_empty() and not _has_shortcut() and not _shortcut_braking:
		return _finish(&"no_path")
	var remaining := _remaining_path_distance(position)
	if _shortcut_checked and _horizontal_distance(horizontal_goal, _shortcut_checked_goal) >= GOAL_REFRESH_DISTANCE:
		_reset_shortcut_route()
	var forward := _horizontal(_tank.global_transform.basis * Vector3.LEFT).normalized()
	var direct_direction := (horizontal_goal - position).normalized()
	var direct_angle := atan2(forward.cross(direct_direction).y, forward.dot(direct_direction))
	if not _has_shortcut() and not _shortcut_braking and not _shortcut_checked and remaining > direct_distance + SHORTCUT_SAVING_METRES:
		_shortcut_checked = true
		_shortcut_checked_goal = horizontal_goal
		if _clearance.can_travel(horizontal_goal, stop_distance, direct_angle, true) and _clearance.can_turn(direct_angle):
			_activate_shortcut(&"direct", [horizontal_goal])
		elif direct_distance <= LocalRouteSearch.MAX_DISTANCE:
			_local_pending = true
	if _local_pending:
		## 固定候選搜尋期間先煞停，避免候選的起點在查詢間漂移。
		_reset_stuck()
		if speed > 0.1:
			return _command(0.0, 0.0, &"moving")
		if not _local_started:
			_local_search.begin(position, horizontal_goal, stop_distance, remaining)
			_local_started = true
		var result: Dictionary = _local_search.step(_clearance)
		if result.status == &"pending":
			return _command(0.0, 0.0, &"moving")
		_local_pending = false
		if result.status == &"found":
			_activate_shortcut(&"local", [result.point, horizontal_goal])
	if _shortcut_braking:
		if speed > 0.1:
			return _command(0.0, 0.0, &"moving")
		_shortcut_braking = false
	var leg_stop := stop_distance
	if _has_shortcut():
		_shortcut_points[-1] = horizontal_goal
		if _shortcut_index < _shortcut_points.size() - 1 and _horizontal_distance(position, _shortcut_points[_shortcut_index]) <= WAYPOINT_DISTANCE:
			if speed > 0.1:
				return _command(0.0, 0.0, &"moving")
			_shortcut_index += 1
			_shortcut_aligning = true
			_reset_stuck()
		next = _shortcut_points[_shortcut_index]
		leg_stop = 0.25 if _shortcut_index < _shortcut_points.size() - 1 else stop_distance
		var leg_direction := (next - position).normalized()
		var leg_angle := atan2(forward.cross(leg_direction).y, forward.dot(leg_direction))
		if absf(leg_angle) > DIRECT_ALIGNMENT_RADIANS * 3.0:
			_shortcut_aligning = true
		if _shortcut_aligning:
			_reset_stuck()
			if speed > 0.1:
				return _command(0.0, 0.0, &"moving")
			if not _clearance.can_turn(leg_angle):
				_reject_shortcut_route()
				return _command(0.0, 0.0, &"moving")
			if absf(leg_angle) > DIRECT_ALIGNMENT_RADIANS:
				return _command(0.0, clampf(leg_angle / TURN_IN_PLACE_RADIANS, -1.0, 1.0), &"moving")
			_shortcut_aligning = false
		## 規劃只排除可移動車輛，執行則重新檢查真實姿態與所有實物。
		if not _clearance.can_turn(leg_angle) or not _clearance.can_travel(next, leg_stop):
			_reject_shortcut_route()
			return _command(0.0, 0.0, &"moving")
		remaining = _horizontal_distance(position, next)
		for index in range(_shortcut_index + 1, _shortcut_points.size()):
			remaining += _horizontal_distance(_shortcut_points[index - 1], _shortcut_points[index])
	if not _has_shortcut() and (remaining <= 0.5 or _agent.is_navigation_finished()):
		## 真正抵達只由上面的原始世界位置判斷；投影末端不冒充目擊點。
		return _finish(&"partial_end") if speed <= 0.1 else _command(0.0, 0.0, &"moving")
	var desired := _horizontal(next) - position
	if desired.length_squared() <= 0.0001:
		desired = horizontal_goal - position
	if desired.length_squared() <= 0.0001:
		return _finish(&"partial_end" if not _agent.is_target_reachable() else &"arrived")
	var direction := desired.normalized()
	var angle := atan2(forward.cross(direction).y, forward.dot(direction))
	## 離開navmesh的近路失效後，不能直接切向投影路點穿過建築。
	if _guard_rejoin and not _has_shortcut():
		if not _clearance.can_turn(angle) or not _clearance.can_travel(next, 0.3, angle):
			return _finish(&"stuck")
	var turn := clampf(angle / TURN_IN_PLACE_RADIANS, -1.0, 1.0)
	var braking_distance := _braking_distance()
	var movement := 0.0
	var braking := false
	if absf(angle) <= TURN_IN_PLACE_RADIANS:
		## 交戰半徑作用於原始目標，不能從「部分路線」長度扣40m而提早卡死。
		var available := minf(maxf(direct_distance - maxf(stop_distance - 0.2, 0.0), 0.0), maxf(remaining - 0.3, 0.0))
		if _has_shortcut():
			available = minf(available, maxf(_horizontal_distance(position, next) - maxf(leg_stop - 0.2, 0.0), 0.0))
		var mass := maxf(float(_tank.get("tank_mass_tonnes")), 0.001)
		var deceleration := maxf(float(_tank.get("brake_force_kilonewtons")) / mass, 0.001)
		var speed_limit := maxf(float(_tank.get("movement_speed")), 0.01)
		speed_limit *= lerpf(1.0, float(_tank.get("turning_movement_speed_ratio")), absf(turn))
		var desired_speed := minf(speed_limit, sqrt(2.0 * deceleration * available))
		## 折角前預留煞車距離；進入下一段後才原地轉向，不能滿速切建築角。
		var index := _agent.get_current_navigation_path_index()
		if not _has_shortcut() and index < path.size() - 1:
			var following := _horizontal(path[index + 1] - path[index])
			if not following.is_zero_approx() and direction.angle_to(following.normalized()) > deg_to_rad(10.0):
				var corner_distance := maxf(_horizontal_distance(position, next) - 0.5, 0.0)
				desired_speed = minf(desired_speed, sqrt(2.0 * deceleration * corner_distance))
		movement = clampf(desired_speed / speed_limit, 0.0, 1.0)
		braking = desired_speed < speed - 0.05 or available <= braking_distance + 0.5
	if movement > 0.05 and not braking:
		_stuck_elapsed += maxf(delta, 0.0)
		if _horizontal_distance(position, _stuck_origin) >= STUCK_PROGRESS_METRES:
			_reset_stuck()
		elif _stuck_elapsed >= STUCK_SECONDS:
			return _finish(&"stuck")
	else:
		_reset_stuck()
	_status = &"moving"
	return _command(movement, turn, _status)


func _finish(status: StringName) -> Dictionary:
	_status = status
	_terminal = true
	_reset_stuck()
	return _command(0.0, 0.0, status)


func _command(movement: float, turn: float, status: StringName) -> Dictionary:
	return {"movement": clampf(movement, 0.0, 1.0), "turn": clampf(turn, -1.0, 1.0), "status": status,
		"route": _shortcut_kind if _has_shortcut() else &"navmesh"}


func _has_shortcut() -> bool:
	return _shortcut_kind != &"none"


func _activate_shortcut(kind: StringName, points: Array[Vector3]) -> void:
	_shortcut_kind = kind
	_shortcut_points = points
	_shortcut_index = 0
	_shortcut_aligning = true


func _reset_shortcut_route() -> void:
	_guard_rejoin = false
	_local_pending = false
	_local_started = false
	if _local_search != null:
		_local_search.clear()
	_shortcut_kind = &"none"
	_shortcut_points.clear()
	_shortcut_index = 0
	_shortcut_aligning = false
	_shortcut_braking = false
	_shortcut_checked = false
	_shortcut_checked_goal = Vector3.ZERO


func _reject_shortcut_route() -> void:
	_guard_rejoin = _guard_rejoin or _shortcut_kind == &"local"
	_shortcut_kind = &"none"
	_shortcut_points.clear()
	_shortcut_index = 0
	_shortcut_aligning = false
	_shortcut_braking = true
	_reset_stuck()


func _stable_center() -> Vector3:
	if _tank.has_method("stable_world_center"):
		return _tank.call("stable_world_center") as Vector3
	return _tank.global_position


func _remaining_path_distance(position: Vector3) -> float:
	var path := _agent.get_current_navigation_path()
	if path.is_empty():
		return 0.0
	var index := clampi(_agent.get_current_navigation_path_index(), 0, path.size() - 1)
	var distance := _horizontal_distance(position, path[index])
	for point_index in range(index + 1, path.size()):
		distance += _horizontal_distance(path[point_index - 1], path[point_index])
	return distance


func _braking_distance() -> float:
	var speed := absf(float(_tank.get("forward_speed")))
	var mass := maxf(float(_tank.get("tank_mass_tonnes")), 0.001)
	var force := maxf(float(_tank.get("brake_force_kilonewtons")), 0.001)
	return speed * speed / (2.0 * force / mass)


func _reset_stuck() -> void:
	_stuck_elapsed = 0.0
	_stuck_origin = _stable_center() if _tank != null else Vector3.ZERO


static func _horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return _horizontal(a).distance_to(_horizontal(b))
