## LEA-xxx：角落接觸的有限側轉脫困；unit 狀態機與一台真 Tank1 的接觸快照皆覆蓋。
extends SceneTree

const Recovery := preload("res://src/ai/tank_recovery.gd")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const DT := 1.0 / 60.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_mirrored_contact_turns_and_snapshot_lifetime()
	_validate_observation_window_contact_cache()
	_validate_turn_timeout_and_lifecycle_cancellation()
	await _validate_real_corner_contact_escape()
	if _failures.is_empty():
		print("ENEMY_CORNER_RECOVERY PASS: mirrored contacts, retained side choice, bounded turn, lifecycle, real Tank1 corner.")
		quit(0)
		return
	for failure in _failures:
		push_error("ENEMY_CORNER_RECOVERY FAIL: %s" % failure)
	quit(1)


func _validate_mirrored_contact_turns_and_snapshot_lifetime() -> void:
	var forward := Vector3.LEFT
	var left_contact: Array[Dictionary] = [{"position": Vector3(0.0, 0.0, 1.0), "normal": Vector3.RIGHT}]
	var right_contact: Array[Dictionary] = [{"position": Vector3(0.0, 0.0, -1.0), "normal": Vector3.RIGHT}]
	var left := _start_corner_recovery(forward, left_contact)
	var right := _start_corner_recovery(forward, right_contact)
	var left_escape := left.get("_escape_forward") as Vector3
	var right_escape := right.get("_escape_forward") as Vector3
	if left_escape.is_zero_approx() or right_escape.is_zero_approx() or left_escape.z * right_escape.z >= 0.0:
		_fail("Mirrored corner contact positions must select opposite escape sides; left=%s right=%s." % [left_escape, right_escape])
		return
	var left_turn: float = _reach_turning(left, forward)
	var right_turn: float = _reach_turning(right, forward)
	if left_turn == 0.0 or right_turn == 0.0 or left_turn * right_turn >= 0.0:
		_fail("Mirrored corner contacts must command opposite non-zero turns away from their wall side; left=%.3f right=%.3f." % [left_turn, right_turn])
	## Contact data is intentionally absent after reversing; the first snapshot must remain authoritative.
	if left.get("_escape_forward") != left_escape or right.get("_escape_forward") != right_escape:
		_fail("A contact snapshot selected at stall entry must survive reverse even after contacts disappear.")
	## Replan belongs only after the side advance and its final settle, never while turning or advancing.
	if left.get("phase") != &"turning" or left.drive(Vector3.ZERO, forward, 0.0, 2.0, 1.0, DT).get("replan", false):
		_fail("Turning must not issue replan before side advance completes.")


func _validate_turn_timeout_and_lifecycle_cancellation() -> void:
	var recovery := _start_corner_recovery(Vector3.LEFT, [{"position": Vector3(0.0, 0.0, 1.0), "normal": Vector3.RIGHT}])
	_reach_turning(recovery, Vector3.LEFT)
	var saw_forward := false
	var saw_timeout_settling := false
	for unused in 190: ## > 3 seconds while an external blocker prevents any actual yaw.
		var command: Dictionary = recovery.drive(Vector3.ZERO, Vector3.LEFT, 0.0, 2.0, 1.0, DT, 7.0, 0.0)
		saw_forward = saw_forward or float(command.get("movement", 0.0)) > 0.05
		saw_timeout_settling = saw_timeout_settling or recovery.phase == &"escape_settling"
	if not saw_timeout_settling or saw_forward:
		_fail("A blocked turn must time out into settling without hard-pushing forward; settled=%s phase=%s forward=%s." % [saw_timeout_settling, recovery.phase, saw_forward])
	## Both in-flight side phases must be cancelled by goal/lifecycle reset, including the retained escape direction.
	for cancelled_phase in [&"turning", &"advancing"]:
		recovery.set("phase", cancelled_phase)
		recovery.set("_escape_forward", Vector3.FORWARD)
		recovery.reset(Vector3(3.0, 0.0, 0.0), Vector3.LEFT)
		if recovery.phase != &"normal" or recovery.attempts != 0 or not (recovery.get("_escape_forward") as Vector3).is_zero_approx():
			_fail("Reset must cancel %s and clear its side direction." % cancelled_phase)


