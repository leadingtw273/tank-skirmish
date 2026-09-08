## 沿實際砲口方向排列動態數量的擴散截面框；只繪圖，不決定彈道。
extends Node3D

var frames: Array[Node3D] = []
var _segments: Array = []
var _dots: Array = []
## 每層目前的草圖樣式，供更新時避免不必要的幾何重建與 smoke 驗證。
var frame_styles: Array[int] = []
var _material := StandardMaterial3D.new()
var _stroke_mesh := CylinderMesh.new()


## 先建立四個容器；有效更新會依距離增減，草圖僅在半徑跨越樣式門檻時重建。
func initialize() -> void:
	if not frames.is_empty():
		return
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = Material.RENDER_PRIORITY_MAX
	_stroke_mesh.top_radius = 1.0
	_stroke_mesh.bottom_radius = 1.0
	_stroke_mesh.height = 1.0
	_stroke_mesh.radial_segments = 6
	for unused_index in range(4):
		_add_frame()
	visible = false


## 所有框使用同一個擴散半角；距離越遠，截面半徑越大。
func update_frames(origin: Vector3, end: Vector3, half_angle_degrees: float, enabled: bool, color: Color, line_width: float, near_hidden_distance: float, style_0_max_radius_meters: float, style_1_max_radius_meters: float, style_2_max_radius_meters: float, min_spacing_meters := 10.0, max_spacing_meters := 25.0, inset_meters: float = 0.0, terminal_style: int = -1) -> void:
	initialize()
	var length := origin.distance_to(end)
	visible = enabled and length > maxf(near_hidden_distance, 0.05) and half_angle_degrees > 0.0
	if not visible:
		return
	_adjust_frame_count(length, min_spacing_meters, max_spacing_meters)
	_material.albedo_color = color
	var forward := (end - origin) / length
	var reference_up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var right := forward.cross(reference_up).normalized()
	var up := right.cross(forward).normalized()
	var orientation := Basis(right, up, -forward)
	var tangent := tan(deg_to_rad(clampf(half_angle_degrees, 0.0, 89.0)))
	var width := maxf(line_width, 0.002)
	var frame_count := frames.size()
	for index in range(frame_count):
		var distance := length * float(index + 1) / float(frame_count)
		# 整串切片一起往砲口平移，保留彼此間距；退到近端的切片會隱藏。
		distance = maxf(distance - maxf(inset_meters, 0.0), 0.0)
		var radius := distance * tangent
		var frame := frames[index]
		frame.visible = distance > near_hidden_distance and radius > 0.001
		if not frame.visible:
			continue
		var style := _style_for_radius(radius, style_0_max_radius_meters, style_1_max_radius_meters, style_2_max_radius_meters)
		# 貼地末片可固定圖樣；半徑仍依擴散更新，中途切片繼續依門檻換款。
		if index == frame_count - 1 and terminal_style >= 0:
			style = clampi(terminal_style, 0, 3)
		if frame_styles[index] != style:
			_rebuild_frame_geometry(index, style)
		frame.global_transform = Transform3D(orientation.scaled(Vector3.ONE * radius), origin + forward * distance)
		## 抵銷截面縮放對線寬的影響，遠近切片維持相同世界線寬。
		for segment: Dictionary in _segments[index]:
			var stroke := segment["node"] as MeshInstance3D
			stroke.scale = Vector3(width * 0.5 / radius, segment["length"], width * 0.5 / radius)
		var dot := _dots[index] as MeshInstance3D
		if dot != null:
			dot.scale = Vector3.ONE * width / radius


func _adjust_frame_count(length: float, min_spacing_meters: float, max_spacing_meters: float) -> void:
	var safe_min_spacing := maxf(min_spacing_meters, 0.001)
	var safe_max_spacing := maxf(max_spacing_meters, safe_min_spacing)
	var desired_count := frames.size()
	if length / float(desired_count) > safe_max_spacing:
		desired_count = maxi(ceili(length / safe_max_spacing), 1)
	elif length / float(desired_count) < safe_min_spacing:
		## 若減片會超過最大間距，保留必要片數，避免兩種片數之間來回跳動。
		desired_count = maxi(maxi(floori(length / safe_min_spacing), ceili(length / safe_max_spacing)), 1)
	while frames.size() < desired_count:
		_add_frame()
	while frames.size() > desired_count:
		_remove_last_frame()


