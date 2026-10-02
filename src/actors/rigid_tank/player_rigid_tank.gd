## 敵我共用載具；歷史檔名保留以相容既有測試，操控者只提交指令。
extends "res://src/actors/rigid_tank/contact_tank.gd"

const ShotEvent := preload("res://src/combat/shot_event.gd")
signal shot_event_fired(event: ShotEvent)

const Catalog := preload("res://src/actors/tank/tank_catalog.gd")
const RigidPrediction := preload("res://src/actors/rigid_tank/rigid_tank_prediction.gd")
@export_enum("tank1", "tank2", "tank3", "tank4") var vehicle_id := "tank2"
var _body_contacts: Array[Dictionary] = []
var _prediction_inertia := 1.0

var forward_speed: float:
	get: return get_actual_linear_speed()
var actual_angular_speed: float:
	get: return get_actual_angular_speed()
var movement_speed: float:
	get: return _drive_intent.forward_speed
var reverse_movement_speed: float:
	get: return _drive_intent.reverse_speed
var turning_movement_speed_ratio: float:
	get: return _drive_intent.turning_ratio
var tank_mass_tonnes: float:
	get: return mass / 1000.0
var brake_force_kilonewtons: float:
	get: return side_brake_force_limit * 2.0 / 1000.0
var ai_stop_distance: float:
	get: return combat_tank.ai_stop_distance if is_instance_valid(combat_tank) else 0.0
var ai_resume_distance: float:
	get: return combat_tank.ai_resume_distance if is_instance_valid(combat_tank) else 0.0
var vision_near_radius: float:
	get: return combat_tank.vision_near_radius if is_instance_valid(combat_tank) else 0.0
	set(value):
		if is_instance_valid(combat_tank): combat_tank.vision_near_radius = value
var vision_far_radius: float:
	get: return combat_tank.vision_far_radius if is_instance_valid(combat_tank) else 0.0
	set(value):
		if is_instance_valid(combat_tank): combat_tank.vision_far_radius = value
var vision_field_of_view_degrees: float:
	get: return combat_tank.vision_field_of_view_degrees if is_instance_valid(combat_tank) else 0.0
	set(value):
		if is_instance_valid(combat_tank): combat_tank.vision_field_of_view_degrees = value
var ground_max_slope_degrees := 35.0
var ground_step_height := 0.5
var ground_snap_distance := 0.3
var ground_alignment_rate := 8.0
var ground_gravity := GRAVITY

@export_range(0.0, 60000.0, 100.0) var recoil_impulse := 12000.0
var combat_tank: CharacterBody3D
var turret_pivot: Node3D
var _dead := false
var _pending_shots: Array[ShotEvent] = []
var recoil_application_count := 0
var _has_aim_target := false
var _aim_target := Vector3.ZERO


func _ready() -> void:
	var definition: Dictionary = Catalog.definition(StringName(vehicle_id))
	if definition.is_empty(): return
	donor_scene = load(definition.donor_path) as PackedScene
	side_drive_force_limit = definition.side_drive_force_limit
	recoil_impulse = definition.recoil_impulse
	if not is_finite(recoil_impulse) or recoil_impulse < 0.0:
		push_error("PlayerRigidTank refuses an invalid recoil impulse.")
		return
	super._ready()


func _prepare_donor(donor: CharacterBody3D) -> void:
	# 初始化 snapshot 期間不處理；完成接線後才啟用戰鬥 tick。
	donor.name = "CombatTank"


func _finish_donor(donor: CharacterBody3D) -> void:
	combat_tank = donor
	donor.configure_external_physics(self)
	var health := donor.get_node("HealthComponent")
	health.reparent(self, false)
	get_node("DamageReceiver").health_component = health
	donor.get_node("DamageReceiver").free()
	_damage_visuals(donor).health_source = health
	health.depleted.connect(_on_depleted)
	health.health_changed.connect(_on_health_changed)
	turret_pivot = donor.turret_pivot
	donor.shot_event_fired.connect(_on_shot)
	donor.process_mode = Node.PROCESS_MODE_INHERIT
	donor.get_node("TrackContactEffects").set_physics_process(false)
	# 根層 reporter 保持唯一來源，但四點位置必須沿用該車型的手調配置。
	var source_points = donor.get_node("TrackContactEffects").contact_points
	var target_points = get_node("TrackContactEffects").contact_points
	for index in target_points.size():
		target_points[index].global_transform = source_points[index].global_transform
	driving_feel_enabled = true