func _validate_observation_window_contact_cache() -> void:
	var contact: Array[Dictionary] = [{"position": Vector3(0.0, 0.0, 1.0), "normal": Vector3.RIGHT}]
	var cached := Recovery.new()
	cached.reset(Vector3.ZERO, Vector3.LEFT)
	## A real collision can be reported only at the beginning of the three-second no-progress window.
	cached.observe(Vector3.ZERO, Vector3.LEFT, 1.0, 0.0, 0.1, contact)
	cached.observe(Vector3.ZERO, Vector3.LEFT, 1.0, 0.0, 2.91, [])
	if cached.phase != &"braking" or (cached.get("_escape_forward") as Vector3).is_zero_approx():
		_fail("An early corner contact must still select a side turn when the triggering observe has no contacts.")
	var progressed := Recovery.new()
	progressed.reset(Vector3.ZERO, Vector3.LEFT)
	progressed.observe(Vector3.ZERO, Vector3.LEFT, 1.0, 0.0, 0.1, contact)
	## Actual >=0.5m progress begins a new window and must discard the prior wall-side decision.
	progressed.observe(Vector3.RIGHT * Recovery.PROGRESS_METRES, Vector3.LEFT, 1.0, 0.0, 0.1, [])
	progressed.observe(Vector3.RIGHT * Recovery.PROGRESS_METRES, Vector3.LEFT, 1.0, 0.0, 3.01, [])
	if progressed.phase != &"braking" or not (progressed.get("_escape_forward") as Vector3).is_zero_approx():
		_fail("Actual progress must clear an old contact side; a later contact-free stall uses the straight reverse path.")


func _validate_real_corner_contact_escape() -> void:
	for side_sign in [-1.0, 1.0]:
		## 長側牆形成凹角：倒車後車尾仍無側轉空間，只能有界地 timeout/replan。
		await _validate_real_corner_case(side_sign, false)
	for side_sign in [-1.0, 1.0]:
		## 單一建築只咬住該側履帶前端；倒車後鼻端越過凸角，留下實際側轉空間。
		await _validate_real_corner_case(side_sign, true)


