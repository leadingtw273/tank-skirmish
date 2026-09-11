## 將原生導航路線轉成坦克車身的「需求」，不直接寫入任何載具控制欄位。
extends RefCounted

const Recovery := preload("res://src/ai/tank_recovery.gd")
const AGENT_NAME := &"TankNavigationAgent"
const MAP_READY_ITERATION := 0
const GOAL_REFRESH_SECONDS := 0.25
const GOAL_REFRESH_DISTANCE := 1.0
const TURN_IN_PLACE_RADIANS := deg_to_rad(32.0)
const RETRY_GOAL_DISTANCE := 3.0

var _tank: Node3D
var _agent: NavigationAgent3D
var _generation := -1
var _goal := Vector3.ZERO
var _last_route_goal := Vector3.ZERO
var _route_refresh_age := INF
var _status: StringName = &"waiting_map"
var _terminal := false
var _recovery := Recovery.new()
var _attempt_goal := Vector3.ZERO


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
	clear()


func dispose() -> void:
	if is_instance_valid(_agent):
		_agent.queue_free()
	_agent = null
	_tank = null
	clear()


func clear() -> void:
	_generation = -1
	_goal = Vector3.ZERO
	_last_route_goal = Vector3.ZERO
	_route_refresh_age = INF
	_status = &"waiting_map"
	_terminal = false
	_attempt_goal = Vector3.ZERO
	_recovery.reset()


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
	if generation != _generation or _horizontal_distance(horizontal_goal, _attempt_goal) >= RETRY_GOAL_DISTANCE:
		_generation = generation
		_goal = horizontal_goal
		_last_route_goal = horizontal_goal
		_route_refresh_age = 0.0
		_terminal = false
		_status = &"moving"
		_attempt_goal = horizontal_goal
		_recovery.reset(_horizontal(_stable_center()), _forward_direction())
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
	var position := _horizontal(_stable_center())
	var direct_distance := _horizontal_distance(position, horizontal_goal)
	var speed := absf(float(_tank.get("forward_speed")))
	if direct_distance <= maxf(stop_distance, 0.0):
		return _finish(&"arrived") if speed <= 0.1 else _command(0.0, 0.0, &"moving")
	if _recovery.phase != &"normal":
		return _drive_recovery(delta)
	var next := _agent.get_next_path_position()
	## 世界原點是合法路徑點；無路由空路徑判定，不能把零座標當哨兵。
	var path := _agent.get_current_navigation_path()
	if path.is_empty():
		return _finish(&"no_path")
	var remaining := _remaining_path_distance(position)
	var forward := _forward_direction()
	if remaining <= 0.5 or _agent.is_navigation_finished():
		## 真正抵達只由上面的原始世界位置判斷；投影末端不冒充目擊點。
		return _finish(&"partial_end") if speed <= 0.1 else _command(0.0, 0.0, &"moving")
	var desired := _horizontal(next) - position
	if desired.length_squared() <= 0.0001:
		desired = horizontal_goal - position
	if desired.length_squared() <= 0.0001:
		return _finish(&"partial_end" if not _agent.is_target_reachable() else &"arrived")
	var direction := desired.normalized()
	var angle := atan2(forward.cross(direction).y, forward.dot(direction))
	var turn := clampf(angle / TURN_IN_PLACE_RADIANS, -1.0, 1.0)
	var movement := 0.0
	var braking := false
	if absf(angle) <= TURN_IN_PLACE_RADIANS:
		## 交戰半徑作用於原始目標，不能從「部分路線」長度扣40m而提早卡死。
		var available := minf(maxf(direct_distance - maxf(stop_distance - 0.2, 0.0), 0.0), maxf(remaining - 0.3, 0.0))
		var mass := maxf(float(_tank.get("tank_mass_tonnes")), 0.001)
		var deceleration := maxf(float(_tank.get("brake_force_kilonewtons")) / mass, 0.001)
		var speed_limit := maxf(float(_tank.get("movement_speed")), 0.01)
		speed_limit *= lerpf(1.0, float(_tank.get("turning_movement_speed_ratio")), absf(turn))
		var desired_speed := minf(speed_limit, sqrt(2.0 * deceleration * available))
		## 折角前預留煞車距離；進入下一段後才原地轉向，不能滿速切建築角。
		var index := _agent.get_current_navigation_path_index()
		if index < path.size() - 1:
			var following := _horizontal(path[index + 1] - path[index])
			if not following.is_zero_approx() and direction.angle_to(following.normalized()) > deg_to_rad(10.0):
				var corner_distance := maxf(_horizontal_distance(position, next) - 0.5, 0.0)
				desired_speed = minf(desired_speed, sqrt(2.0 * deceleration * corner_distance))
		movement = clampf(desired_speed / speed_limit, 0.0, 1.0)
		## 只有實際需要減速才排除受阻計時；接近終點但靜止的正向需求仍可能被牆擋住。
		braking = desired_speed < speed - 0.05
	## 正常轉向有角度進展就不算卡住；轉向被牆阻擋則也必須能進入脫困。
	var contacts: Array[Dictionary] = _tank.call("get_recovery_contacts") if _tank.has_method("get_recovery_contacts") else []
	_recovery.observe(position, forward, 0.0 if braking else movement, turn, delta, contacts)
	if _recovery.phase != &"normal":
		return _drive_recovery(delta)
	_status = &"moving"
	return _command(movement, turn, _status)


func _finish(status: StringName) -> Dictionary:
	_status = status
	_terminal = true
	_recovery.reset()
	return _command(0.0, 0.0, status)


func _command(movement: float, turn: float, status: StringName) -> Dictionary:
	return {"movement": clampf(movement, -1.0 if status == &"recovering" else 0.0, 1.0), "turn": clampf(turn, -1.0, 1.0), "status": status,
		"route": &"navmesh"}


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


func _drive_recovery(delta: float) -> Dictionary:
	var mass := maxf(float(_tank.get("tank_mass_tonnes")), 0.001)
	var deceleration := maxf(float(_tank.get("brake_force_kilonewtons")) / mass, 0.001)
	var result := _recovery.drive(_horizontal(_stable_center()), _forward_direction(),
		float(_tank.get("forward_speed")), float(_tank.get("reverse_movement_speed")), deceleration, delta,
		float(_tank.get("movement_speed")), float(_tank.get("actual_angular_speed")))
	if result.get("replan", false):
		_agent.target_position = _goal
		_last_route_goal = _goal
		_route_refresh_age = 0.0
	if result.get("status") == &"stuck":
		return _finish(&"stuck")
	_status = &"recovering"
	return _command(float(result.get("movement", 0.0)), float(result.get("turn", 0.0)), _status)


func _forward_direction() -> Vector3:
	return _horizontal(_tank.global_transform.basis * Vector3.LEFT).normalized()


static func _horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return _horizontal(a).distance_to(_horizontal(b))
