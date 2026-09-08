## 隔離驗證瞄準擴散的幾何與外觀，避免污染正式 AimPresentation。
extends RefCounted


static func run(tank: Node3D, live_presentation: Node) -> bool:
	var fixture := Node3D.new()
	fixture.name = "AimSpreadPresentationSmokeFixture"
	live_presentation.get_parent().add_child(fixture)
	var presentation := _create_isolated_presentation(live_presentation, tank, fixture)
	var success := presentation != null
	if success:
		success = _validate_spread_cone_preview(tank, presentation) and success
		success = _validate_live_spread_cone_preview(tank, live_presentation) and success
		success = _validate_spread_frames(tank, presentation) and success
	fixture.queue_free()
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
	(presentation.get("spread_frames") as Node).call("initialize")
	var cone := presentation.call("_create_aim_line", "SpreadConePreview", presentation.get("spread_cone_color")) as MeshInstance3D
	var mesh := cone.mesh as CylinderMesh
	mesh.bottom_radius = 0.0
	mesh.top_radius = 1.0
	mesh.radial_segments = 48
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/player/spread_cone_preview.gdshader")
	material.set_shader_parameter("cone_color", presentation.get("spread_cone_color"))
	material.set_shader_parameter("ground_contact_color", presentation.get("spread_cone_ground_contact_color"))
	cone.material_override = material
	presentation.set("spread_cone_preview", cone)
	return presentation


static func _refresh_spread(presentation: Node, origin: Vector3, direction: Vector3, end: Vector3, half_angle: float) -> Node3D:
	var ray: Dictionary = presentation.call("_resolve_aim_ray", origin, direction) as Dictionary
	var ground: Dictionary = presentation.call("_sample_ground", origin, end) as Dictionary
	var terminal: Node3D = presentation.call("_update_spread_reticle", origin, end, bool(ray["is_ground"]), half_angle, ground) as Node3D
	presentation.call("_update_slice_ground_markers", direction, terminal)
	return terminal


static func _validate_spread_cone_preview(tank: Node3D, presentation: Node) -> bool:
	var cone := presentation.get("spread_cone_preview") as MeshInstance3D
	if presentation.get("show_spread_cone") or (cone != null and cone.visible):
		push_error("Spread cone must start disabled and hidden")
		return false
	presentation.set("show_spread_cone", true)
	var mesh := cone.mesh as CylinderMesh if cone != null else null
	var material := cone.material_override as ShaderMaterial if cone != null else null
	if mesh == null or material == null or not is_zero_approx(mesh.bottom_radius) \
			or not is_equal_approx(mesh.top_radius, 1.0) \
			or material.shader == null \
			or material.get_shader_parameter("cone_color").a <= 0.0 \
			or material.get_shader_parameter("cone_color").a >= 1.0:
		push_error("Temporary spread preview must be a translucent cone with its apex at local -Y")
		return false
	var saved_spread := float(tank.get("current_spread_degrees"))
	var previous_radius := 0.0
	var origin: Vector3 = tank.call("muzzle_global_position")
	var direction: Vector3 = tank.call("muzzle_global_direction")
	for half_angle: float in [1.0, 2.5]:
		tank.set("current_spread_degrees", half_angle)
		presentation.call("_update_spread_cone", origin, origin + direction * 100.0, float(tank.get("current_spread_degrees")))
		var basis := cone.global_transform.basis
		var shader_inverse: Transform3D = material.get_shader_parameter("world_to_cone")
		if not shader_inverse.is_equal_approx(cone.global_transform.affine_inverse()):
			push_error("Ground contact preview must track the current cone transform")
			return false
		var radius := basis.x.length()
		if not cone.visible or not (cone.global_transform * (Vector3.DOWN * 0.5)).is_equal_approx(origin) \
				or basis.y.normalized().dot(direction) < 0.999 \
				or not is_equal_approx(radius, basis.y.length() * tan(deg_to_rad(half_angle))) \
				or radius <= previous_radius:
			push_error("Spread cone must follow the actual muzzle and widen with the current half-angle")
			return false
		previous_radius = radius
	tank.set("current_spread_degrees", 1.0)
	presentation.call("_update_spread_cone", origin, origin + direction * 100.0, float(tank.get("current_spread_degrees")))
	if cone.global_transform.basis.x.length() >= previous_radius:
		push_error("Spread cone must shrink as accuracy recovers")
		return false
	presentation.set("show_spread_cone", false)
	presentation.call("_update_spread_cone", origin, origin + direction * 100.0, float(tank.get("current_spread_degrees")))
	if cone.visible:
		push_error("Temporary spread cone toggle must hide the preview")
		return false
	tank.set("current_spread_degrees", saved_spread)
	presentation.call("_update_spread_cone", origin, origin + direction * 100.0, float(tank.get("current_spread_degrees")))
	return true