func _validate_real_corner_case(side_sign: float, require_advance: bool) -> void:
	var fixture := await _make_corner_fixture(side_sign, require_advance)
	if fixture.is_empty():
		return
	var tank := fixture.tank as CharacterBody3D
	var front_wall := fixture.front as StaticBody3D
	var side_wall := fixture.side as StaticBody3D
	var recovery := Recovery.new()
	var saw_real_contact := false
	var saw_contact_on_expected_side := false
	var observed_normals: Array[Vector3] = []
	## 凸角直行撞上建築前表面；側別來自真實接觸點，不要求法線必須帶 Z 分量。
	for unused in 360:
		tank.set_movement_input(1.0)
		tank.set_turn_input(0.55 * side_sign if not require_advance else 0.0)
		await physics_frame
		if _part_hits(tank, front_wall) or _part_hits(tank, side_wall):
			_fail("Mirror %.0f Tank1 penetrated an authored corner wall while acquiring the real contact." % side_sign)
			await _free_fixture(fixture)
			return
		var contacts: Array[Dictionary] = tank.get_recovery_contacts()
		for contact in contacts:
			saw_real_contact = true
			var normal := contact.get("normal", Vector3.ZERO) as Vector3
			if not observed_normals.has(normal):
				observed_normals.append(normal)
			var point := contact.get("position", tank.stable_world_center()) as Vector3
			if (point - tank.stable_world_center()).z * side_sign > 0.1:
				saw_contact_on_expected_side = true
		if saw_real_contact and (saw_contact_on_expected_side or not require_advance):
			break
	if not saw_real_contact or (require_advance and not saw_contact_on_expected_side):
		_fail("Mirror %.0f real Tank1 corner fixture must produce a true contact point on the expected track side; contact=%s side=%s normals=%s." % [side_sign, saw_real_contact, saw_contact_on_expected_side, observed_normals])
		await _free_fixture(fixture)
		return
	var actual_contacts: Array[Dictionary] = tank.get_recovery_contacts()
	var position: Vector3 = tank.stable_world_center()
	var forward: Vector3 = _forward(tank)
	recovery.reset(position, forward)
	recovery.observe(position, forward, 1.0, 0.0, 3.01, actual_contacts)
	if recovery.phase != &"braking" or (recovery.get("_escape_forward") as Vector3).is_zero_approx():
		_fail("Mirror %.0f real corner contacts must arm a side escape at the stall boundary; phase=%s escape=%s." % [side_sign, recovery.phase, recovery.get("_escape_forward")])
		await _free_fixture(fixture)
		return
	var saw_turn := false
	var saw_advance := false
	var saw_replan := false
	var replan_before_advance := false
	var penetrated := false
	var turn_start := Vector3.ZERO
	var turn_end := Vector3.ZERO
	var turn_last := Vector3.ZERO
	var advance_start := Vector3.ZERO
	var advance_distance := 0.0
	var escape := recovery.get("_escape_forward") as Vector3
	if require_advance and escape.z * side_sign >= 0.0:
		_fail("Convex mirror %.0f must lock escape away from the contacted track side; escape=%s." % [side_sign, escape])
		await _free_fixture(fixture)
		return
	var recovery_start: Vector3 = tank.stable_world_center()
	var reverse_distance := 0.0
	for unused in 900:
		var command: Dictionary = recovery.drive(tank.stable_world_center(), _forward(tank), absf(float(tank.get("forward_speed"))), float(tank.get("reverse_movement_speed")), 5.0, DT, float(tank.get("movement_speed")), absf(float(tank.get("actual_angular_speed"))))
		if recovery.phase == &"turning" and absf(float(command.get("turn", 0.0))) > 0.01:
			if not saw_turn:
				turn_start = _forward(tank)
			saw_turn = true
		if recovery.phase == &"advancing" and float(command.get("movement", 0.0)) > 0.05:
			if not saw_advance:
				turn_end = _forward(tank)
				advance_start = tank.stable_world_center()
			saw_advance = true
		if bool(command.get("replan", false)) and not saw_advance:
			replan_before_advance = true
		saw_replan = saw_replan or bool(command.get("replan", false))
		tank.set_movement_input(float(command.get("movement", 0.0)))
		tank.set_turn_input(float(command.get("turn", 0.0)))
		await physics_frame
		penetrated = penetrated or _part_hits(tank, front_wall) or _part_hits(tank, side_wall)
		if saw_turn:
			turn_last = _forward(tank)
		var actual_reverse: float = (tank.stable_world_center() - recovery_start).dot(-forward)
		reverse_distance = maxf(reverse_distance, actual_reverse)
		if saw_advance:
			var along_escape: float = (tank.stable_world_center() - advance_start).dot(escape)
			advance_distance = maxf(advance_distance, along_escape)
		if saw_replan:
			break
	var turn_degrees := rad_to_deg(turn_start.angle_to(turn_end)) if saw_turn and saw_advance else 0.0
	var faces_escape := turn_end.dot(escape) >= cos(deg_to_rad(10.0)) if saw_advance else false
	var timeout_turn_degrees := rad_to_deg(turn_start.angle_to(turn_last)) if saw_turn else 0.0
	var timeout_error_degrees := absf(rad_to_deg(turn_last.signed_angle_to(escape, Vector3.UP))) if saw_turn else 180.0
	var case_name := "convex" if require_advance else "concave"
	print("CORNER_METRIC case=%s sign=%.0f turn_deg=%.2f timeout_turn_deg=%.2f timeout_error_deg=%.2f reverse_m=%.3f advance_m=%.3f faces_escape=%s replan=%s replan_before_advance=%s penetrated=%s" % [case_name, side_sign, turn_degrees, timeout_turn_degrees, timeout_error_degrees, reverse_distance, advance_distance, faces_escape, saw_replan, replan_before_advance, penetrated])
	if require_advance:
		if not saw_turn or not saw_advance or turn_degrees < 10.0 or not faces_escape or advance_distance < 0.4 or not saw_replan or replan_before_advance:
			_fail("Convex mirror %.0f Tank1 must turn >=10deg toward escape then advance >=0.4m along it before replan; turn=%s/%.2fdeg faces=%s advance=%s/%.3f replan=%s early=%s." % [side_sign, saw_turn, turn_degrees, faces_escape, saw_advance, advance_distance, saw_replan, replan_before_advance])
	else:
		if not saw_turn or timeout_turn_degrees <= 1.0 or saw_advance or not saw_replan:
			_fail("Concave mirror %.0f must make a real bounded turn attempt but never force advance before timeout/replan; turn=%s/%.2fdeg advance=%s replan=%s." % [side_sign, saw_turn, timeout_turn_degrees, saw_advance, saw_replan])
	if penetrated:
		_fail("%s mirror %.0f Tank1 corner recovery must never penetrate either authored StaticBody3D wall on any physics frame." % [case_name, side_sign])
	await _free_fixture(fixture)


