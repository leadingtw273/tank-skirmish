## AI-only planar experiment; collision/support validation belongs to the caller.
## Force limits are caps, not guaranteed braking acceleration.
extends RefCounted

const Intent := preload("res://src/actors/rigid_tank/tank_drive_intent.gd")

var root := Transform3D.IDENTITY
var velocity := Vector3.ZERO
var angular := 0.0
var pending_force := Vector3.ZERO
var pending_torque := 0.0
var intent := Intent.new()
var config: Dictionary
var elapsed := 0.0
var geometry := {}
var _pending_is_linear := false


static func capture(tank: RigidBody3D, snapshot: Dictionary) -> Dictionary:
	var direct := PhysicsServer3D.body_get_direct_state(tank.get_rid())
	if direct == null or not bool(snapshot.get("grounded", false)):
		return {}
	var source: RefCounted = tank.get("_drive_intent")
	var telemetry: Dictionary = tank.call("telemetry")
	var parameters := {"mass": tank.mass, "inertia": float(tank.get("_prediction_inertia")),
		"linear_damp": direct.total_linear_damp, "angular_damp": direct.total_angular_damp,
		"drive": float(tank.get("side_drive_force_limit")), "brake": float(tank.get("side_brake_force_limit")),
		"stations": [], "half_width": 0.0, "mean_x_squared": 0.0}
	for key in ["forward_speed", "reverse_speed", "acceleration", "deceleration", "turn_speed", "turn_response", "turning_ratio"]:
		parameters[key] = source.get(key)
	var stations: Array = tank.get("_stations")
	for station: Dictionary in stations:
		var offset: Vector3 = (station.local as Vector3) - tank.center_of_mass
		parameters.stations.append({"side": station.side, "x": offset.x, "z": offset.z})
		parameters.half_width += absf(offset.z) / stations.size()
		parameters.mean_x_squared += offset.x * offset.x / stations.size()
	var root_pose: Transform3D = snapshot.root
	var world_com := root_pose * tank.center_of_mass
	var torque := Vector3.ZERO
	for point: Dictionary in telemetry.spring_points:
		if bool(point.contact):
			var force: Vector3 = (point.normal as Vector3) * float(point.normal_load) + (point.traction as Vector3)
			torque += ((point.position as Vector3) - world_com).cross(force)
	for point: Dictionary in telemetry.native_track_contacts:
		torque += ((point.position as Vector3) - world_com).cross(point.traction as Vector3)
	for point: Dictionary in telemetry.native_passive_contacts:
		torque += ((point.position as Vector3) - world_com).cross(point.friction as Vector3)
	return {"config": parameters, "initial": {"root": root_pose,
		"velocity": snapshot.linear_velocity, "angular": tank.angular_velocity.y,
		"pending_force": telemetry.applied_force, "pending_torque": torque.y,
		"longitudinal": source.get("longitudinal"), "steering": source.get("steering")},
		"physics_frame": Engine.get_physics_frames()}


func initialize(parameters: Dictionary, initial: Dictionary) -> void:
	config = parameters.duplicate(true)
	root = initial.root
	velocity = initial.velocity
	velocity.y = 0.0
	angular = float(initial.angular)
	pending_force = initial.pending_force
	pending_force.y = 0.0
	pending_torque = float(initial.pending_torque)
	for key in ["forward_speed", "reverse_speed", "acceleration", "deceleration", "turn_speed", "turn_response", "turning_ratio"]:
		intent.set(key, float(config[key]))
	intent.longitudinal = float(initial.longitudinal)
	intent.steering = float(initial.steering)
	geometry = _aggregate_station_geometry(config.stations as Array)
	elapsed = 0.0
	_pending_is_linear = false


func _aggregate_station_geometry(stations: Array) -> Dictionary:
	var result := {"left": _empty_side_geometry(), "right": _empty_side_geometry()}
	for station: Dictionary in stations:
		var entry: Dictionary = result[station.side]
		var x := float(station.x)
		var z := float(station.z)
		entry.count = int(entry.count) + 1
		entry.sum_x = float(entry.sum_x) + x
		entry.sum_z = float(entry.sum_z) + z
		entry.sum_x_squared = float(entry.sum_x_squared) + x * x
		entry.sum_z_squared = float(entry.sum_z_squared) + z * z
		entry.max_abs_x = maxf(float(entry.max_abs_x), absf(x))
		entry.max_abs_z = maxf(float(entry.max_abs_z), absf(z))
		result[station.side] = entry
	return result