static func _validate_live_spread_cone_preview(tank: Node3D, presentation: Node) -> bool:
	var cone := presentation.get("spread_cone_preview") as MeshInstance3D
	var frames := presentation.get("spread_frames") as Node3D
	var markers := presentation.get("slice_ground_markers") as Node3D
	var outline := presentation.get("ground_spread_outline") as Node3D
	var mesh := cone.mesh as CylinderMesh if cone != null else null
	var material := cone.material_override as ShaderMaterial if cone != null else null
	if frames == null or markers == null or outline == null or frames.get_parent() != presentation \
			or markers.get_parent() != presentation or outline.get_parent() != presentation or mesh == null or material == null \
			or not is_zero_approx(mesh.bottom_radius) or not is_equal_approx(mesh.top_radius, 1.0) \
			or material.shader == null or material.get_shader_parameter("cone_color").a <= 0.0 \
			or material.get_shader_parameter("cone_color").a >= 1.0:
		push_error("Live AimPresentation must initialize its owned spread displays and translucent apex cone")
		return false
	if bool(presentation.get("show_spread_cone")) or cone.visible:
		push_error("Live spread cone must start disabled and hidden")
		return false
	var saved_spread := float(tank.get("current_spread_degrees"))
	var saved_toggle := bool(presentation.get("show_spread_cone"))
	var saved_target: Vector3 = presentation.get("world_target") as Vector3
	var success := true
	var origin: Vector3 = tank.call("muzzle_global_position") as Vector3
	var direction: Vector3 = tank.call("muzzle_global_direction") as Vector3
	presentation.set("show_spread_cone", true)
	var previous_radius := 0.0
	for half_angle: float in [1.0, 2.5]:
		tank.set("current_spread_degrees", half_angle)
		presentation.call("set_world_target", origin + direction * 100.0)
		var basis := cone.global_transform.basis
		var radius := basis.x.length()
		if not cone.visible or not (cone.global_transform * (Vector3.DOWN * 0.5)).is_equal_approx(origin) \
				or basis.y.normalized().dot(direction) < 0.999 \
				or not is_equal_approx(radius, basis.y.length() * tan(deg_to_rad(half_angle))) \
				or radius <= previous_radius:
			push_error("Live spread cone must follow the muzzle and widen with the current half-angle")
			success = false
		previous_radius = radius
	tank.set("current_spread_degrees", saved_spread)
	presentation.set("show_spread_cone", saved_toggle)
	presentation.call("set_world_target", saved_target)
	return success


