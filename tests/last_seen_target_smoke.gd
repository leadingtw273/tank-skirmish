extends SceneTree

const TANK2_SCENE := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const TANK3_SCENE := preload("res://src/actors/tank/variants/tank3/tank3.tscn")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")
const TANK_SCENES := [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	TANK2_SCENE, TANK3_SCENE,
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_cmdline_user_args().has("--m2"):
		if await _m2_recomputes_same_world_point_after_observer_moves():
			print("Last-seen target M2 passed.")
			quit(0)
		return
	if not await _m1_remembers_body_center_without_firing():
		return
	if not await _m2_recomputes_same_world_point_after_observer_moves():
		return
	if not await _l1_disabled_combat_does_not_restore_last_seen_aim():
		return
	if not await _m1_gun_only_saves_body_center():
		return
	print("PASS M1 gun-only stable center / A1 collision guard")
	if not await _m3_origin_retention_and_reacquisition():
		return
	print("PASS M3 origin / retention / reacquisition")
	if not await _p1_p2_priority():
		return
	print("PASS P1/P2 targeting priority")
	if not await _l1_lifecycle():
		return
	print("PASS L1 lifecycle clearing")
	if not await _a1_four_tanks():
		return
	print("Last-seen target smoke validation passed.")
	quit(0)


func _m1_remembers_body_center_without_firing() -> bool:
	var fixture := await _make_fixture(Vector3(0, 30, 0), Vector3(0, 30, 12))
	var observer := fixture.observer as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var vision := fixture.vision as Node
	var ai := fixture.ai as Node
	if observer == null or target == null or vision == null or ai == null:
		return _fail("M1 requires real Tank2/Tank3, Vision, and CombatAI.")
	var saved_center := target.call("stable_world_center") as Vector3
	var shots: Array[ShotEvent] = []
	observer.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
	if not await _manual_tick(ai) or (vision.call("visible_target_points", target) as PackedVector3Array).is_empty():
		return _fail("M1 setup requires a true visible target before sight is blocked.")
	var hidden_offset := Vector3(6, 0, 2)
	var blocker := _make_full_screen(observer, target, hidden_offset)
	fixture.root.add_child(blocker)
	target.global_position += hidden_offset
	await physics_frame
	await physics_frame
	if not (vision.call("visible_target_points", target) as PackedVector3Array).is_empty():
		return _fail("M1 setup requires the moved target to be physically hidden.")
	var yaw_before := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_rotation.y
	for _frame in 30:
		if not await _manual_tick(ai):
			return false
	var yaw_after := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_rotation.y
	if absf(angle_difference(yaw_before, yaw_after)) <= deg_to_rad(2.0):
		return _fail("M1 lost sight must continue turning toward the last visible body center.")
	var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var hidden_center := target.call("stable_world_center") as Vector3
	if _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, saved_center)) \
			>= _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, hidden_center)):
		return _fail("M1 hidden target movement must not replace the saved body-center world point.")
	if not (saved_center - hidden_center).length() > 1.0:
		return _fail("M1 fixture must move the hidden target after saving its center.")
	if not shots.is_empty():
		return _fail("M1 last-seen aiming must emit zero ShotEvent values.")
	fixture.root.queue_free()
	await physics_frame
	return true


func _m2_recomputes_same_world_point_after_observer_moves() -> bool:
	var fixture := await _make_fixture(Vector3(0, 30, 0), Vector3(0, 30, 12))
	var observer := fixture.observer as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var vision := fixture.vision as Node
	var ai := fixture.ai as Node
	if observer == null or target == null or vision == null or ai == null:
		return _fail("M2 requires real Tank2/Tank3, Vision, and CombatAI.")
	var saved_center := target.call("stable_world_center") as Vector3
	if not await _manual_tick(ai):
		return false
	var blocker := _make_full_screen(observer, target)
	fixture.root.add_child(blocker)
	await physics_frame
	await physics_frame
	if not (vision.call("visible_target_points", target) as PackedVector3Array).is_empty():
		return _fail("M2 setup requires a physically hidden target after saving its center.")
	observer.global_position += Vector3(10, 0, 0)
	await physics_frame
	## 移位後重新以真實遮蔽物封住新視線，避免把一般可見追蹤誤當成位置記憶。
	blocker.queue_free()
	await physics_frame
	blocker = _make_full_screen(observer, target)
	fixture.root.add_child(blocker)
	await physics_frame
	if not (vision.call("visible_target_points", target) as PackedVector3Array).is_empty():
		return _fail("M2 moved-observer setup must remain physically hidden.")
	var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var initial_error := _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, saved_center))
	if Vector2(turret.global_position.x - saved_center.x, turret.global_position.z - saved_center.z).length() <= 3.0:
		return _fail("M2 observer turret must be more than 3m from the saved world center.")
	for _frame in 45:
		if not await _manual_tick(ai):
			return false
	var final_error := _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, saved_center))
	if final_error >= initial_error - deg_to_rad(2.0):
		return _fail("M2 moved observer must turn toward the same saved world point, not freeze at its old angle.")
	fixture.root.queue_free()
	await physics_frame
	return true


