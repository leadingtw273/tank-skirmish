## 玩家與精簡測試入口共用的有限接觸剛體驅動。
class_name ContactTank
extends RigidBody3D

const TANK2_SCENE := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const DriveIntent := preload("res://src/actors/rigid_tank/tank_drive_intent.gd")
const TreadVisual := preload("res://src/actors/rigid_tank/tank_tread_visual.gd")
const POINTS_PER_SIDE := 5
const STATION_COUNT := POINTS_PER_SIDE * 2
const GRAVITY := 9.81
const SPRING_REST := 0.6
const EQUILIBRIUM_COMPRESSION := 0.15
const EXPECTED_HULL_CLEARANCE := 0.04
const SPHERE_RADIUS := 0.4 # Track width is ~0.905 m, so this is intentionally smaller.
const QUERY_MARGIN := 0.002
const LONGITUDINAL_MU := 0.8
const LATERAL_MU := 0.55
const VELOCITY_RATE := 2.0
const LATERAL_RATE := 3.0
const MAX_SPEED := 2.0
const PASSIVE_MU := 0.6
const SIDE_MOTOR_FORCE_LIMIT := 120000.0

# Default preserves the explicitly fixed T1 baseline; the playtest enables feel.
@export var driving_feel_enabled := false
@export var donor_scene: PackedScene = TANK2_SCENE
@export var side_drive_force_limit := SIDE_MOTOR_FORCE_LIMIT
var side_brake_force_limit := SIDE_MOTOR_FORCE_LIMIT
var collision_shapes: Array[CollisionShape3D] = []
var _drive_intent := DriveIntent.new()
var _drive_targets := {"left": 0.0, "right": 0.0, "longitudinal": 0.0, "steering": 0.0, "phase": "fixed_contact"}

var hull_bottom_local := -0.018404
var source_shape_count := 0
var full_shape_count := 0
var _stations: Array[Dictionary] = []
var _hull_local_vertices: Array[Vector3] = []
## 每車獨立的唯讀局部支撐點；只省幾何計算，不保存世界碰撞查詢。
var _prediction_support_points: Array[Vector3] = []
var _prediction_support_key := Vector2(INF, INF)
var _sphere := SphereShape3D.new()
var _movement_input := 0.0
var _turn_input := 0.0
var _ready_for_physics := false
var _spring_k := 0.0
var _damper_c := 0.0
var _station_load_cap := 0.0
var _left_contacts := 0
var _right_contacts := 0
var _total_support_force := 0.0
var _drive_force := Vector3.ZERO
var _applied_force := Vector3.ZERO
var _invalid_contacts := 0
var _spring_points: Array[Dictionary] = []
var _track_shapes: Dictionary = {}
var _native_track_contacts: Array[Dictionary] = []
var _native_passive_contacts: Array[Dictionary] = []
var _longitudinal_used := {"left": 0.0, "right": 0.0}
var _side_budget_used := {"left": 0.0, "right": 0.0}
var _drive_used := {"left": 0.0, "right": 0.0}
var _brake_used := {"left": 0.0, "right": 0.0}
var _tread_visual := TreadVisual.new()

func _process(delta: float) -> void:
	if not _ready_for_physics: return
	var speed := linear_velocity.dot(-global_basis.x.normalized())
	var yaw := -angular_velocity.dot(global_basis.y.normalized())
	if absf(_movement_input) > 0.01 or absf(_turn_input) > 0.01:
		# Nominal drive intent remains nonzero against a wall; exclude force feed-forward.
		speed = _drive_intent.longitudinal if driving_feel_enabled else _movement_input * MAX_SPEED
		yaw = _drive_intent.steering if driving_feel_enabled else _turn_input * _drive_intent.turn_speed
	else:
		if absf(speed) < 0.01: speed = 0.0
		if absf(yaw) < 0.01: yaw = 0.0
	_tread_visual.step(delta, speed, yaw)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 128
	continuous_cd = true
	max_contacts_reported = 32
	physics_material_override = PhysicsMaterial.new()
	# Normal collision remains in the solver; tangential response is owned below.
	physics_material_override.friction = 0.0
	physics_material_override.bounce = 0.0
	_adopt_vehicle_snapshot()