static func _validate_spread_frames(tank: Node3D, presentation: Node) -> bool:
	if not _validate_slice_ground_markers(presentation):
		return false
	if not _validate_ground_spread_outline(tank, presentation):
		return false
	var display = presentation.get("spread_frames")
	if display == null:
		push_error("Spread presentation must create spread frame containers")
		return false
	if not _validate_dynamic_spread_frame_count(display, presentation):
		return false
	var saved_spread := float(tank.get("current_spread_degrees"))
	var origin: Vector3 = tank.call("muzzle_global_position")
	var direction: Vector3 = tank.call("muzzle_global_direction")
	var end: Vector3 = presentation.call("_aim_line_end", origin, direction)
	for half_angle: float in [1.0, 2.5, 1.0]:
		tank.set("current_spread_degrees", half_angle)
		var terminal_frame: Node3D = _refresh_spread(presentation, origin, direction, end, float(tank.get("current_spread_degrees")))
		var frame_count: int = display.frames.size()
		for index in range(frame_count):
			var frame: Node3D = display.frames[index]
			var distance := origin.distance_to(end) * float(index + 1) / float(frame_count)
			distance = maxf(distance - float(presentation.get("spread_frames_inset_meters")), 0.0)
			if distance <= float(presentation.get("aim_line_near_tank_hidden_distance")):
				if frame.visible:
					return false
				continue
			if index == frame_count - 1 and bool(presentation.call("_resolve_aim_ray", origin, direction)["is_ground"]):
				if display.frame_styles[index] != 1:
					push_error("Ground reticle must keep the third-largest design while its radius changes")
					return false
				var toward_tank := tank.global_position - frame.global_position
				toward_tank.y = 0.0
				if absf(frame.global_position.x - end.x) > 0.001 or absf(frame.global_position.z - end.z) > 0.001 \
						or absf(frame.global_position.y - 0.03) > 0.001 \
						or frame.global_basis.z.normalized().dot(Vector3.UP) < 0.999 \
						or frame.global_basis.y.normalized().dot(toward_tank.normalized()) < 0.999 \
						or not is_equal_approx(frame.global_basis.x.length(), distance * tan(deg_to_rad(half_angle))):
					push_error("Terminal reticle must lie on ground at the aim point, with its top facing the tank")
					return false
				continue
			if not frame.global_position.is_equal_approx(origin + direction * distance) \
					or absf(frame.global_basis.z.normalized().dot(direction)) < 0.999 \
					or not is_equal_approx(frame.global_basis.x.length(), distance * tan(deg_to_rad(half_angle))):
				push_error("Dynamic spread frames must follow the actual muzzle axis and distance-scaled spread")
				return false
		var expected_markers := 0
		for frame: Node3D in display.frames:
			if frame.visible and frame != terminal_frame:
				expected_markers += 1
		if presentation.get("slice_ground_markers").markers.size() != expected_markers:
			push_error("Terminal ground reticle must not also receive a drop line or triangle")
			return false
	if not _validate_spread_frame_styles(display, presentation):
		return false
	presentation.set("show_spread_frames", false)
	_refresh_spread(presentation, origin, direction, end, float(tank.get("current_spread_degrees")))
	if display.visible:
		push_error("Spread frames switch must hide all four layers")
		return false
	presentation.set("show_spread_frames", true)
	tank.set("current_spread_degrees", saved_spread)
	_refresh_spread(presentation, origin, direction, end, float(tank.get("current_spread_degrees")))
	return true