func _l1_disabled_combat_does_not_restore_last_seen_aim() -> bool:
	var fixture := await _make_fixture(Vector3(0, 30, 0), Vector3(0, 30, 12))
	var observer := fixture.observer as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var vision := fixture.vision as Node
	var ai := fixture.ai as Node
	if observer == null or target == null or vision == null or ai == null:
		return _fail("L1 requires a complete real fixture.")
	if not await _manual_tick(ai):
		return false
	var blocker := _make_full_screen(observer, target)
	fixture.root.add_child(blocker)
	await physics_frame
	if not (vision.call("visible_target_points", target) as PackedVector3Array).is_empty():
		return _fail("L1 setup requires a hidden target after a visible tick.")
	ai.call("set_combat_enabled", false)
	ai.call("set_combat_enabled", true)
	observer.global_position += Vector3(10, 0, 0)
	await physics_frame
	blocker.queue_free()
	await physics_frame
	blocker = _make_full_screen(observer, target)
	fixture.root.add_child(blocker)
	await physics_frame
	var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var yaw_before := turret.global_rotation.y
	for _frame in 30:
		if not await _manual_tick(ai):
			return false
	if absf(angle_difference(yaw_before, turret.global_rotation.y)) > deg_to_rad(1.0):
		return _fail("L1 combat disable/restore must not revive hidden last-seen aim.")
	fixture.root.queue_free()
	await physics_frame
	return true


## 射線 fixture 沿既有 partial_visibility_smoke 的有限部位遮罩做法。
func _m1_gun_only_saves_body_center() -> bool:
	var f := await _make_fixture(Vector3(0, 30, 0), Vector3(0, 30, 12))
	var observer: CharacterBody3D = f.observer
	var target: CharacterBody3D = f.target
	var origin := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_position
	var center := target.call("stable_world_center") as Vector3
	var points := target.call("part_world_surface_points") as PackedVector3Array
	var blocked := PackedVector3Array([center])
	for i in points.size():
		if _sample_part(target, i) != &"gun":
			blocked.append(points[i])
	var selected := Vector3.ZERO
	var best_clearance := 0.0
	for i in points.size():
		if _sample_part(target, i) != &"gun":
			continue
		var hit := _ray(observer, origin, points[i])
		if hit.get("collider") != target:
			continue
		var owner := target.shape_owner_get_owner(target.shape_find_owner(int(hit.shape))) as Node
		if not String(owner.name).begins_with("PartCollision_gun_"):
			continue
		var clearance := PI
		for rival in blocked:
			clearance = minf(clearance, (points[i] - origin).angle_to(rival - origin))
		if clearance > best_clearance:
			best_clearance = clearance
			selected = points[i]
	if best_clearance <= 0.000001:
		return _fail("M1 gun-only fixture needs a real exposed gun ray distinct from center/other parts.")
	var screens: Array[StaticBody3D] = []
	for point in blocked:
		var position := origin + (point - origin).normalized() * 3.0
		var direction := (selected - origin).normalized()
		var separation := position.distance_to(origin + direction * (position - origin).dot(direction))
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = minf(0.09, separation * 0.35)
		collision.shape = shape
		body.add_child(collision)
		body.position = position
		f.root.add_child(body)
		screens.append(body)
	await physics_frame
	await physics_frame
	var visible := f.vision.call("visible_target_points", target) as PackedVector3Array
	if visible.is_empty() or visible.has(center):
		return _fail("M1 gun-only fixture must expose gun while blocking the stable center.")
	for point in visible:
		var index := -1
		for i in points.size():
			if points[i].is_equal_approx(point):
				index = i
		if index < 0 or _sample_part(target, index) != &"gun":
			return _fail("M1 gun-only fixture must not expose any other body part.")
	await _manual_tick(f.ai)
	if not (f.ai.get("_last_seen_position") as Vector3).is_equal_approx(center):
		return _fail("M1 gun-only visibility must save body center, not the first exposed gun sample.")
	_hide_by_range(observer)
	var collision_stopped := false
	for tick in 150:
		await _manual_tick(f.ai)
		var stats := observer.call("get_motion_guard_attempt_stats", &"turret") as Dictionary
		var reason := str(stats.get("blocked_reason", ""))
		collision_stopped = collision_stopped or reason.begins_with("new-collider:") or reason.begins_with("old-contact-inward:")
	if not collision_stopped:
		return _fail("A1 remembered aiming must encounter the real near-gun screen through the existing collision guard.")
	## 保存中心後改由範圍維持失視，移除靠近炮管的射線遮罩，避免它阻擋合法旋轉。
	for screen in screens:
		screen.queue_free()
	await physics_frame
	var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	await _ticks(f.ai, 150)
	if _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, center)) > deg_to_rad(1.0):
		return _fail("M1 gun-only last sight must finish aiming at saved body center.")
	await _dispose(f)
	return true