func _empty_side_geometry() -> Dictionary:
	return {"count": 0, "sum_x": 0.0, "sum_z": 0.0,
		"sum_x_squared": 0.0, "sum_z_squared": 0.0,
		"max_abs_x": 0.0, "max_abs_z": 0.0}


func step(movement: float, turn: float, braking: bool, dt: float) -> Dictionary:
	# The captured force affects the next tick, just as the rigid body's integration.
	velocity = velocity * (1.0 - float(config.linear_damp) * dt) + pending_force * (dt / float(config.mass))
	angular = angular * (1.0 - float(config.angular_damp) * dt) + pending_torque * dt / float(config.inertia)
	root.basis = Basis(Vector3.UP, angular * dt) * root.basis
	root.origin += velocity * dt
	var forward := -root.basis.x
	forward.y = 0.0
	forward = forward.normalized()
	var side := Vector3.UP.cross(forward)
	var longitudinal := velocity.dot(forward)
	var lateral := velocity.dot(side)
	intent.step(movement, -turn, longitudinal, dt)
	var stations: Array = config.stations
	var station_mass := float(config.mass) / stations.size()
	var normal_load := station_mass * 9.81
	var width := float(config.half_width)
	var lever := width + 1.5 * float(config.mean_x_squared) / width
	var release_feedback_only := braking and not bool(config.get("braking_feedforward", false))
	var linear_feed := 0.0 if release_feedback_only else intent.linear_acceleration / 2.0
	var angular_feed := 0.0 if release_feedback_only else intent.angular_acceleration * float(config.inertia) / (float(config.mass) * 2.0 * width)
	var targets := {
		"left": intent.longitudinal + linear_feed + intent.steering * lever + angular_feed,
		"right": intent.longitudinal + linear_feed - intent.steering * lever - angular_feed,
	}
	var used := {"left": 0.0, "right": 0.0}
	var absolute := {"left": 0.0, "right": 0.0}
	var sum_forward := 0.0
	var sum_lateral := 0.0
	pending_torque = 0.0
	_pending_is_linear = false
	if _provably_unsaturated(targets, longitudinal, lateral, angular, station_mass, normal_load):
		# Bounds above prove every point avoids both friction clamps/ellipse and either side cap.
		# These sums are therefore algebraically identical to the station loop below.
		for track in ["left", "right"]:
			var g: Dictionary = geometry[track]
			var count := float(g.count)
			var force := station_mass * 2.0 * (count * (float(targets[track]) - longitudinal) + angular * float(g.sum_z))
			var lateral_force := station_mass * 3.0 * (-count * lateral + angular * float(g.sum_x))
			sum_forward += force
			sum_lateral += lateral_force
			pending_torque -= station_mass * 2.0 * ((float(targets[track]) - longitudinal) * float(g.sum_z) + angular * float(g.sum_z_squared))
			pending_torque -= station_mass * 3.0 * (-lateral * float(g.sum_x) + angular * float(g.sum_x_squared))
		pending_force = forward * sum_forward + side * sum_lateral
		_pending_is_linear = true
		elapsed += dt
		return {"root": root, "velocity": velocity, "angular_speed": angular, "forward_speed": longitudinal, "elapsed": elapsed}
	for station: Dictionary in stations:
		var track: String = station.side
		var point_speed := longitudinal - angular * float(station.z)
		var point_lateral := lateral - angular * float(station.x)
		var force := clampf((float(targets[track]) - point_speed) * station_mass * 2.0, -normal_load * 0.8, normal_load * 0.8)
		var is_braking := absf(point_speed) > 0.01 and force * point_speed < 0.0
		var limit := float(config.brake if is_braking else config.drive)
		var remaining := maxf(0.0, limit - float(absolute[track])) if float(config.drive) == float(config.brake) else limit * maxf(0.0, 1.0 - float(used[track]))
		force = clampf(force, -remaining, remaining)
		var lateral_force := clampf(-point_lateral * station_mass * 3.0, -normal_load * 0.55, normal_load * 0.55)
		var ellipse := Vector2(force / (normal_load * 0.8), lateral_force / (normal_load * 0.55)).length()
		if ellipse > 1.0:
			force /= ellipse
			lateral_force /= ellipse
		used[track] = float(used[track]) + absf(force) / limit
		absolute[track] = float(absolute[track]) + absf(force)
		sum_forward += force
		sum_lateral += lateral_force
		pending_torque -= float(station.z) * force + float(station.x) * lateral_force
	pending_force = forward * sum_forward + side * sum_lateral
	elapsed += dt
	return {"root": root, "velocity": velocity, "angular_speed": angular, "forward_speed": longitudinal, "elapsed": elapsed}