static func _validate_slice_ground_markers(presentation: Node) -> bool:
	var display: Node3D = presentation.get("slice_ground_markers")
	var slices: Node3D = presentation.get("spread_frames")
	if display == null or slices == null:
		push_error("Slice ground markers must be connected to AimPresentation")
		return false
	var origin := Vector3(0, 3, 0)
	var end := Vector3(0, 3, -100)
	slices.update_frames(origin, end, 2.0, true, Color.WHITE, 0.08, 3.0, 1.0, 2.0, 4.0, 15.0, 25.0)
	presentation.call("_update_slice_ground_markers", Vector3.FORWARD, null)
	if display.markers.size() != slices.frames.size() or not display.visible:
		push_error("Each visible above-ground slice must get one ground marker")
		return false
	for index in range(display.markers.size()):
		var marker: Node3D = display.markers[index]
		var center: Vector3 = slices.frames[index].global_position
		var line := marker.get_node("DropLine") as MeshInstance3D
		var a := line.global_position - line.global_basis.y * 0.5
		var b := line.global_position + line.global_basis.y * 0.5
		var ground := Vector3(center.x, 0, center.z)
		if not ((a.is_equal_approx(center) and b.is_equal_approx(ground)) or (b.is_equal_approx(center) and a.is_equal_approx(ground))):
			push_error("Slice drop line must connect its center vertically to actual ground")
			return false
		var triangle_center := Vector3.ZERO
		var expected_tip := ground + Vector3.UP * 0.03 + Vector3.FORWARD * float(presentation.get("slice_ground_triangle_size"))
		var found_tip := false
		for edge_index in range(3):
			var edge := marker.get_node("TriangleEdge%d" % edge_index) as MeshInstance3D
			triangle_center += edge.global_position / 3.0
			for point: Vector3 in [edge.global_position - edge.global_basis.y * 0.5, edge.global_position + edge.global_basis.y * 0.5]:
				if absf(point.y - 0.03) > 0.001:
					push_error("Triangle must lie on the ground rather than face the camera")
					return false
				found_tip = found_tip or point.is_equal_approx(expected_tip)
		if not triangle_center.is_equal_approx(ground + Vector3.UP * 0.03) or not found_tip:
			push_error("Triangle must be centered at the landing point and point along aim")
			return false
	if float(presentation.get("slice_ground_triangle_min_height")) != 1.0:
		push_error("Slice triangle minimum height must default to 1m")
		return false
	for height: float in [0.99, 1.0, 1.01, 0.99, 1.0]:
		var low_origin := Vector3(0, height, 0)
		slices.update_frames(low_origin, low_origin + Vector3.FORWARD * 20.0, 2.0, true, Color.WHITE, 0.08, 3.0, 1.0, 2.0, 4.0, 15.0, 25.0)
		presentation.call("_update_slice_ground_markers", Vector3.FORWARD, null)
		if display.markers.size() != 1 or not slices.frames[0].visible:
			push_error("Height threshold must preserve the marker and slice")
			return false
		var low_marker: Node3D = display.markers[0]
		if not (low_marker.get_node("DropLine") as MeshInstance3D).visible:
			push_error("Triangle threshold must not hide the vertical line")
			return false
		for edge_index in range(3):
			if (low_marker.get_node("TriangleEdge%d" % edge_index) as MeshInstance3D).visible != (height >= 1.0):
				push_error("Triangle must hide below 1m and recover at or above the threshold")
				return false
	presentation.set("slice_ground_triangle_min_height", 2.0)
	presentation.call("_update_slice_ground_markers", Vector3.FORWARD, null)
	if (display.markers[0].get_node("TriangleEdge0") as MeshInstance3D).visible:
		push_error("Inspector triangle height threshold must affect rendering")
		return false
	presentation.set("slice_ground_triangle_min_height", 1.0)
	presentation.set("show_slice_ground_markers", false)
	presentation.call("_update_slice_ground_markers", Vector3.FORWARD, null)
	if display.visible:
		return false
	presentation.set("show_slice_ground_markers", true)
	# 地下、地圖外、再回地面上：標示不可留下殘影，也必須能恢復。
	for sample_origin: Vector3 in [Vector3(0, -1, 0), Vector3(5000, 3, 5000), Vector3(0, 3, 0)]:
		slices.update_frames(sample_origin, sample_origin + Vector3.FORWARD * 20.0, 2.0, true, Color.WHITE, 0.08, 3.0, 1.0, 2.0, 4.0, 15.0, 25.0)
		presentation.call("_update_slice_ground_markers", Vector3.FORWARD, null)
		var should_show := sample_origin == Vector3(0, 3, 0)
		if display.visible != should_show or display.markers.size() != (1 if should_show else 0):
			push_error("Markers must shrink with slices, hide without ground and recover on valid ground")
			return false
	slices.update_frames(origin, end, 2.0, false, Color.WHITE, 0.08, 3.0, 1.0, 2.0, 4.0)
	presentation.call("_update_slice_ground_markers", Vector3.FORWARD, null)
	if display.visible:
		push_error("Hidden slices must not leave ground markers")
		return false
	return true