func _add_frame() -> void:
	var frame := Node3D.new()
	frame.name = "SpreadFrame%d" % (frames.size() + 1)
	add_child(frame)
	frames.append(frame)
	_segments.append([])
	_dots.append(null)
	frame_styles.append(-1)


func _remove_last_frame() -> void:
	var frame: Node3D = frames.pop_back()
	remove_child(frame)
	frame.queue_free()
	_segments.pop_back()
	_dots.pop_back()
	frame_styles.pop_back()


func _style_for_radius(radius: float, style_0_max_radius_meters: float, style_1_max_radius_meters: float, style_2_max_radius_meters: float) -> int:
	if radius <= style_0_max_radius_meters:
		return 0
	if radius <= style_1_max_radius_meters:
		return 1
	if radius <= style_2_max_radius_meters:
		return 2
	return 3


func _rebuild_frame_geometry(index: int, style: int) -> void:
	for child in frames[index].get_children():
		frames[index].remove_child(child)
		child.queue_free()
	_segments[index].clear()
	_dots[index] = null
	var left := PackedVector2Array([Vector2(-0.58, 0.66), Vector2(-0.866, 0.5), Vector2(-0.866, -0.5), Vector2(-0.58, -0.66)])
	if style == 0:
		_add_path(index, PackedVector2Array([Vector2(0, 1), Vector2(0.866, 0.5), Vector2(0.866, -0.5), Vector2(0, -1), Vector2(-0.866, -0.5), Vector2(-0.866, 0.5), Vector2(0, 1)]))
	else:
		_add_path(index, left)
		var right := PackedVector2Array()
		for point in left:
			right.append(Vector2(-point.x, point.y))
		_add_path(index, right)
		var cap_width := 0.32 if style == 1 else 0.2
		_add_path(index, PackedVector2Array([Vector2(-cap_width, 0.84), Vector2(0, 1), Vector2(cap_width, 0.84)]))
		_add_path(index, PackedVector2Array([Vector2(-cap_width, -0.84), Vector2(0, -1), Vector2(cap_width, -0.84)]))
		var tick_length := 0.15 if style < 3 else 0.28
		_add_stroke(index, Vector2(-0.866, 0), Vector2(-0.866 + tick_length, 0))
		_add_stroke(index, Vector2(0.866, 0), Vector2(0.866 - tick_length, 0))
		if style >= 2:
			_add_stroke(index, Vector2(0, 1), Vector2(0, 0.68))
			_add_stroke(index, Vector2(0, -1), Vector2(0, -0.68))
			var cross_size := 0.08 if style == 2 else 0.2
			_add_stroke(index, Vector2(-cross_size, 0), Vector2(cross_size, 0))
			_add_stroke(index, Vector2(0, -cross_size), Vector2(0, cross_size))
	if style < 2:
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		dot.mesh = sphere
		dot.material_override = _material
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frames[index].add_child(dot)
		_dots[index] = dot
	frame_styles[index] = style


func _add_path(index: int, points: PackedVector2Array) -> void:
	## 相鄰點接成折線；分開呼叫的路徑之間保留草圖缺口。
	for point_index in range(points.size() - 1):
		_add_stroke(index, points[point_index], points[point_index + 1])


func _add_stroke(index: int, start: Vector2, end: Vector2) -> void:
	## 圓柱線段的本地Y軸朝向線段，框本身則位於本地XY平面。
	var stroke := MeshInstance3D.new()
	stroke.mesh = _stroke_mesh
	stroke.material_override = _material
	stroke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var offset := Vector3(end.x - start.x, end.y - start.y, 0)
	var axis := offset.normalized()
	stroke.basis = Basis(axis.cross(Vector3.BACK), axis, Vector3.BACK)
	stroke.position = Vector3((start.x + end.x) * 0.5, (start.y + end.y) * 0.5, 0)
	frames[index].add_child(stroke)
	_segments[index].append({"node": stroke, "length": offset.length()})