func set_movement_input(value: float) -> void:
	_movement_input = clampf(value, -1.0, 1.0)


func set_turn_input(value: float) -> void:
	_turn_input = clampf(value, -1.0, 1.0)

func slow_movement_input(value: float) -> float:
	var limit := _drive_intent.forward_speed if value >= 0.0 else _drive_intent.reverse_speed
	return value * minf(1.0, MAX_SPEED / maxf(limit, 0.001))


func shape_count() -> int:
	return full_shape_count


func hull_world_bottom() -> float:
	# Hull-anchor vertices include tracks and follow roll/pitch; turret/gun are excluded.
	var result := INF
	for vertex in _hull_local_vertices:
		result = minf(result, (global_transform * vertex).y)
	return result if result < INF else global_position.y + hull_bottom_local


func telemetry() -> Dictionary:
	return {
		"left_contacts": _left_contacts,
		"right_contacts": _right_contacts,
		"total_support_force": _total_support_force,
		"drive_force": _drive_force,
		"applied_force": _applied_force,
		"invalid_contacts": _invalid_contacts,
		"spring_points": _spring_points,
		"native_track_contacts": _native_track_contacts,
		"native_passive_contacts": _native_passive_contacts,
		"longitudinal_used": _longitudinal_used,
		"side_budget_used": _side_budget_used,
		"drive_used": _drive_used,
		"brake_used": _brake_used,
		"side_drive_limit": side_drive_force_limit,
		"side_brake_limit": side_brake_force_limit,
		"drive_targets": _drive_targets.duplicate(),
		"driving_feel_enabled": driving_feel_enabled,
		"ready": _ready_for_physics,
		"hull_bottom_local": hull_bottom_local,
		"speed": linear_velocity.dot(-global_transform.basis.x.normalized()),
		"rest": SPRING_REST,
		"margin": QUERY_MARGIN,
		"sphere_radius": _sphere.radius,
		"longitudinal_mu": LONGITUDINAL_MU,
		"lateral_mu": LATERAL_MU,
	}


func _adopt_vehicle_snapshot() -> void:
	if donor_scene == null:
		push_error("ContactTank requires a donor scene.")
		return
	var donor := donor_scene.instantiate() as CharacterBody3D
	if donor == null:
		push_error("ContactTank could not instantiate vehicle donor.")
		return
	var vehicle_mass := float(donor.get("tank_mass_tonnes")) * 1000.0
	var brake_limit := float(donor.get("brake_force_kilonewtons")) * 500.0
	if not is_finite(vehicle_mass) or vehicle_mass <= 0.0 or not is_finite(brake_limit) or brake_limit <= 0.0 \
			or not is_finite(side_drive_force_limit) or side_drive_force_limit <= 0.0:
		push_error("ContactTank refuses invalid mass or longitudinal force limits.")
		donor.free()
		return
	mass = vehicle_mass
	side_brake_force_limit = brake_limit
	_spring_k = mass * GRAVITY / (float(STATION_COUNT) * EQUILIBRIUM_COMPRESSION)
	_damper_c = 0.7 * 2.0 * sqrt(_spring_k * mass / float(STATION_COUNT))
	_station_load_cap = 3.0 * mass * GRAVITY / float(STATION_COUNT)
	donor.process_mode = Node.PROCESS_MODE_DISABLED
	donor.collision_layer = 0
	donor.collision_mask = 0
	_prepare_donor(donor)
	add_child(donor)
	# The donor may run only long enough to initialize its immutable snapshot.
	var snapshot: Dictionary = donor.predictive_driving_snapshot()
	_drive_intent.configure(donor)
	var geometry = donor.get("part_geometry")
	if geometry != null:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = geometry.stable_center
	var shapes: Array = snapshot.get("shapes", [])
	var transforms: Array = snapshot.get("root_local_transforms", [])
	var ranges: Array = snapshot.get("part_ranges", [])
	var vertices: Array = snapshot.get("shape_vertices", [])
	if shapes.is_empty() or shapes.size() != transforms.size():
		push_error("ContactTank refuses an incomplete vehicle collision snapshot.")
		donor.free()
		return
	if not _derive_track_geometry(ranges, transforms, vertices):
		push_error("ContactTank could not derive measured vehicle track geometry.")
		donor.free()
		return
	var half_width := 0.0
	for station in _stations:
		half_width += absf((station.local as Vector3).z - center_of_mass.z) / float(STATION_COUNT)
	if not _tread_visual.configure(donor.tread_animation_player, donor.tread_forward_animation,
			donor.tread_animation_reference_speed, donor.tread_animation_speed_multiplier, half_width):
		push_error("ContactTank could not bind independent tread visuals.")
		donor.free()
		return
	source_shape_count = shapes.size()
	var label := donor_scene.resource_path.get_file().get_basename()
	label = label.substr(0, 1).to_upper() + label.substr(1)
	for index in shapes.size():
		var collision := CollisionShape3D.new()
		# 名稱僅供編輯器辨識；同步依 collision_shapes，不依車型字串查找。
		collision.name = "%sConvex%02d" % [label, index]
		collision.shape = shapes[index] as Shape3D
		collision.transform = transforms[index] as Transform3D
		add_child(collision)
		collision_shapes.append(collision)
		full_shape_count += 1
	_finish_donor(donor)
	_ready_for_physics = _stations.size() == STATION_COUNT and full_shape_count == source_shape_count