static func _validate_ground_spread_outline(tank: Node3D, presentation: Node) -> bool:
	var display: Node3D = presentation.get("ground_spread_outline")
	if display == null:
		push_error("Ground spread outline must be connected to AimPresentation")
		return false
	var geometry: Script = display.get_script()
	var origin := Vector3(0, 3, 0)
	var end := Vector3(0, 3, -100)
	var corners: PackedVector3Array = geometry.calculate_corners(origin, end, 3.0, Vector3.ZERO, Vector3.UP)
	if corners.size() != 4:
		push_error("A cone intersecting the ground must produce four trapezoid corners")
		return false
	var max_width := 0.0
	for point in corners:
		if not point.is_finite() or absf(point.y) > 0.001 or point.z > -56.0 or point.z < -100.01:
			push_error("Outline corners must stay on the ground within the finite cone contact depth")
			return false
		max_width = maxf(max_width, absf(point.x))
	var wider: PackedVector3Array = geometry.calculate_corners(origin, end, 4.0, Vector3.ZERO, Vector3.UP)
	var wider_width := 0.0
	for point in wider:
		wider_width = maxf(wider_width, absf(point.x))
	if wider_width <= max_width:
		push_error("Ground outline must widen when the actual spread increases")
		return false
	var rotated: PackedVector3Array = geometry.calculate_corners(origin, Vector3(-100, 3, 0), 3.0, Vector3.ZERO, Vector3.UP)
	if rotated.size() != 4:
		return false
	for index in range(4):
		if not rotated[index].is_equal_approx(corners[index].rotated(Vector3.UP, PI * 0.5)):
			push_error("Ground outline must rotate with the barrel rather than face the camera")
			return false
	if not geometry.calculate_corners(origin, Vector3(0, 3, -20), 1.0, Vector3.ZERO, Vector3.UP).is_empty() \
			or not geometry.calculate_corners(origin, end, 0.0, Vector3.ZERO, Vector3.UP).is_empty():
		push_error("No contact and zero spread must not produce a ground outline")
		return false
	var saved_spread := float(tank.get("current_spread_degrees"))
	var saved_cone := bool(presentation.get("show_spread_cone"))
	presentation.set("show_spread_cone", false)
	tank.set("current_spread_degrees", 3.0)
	presentation.call("_update_ground_spread_outline", origin, end, float(tank.get("current_spread_degrees")), presentation.call("_sample_ground", origin, end) as Dictionary)
	if not display.visible:
		push_error("Ground outline must work with the blue cone disabled using the scene ground")
		return false
	var outline_material: ShaderMaterial = display.get("_material")
	var outline_color: Color = outline_material.get_shader_parameter("line_color")
	if not is_equal_approx(outline_color.a, 0.4) or float(outline_material.get_shader_parameter("gap_length")) != 0.0:
		push_error("Ground outline must use a solid line with alpha 0.4")
		return false
	presentation.set("show_ground_spread_outline", false)
	presentation.call("_update_ground_spread_outline", origin, end, float(tank.get("current_spread_degrees")), presentation.call("_sample_ground", origin, end) as Dictionary)
	if display.visible:
		push_error("Independent ground outline toggle must hide its rendering")
		return false
	presentation.set("show_ground_spread_outline", true)
	presentation.call("_update_ground_spread_outline", origin, end, float(tank.get("current_spread_degrees")), presentation.call("_sample_ground", origin, end) as Dictionary)
	if not display.visible:
		push_error("Ground outline must reappear when its toggle is enabled again")
		return false
	presentation.call("_update_ground_spread_outline", origin, Vector3(0, 3, -20), float(tank.get("current_spread_degrees")), presentation.call("_sample_ground", origin, Vector3(0, 3, -20)) as Dictionary)
	if display.visible:
		push_error("Ground outline must disappear when the cone no longer touches ground")
		return false
	presentation.call("_update_ground_spread_outline", origin, end, float(tank.get("current_spread_degrees")), presentation.call("_sample_ground", origin, end) as Dictionary)
	if not display.visible:
		push_error("Ground outline must reappear when aiming back at the ground")
		return false
	tank.set("current_spread_degrees", saved_spread)
	presentation.set("show_spread_cone", saved_cone)
	return true


