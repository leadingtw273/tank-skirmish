## 將有限瞄準圓錐與平面地面相交的近似範圍畫成深色虛線梯形；不參與射擊或物理。
extends Node3D

const RING_COUNT := 128
const EPSILON := 0.0001
const MIN_HALF_WIDTH := 0.001
const GROUND_OFFSET := 0.03

var corners := PackedVector3Array()

var _outline_mesh: ImmediateMesh
var _outline_instance: MeshInstance3D
var _material: ShaderMaterial


## 以已解析的地面平面更新呈現；呼叫端負責提供地面位置與法線。
func update_outline(origin: Vector3, end: Vector3, half_angle_degrees: float, ground_position: Vector3, ground_normal: Vector3, enabled: bool, color: Color, line_width: float, dash_length: float, gap_length: float) -> void:
	_ensure_mesh()
	corners = calculate_corners(origin, end, half_angle_degrees, ground_position, ground_normal)
	visible = enabled and corners.size() == 4
	if not enabled or corners.size() != 4:
		_outline_instance.visible = false
		return
	var safe_width := maxf(line_width, EPSILON)
	var safe_dash := maxf(dash_length, EPSILON)
	var safe_gap := maxf(gap_length, 0.0)
	_material.set_shader_parameter("line_color", color)
	_material.set_shader_parameter("dash_length", safe_dash)
	_material.set_shader_parameter("gap_length", safe_gap)
	_rebuild_mesh(corners, ground_normal.normalized(), safe_width)
	_outline_instance.visible = true


## 將有限圓錐在指定平面上的採樣交點包成梯形；無交界或退化時回傳空陣列。
static func calculate_corners(origin: Vector3, end: Vector3, half_angle_degrees: float, ground_position: Vector3, ground_normal: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	var path := end - origin
	var length := path.length()
	var normal_length := ground_normal.length()
	if length <= EPSILON or normal_length <= EPSILON or half_angle_degrees <= 0.0:
		return result
	var axis := path / length
	var normal := ground_normal / normal_length
	var longitudinal_raw := axis - normal * axis.dot(normal)
	if longitudinal_raw.length_squared() <= EPSILON * EPSILON:
		return result
	var longitudinal := longitudinal_raw.normalized()
	var lateral_raw := axis.cross(normal)
	if lateral_raw.length_squared() <= EPSILON * EPSILON:
		return result
	var lateral := lateral_raw.normalized()
	var ring_vertical := lateral.cross(axis).normalized()
	var vertical_denominator := normal.dot(ring_vertical)
	if absf(vertical_denominator) <= EPSILON:
		return result
	var tangent := tan(deg_to_rad(clampf(half_angle_degrees, 0.0, 89.0)))
	if tangent <= EPSILON:
		return result

	var sample_depths: Array[float] = []
	var sample_widths: Array[float] = []
	for ring_index in range(RING_COUNT):
		var distance := length * float(ring_index) / float(RING_COUNT - 1)
		var center := origin + axis * distance
		var radius := distance * tangent
		var vertical_offset := normal.dot(ground_position - center) / vertical_denominator
		var lateral_squared := radius * radius - vertical_offset * vertical_offset
		if lateral_squared < -EPSILON:
			continue
		var half_width := sqrt(maxf(lateral_squared, 0.0))
		var contact_center := center + ring_vertical * vertical_offset
		var depth := longitudinal.dot(contact_center - ground_position)
		if not sample_depths.is_empty() and absf(depth - sample_depths.back()) <= EPSILON:
			sample_widths[sample_widths.size() - 1] = maxf(sample_widths[sample_widths.size() - 1], half_width)
			continue
		sample_depths.append(depth)
		sample_widths.append(half_width)

	if sample_depths.size() < 2:
		return result
	var near_depth := sample_depths[0]
	var far_depth := sample_depths[sample_depths.size() - 1]
	var depth_span := far_depth - near_depth
	if depth_span <= EPSILON:
		return result
	var far_half_width := 0.0
	for sample_width: float in sample_widths:
		far_half_width = maxf(far_half_width, sample_width)
	if far_half_width <= EPSILON:
		return result
	var near_half_width := 0.0
	for sample_index in range(sample_depths.size()):
		var interpolation := (sample_depths[sample_index] - near_depth) / depth_span
		if interpolation >= 1.0 - EPSILON:
			continue
		var required_near_width := (sample_widths[sample_index] - far_half_width * interpolation) / maxf(1.0 - interpolation, EPSILON)
		near_half_width = maxf(near_half_width, required_near_width)
	near_half_width = clampf(maxf(near_half_width, MIN_HALF_WIDTH), 0.0, far_half_width)
	far_half_width = maxf(far_half_width, MIN_HALF_WIDTH)
	var near_center := ground_position + longitudinal * near_depth
	var far_center := ground_position + longitudinal * far_depth
	result.append(near_center - lateral * near_half_width)
	result.append(near_center + lateral * near_half_width)
	result.append(far_center + lateral * far_half_width)
	result.append(far_center - lateral * far_half_width)
	return result


func _ensure_mesh() -> void:
	if _outline_instance != null:
		return
	_outline_mesh = ImmediateMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://src/player/aim_ground_outline.gdshader")
	_outline_instance = MeshInstance3D.new()
	_outline_instance.name = "AimGroundOutline"
	_outline_instance.top_level = true
	_outline_instance.global_transform = Transform3D.IDENTITY
	_outline_instance.mesh = _outline_mesh
	_outline_instance.material_override = _material
	_outline_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_instance.visible = false
	add_child(_outline_instance)


func _rebuild_mesh(points: PackedVector3Array, normal: Vector3, line_width: float) -> void:
	_outline_mesh.clear_surfaces()
	_outline_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point_index in range(points.size()):
		var start := points[point_index] + normal * GROUND_OFFSET
		var end := points[(point_index + 1) % points.size()] + normal * GROUND_OFFSET
		var edge := end - start
		var edge_length := edge.length()
		if edge_length <= EPSILON:
			continue
		var side := normal.cross(edge / edge_length).normalized() * line_width * 0.5
		_outline_mesh.surface_set_uv(Vector2(0.0, 0.0))
		_outline_mesh.surface_add_vertex(start - side)
		_outline_mesh.surface_set_uv(Vector2(edge_length, 0.0))
		_outline_mesh.surface_add_vertex(end - side)
		_outline_mesh.surface_set_uv(Vector2(edge_length, 1.0))
		_outline_mesh.surface_add_vertex(end + side)
		_outline_mesh.surface_set_uv(Vector2(0.0, 0.0))
		_outline_mesh.surface_add_vertex(start - side)
		_outline_mesh.surface_set_uv(Vector2(edge_length, 1.0))
		_outline_mesh.surface_add_vertex(end + side)
		_outline_mesh.surface_set_uv(Vector2(0.0, 1.0))
		_outline_mesh.surface_add_vertex(start + side)
	_outline_mesh.surface_end()