## 預設維持獨立測試候選；玩家 adapter 可保留戰鬥子樹而不複製物理核心。
func _prepare_donor(donor: CharacterBody3D) -> void:
	var damage_visuals := _damage_visuals(donor)
	if damage_visuals != null:
		damage_visuals.free()


func _damage_visuals(donor: Node) -> TankDamageVisuals:
	for child in donor.get_children():
		if child is TankDamageVisuals:
			return child
	return null


func _finish_donor(donor: CharacterBody3D) -> void:
	var pivot := donor.get_node_or_null("VisualRecoilPivot") as Node3D
	if pivot != null:
		var pivot_transform := pivot.transform
		donor.remove_child(pivot)
		add_child(pivot)
		pivot.transform = pivot_transform
	# No controller remains alive after the pure visual has moved.
	donor.free()


func _derive_track_geometry(ranges: Array, transforms: Array, vertices: Array) -> bool:
	_prediction_support_points = []
	_prediction_support_key = Vector2(INF, INF)
	_stations.clear()
	_track_shapes.clear()
	_hull_local_vertices.clear()
	var tracks := {"left_track": [], "right_track": []}
	for part_range in ranges:
		var part_id := String(part_range.get("part_id", ""))
		var anchor := String(part_range.get("anchor", ""))
		for offset in int(part_range.get("count", 0)):
			var index := int(part_range.get("start", 0)) + offset
			if index >= transforms.size() or index >= vertices.size(): return false
			if part_id in ["left_track", "right_track"]:
				_track_shapes[index] = "left" if part_id == "left_track" else "right"
			for raw_vertex in vertices[index]:
				var vertex: Vector3 = transforms[index] * (raw_vertex as Vector3)
				if anchor == "hull": _hull_local_vertices.append(vertex)
				if tracks.has(part_id): tracks[part_id].append(vertex)
	if tracks.left_track.is_empty() or tracks.right_track.is_empty(): return false
	var half_width := INF
	for track in tracks.values():
		var min_z := INF; var max_z := -INF
		for vertex in track:
			min_z = minf(min_z, vertex.z); max_z = maxf(max_z, vertex.z)
		half_width = minf(half_width, (max_z - min_z) * 0.5)
	_sphere.radius = minf(SPHERE_RADIUS, half_width)
	for part_id in ["left_track", "right_track"]:
		var track: Array = tracks[part_id]
		var bottom := INF
		for vertex in track: bottom = minf(bottom, vertex.y)
		var flat: Array[Vector3] = []
		for vertex in track:
			if vertex.y <= bottom + 0.0001: flat.append(vertex)
		if flat.is_empty(): return false
		var min_x := INF; var max_x := -INF; var sum_z := 0.0
		for vertex in flat:
			min_x = minf(min_x, vertex.x); max_x = maxf(max_x, vertex.x); sum_z += vertex.z
		var mount_y := bottom + _sphere.radius + SPRING_REST - EQUILIBRIUM_COMPRESSION - EXPECTED_HULL_CLEARANCE
		for i in POINTS_PER_SIDE:
			_stations.append({"side": "left" if part_id == "left_track" else "right", "local": Vector3(lerpf(min_x, max_x, float(i) / float(POINTS_PER_SIDE - 1)), mount_y, sum_z / float(flat.size()))})
	hull_bottom_local = INF
	for vertex in _hull_local_vertices: hull_bottom_local = minf(hull_bottom_local, vertex.y)
	return hull_bottom_local < INF


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_reset_telemetry()
	if not _ready_for_physics:
		return
	var body_up := state.transform.basis.y.normalized()
	var body_forward := -state.transform.basis.x.normalized()
	if driving_feel_enabled:
		_drive_intent.step(_movement_input, _turn_input, state.linear_velocity.dot(body_forward), state.step)
		_drive_targets = _drive_intent.snapshot()
	else:
		_drive_targets = {"left": (_movement_input + _turn_input) * MAX_SPEED, "right": (_movement_input - _turn_input) * MAX_SPEED, "longitudinal": _movement_input * MAX_SPEED, "steering": _turn_input, "phase": "fixed_contact"}
	var world_com := state.transform.origin + state.center_of_mass
	var space := state.get_space_state()
	for station in _stations:
		var report := {"side": station.side, "contact": false, "normal_load": 0.0, "traction": Vector3.ZERO, "position": state.transform * (station.local as Vector3)}
		var contact := _query_station(space, state.transform, body_up, station)
		if contact.is_empty():
			_spring_points.append(report)
			continue
		var normal: Vector3 = contact.normal
		if normal.dot(body_up) <= 0.2 or normal.dot(Vector3.UP) <= 0.2:
			_spring_points.append(report)
			continue
		var position: Vector3 = contact.position
		var offset := position - state.transform.origin
		var point_velocity := state.linear_velocity + state.angular_velocity.cross(position - world_com)
		var compression: float = contact.compression
		var normal_load := clampf(_spring_k * compression - _damper_c * point_velocity.dot(normal), 0.0, _station_load_cap)
		if normal_load <= 0.0:
			_spring_points.append(report)
			continue
		var support := normal * normal_load
		_apply_contact_force(support, offset)
		_total_support_force += normal_load
		if station.side == "left": _left_contacts += 1
		else: _right_contacts += 1
		_spring_points.append({"side": station.side, "contact": true, "normal_load": normal_load, "traction": Vector3.ZERO, "position": position, "normal": normal})
	if driving_feel_enabled:
		_map_drive_targets(state)
	_apply_native_track_drive(state, body_forward)
	for report in _spring_points:
		if report.contact:
			report.traction = _apply_surface_forces(state, world_com, body_forward, report.position, report.normal, report.normal_load, report)