func _process(delta: float) -> void:
	if not _dead:
		super._process(delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	# 唯讀遥測放在既有施力之後，不改動玩家的力或其順序。
	_prediction_inertia = 1.0 / maxf(state.inverse_inertia.y, 0.000000001)
	_body_contacts.clear()
	for index in state.get_contact_count():
		var normal := state.get_contact_local_normal(index)
		var point := state.get_contact_local_position(index)
		if not normal.is_finite() or not point.is_finite(): continue
		var shape_index := state.get_contact_local_shape(index)
		var shape_owner := shape_find_owner(shape_index)
		var shape_node := shape_owner_get_owner(shape_owner)
		_body_contacts.append({"rid": state.get_contact_collider(index), "normal": normal,
			"position": point, "shape_index": shape_index,
			"shape_node": shape_node.name if shape_node != null else &"",
			"support": normal.dot(Vector3.UP) >= cos(deg_to_rad(ground_max_slope_degrees)),
			"source": &"body_state"})
	for shot in _pending_shots:
		# basis.x 是砲口 -X 射向的反向。位置參數為相對 body 原點的世界軸偏移。
		var impulse := shot.muzzle_transform.basis.x.normalized() * recoil_impulse
		state.apply_impulse(impulse, shot.muzzle_transform.origin - state.transform.origin)
		recoil_application_count += 1
	_pending_shots.clear()


func set_movement_input(value: float) -> void:
	super.set_movement_input(0.0 if _dead else value)
	if not _dead and not is_zero_approx(value): sleeping = false


func set_turn_input(value: float) -> void:
	# 主玩家命令正值為 A/左轉；物理核心命令正值為 D/右轉。
	super.set_turn_input(0.0 if _dead else -value)
	if not _dead and not is_zero_approx(value): sleeping = false


func aim_turret_at(target: Vector3, delta: float) -> void:
	if _dead: return
	_has_aim_target = true
	_aim_target = target
	combat_tank.aim_turret_at(target, delta)
	_sync_rigid_parts()


func aim_gun_pitch_at_target(target: Vector3, delta: float) -> void:
	if _dead: return
	combat_tank.aim_gun_pitch_at_target(target, delta)
	_sync_rigid_parts()


func _sync_rigid_parts() -> void:
	var transforms: Array = combat_tank.part_shape_world_transforms()
	if transforms.size() != full_shape_count:
		push_error("PlayerRigidTank collision mapping changed unexpectedly.")
		return
	var root_inverse := global_transform.affine_inverse()
	for index in transforms.size():
		var shape := collision_shapes[index]
		var next_transform: Transform3D = root_inverse * transforms[index]
		if not shape.transform.is_equal_approx(next_transform):
			shape.transform = next_transform


func request_fire() -> void:
	if not _dead: combat_tank.request_fire()


func _on_shot(event: ShotEvent) -> void:
	if _dead: return
	# donor 的外部物理 context 已將 shooter_rid 指向本體；不轉發舊 RID。
	if event.shooter_rid != get_rid():
		push_error("PlayerRigidTank rejected a shot with the wrong shooter RID.")
		return
	_pending_shots.append(event)
	sleeping = false
	shot_event_fired.emit(event)


func _on_depleted() -> void:
	_dead = true
	# 已發出的砲彈仍須完成其後座；死亡只阻止之後的輸入與射擊。
	set_movement_input(0.0)
	set_turn_input(0.0)
	_drive_intent.longitudinal = 0.0
	_drive_intent.steering = 0.0
	cancel_aim()
	# damage visuals 的 signal 隨後套用砲管垂下姿態，再同步碰撞。
	call_deferred("_sync_rigid_parts")


func _on_health_changed(current: float, _maximum: float) -> void:
	# 訓練展示靶沿用回滿機制；正常玩家/敵車仍由協調器重生。
	if current > 0.0 and freeze:
		_dead = false


func cancel_aim() -> void:
	_has_aim_target = false
	combat_tank.cancel_aim()


func stop_hull_aim_turn() -> void:
	combat_tank.stop_hull_aim_turn()
	set_turn_input(0.0)


func get_hull_aim_turn_input() -> float:
	if _dead or not _has_aim_target or not combat_tank.hull_aim_assist_enabled:
		return 0.0
	if combat_tank._is_target_inside_turret_dead_zone(_aim_target):
		return 0.0
	# 車身以真正砲口的水平射向對準；不能用砲塔原點的局部角差代替。
	var forward := muzzle_global_direction()
	var desired := _aim_target - muzzle_global_position()
	forward.y = 0.0
	desired.y = 0.0
	if forward.length_squared() < 0.000001 or desired.length_squared() < 0.000001:
		return 0.0
	var error := forward.normalized().signed_angle_to(desired.normalized(), Vector3.UP)
	# 留半個容差作物理停車餘裕，接近目標漸減意圖而非反覆全力轉向。
	var tolerance := deg_to_rad(combat_tank.hull_aim_alignment_tolerance_degrees)
	if absf(error) <= tolerance * 0.5:
		return 0.0
	return clampf(error / deg_to_rad(5.0), -1.0, 1.0)


func set_manual_turn_active(active: bool) -> void:
	combat_tank.set_manual_turn_active(active and not _dead)


func muzzle_global_position() -> Vector3:
	return combat_tank.muzzle_global_position()


func muzzle_global_direction() -> Vector3:
	return combat_tank.muzzle_global_direction()


func get_current_spread_degrees() -> float:
	return combat_tank.get_current_spread_degrees()


func get_max_camera_look_ahead_distance() -> float:
	return combat_tank.get_max_camera_look_ahead_distance()


func get_actual_linear_speed() -> float:
	return linear_velocity.dot(-global_basis.x.normalized())


func get_actual_angular_speed() -> float:
	return angular_velocity.dot(global_basis.y.normalized())


func part_world_bounds() -> AABB:
	return combat_tank.part_world_bounds()


func stable_world_center() -> Vector3:
	return combat_tank.stable_world_center()


func part_world_surface_points() -> PackedVector3Array:
	return combat_tank.part_world_surface_points()


func get_turret_pivot() -> Node3D:
	return turret_pivot


func get_recovery_contacts() -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	for contact in _body_contacts:
		if not bool(contact.support): contacts.append(contact.duplicate())
	return contacts


func predictive_driving_snapshot() -> Dictionary:
	if not is_instance_valid(combat_tank): return {}
	var snapshot: Dictionary = combat_tank.predictive_driving_snapshot()
	snapshot.root = global_transform
	snapshot.forward_speed = forward_speed
	snapshot.angular_speed = actual_angular_speed
	snapshot.vertical_speed = linear_velocity.y
	snapshot["linear_velocity"] = linear_velocity
	snapshot.ground_points = RigidPrediction.support_points(self)
	snapshot.self_rid = get_rid()
	snapshot.collision_mask = collision_mask
	snapshot.contacts = get_recovery_contacts()
	snapshot.grounded = _left_contacts + _right_contacts > 0
	snapshot["approximate_rigid"] = true
	return snapshot


func predictive_driving_step(speed: float, angular: float, movement: float, turn: float, delta: float) -> Dictionary:
	return RigidPrediction.step(self, speed, angular, movement, turn, delta)


func ground_support_at(pose: Transform3D, height: float = 0.0) -> Dictionary:
	return RigidPrediction.support(self, pose, height)


func create_ground_motion_query(snapshot: Dictionary) -> RefCounted:
	var query := preload("res://src/actors/rigid_tank/rigid_ground_prediction.gd").new()
	query.setup(self, snapshot)
	return query


func set_driving_trace_enabled(enabled: bool) -> void:
	combat_tank.set_driving_trace_enabled(enabled)


func is_driving_trace_enabled() -> bool:
	return combat_tank.is_driving_trace_enabled()


func get_driving_trace_descriptor() -> Dictionary:
	var descriptor: Dictionary = combat_tank.get_driving_trace_descriptor()
	descriptor["vehicle_id"] = vehicle_id
	descriptor["body_type"] = "RigidBody3D"
	return descriptor


func get_driving_trace_frame() -> Dictionary:
	var frame: Dictionary = combat_tank.get_driving_trace_frame()
	frame["rigid_linear_velocity"] = linear_velocity
	frame["rigid_angular_velocity"] = angular_velocity
	frame["rigid_contacts"] = _body_contacts.duplicate(true)
	return frame


func get_driving_trace_state() -> Dictionary:
	return {"vehicle_id": vehicle_id, "forward_speed": forward_speed,
		"angular_speed": actual_angular_speed, "telemetry": telemetry()}
