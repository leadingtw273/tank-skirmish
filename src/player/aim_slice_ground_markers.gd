## 將已確認接地的瞄準切片畫成垂線與空心方向三角形；不參與物理、相機或射擊。
extends Node3D

const EPSILON := 0.0001
const GROUND_OFFSET := 0.03
const SQRT_THREE_OVER_TWO := 0.8660254

var markers: Array[Node3D] = []

var _material: StandardMaterial3D
var _stroke_mesh: CylinderMesh


## 呼叫端負責過濾有效接地樣本；這裡只將其轉成世界座標輔助標記。
func update_markers(samples: Array[Dictionary], forward: Vector3, enabled: bool, color: Color, line_width: float, triangle_size: float, triangle_min_height: float = 1.0) -> void:
	_ensure_resources()
	_adjust_marker_count(samples.size())
	visible = enabled and not samples.is_empty()
	if not visible:
		return

	_material.albedo_color = color
	var safe_width := maxf(line_width, EPSILON)
	var safe_triangle_size := maxf(triangle_size, EPSILON)
	for index in range(samples.size()):
		var sample: Dictionary = samples[index]
		var center: Vector3 = sample["center"] as Vector3
		var ground: Vector3 = sample["ground"] as Vector3
		var normal: Vector3 = sample["normal"] as Vector3
		_update_marker(markers[index], center, ground, normal, forward, safe_width, safe_triangle_size)
		# 高度取未加離地偏移的實際落點；每次更新皆重判，升高後會自動恢復。
		# 地面射線有浮點誤差，保留0.1mm容差讓等於門檻時穩定顯示。
		if center.y - ground.y + EPSILON < maxf(triangle_min_height, 0.0):
			for edge_index in range(3):
				(markers[index].get_node("TriangleEdge%d" % edge_index) as MeshInstance3D).visible = false


func _ensure_resources() -> void:
	if _stroke_mesh != null:
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = Material.RENDER_PRIORITY_MAX
	_stroke_mesh = CylinderMesh.new()
	_stroke_mesh.top_radius = 1.0
	_stroke_mesh.bottom_radius = 1.0
	_stroke_mesh.height = 1.0
	_stroke_mesh.radial_segments = 8


func _adjust_marker_count(desired_count: int) -> void:
	while markers.size() < desired_count:
		_add_marker()
	while markers.size() > desired_count:
		_remove_last_marker()


func _add_marker() -> void:
	var marker := Node3D.new()
	marker.name = "AimSliceGroundMarker%d" % (markers.size() + 1)
	## 不繼承外層任何切片半徑縮放；子線段座標直接就是世界座標。
	marker.top_level = true
	marker.global_transform = Transform3D.IDENTITY
	add_child(marker)
	markers.append(marker)
	_add_stroke(marker, "DropLine")
	_add_stroke(marker, "TriangleEdge0")
	_add_stroke(marker, "TriangleEdge1")
	_add_stroke(marker, "TriangleEdge2")


func _remove_last_marker() -> void:
	var marker: Node3D = markers.pop_back()
	remove_child(marker)
	marker.queue_free()


func _add_stroke(marker: Node3D, stroke_name: String) -> void:
	var stroke := MeshInstance3D.new()
	stroke.name = stroke_name
	stroke.mesh = _stroke_mesh
	stroke.material_override = _material
	stroke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(stroke)


func _update_marker(marker: Node3D, center: Vector3, ground: Vector3, normal: Vector3, forward: Vector3, width: float, triangle_size: float) -> void:
	marker.global_transform = Transform3D.IDENTITY
	var drop_line := marker.get_node("DropLine") as MeshInstance3D
	_set_stroke(drop_line, center, ground, width)

	var surface_normal := normal.normalized()
	var direction := forward - surface_normal * forward.dot(surface_normal)
	if direction.length_squared() <= EPSILON * EPSILON:
		var fallback := Vector3.UP if absf(surface_normal.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
		direction = fallback - surface_normal * fallback.dot(surface_normal)
	direction = direction.normalized()
	var right := surface_normal.cross(direction).normalized()
	var triangle_center := ground + surface_normal * GROUND_OFFSET
	var tip := triangle_center + direction * triangle_size
	var back_center := triangle_center - direction * (triangle_size * 0.5)
	var back_left := back_center + right * (triangle_size * SQRT_THREE_OVER_TWO)
	var back_right := back_center - right * (triangle_size * SQRT_THREE_OVER_TWO)
	_set_stroke(marker.get_node("TriangleEdge0") as MeshInstance3D, tip, back_left, width)
	_set_stroke(marker.get_node("TriangleEdge1") as MeshInstance3D, back_left, back_right, width)
	_set_stroke(marker.get_node("TriangleEdge2") as MeshInstance3D, back_right, tip, width)


func _set_stroke(stroke: MeshInstance3D, start: Vector3, end: Vector3, width: float) -> void:
	var offset := end - start
	var length := offset.length()
	stroke.visible = length > EPSILON
	if not stroke.visible:
		return
	var axis := offset / length
	stroke.position = (start + end) * 0.5
	stroke.basis = _basis_with_y(axis)
	stroke.scale = Vector3(width * 0.5, length, width * 0.5)


func _basis_with_y(axis: Vector3) -> Basis:
	var reference := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var local_x := axis.cross(reference).normalized()
	var local_z := local_x.cross(axis).normalized()
	return Basis(local_x, axis, local_z)
