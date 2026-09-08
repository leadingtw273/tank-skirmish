## 以遠離既有地圖的真實物理 fixture 驗證砲口射線終點的地面／立體命中模式。
extends RefCounted


static func run(presentation: Node, scene: Node3D) -> bool:
	var success := true
	var controlled_tank := presentation.get("controlled_tank") as Node3D
	if controlled_tank == null:
		push_error("Aim target mode smoke requires AimPresentation.controlled_tank")
		return false
	var saved_spread: float = float(controlled_tank.get("current_spread_degrees"))
	var fixture := Node3D.new()
	fixture.name = "AimTargetModeSmokeFixture"
	scene.add_child(fixture)
	var isolated_presentation := _create_isolated_presentation(presentation, controlled_tank, fixture)
	if isolated_presentation == null:
		fixture.queue_free()
		push_error("Aim target mode smoke could not create an isolated presentation")
		return false
	var floor := _create_box_body("AimTargetModeFloor", Vector3(3000.0, -0.5, 3000.0), Vector3(200.0, 1.0, 200.0), 128)
	var blocker := _create_box_body("AimTargetModeBlocker", Vector3(3000.0, 8.0, 2990.0), Vector3(4.0, 4.0, 4.0), 0)
	fixture.add_child(floor)
	fixture.add_child(blocker)
	controlled_tank.set("current_spread_degrees", 2.5)

	await scene.get_tree().physics_frame
	await scene.get_tree().physics_frame
	var origin := Vector3(3000.0, 10.0, 3000.0)
	var direction := Vector3(0.0, -0.2, -1.0).normalized()
	var ground_first: Dictionary = presentation.call("_resolve_aim_ray", origin, direction) as Dictionary
	success = _expect_ground_hit(ground_first, origin, direction) and success
	var ground_terminal := _update_reticle_and_markers(isolated_presentation, origin, ground_first, direction)
	success = _expect_ground_reticle(isolated_presentation, ground_terminal) and success

	blocker.collision_layer = 1
	await scene.get_tree().physics_frame
	var blocker_first: Dictionary = presentation.call("_resolve_aim_ray", origin, direction) as Dictionary
	success = _expect_blocker_hit(blocker_first, origin, direction) and success
	var blocker_terminal := _update_reticle_and_markers(isolated_presentation, origin, blocker_first, direction)
	success = _expect_air_reticle_with_markers(isolated_presentation, origin, blocker_first, direction, true, blocker_terminal) and success

	blocker.collision_layer = 0
	await scene.get_tree().physics_frame
	var ground_again: Dictionary = presentation.call("_resolve_aim_ray", origin, direction) as Dictionary
	success = _expect_ground_hit(ground_again, origin, direction) and success
	var ground_again_terminal := _update_reticle_and_markers(isolated_presentation, origin, ground_again, direction)
	success = _expect_ground_reticle(isolated_presentation, ground_again_terminal) and success

	blocker.collision_layer = 1
	await scene.get_tree().physics_frame
	var blocker_again: Dictionary = presentation.call("_resolve_aim_ray", origin, direction) as Dictionary
	success = _expect_blocker_hit(blocker_again, origin, direction) and success
	var blocker_again_terminal := _update_reticle_and_markers(isolated_presentation, origin, blocker_again, direction)
	success = _expect_air_reticle_with_markers(isolated_presentation, origin, blocker_again, direction, true, blocker_again_terminal) and success

	var miss_origin := Vector3(3300.0, 10.0, 3300.0)
	var miss_direction := Vector3.FORWARD
	var miss: Dictionary = presentation.call("_resolve_aim_ray", miss_origin, miss_direction) as Dictionary
	success = _expect_miss(presentation, miss, miss_origin, miss_direction) and success
	var miss_terminal := _update_reticle_and_markers(isolated_presentation, miss_origin, miss, miss_direction)
	success = _expect_air_reticle_with_markers(isolated_presentation, miss_origin, miss, miss_direction, false, miss_terminal) and success

	controlled_tank.set("current_spread_degrees", saved_spread)
	fixture.queue_free()
	await scene.get_tree().physics_frame
	return success


static func _create_isolated_presentation(template: Node, tank: Node3D, fixture: Node3D) -> Node:
	var presentation := (template.get_script() as Script).new() as Node
	if presentation == null:
		return null
	fixture.add_child(presentation)
	presentation.call("set_controlled_tank", tank)
	for spec: Dictionary in [
		{"property": "spread_frames", "script": preload("res://src/player/aim_spread_frames.gd"), "name": "SpreadFrames"},
		{"property": "slice_ground_markers", "script": preload("res://src/player/aim_slice_ground_markers.gd"), "name": "SliceGroundMarkers"},
		{"property": "ground_spread_outline", "script": preload("res://src/player/aim_ground_outline.gd"), "name": "GroundSpreadOutline"},
	]:
		var display := (spec["script"] as Script).new() as Node3D
		display.name = spec["name"]
		presentation.add_child(display)
		presentation.set(spec["property"], display)
	if presentation.get("spread_frames") != null:
		(presentation.get("spread_frames") as Node).call("initialize")
	return presentation