func _m3_origin_retention_and_reacquisition() -> bool:
	var f := await _make_fixture(Vector3(0, 0, -12), Vector3.ZERO)
	var target: Node3D = f.target
	var observer: Node3D = f.observer
	var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	target.global_position -= target.call("stable_world_center") as Vector3
	await physics_frame
	if not (target.call("stable_world_center") as Vector3).is_zero_approx():
		return _fail("M3 fixture must put stable body center, not merely node origin, at world zero.")
	_hide_by_range(observer)
	var no_memory_yaw := turret.global_rotation.y
	await _ticks(f.ai, 5)
	if not is_equal_approx(no_memory_yaw, turret.global_rotation.y):
		return _fail("M3 no initial sight must not invent an origin target.")
	observer.set("vision_near_radius", 60.0)
	await _manual_tick(f.ai)
	_hide_by_range(observer)
	var shots: Array[ShotEvent] = []
	observer.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
	await _ticks(f.ai, 180)
	if _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, Vector3.ZERO)) > deg_to_rad(1.0):
		return _fail("M3 a remembered world origin must be aimed at outside the 3m dead zone.")
	await _ticks(f.ai, 60)
	observer.global_position += Vector3(10, 0, 0)
	await _ticks(f.ai, 120)
	if _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, Vector3.ZERO)) > deg_to_rad(1.0):
		return _fail("M3 alignment and elapsed ticks must not discard the remembered world point.")
	if not shots.is_empty():
		return _fail("M3 hidden origin aiming must not fire, even when a muzzle ray could hit the target.")
	## 重新目擊的射擊案例留足水平距離，避免把既有俯角限制造成的停火誤判為記憶失效。
	target.global_position += Vector3(-20, 0, -12)
	observer.set("vision_near_radius", 60.0)
	await physics_frame
	await _ticks(f.ai, 180)
	if not (f.ai.get("_last_seen_position") as Vector3).is_equal_approx(target.call("stable_world_center") as Vector3) or shots.is_empty():
		return _fail("M3 seeing target again must refresh its center and restore real gated fire.")
	await _dispose(f)
	return true