func _map_drive_targets(state: PhysicsDirectBodyState3D) -> void:
	# Differential speed must also overcome the existing lateral scrub forces.
	# Derive the lever from the same ten physical stations, not a tuned tank width.
	var half_width := 0.0
	var longitudinal_moment := 0.0
	for station in _stations:
		var offset: Vector3 = station.local - center_of_mass
		half_width += absf(offset.z) / float(STATION_COUNT)
		longitudinal_moment += offset.x * offset.x / float(STATION_COUNT)
	var lever := half_width + LATERAL_RATE / VELOCITY_RATE * longitudinal_moment / half_width
	var grounded := _total_support_force > 0.0 or state.get_contact_count() > 0
	var linear_feed := _drive_intent.linear_acceleration / VELOCITY_RATE if grounded else 0.0
	var inertia := 1.0 / maxf(state.inverse_inertia.y, 0.000000001)
	var angular_feed := _drive_intent.angular_acceleration * inertia / (mass * VELOCITY_RATE * half_width) if grounded else 0.0
	var differential := _drive_intent.steering * lever + angular_feed
	_drive_targets.left = _drive_intent.longitudinal + linear_feed + differential
	_drive_targets.right = _drive_intent.longitudinal + linear_feed - differential
	_drive_targets.linear_feed = linear_feed
	_drive_targets.angular_feed = angular_feed
	# Targets enter the existing velocity feedback BEFORE friction ellipse and side cap.

