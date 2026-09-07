## 沿實際砲口方向排列四層擴散截面框；只繪圖，不決定彈道。
extends Node3D

var frames: Array[Node3D] = []
var _segments: Array = []
var _dots: Array[MeshInstance3D] = []
var _material := StandardMaterial3D.new()
var _stroke_mesh := CylinderMesh.new()


## 四種草圖只建立一次，更新時只移動與縮放既有節點。
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
	for index in range(4):
		var frame := Node3D.new()
		frame.name = "SpreadFrame%d" % (index + 1)
		add_child(frame)
		frames.append(frame)
		_segments.append([])
		var left := PackedVector2Array([Vector2(-0.58, 0.66), Vector2(-0.866, 0.5), Vector2(-0.866, -0.5), Vector2(-0.58, -0.66)])
		if index == 0:
			_add_path(index, PackedVector2Array([Vector2(0, 1), Vector2(0.866, 0.5), Vector2(0.866, -0.5), Vector2(0, -1), Vector2(-0.866, -0.5), Vector2(-0.866, 0.5), Vector2(0, 1)]))
		else:
			_add_path(index, left)
			var right := PackedVector2Array()
			for point in left:
				right.append(Vector2(-point.x, point.y))
			_add_path(index, right)
			var cap_width := 0.32 if index == 1 else 0.2
			_add_path(index, PackedVector2Array([Vector2(-cap_width, 0.84), Vector2(0, 1), Vector2(cap_width, 0.84)]))
			_add_path(index, PackedVector2Array([Vector2(-cap_width, -0.84), Vector2(0, -1), Vector2(cap_width, -0.84)]))
			var tick_length := 0.15 if index < 3 else 0.28
			_add_stroke(index, Vector2(-0.866, 0), Vector2(-0.866 + tick_length, 0))
			_add_stroke(index, Vector2(0.866, 0), Vector2(0.866 - tick_length, 0))
			if index >= 2:
				_add_stroke(index, Vector2(0, 1), Vector2(0, 0.68))
				_add_stroke(index, Vector2(0, -1), Vector2(0, -0.68))
				var cross_size := 0.08 if index == 2 else 0.2
				_add_stroke(index, Vector2(-cross_size, 0), Vector2(cross_size, 0))
				_add_stroke(index, Vector2(0, -cross_size), Vector2(0, cross_size))
		if index < 2:
			var dot := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 8
			sphere.rings = 4
			dot.mesh = sphere
			dot.material_override = _material
			dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			frame.add_child(dot)
			_dots.append(dot)
	visible = false


## 所有框使用同一個擴散半角；距離越遠，截面半徑越大。
func update_frames(origin: Vector3, end: Vector3, half_angle_degrees: float, enabled: bool, color: Color, line_width: float, near_hidden_distance: float) -> void:
	initialize()
	var length := origin.distance_to(end)
	visible = enabled and length > maxf(near_hidden_distance, 0.05) and half_angle_degrees > 0.0
	if not visible:
		return
	_material.albedo_color = color
	var forward := (end - origin) / length
	var reference_up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var right := forward.cross(reference_up).normalized()
	var up := right.cross(forward).normalized()
	var orientation := Basis(right, up, -forward)
	var tangent := tan(deg_to_rad(clampf(half_angle_degrees, 0.0, 89.0)))
	var width := maxf(line_width, 0.002)
	for index in range(4):
		var distance := length * float(index + 1) / 4.0
		var radius := distance * tangent
		var frame := frames[index]
		frame.visible = distance > near_hidden_distance and radius > 0.001
		if not frame.visible:
			continue
		frame.global_transform = Transform3D(orientation.scaled(Vector3.ONE * radius), origin + forward * distance)
		## 抵銷截面縮放對線寬的影響，遠近四層維持相同世界線寬。
		for segment: Dictionary in _segments[index]:
			var stroke := segment["node"] as MeshInstance3D
			stroke.scale = Vector3(width * 0.5 / radius, segment["length"], width * 0.5 / radius)
		if index < _dots.size():
			_dots[index].scale = Vector3.ONE * width / radius


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
