## LEA-176：四款真剛體在雙向最高穩態速度下，驗證首次近端 predictor 介入後的煞停契約。
## 只使用 actor command surface；首次介入只執行一 tick，後續正常零輸入煞停。
extends SceneTree

const Catalog := preload("res://src/actors/tank/tank_catalog.gd")
const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const DT := 1.0 / 60.0
const SETTLE_TICKS := 180
const TOP_TIMEOUT_TICKS := 900
const APPROACH_TIMEOUT_TICKS := 3600
const BRAKE_TIMEOUT_TICKS := 900
const PLATEAU_TICKS := 60
const STOP_SPEED := 0.10
const STOP_YAW_RATE := 0.02
const WALL_THICKNESS := 0.5
const WALL_WIDTH := 200.0
const WALL_HEIGHT := 6.0

const MATRIX: Array[Dictionary] = [
	{"vehicle": &"tank1", "sign": 1.0, "target": 7.48},
	{"vehicle": &"tank1", "sign": -1.0, "target": 3.74},
	{"vehicle": &"tank2", "sign": 1.0, "target": 5.725191058213},
	{"vehicle": &"tank2", "sign": -1.0, "target": 2.862595529107},
	{"vehicle": &"tank3", "sign": 1.0, "target": 4.32},
	{"vehicle": &"tank3", "sign": -1.0, "target": 2.16},
	{"vehicle": &"tank4", "sign": 1.0, "target": 6.2},
	{"vehicle": &"tank4", "sign": -1.0, "target": 3.1},
]

var _world: Node3D
var _failures: Array[String] = []
var _results: Array[Dictionary] = []

func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")

func _run() -> void:
	print("HIGH_SPEED_E2E begin ticks=", Engine.physics_ticks_per_second, " matrix=", MATRIX.size(), " paused=", paused, " time_scale=", Engine.time_scale)
	for item in MATRIX:
		_results.append(await _run_case(item))
	for result in _results:
		print("HIGH_SPEED_E2E RESULT ", result)
	if not _failures.is_empty():
		push_error("HIGH_SPEED_E2E first_failure: %s" % _failures[0])
	print("HIGH_SPEED_E2E failures=", _failures.size(), " results=", _results.size())
	await _cleanup()
	quit(0 if _failures.is_empty() else 1)