func _p1_p2_priority() -> bool:
	var f := await _make_fixture(Vector3(0, 30, 0), Vector3(0, 30, 12))
	var observer: Node3D = f.observer
	var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	await _manual_tick(f.ai)
	f.target.global_position += Vector3(0, 0, 3)
	await physics_frame
	var hit_position := (observer.call("stable_world_center") as Vector3) + Vector3(0, 0, -5)
	f.ai.call("inspect_hit_position", hit_position)
	await _manual_tick(f.ai)
	if not (f.ai.get("_inspection_direction") as Vector3).is_zero_approx() \
			or not (f.ai.get("_last_seen_position") as Vector3).is_equal_approx(f.target.call("stable_world_center") as Vector3):
		return _fail("P1 visible target must outrank side-hit inspection and refresh its moved center.")
	_hide_by_range(observer)
	f.ai.call("inspect_hit_position", hit_position)
	var inspection := f.ai.get("_inspection_direction") as Vector3
	if inspection.is_zero_approx():
		return _fail("P2 hidden side hit must actually start an inspection.")
	var shots: Array[ShotEvent] = []
	observer.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
	await _ticks(f.ai, 180)
	if not (f.ai.get("_inspection_direction") as Vector3).is_zero_approx() or _horizontal_forward(turret).angle_to(inspection) > deg_to_rad(3.1):
		return _fail("P2 inspection must take precedence over last sight and finish facing the hit side.")
	var finished_yaw := turret.global_rotation.y
	await _ticks(f.ai, 90)
	if absf(angle_difference(finished_yaw, turret.global_rotation.y)) > 0.0001 or not shots.is_empty():
		return _fail("P2 completed inspection must not return to old sight or fire while hidden.")
	observer.set("vision_near_radius", 60.0)
	await _manual_tick(f.ai)
	_hide_by_range(observer)
	await _ticks(f.ai, 240)
	var saved := f.target.call("stable_world_center") as Vector3
	if _horizontal_forward(turret).angle_to(_horizontal_direction(turret.global_position, saved)) > deg_to_rad(1.0):
		return _fail("P2 new visibility must establish new position memory after cancelled inspection.")
	await _dispose(f)
	return true


func _l1_lifecycle() -> bool:
	for mode in ["observer_dead", "target_dead", "target_null", "target_new"]:
		var f := await _make_fixture(Vector3(0, 30, 0), Vector3(0, 30, 12))
		await _manual_tick(f.ai)
		_hide_by_range(f.observer)
		if mode == "observer_dead" or mode == "target_dead":
			var subject: Node3D = f.observer if mode == "observer_dead" else f.target
			var health := subject.get_node("HealthComponent")
			health.call("apply_damage", 100000.0)
			if float(health.get("current_health")) > 0.0:
				return _fail("L1 fixture must actually deplete health before the clearing tick.")
			await _manual_tick(f.ai)
			health.call("reset_to_maximum")
		elif mode == "target_null":
			f.ai.call("set_target", null)
			await _manual_tick(f.ai)
			f.ai.call("set_target", f.target)
		else:
			var replacement := TANK3_SCENE.instantiate() as Node3D
			replacement.position = Vector3(100, 30, 0)
			replacement.set_physics_process(false)
			f.root.add_child(replacement)
			f.ai.call("set_target", replacement)
		var turret := f.observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
		var yaw_before := turret.global_rotation.y
		await _ticks(f.ai, 30)
		if absf(angle_difference(yaw_before, turret.global_rotation.y)) > 0.0001:
			return _fail("L1 %s must clear memory and never resume old aiming after restore/rebind." % mode)
		await _dispose(f)
	return true


func _a1_four_tanks() -> bool:
	for model in TANK_SCENES.size():
		var f := await _make_fixture(Vector3(0, 30, 0), Vector3(0, 36, 12), model)
		var observer: Node3D = f.observer
		var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
		var gun := turret.get_node("GunPitchPivot") as Node3D
		await _manual_tick(f.ai)
		_hide_by_range(observer)
		var initial_position := observer.global_position
		var initial_yaw := observer.global_rotation.y
		var initial_gun_pitch := gun.rotation.z
		var initial_turret_yaw := turret.global_rotation.y
		var shots: Array[ShotEvent] = []
		observer.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
		for tick in 45:
			await _manual_tick(f.ai)
			observer.call("_physics_process", 1.0 / 60.0)
			if not is_zero_approx(float(observer.get("movement_command"))) or observer.global_position.distance_to(initial_position) > 0.01:
				return _fail("A1 Tank%d last-seen aiming must remain in place." % (model + 1))
			if absf(turret.rotation.y) > deg_to_rad(float(observer.get("turret_max_yaw_degrees"))) + 0.001 \
					or -gun.rotation.z > deg_to_rad(float(observer.get("gun_max_elevation_degrees"))) + 0.001 \
					or -gun.rotation.z < -deg_to_rad(float(observer.get("gun_max_depression_degrees"))) - 0.001:
				return _fail("A1 Tank%d must preserve mechanical yaw/pitch limits." % (model + 1))
		if absf(gun.rotation.z - initial_gun_pitch) < 0.01 or not shots.is_empty():
			return _fail("A1 Tank%d must pitch toward the remembered elevated point without firing." % (model + 1))
		if model == 0 or model == 3:
			if absf(angle_difference(initial_yaw, observer.global_rotation.y)) < deg_to_rad(2.0):
				return _fail("A1 fixed Tank%d must keep its existing hull assist." % (model + 1))
		elif absf(angle_difference(initial_turret_yaw, turret.global_rotation.y)) < deg_to_rad(2.0) or not is_equal_approx(initial_yaw, observer.global_rotation.y):
			return _fail("A1 rotating Tank%d must turn turret without turning hull." % (model + 1))
		await _dispose(f)
	return true