static func _create_box_body(body_name: String, center: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = center
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


static func _update_reticle_and_markers(presentation: Node, origin: Vector3, ray: Dictionary, direction: Vector3) -> Node3D:
	# 等待物理影格後重新固定測試半角，避免坦克的自然擴散回復改變斷言輸入。
	(presentation.get("controlled_tank") as Node).set("current_spread_degrees", 2.5)
	var end: Vector3 = ray["position"] as Vector3
	var ground: Dictionary = presentation.call("_sample_ground", origin, end) as Dictionary
	var excluded_frame: Node3D = presentation.call("_update_spread_reticle", origin, end, bool(ray["is_ground"]), 2.5, ground) as Node3D
	presentation.call("_update_slice_ground_markers", direction, excluded_frame)
	return excluded_frame


static func _expect_ground_hit(ray: Dictionary, origin: Vector3, direction: Vector3) -> bool:
	var position: Vector3 = ray.get("position", Vector3.INF) as Vector3
	if not bool(ray.get("hit", false)) or not bool(ray.get("is_ground", false)) \
			or not is_zero_approx(position.y) or position.distance_to(origin) <= 0.0 \
			or absf((position - origin).normalized().dot(direction)) < 0.999:
		push_error("Aim ray must use the floor as its first hit while the blocker is disabled")
		return false
	return true


static func _expect_blocker_hit(ray: Dictionary, origin: Vector3, direction: Vector3) -> bool:
	var position: Vector3 = ray.get("position", Vector3.INF) as Vector3
	if not bool(ray.get("hit", false)) or bool(ray.get("is_ground", true)) \
			or position.z < 2991.99 or position.z > 2992.01 \
			or absf((position - origin).normalized().dot(direction)) < 0.999:
		push_error("Aim ray must switch to the solid box when layer 1 is enabled")
		return false
	return true


static func _expect_miss(presentation: Node, ray: Dictionary, origin: Vector3, direction: Vector3) -> bool:
	var expected: Vector3 = origin + direction * float(presentation.get("max_aim_distance"))
	var position: Vector3 = ray.get("position", Vector3.INF) as Vector3
	if bool(ray.get("hit", true)) or bool(ray.get("is_ground", true)) or not position.is_equal_approx(expected):
		push_error("Aim ray must preserve the max-distance fallback when neither layer is hit")
		return false
	return true


static func _expect_ground_reticle(presentation: Node, returned_terminal: Node3D) -> bool:
	var display := presentation.get("spread_frames") as Node3D
	var markers := presentation.get("slice_ground_markers") as Node3D
	if display == null or markers == null or display.frames.is_empty():
		push_error("Aim target mode smoke requires initialized spread displays")
		return false
	var last_index: int = display.frames.size() - 1
	var terminal: Node3D = display.frames[last_index]
	var expected_markers := _visible_frame_count(display) - 1
	if returned_terminal != terminal or terminal.global_basis.z.normalized().dot(Vector3.UP) < 0.999 \
			or display.frame_styles[last_index] != 1 or markers.markers.size() != expected_markers:
		push_error("A floor hit must produce the fixed-style upward-facing ground terminal without a duplicate marker")
		return false
	return true


static func _expect_air_reticle_with_markers(presentation: Node, origin: Vector3, ray: Dictionary, direction: Vector3, expect_markers: bool, returned_terminal: Node3D) -> bool:
	var display := presentation.get("spread_frames") as Node3D
	var markers := presentation.get("slice_ground_markers") as Node3D
	if display == null or markers == null or display.frames.is_empty():
		push_error("Aim target mode smoke requires initialized spread displays")
		return false
	var last_index: int = display.frames.size() - 1
	var terminal: Node3D = display.frames[last_index]
	var end: Vector3 = ray["position"] as Vector3
	var radius: float = origin.distance_to(end) * tan(deg_to_rad(2.5))
	var expected_style := _style_for_radius(presentation, radius)
	var expected_markers := _visible_frame_count(display) if expect_markers else 0
	if returned_terminal != null or absf(terminal.global_basis.z.normalized().dot(direction)) < 0.999 \
			or display.frame_styles[last_index] != expected_style \
			or markers.markers.size() != expected_markers:
		push_error("A non-ground terminal must stay on the muzzle cone, choose radius style, and retain only valid ground markers")
		return false
	return true


static func _visible_frame_count(display: Node3D) -> int:
	var count := 0
	for frame: Node3D in display.frames:
		if frame.visible:
			count += 1
	return count


static func _style_for_radius(presentation: Node, radius: float) -> int:
	if radius <= float(presentation.get("spread_frames_style_0_max_radius_meters")):
		return 0
	if radius <= float(presentation.get("spread_frames_style_1_max_radius_meters")):
		return 1
	if radius <= float(presentation.get("spread_frames_style_2_max_radius_meters")):
		return 2
	return 3