func _run_case(item: Dictionary) -> Dictionary:
	await _cleanup()
	_world = Node3D.new()
	root.add_child(_world)
	var vehicle := item.vehicle as StringName
	var sign := float(item.sign)
	var target := float(item.target)
	var direction := Vector3.LEFT * sign
	var wall_distance := target * 25.0
	_floor(wall_distance)
	var wall := _wall(direction * wall_distance)
	var tank := Catalog.instantiate(vehicle) as RigidBody3D
	if tank == null:
		return _fail_case(vehicle, sign, "catalog instantiate failed")
	tank.position = Vector3(0, 2, 0)
	_world.add_child(tank)
	await _frames(SETTLE_TICKS)
	print("HIGH_SPEED_E2E CASE start vehicle=", vehicle, " sign=", sign, " target=", target, " wall=", wall_distance, " paused=", paused, " y=", tank.global_position.y)
	var plateau := 0
	var peak := 0.0
	var plateau_low := INF
	var plateau_high := -INF
	for tick in TOP_TIMEOUT_TICKS:
		tank.call(&"set_movement_input", sign)
		tank.call(&"set_turn_input", 0.0)
		await physics_frame
		var speed := absf(float(tank.call(&"get_actual_linear_speed")))
		peak = maxf(peak, speed)
		if speed >= target * 0.95 and speed <= target * 1.05:
			plateau += 1
			plateau_low = minf(plateau_low, speed)
			plateau_high = maxf(plateau_high, speed)
			if plateau >= PLATEAU_TICKS: break
		else:
			plateau = 0
			plateau_low = INF
			plateau_high = -INF
		if (tick + 1) % 300 == 0:
			print("HIGH_SPEED_E2E PROGRESS vehicle=", vehicle, " sign=", sign, " phase=top tick=", tick + 1, " speed=", speed, " plateau=", plateau, " paused=", paused)
	if plateau < PLATEAU_TICKS:
		return _fail_case(vehicle, sign, "top plateau absent target=%.6f peak=%.6f plateau=%d/%d wall=%.3f" % [target, peak, plateau, PLATEAU_TICKS, wall_distance])
	var predictor := Predictor.new()
	predictor.setup(tank)
	var goal := direction * (wall_distance + 50.0)
	var intervened := false
	var initial_choice: Dictionary = {}
	var intervention_choice: Dictionary = {}
	var first_actual_speed := -1.0
	var first_gap := INF
	var min_gap := INF
	var first_overlap := ""
	var wall_contacts := 0
	var settled := 0
	var stopped := false
	for tick in APPROACH_TIMEOUT_TICKS:
		var choice: Dictionary = predictor.choose(sign, 0.0, goal, DT, false, true)
		if initial_choice.is_empty(): initial_choice = choice.duplicate(true)
		var movement := float(choice.get("movement", sign))
		var turn := float(choice.get("turn", 0.0))
		var stats: Dictionary = choice.get("stats", {}) as Dictionary
		var changed := not is_equal_approx(movement, sign) or absf(turn) >= 0.05
		if changed and not bool(stats.get("near_verified", false)):
			return _fail_case(vehicle, sign, "predictor changed before near verification target=%.6f choice=%s" % [target, choice])
		if changed and bool(stats.get("near_verified", false)):
			intervened = true
			intervention_choice = choice.duplicate(true)
			first_actual_speed = absf(float(tank.call(&"get_actual_linear_speed")))
			var before: Dictionary = tank.call(&"predictive_driving_snapshot")
			first_gap = _full_shape_front_gap(before, direction, wall_distance)
		tank.call(&"set_movement_input", movement)
		tank.call(&"set_turn_input", turn)
		await physics_frame
		var snapshot: Dictionary = tank.call(&"predictive_driving_snapshot")
		min_gap = minf(min_gap, _full_shape_front_gap(snapshot, direction, wall_distance))
		var overlap := _wall_overlap(tank, snapshot, wall.get_rid())
		if not overlap.is_empty() and first_overlap.is_empty(): first_overlap = overlap
		for contact in tank.call(&"get_recovery_contacts") as Array:
			if contact is Dictionary and contact.get("rid", RID()) == wall.get_rid(): wall_contacts += 1
		if intervened: break
		if (tick + 1) % 300 == 0:
			print("HIGH_SPEED_E2E PROGRESS vehicle=", vehicle, " sign=", sign, " phase=approach tick=", tick + 1, " gap=", min_gap, " paused=", paused)
	if intervened:
		for tick in BRAKE_TIMEOUT_TICKS:
			tank.call(&"set_movement_input", 0.0)
			tank.call(&"set_turn_input", 0.0)
			await physics_frame
			var snapshot: Dictionary = tank.call(&"predictive_driving_snapshot")
			min_gap = minf(min_gap, _full_shape_front_gap(snapshot, direction, wall_distance))
			var overlap := _wall_overlap(tank, snapshot, wall.get_rid())
			if not overlap.is_empty() and first_overlap.is_empty(): first_overlap = overlap
			for contact in tank.call(&"get_recovery_contacts") as Array:
				if contact is Dictionary and contact.get("rid", RID()) == wall.get_rid(): wall_contacts += 1
			var horizontal := Vector2(tank.linear_velocity.x, tank.linear_velocity.z).length()
			if horizontal <= STOP_SPEED and absf(tank.angular_velocity.y) <= STOP_YAW_RATE and first_overlap.is_empty():
				settled += 1
				if settled >= PLATEAU_TICKS:
					stopped = true
					break
			else:
				settled = 0
	var near_limit := maxf(6.0, target * 2.0)
	## 介入前同一 physics frame 的真實縱向速度必須仍是該方向 nominal 的 95–105%。
	var high_speed_intervention := first_actual_speed >= target * 0.95 and first_actual_speed <= target * 1.05
	## first_gap 是介入時機診斷；停止後完整車身的最小間隙才套用既定 near_limit。
	var passed := intervened and high_speed_intervention and min_gap <= near_limit and first_overlap.is_empty() and wall_contacts == 0 and stopped
	var detail := "target=%.6f peak=%.6f plateau=[%.6f,%.6f] wall=%.3f first_speed=%.6f first_gap=%.6f min_gap=%.6f near_limit=%.6f intervened=%s high_speed=%s stopped=%s contacts=%d initial=%s intervention=%s overlap=%s" % [target, peak, plateau_low, plateau_high, wall_distance, first_actual_speed, first_gap, min_gap, near_limit, intervened, high_speed_intervention, stopped, wall_contacts, initial_choice, intervention_choice, first_overlap]
	if not passed:
		_failures.append("%s sign=%+.0f %s" % [vehicle, sign, detail])
	return {"vehicle": vehicle, "sign": sign, "pass": passed, "detail": detail}