func _provably_unsaturated(targets: Dictionary, longitudinal: float, lateral: float, yaw: float, station_mass: float, normal_load: float) -> bool:
	var longitudinal_limit := normal_load * 0.8
	var lateral_limit := normal_load * 0.55
	var side_limit := minf(float(config.drive), float(config.brake))
	if longitudinal_limit <= 0.0 or lateral_limit <= 0.0 or side_limit <= 0.0:
		return false
	for track in ["left", "right"]:
		var g: Dictionary = geometry[track]
		var force_bound := (absf(float(targets[track]) - longitudinal) + absf(yaw) * float(g.max_abs_z)) * station_mass * 2.0
		var lateral_bound := (absf(lateral) + absf(yaw) * float(g.max_abs_x)) * station_mass * 3.0
		# Bound the full ellipse, not only each axis independently.
		if Vector2(force_bound / longitudinal_limit, lateral_bound / lateral_limit).length() > 1.0:
			return false
		# min(drive, brake) is conservative for the mixed normalized-budget case;
		# every prefix is bounded by this total, hence remaining cannot clamp.
		if float(g.count) * force_bound > side_limit:
			return false
	return true


## 只界定此平面數值模型的無限尾段，不是對真車外力／懸吊的保證。
## 動能座標的對稱阻尼矩陣經任意yaw旋轉仍有相同特徵值。
func remaining_vertex_travel(radius: float, dt: float) -> float:
	if not _pending_is_linear or intent.longitudinal != 0.0 or intent.steering != 0.0 or intent.linear_acceleration != 0.0 or intent.angular_acceleration != 0.0:
		return INF
	var mass := float(config.mass)
	var inertia := float(config.inertia)
	var count := float((config.stations as Array).size())
	var sum_x := float(geometry.left.sum_x) + float(geometry.right.sum_x)
	var sum_z := float(geometry.left.sum_z) + float(geometry.right.sum_z)
	var xx := (float(geometry.left.sum_x_squared) + float(geometry.right.sum_x_squared)) / count
	var zz := (float(geometry.left.sum_z_squared) + float(geometry.right.sum_z_squared)) / count
	var coupling_x := absf(2.0 * sqrt(mass / inertia) * sum_z / count)
	var coupling_z := absf(3.0 * sqrt(mass / inertia) * sum_x / count)
	var dx := 2.0 + float(config.linear_damp)
	var dz := 3.0 + float(config.linear_damp)
	var dw := mass / inertia * (2.0 * zz + 3.0 * xx) + float(config.angular_damp)
	var lower := minf(minf(dx - coupling_x, dz - coupling_z), dw - coupling_x - coupling_z)
	var upper := maxf(maxf(dx + coupling_x, dz + coupling_z), dw + coupling_x + coupling_z)
	if lower <= 0.0: return INF
	var contraction := maxf(absf(1.0 - dt * lower), absf(1.0 - dt * upper))
	if contraction >= 1.0: return INF
	var energy_norm := sqrt(mass * velocity.length_squared() + inertia * angular * angular)
	# 以整個未來能量上界確認每站橢圓與各側額度永不飽和，才能使用線性矩陣。
	var max_linear := energy_norm / sqrt(mass)
	var max_yaw := energy_norm / sqrt(inertia)
	if not _provably_unsaturated({"left": 0.0, "right": 0.0}, max_linear, max_linear, max_yaw, mass / count, mass * 9.81 / count):
		return INF
	return sqrt(1.0 / mass + radius * radius / inertia) * energy_norm * dt * contraction / (1.0 - contraction)