func _hide_by_range(observer: Node3D) -> void:
	observer.set("vision_near_radius", 0.1)
	observer.set("vision_far_radius", 0.0)


func _ticks(ai: Node, count: int) -> void:
	for tick in count:
		await _manual_tick(ai)


func _dispose(f: Dictionary) -> void:
	f.root.queue_free()
	await physics_frame


func _sample_part(target: Node3D, wanted: int) -> StringName:
	var cursor := 0
	for part: Resource in (target.get("part_geometry") as Resource).get("parts") as Array:
		var count := (part.get("surface_points") as PackedVector3Array).size()
		if wanted < cursor + count:
			return StringName(str(part.get("id")))
		cursor += count
	return &""


func _ray(observer: CharacterBody3D, from: Vector3, to: Vector3) -> Dictionary:
	return observer.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 129, [observer.get_rid()]))


func _make_fixture(observer_position: Vector3, target_position: Vector3, model := 1) -> Dictionary:
	var fixture := Node3D.new()
	var observer := TANK_SCENES[model].instantiate() as CharacterBody3D
	var target := TANK3_SCENE.instantiate() as CharacterBody3D
	var vision := TankVision.new()
	var ai := TankCombatAI.new()
	if observer == null or target == null:
		return {}
	observer.position = observer_position
	observer.set_physics_process(false)
	target.position = target_position
	target.set_physics_process(false)
	vision.observer = observer
	ai.controlled_tank = observer
	ai.vision = vision
	fixture.add_child(observer)
	fixture.add_child(target)
	fixture.add_child(vision)
	fixture.add_child(ai)
	root.add_child(fixture)
	ai.set_physics_process(false)
	ai.set_target(target)
	ai.set_combat_enabled(true)
	await physics_frame
	await physics_frame
	return {"root": fixture, "observer": observer, "target": target, "vision": vision, "ai": ai}


func _manual_tick(ai: Node) -> bool:
	ai.call("_physics_process", 1.0 / 60.0)
	await physics_frame
	return true


func _make_full_screen(observer: Node3D, target: Node3D, extra_target_offset := Vector3.ZERO) -> StaticBody3D:
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	collision.shape = shape
	blocker.add_child(collision)
	var origin := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_position
	var center := target.call("stable_world_center") as Vector3
	var normal := (center - origin).normalized()
	var tangent_x := normal.cross(Vector3.UP).normalized()
	var tangent_y := normal.cross(tangent_x).normalized()
	var screen_center := origin.lerp(center, 0.5)
	var screen_depth := normal.dot(screen_center - origin)
	var half_width := 0.0
	var half_height := 0.0
	var points: PackedVector3Array = target.call("part_world_surface_points") as PackedVector3Array
	points.append(center)
	for point in points:
		for candidate in PackedVector3Array([point, point + extra_target_offset]):
			var ray := candidate - origin
			var hit := origin + ray * (screen_depth / normal.dot(ray))
			var offset := hit - screen_center
			half_width = maxf(half_width, absf(offset.dot(tangent_x)))
			half_height = maxf(half_height, absf(offset.dot(tangent_y)))
	blocker.global_transform = Transform3D(Basis(tangent_x, tangent_y, normal), screen_center)
	shape.size = Vector3(half_width * 2.0 + 0.2, half_height * 2.0 + 0.2, 0.2)
	return blocker


func _horizontal_forward(turret: Node3D) -> Vector3:
	var forward := -turret.global_basis.x
	forward.y = 0.0
	return forward.normalized()


func _horizontal_direction(from: Vector3, to: Vector3) -> Vector3:
	var direction := to - from
	direction.y = 0.0
	return direction.normalized()


func _fail(message: String) -> bool:
	push_error(message)
	print("FAIL: ", message)
	quit(1)
	return false
