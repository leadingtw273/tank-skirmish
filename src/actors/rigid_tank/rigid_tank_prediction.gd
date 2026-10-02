## AI 專用純近似；不寫入 actor、命令曲線或物理狀態。
extends RefCounted

const Intent := preload("res://src/actors/rigid_tank/tank_drive_intent.gd")
const Grounding := preload("res://src/actors/tank/geometry/tank_grounding.gd")

static func step(tank: Node3D, speed: float, angular: float, movement: float, turn: float, delta: float) -> Dictionary:
	if not is_finite(speed) or not is_finite(angular) or not is_finite(delta) or delta <= 0.0:
		return {}
	var intent := Intent.new()
	intent.configure(tank.combat_tank)
	intent.longitudinal = speed
	intent.steering = -angular
	intent.step(movement, -turn, speed, delta)
	# 命令曲線仍受兩側有限力和實際慣量所約束；不是另一個物理 solver。
	var force: float = tank.side_brake_force_limit if is_zero_approx(movement) or speed * movement < 0.0 else tank.side_drive_force_limit
	var acceleration: float = 2.0 * force / tank.mass
	var half_width := 0.0
	for station: Dictionary in tank._stations:
		half_width = maxf(half_width, absf((station.local as Vector3).z - tank.center_of_mass.z))
	var yaw_force: float = tank.side_brake_force_limit if is_zero_approx(turn) or angular * turn < 0.0 else tank.side_drive_force_limit
	var yaw_acceleration: float = 2.0 * yaw_force * half_width / maxf(tank._prediction_inertia, 1.0)
	return {"forward_speed": move_toward(speed, intent.longitudinal, acceleration * delta),
		"angular_speed": move_toward(angular, -intent.steering, yaw_acceleration * delta)}

# 同一同步 ground query 的唯讀參數；candidate 間只重設影響 step 的狀態。
var _cached_intent := Intent.new()
var _drive_acceleration := 0.0
var _brake_acceleration := 0.0
var _drive_yaw_acceleration := 0.0
var _brake_yaw_acceleration := 0.0

func configure(tank: Node3D) -> void:
	_cached_intent.configure(tank.combat_tank)
	_drive_acceleration = 2.0 * tank.side_drive_force_limit / tank.mass
	_brake_acceleration = 2.0 * tank.side_brake_force_limit / tank.mass
	var half_width := 0.0
	for station: Dictionary in tank._stations:
		half_width = maxf(half_width, absf((station.local as Vector3).z - tank.center_of_mass.z))
	_drive_yaw_acceleration = 2.0 * tank.side_drive_force_limit * half_width / maxf(tank._prediction_inertia, 1.0)
	_brake_yaw_acceleration = 2.0 * tank.side_brake_force_limit * half_width / maxf(tank._prediction_inertia, 1.0)

func step_cached(speed: float, angular: float, movement: float, turn: float, delta: float) -> Dictionary:
	if not is_finite(speed) or not is_finite(angular) or not is_finite(delta) or delta <= 0.0: return {}
	_cached_intent.longitudinal = speed
	_cached_intent.steering = -angular
	_cached_intent.step(movement, -turn, speed, delta)
	var acceleration := _brake_acceleration if is_zero_approx(movement) or speed * movement < 0.0 else _drive_acceleration
	var yaw_acceleration := _brake_yaw_acceleration if is_zero_approx(turn) or angular * turn < 0.0 else _drive_yaw_acceleration
	return {"forward_speed": move_toward(speed, _cached_intent.longitudinal, acceleration * delta),
		"angular_speed": move_toward(angular, -_cached_intent.steering, yaw_acceleration * delta)}

static func support_points(tank: Node3D) -> Array[Vector3]:
	# local vertices/stations 僅在 derive 時重建並清空；世界姿態不影響這四點。
	var key := Vector2(tank.hull_bottom_local, tank.ground_step_height)
	if tank._prediction_support_key == key and not tank._prediction_support_points.is_empty():
		return tank._prediction_support_points
	var points: Array[Vector3] = []
	# 圓弧履帶的最前緣比平底彈簧站更早遇到台階，使用低處完整幾何的前後界。
	var front := INF
	var rear := -INF
	for vertex: Vector3 in tank._hull_local_vertices:
		if vertex.y <= tank.hull_bottom_local + tank.ground_step_height:
			front = minf(front, vertex.x)
			rear = maxf(rear, vertex.x)
	for index in [0, 4, 5, 9]:
		var point: Vector3 = tank._stations[index].local
		point.x = front if index in [0, 5] else rear
		point.y = tank.hull_bottom_local
		points.append(point)
	points.make_read_only()
	tank._prediction_support_key = key
	tank._prediction_support_points = points
	return points

static func support(tank: Node3D, pose: Transform3D, height: float) -> Dictionary:
	# 這是三秒近似姿態的唯讀取樣，不是實體接地/吸附距離。
	# 車身在路肩頂俯仰時，前後端可能高過下方路面一個完整階差；
	# 只用 snap_distance 會漏掉真實存在的支撐，誤把路肩重新當牆。
	var look_down: float = tank.ground_snap_distance + tank.ground_step_height
	return Grounding.sample_support(tank.get_world_3d().direct_space_state, pose, support_points(tank),
		[tank.get_rid()], tank.collision_mask, height, look_down, tank.ground_max_slope_degrees)