func _start_corner_recovery(forward: Vector3, contacts: Array[Dictionary]) -> RefCounted:
	var recovery := Recovery.new()
	recovery.reset(Vector3.ZERO, forward)
	recovery.observe(Vector3.ZERO, forward, 1.0, 0.0, 3.01, contacts)
	return recovery


func _reach_turning(recovery: RefCounted, forward: Vector3) -> float:
	## Braking -> reversing -> settling -> turning.  No contacts are supplied after the first observe call.
	recovery.drive(Vector3.ZERO, forward, 0.0, 2.0, 1.0, DT)
	recovery.drive(Vector3.ZERO, forward, 0.0, 2.0, 1.0, DT)
	recovery.drive(Vector3.RIGHT * Recovery.REVERSE_METRES, forward, 0.0, 2.0, 1.0, DT)
	recovery.drive(Vector3.RIGHT * Recovery.REVERSE_METRES, forward, 0.0, 2.0, 1.0, DT)
	var turn: Dictionary = recovery.drive(Vector3.RIGHT * Recovery.REVERSE_METRES, forward, 0.0, 2.0, 1.0, DT)
	return float(turn.get("turn", 0.0))


func _make_corner_fixture(side_sign: float, require_advance: bool) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var ground := _box(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
	world.add_child(ground)
	var tank := TANK1.instantiate() as CharacterBody3D
	world.add_child(tank)
	tank.global_position = Vector3(0.0, 0.0, 0.0)
	tank.rotation.y = 0.0
	await physics_frame
	var min_x: float = -_support(tank, Vector3.LEFT)
	var side_direction := Vector3(0.0, 0.0, side_sign)
	var side_support: float = _support(tank, side_direction)
	var front: StaticBody3D
	var side: StaticBody3D
	if require_advance:
		## 一個凸建築：近表面只比車鼻前 8cm，內側 Z 邊界侵入該側履帶 30cm。
		## 建築只向前方(-X)與外側(+/-Z)延伸；後方沒有沿車身延伸的側牆。
		var depth := 8.0
		var width := 8.0
		var front_surface_x := min_x - 0.08
		var inner_z := side_direction.z * (side_support - 0.30)
		front = _box(Vector3(front_surface_x - depth * 0.5, 3.0, inner_z + side_direction.z * width * 0.5), Vector3(depth, 8.0, width))
		side = front
	else:
		## 保留長側牆凹角安全案例，證明無空間時只會 timeout/replan 而不穿牆。
		front = _box(Vector3(min_x - 2.0, 3.0, 0.0), Vector3(1.0, 8.0, 14.0))
		side = _box(Vector3(0.0, 3.0, side_direction.z * (side_support + 0.75)), Vector3(14.0, 8.0, 1.0))
	world.add_child(front)
	if side != front:
		world.add_child(side)
	await physics_frame
	if _part_hits(tank, front) or _part_hits(tank, side):
		_fail("Corner fixture must start clear of both walls.")
		world.queue_free()
		await physics_frame
		return {}
	return {"world": world, "tank": tank, "front": front, "side": side}


func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _support(tank: CharacterBody3D, direction: Vector3) -> float:
	var result := -INF
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points:
				result = maxf(result, direction.dot(transforms[index] * point))
			index += 1
	return result


func _part_hits(tank: CharacterBody3D, body: StaticBody3D) -> bool:
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = transforms[index]
			query.collision_mask = 1
			query.exclude = [tank.get_rid()]
			for hit in tank.get_world_3d().direct_space_state.intersect_shape(query, 16):
				if hit.get("collider") == body:
					return true
			index += 1
	return false


func _forward(tank: CharacterBody3D) -> Vector3:
	var result := tank.global_basis * Vector3.LEFT
	result.y = 0.0
	return result.normalized()


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.world as Node3D).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