func _fail_case(vehicle: StringName, sign: float, detail: String) -> Dictionary:
	_failures.append("%s sign=%+.0f %s" % [vehicle, sign, detail])
	return {"vehicle": vehicle, "sign": sign, "pass": false, "detail": detail}

func _floor(wall_distance: float) -> void:
	_box(Vector3(maxf(500.0, wall_distance * 2.0 + 50.0), 0.2, WALL_WIDTH + 40.0), Vector3(0, -0.1, 0), "floor")

func _wall(center: Vector3) -> StaticBody3D:
	return _box(Vector3(WALL_THICKNESS, WALL_HEIGHT, WALL_WIDTH), Vector3(center.x, WALL_HEIGHT * 0.5, 0), "wall")

func _box(size: Vector3, center: Vector3, name_value: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_value
	body.collision_layer = 128
	body.position = center
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_world.add_child(body)
	return body

func _wall_overlap(tank: RigidBody3D, snapshot: Dictionary, wall_rid: RID) -> String:
	var shapes: Array = snapshot.get("shapes", [])
	var transforms: Array = snapshot.get("transforms", [])
	if shapes.size() != transforms.size(): return "snapshot shape/transform mismatch %d/%d" % [shapes.size(), transforms.size()]
	var state := tank.get_world_3d().direct_space_state
	for index in shapes.size():
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shapes[index] as Shape3D
		query.transform = transforms[index] as Transform3D
		query.collision_mask = 128
		query.exclude = [tank.get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		for hit in state.intersect_shape(query, 32):
			if hit.get("rid", RID()) == wall_rid: return "shape=%d rid=%s" % [index, wall_rid]
	return ""

func _full_shape_front_gap(snapshot: Dictionary, direction: Vector3, wall_distance: float) -> float:
	var shapes: Array = snapshot.get("shapes", [])
	var transforms: Array = snapshot.get("transforms", [])
	var leading := -INF
	for index in mini(shapes.size(), transforms.size()):
		for vertex in _vertices(shapes[index] as Shape3D):
			leading = maxf(leading, direction.dot((transforms[index] as Transform3D) * vertex))
	return wall_distance - WALL_THICKNESS * 0.5 - leading

func _vertices(shape: Shape3D) -> PackedVector3Array:
	var data: Variant = PhysicsServer3D.shape_get_data(shape.get_rid())
	if data is PackedVector3Array: return data as PackedVector3Array
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5
		return PackedVector3Array([Vector3(-half.x,-half.y,-half.z), Vector3(-half.x,-half.y,half.z), Vector3(-half.x,half.y,-half.z), Vector3(-half.x,half.y,half.z), Vector3(half.x,-half.y,-half.z), Vector3(half.x,-half.y,half.z), Vector3(half.x,half.y,-half.z), Vector3(half.x,half.y,half.z)])
	return PackedVector3Array()

func _frames(count: int) -> void:
	for unused in count: await physics_frame

func _cleanup() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		await _frames(2)
	_world = null