static func _validate_dynamic_spread_frame_count(existing_display: Node3D, presentation: Node) -> bool:
	# 使用獨立容器從初始四片驗證，避免前面場景更新的片數污染測試。
	var display: Node3D = existing_display.get_script().new()
	presentation.add_child(display)
	var origin := Vector3.ZERO
	var forward := Vector3.FORWARD
	var thresholds := [
		float(presentation.get("spread_frames_style_0_max_radius_meters")),
		float(presentation.get("spread_frames_style_1_max_radius_meters")),
		float(presentation.get("spread_frames_style_2_max_radius_meters")),
	]
	var half_angle := 2.0
	display.update_frames(origin, forward * 100.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	if display.frames.size() != 4:
		push_error("100m must retain four spread frames at default spacing")
		return false
	display.update_frames(origin, forward * 104.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	if display.frames.size() != 5 or not is_equal_approx(display.frames[0].global_position.distance_to(origin), 20.8) \
			or not display.frames[4].global_position.is_equal_approx(forward * 104.0):
		push_error("104m must add a fifth frame with evenly divided positions ending at the target")
		return false
	display.update_frames(origin, forward * 50.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	if display.frames.size() != 5:
		push_error("50m must retain five frames at the minimum spacing")
		return false
	display.update_frames(origin, forward * 49.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	if display.frames.size() != 4:
		push_error("49m must remove a frame below the minimum spacing")
		return false
	display.update_frames(origin, forward * 100.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	if display.frames.size() != 4:
		push_error("100m must remain at four frames after shrinking")
		return false
	display.update_frames(origin, forward * 5.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	if display.frames.size() != 1:
		push_error("Short distances must retain exactly one spread frame")
		return false
	display.update_frames(origin, forward * 180.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	if display.frames.size() != 8:
		push_error("A large distance increase must add all required frames in one update")
		return false
	var frame_identity: Array[Node3D] = display.frames.duplicate()
	display.update_frames(origin, forward * 180.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	for index in range(display.frames.size()):
		if display.frames[index] != frame_identity[index]:
			push_error("Unchanged distance must preserve spread frame node identity")
			return false
	display.update_frames(origin, forward * 100.0, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 5.0, 12.5)
	if display.frames.size() != 8:
		push_error("Inspector spacing overrides must set the dynamic frame count")
		return false
	# 新預設15/25：驗證上下門檻，以及26m沒有合法整數片數時保持兩片。
	var spacing_min := float(presentation.get("spread_frames_min_spacing_meters"))
	var spacing_max := float(presentation.get("spread_frames_max_spacing_meters"))
	if spacing_min != 15.0 or spacing_max != 25.0:
		push_error("Gameplay spacing defaults must be 15m and 25m")
		return false
	for sample: Vector2 in [Vector2(100, 6), Vector2(90, 6), Vector2(89, 5), Vector2(125, 5), Vector2(126, 6), Vector2(26, 2), Vector2(26, 2), Vector2(25, 1), Vector2(26, 2), Vector2(26, 2)]:
		display.update_frames(origin, forward * sample.x, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], spacing_min, spacing_max)
		if display.frames.size() != int(sample.y):
			push_error("15m/25m spacing must honor limits without toggling the frame count")
			return false
	# 整串退縮10m，片數與彼此間距不變，半徑依新位置更新。
	if float(presentation.get("spread_frames_inset_meters")) != 0.0:
		return false
	display.update_frames(origin, forward * 100.0, half_angle, true, Color.WHITE, 0.08, 3.0, thresholds[0], thresholds[1], thresholds[2], 15.0, 25.0, 0.0)
	var original_positions := PackedVector3Array()
	for frame: Node3D in display.frames:
		original_positions.append(frame.global_position)
	display.update_frames(origin, forward * 100.0, half_angle, true, Color.WHITE, 0.08, 3.0, thresholds[0], thresholds[1], thresholds[2], 15.0, 25.0, 10.0)
	if display.frames.size() != original_positions.size():
		return false
	for index in range(original_positions.size()):
		var expected := original_positions[index] - forward * 10.0
		var frame: Node3D = display.frames[index]
		if not frame.global_position.is_equal_approx(expected) or not is_equal_approx(frame.global_basis.x.length(), origin.distance_to(expected) * tan(deg_to_rad(half_angle))):
			push_error("All slices must move 10m toward the muzzle and retain correct spread radius")
			return false
	display.update_frames(origin, forward * 5.0, half_angle, true, Color.WHITE, 0.08, 3.0, thresholds[0], thresholds[1], thresholds[2], 15.0, 25.0, 10.0)
	if display.frames.size() != 1 or display.frames[0].visible:
		push_error("A last slice inset past the muzzle must hide rather than move behind the tank")
		return false
	return true


static func _validate_spread_frame_styles(display: Node3D, presentation: Node) -> bool:
	var origin := Vector3.ZERO
	var end := Vector3.FORWARD * 4.0
	var thresholds := [
		float(presentation.get("spread_frames_style_0_max_radius_meters")),
		float(presentation.get("spread_frames_style_1_max_radius_meters")),
		float(presentation.get("spread_frames_style_2_max_radius_meters")),
	]
	for threshold_index in range(thresholds.size()):
		var threshold: float = thresholds[threshold_index]
		var expected_style := threshold_index
		for radius in [threshold - 0.01, threshold, threshold + 0.01]:
			var half_angle := rad_to_deg(atan(radius / 4.0))
			display.update_frames(origin, end, half_angle, true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
			var expected := expected_style if radius <= threshold else expected_style + 1
			var last_index: int = display.frame_styles.size() - 1
			if display.frame_styles[last_index] != expected:
				push_error("Spread frame style thresholds must select the expected style before, at, and after each boundary")
				return false
	var expanding_radius: float = thresholds[0] + 0.01
	display.update_frames(origin, end, rad_to_deg(atan(expanding_radius / 4.0)), true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	var last_index: int = display.frame_styles.size() - 1
	if display.frame_styles[last_index] != 1:
		push_error("A frame must change to the wider-radius style as its own radius grows")
		return false
	display.update_frames(origin, end, rad_to_deg(atan((thresholds[0] - 0.01) / 4.0)), true, Color.WHITE, 0.08, 0.0, thresholds[0], thresholds[1], thresholds[2], 10.0, 25.0)
	last_index = display.frame_styles.size() - 1
	if display.frame_styles[last_index] != 0:
		push_error("A frame must return to the narrower-radius style as its own radius shrinks")
		return false
	var saved_threshold := float(presentation.get("spread_frames_style_0_max_radius_meters"))
	presentation.set("spread_frames_style_0_max_radius_meters", 0.75)
	display.update_frames(origin, end, rad_to_deg(atan(0.6 / 4.0)), true, Color.WHITE, 0.08, 0.0, float(presentation.get("spread_frames_style_0_max_radius_meters")), thresholds[1], thresholds[2], 10.0, 25.0)
	last_index = display.frame_styles.size() - 1
	if display.frame_styles[last_index] != 0:
		push_error("Adjusting the Inspector radius threshold must change the selected spread frame style")
		return false
	presentation.set("spread_frames_style_0_max_radius_meters", saved_threshold)
	return true