func _apply_native_track_drive(state: PhysicsDirectBodyState3D, forward: Vector3) -> void:
	var loads := {"left": 0.0, "right": 0.0}
	if state.step <= 0.0: return
	for index in state.get_contact_count():
		var shape := state.get_contact_local_shape(index)
		# Godot direct-state contact positions/normals are world-space despite "local".
		var normal := state.get_contact_local_normal(index)
		var position := state.get_contact_local_position(index)
		var impulse := state.get_contact_impulse(index)
		if not normal.is_finite() or not position.is_finite() or not impulse.is_finite(): continue
		if normal.length_squared() < 0.0001: continue
		normal = normal.normalized()
		var tangent := forward - normal * forward.dot(normal)
		var load := clampf(impulse.dot(normal) / state.step, 0.0, _station_load_cap)
		if load <= 0.0: continue
		var relative_velocity := state.get_contact_local_velocity_at_position(index) - state.get_contact_collider_velocity_at_position(index)
		if not relative_velocity.is_finite(): continue
		if not _track_shapes.has(shape) or normal.dot(Vector3.UP) <= 0.2 or tangent.length_squared() < 0.0001:
			var sliding := relative_velocity - normal * relative_velocity.dot(normal)
			var friction := (-sliding * mass / float(maxi(state.get_contact_count(), 1)) * LATERAL_RATE).limit_length(PASSIVE_MU * load)
			_native_passive_contacts.append({"shape": shape, "load": load, "normal": normal, "position": position, "velocity": relative_velocity, "friction": friction})
			_apply_contact_force(friction, position - state.transform.origin)
			continue
		var side: String = _track_shapes[shape]
		_native_track_contacts.append({"shape": shape, "side": side, "load": load, "normal": normal, "position": position, "tangent": tangent.normalized(), "velocity": relative_velocity, "traction": Vector3.ZERO})
		loads[side] += load
	for contact in _native_track_contacts:
		var side: String = contact.side
		var weight: float = contact.load / loads[side]
		var target: float = _drive_targets[side]
		var speed: float = (contact.velocity as Vector3).dot(contact.tangent)
		var force := (target - speed) * mass * 0.5 * VELOCITY_RATE * weight
		var braking := _is_braking(force, speed)
		var limit := minf(contact.load * LONGITUDINAL_MU, _available_longitudinal_force(side, braking, weight))
		force = clampf(force, -limit, limit)
		var tangent_side := (contact.normal as Vector3).cross(contact.tangent).normalized()
		var lateral: float = -(contact.velocity as Vector3).dot(tangent_side) * mass * 0.5 * LATERAL_RATE * weight
		lateral = clampf(lateral, -contact.load * LATERAL_MU, contact.load * LATERAL_MU)
		var ellipse := sqrt(pow(force / (contact.load * LONGITUDINAL_MU), 2.0) + pow(lateral / (contact.load * LATERAL_MU), 2.0))
		if ellipse > 1.0:
			force /= ellipse
			lateral /= ellipse
		contact.traction = (contact.tangent as Vector3) * force + tangent_side * lateral
		_record_longitudinal_force(side, force, braking)
		_apply_contact_force(contact.traction, (contact.position as Vector3) - state.transform.origin)
		_drive_force += (contact.tangent as Vector3) * force


func _apply_contact_force(force: Vector3, offset: Vector3) -> void:
	apply_force(force, offset)
	_applied_force += force


func _side_motor_limit() -> float:
	return side_drive_force_limit


func _is_braking(force: float, speed: float) -> bool:
	return absf(speed) > 0.01 and force * speed < 0.0


func _available_longitudinal_force(side: String, braking: bool, weight := 1.0) -> float:
	var limit := side_brake_force_limit if braking else side_drive_force_limit
	# 相同上限維持原absolute-budget運算順序，避免Tank2浮點路徑漂移。
	if side_drive_force_limit == side_brake_force_limit:
		return minf(limit * weight, maxf(0.0, limit - float(_longitudinal_used[side])))
	return limit * minf(weight, maxf(0.0, 1.0 - float(_side_budget_used[side])))


func _record_longitudinal_force(side: String, force: float, braking: bool) -> void:
	var amount := absf(force)
	_longitudinal_used[side] += amount
	_side_budget_used[side] += amount / (side_brake_force_limit if braking else side_drive_force_limit)
	if braking:
		_brake_used[side] += amount
	else:
		_drive_used[side] += amount


func _query_station(space: PhysicsDirectSpaceState3D, body: Transform3D, body_up: Vector3, station: Dictionary) -> Dictionary:
	var start := body * (station.local as Vector3)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = -body_up * SPRING_REST
	query.margin = QUERY_MARGIN
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	# cast_motion deliberately ignores initial overlap, so reject it separately.
	if not space.intersect_shape(query, 1).is_empty():
		_invalid_contacts += 1
		return {}
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or float(fractions[1]) >= 1.0:
		return {}
	var unsafe_fraction := float(fractions[1])
	query.transform.origin = start + query.motion * minf(unsafe_fraction + 0.0001, 1.0)
	var rest := space.get_rest_info(query)
	if rest.is_empty() or not rest.has("point") or not rest.has("normal"):
		return {}
	return {"position": rest.point as Vector3, "normal": (rest.normal as Vector3).normalized(), "compression": SPRING_REST * (1.0 - float(fractions[0]))}


func _apply_surface_forces(state: PhysicsDirectBodyState3D, world_com: Vector3, forward: Vector3, position: Vector3, normal: Vector3, load: float, station: Dictionary) -> Vector3:
	var tangent_forward := (forward - normal * forward.dot(normal)).normalized()
	if tangent_forward.length_squared() < 0.0001:
		return Vector3.ZERO
	var tangent_side := normal.cross(tangent_forward).normalized()
	var point_velocity := state.linear_velocity + state.angular_velocity.cross(position - world_com)
	var target: float = _drive_targets[station.side]
	var speed := point_velocity.dot(tangent_forward)
	var desired_long := clampf((target - speed) * mass / float(STATION_COUNT) * VELOCITY_RATE, -load * LONGITUDINAL_MU, load * LONGITUDINAL_MU)
	var braking := _is_braking(desired_long, speed)
	var remaining := _available_longitudinal_force(station.side, braking)
	desired_long = clampf(desired_long, -remaining, remaining)
	var desired_side := clampf(-point_velocity.dot(tangent_side) * mass / float(STATION_COUNT) * LATERAL_RATE, -load * LATERAL_MU, load * LATERAL_MU)
	var ellipse := sqrt(pow(desired_long / maxf(load * LONGITUDINAL_MU, 0.001), 2.0) + pow(desired_side / maxf(load * LATERAL_MU, 0.001), 2.0))
	if ellipse > 1.0:
		desired_long /= ellipse
		desired_side /= ellipse
	_record_longitudinal_force(station.side, desired_long, braking)
	var traction := tangent_forward * desired_long + tangent_side * desired_side
	_apply_contact_force(traction, position - state.transform.origin)
	_drive_force += tangent_forward * desired_long
	return traction


func _reset_telemetry() -> void:
	_left_contacts = 0; _right_contacts = 0; _total_support_force = 0.0
	_drive_force = Vector3.ZERO; _applied_force = Vector3.ZERO; _invalid_contacts = 0
	_spring_points.clear()
	_native_track_contacts.clear()
	_native_passive_contacts.clear()
	_longitudinal_used = {"left": 0.0, "right": 0.0}
	_side_budget_used = {"left": 0.0, "right": 0.0}
	_drive_used = {"left": 0.0, "right": 0.0}
	_brake_used = {"left": 0.0, "right": 0.0}
