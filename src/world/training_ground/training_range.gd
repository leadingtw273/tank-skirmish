@tool
extends Node3D
class_name TrainingRange

signal spread_preview_toggle_requested

## 主靶寬度（公尺）；格線會依此尺寸置中排列。
@export_range(2.0, 20.0, 1.0) var target_width_m := 10.0:
	set(value):
		target_width_m = value
		_rebuild_authored_visuals()

## 主靶高度（公尺）；靶心固定在本場景本地 y=5m。
@export_range(2.0, 20.0, 1.0) var target_height_m := 10.0:
	set(value):
		target_height_m = value
		_rebuild_authored_visuals()

## 命中圓點半徑（公尺），僅影響視覺，不建立碰撞體。
@export_range(0.02, 0.5, 0.01) var marker_radius_m := 0.12

@onready var main_target: StaticBody3D = $MainTarget
@onready var clear_target: StaticBody3D = $ClearTarget
@onready var spread_toggle_target: StaticBody3D = $SpreadToggleTarget
@onready var markers: Node3D = $Markers
@onready var target_grid: Node3D = $MainTarget/TargetGrid
@onready var range_markings: Node3D = $RangeMarkings


func _ready() -> void:
	_rebuild_authored_visuals()


## 消費 CombatRuntime 的有效碰撞事件：主靶累積圓點，清除靶刪除所有圓點。
func consume_impact(event: ImpactEvent) -> void:
	if event == null:
		return
	if event.collider == clear_target:
		clear_markers()
	elif event.collider == spread_toggle_target:
		spread_preview_toggle_requested.emit()
	elif event.collider == main_target:
		_add_marker(event.position, event.normal)


## 清除目前遊戲記憶體中的命中圓點，不會改變任一靶子的碰撞或幾何。
func clear_markers() -> void:
	for marker: Node in markers.get_children():
		marker.free()


## 供整合 smoke 驗證目前保留的命中圓點數量。
func get_marker_count() -> int:
	return markers.get_child_count()


func _add_marker(world_position: Vector3, world_normal: Vector3) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "ImpactMarker"
	var mesh := SphereMesh.new()
	mesh.radius = marker_radius_m
	mesh.height = marker_radius_m * 0.04
	mesh.radial_segments = 16
	mesh.rings = 2
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	var local_normal := global_transform.basis.inverse() * world_normal.normalized()
	marker.position = to_local(world_position) + local_normal * 0.025
	marker.basis = Basis(Quaternion(Vector3.UP, local_normal))
	markers.add_child(marker)


func _rebuild_authored_visuals() -> void:
	if not is_node_ready():
		return
	var target_visual := get_node_or_null("MainTarget/TargetVisual") as MeshInstance3D
	var target_collision := get_node_or_null("MainTarget/CollisionShape3D") as CollisionShape3D
	if target_visual == null or target_collision == null:
		return
	var target_mesh := target_visual.mesh as BoxMesh
	var target_shape := target_collision.shape as BoxShape3D
	if target_mesh != null:
		target_mesh.size = Vector3(target_width_m, target_height_m, 0.2)
	if target_shape != null:
		target_shape.size = Vector3(target_width_m, target_height_m, 0.2)
	_rebuild_target_grid()
	_rebuild_range_markings()


func _rebuild_target_grid() -> void:
	if target_grid == null:
		return
	_clear_children(target_grid)
	var half_width := target_width_m * 0.5
	var half_height := target_height_m * 0.5
	for meter in range(int(-half_width), int(half_width) + 1):
		_add_box_line(target_grid, Vector3(meter, 0.0, 0.111), Vector3(0.05, target_height_m, 0.05), meter == 0)
	for meter in range(int(-half_height), int(half_height) + 1):
		_add_box_line(target_grid, Vector3(0.0, meter, 0.111), Vector3(target_width_m, 0.05, 0.05), meter == 0)


func _rebuild_range_markings() -> void:
	if range_markings == null:
		return
	_clear_children(range_markings)
	for distance in [25, 50, 75, 100]:
		var line := _add_box_line(range_markings, Vector3(0.0, 0.025, distance), Vector3(10.0, 0.03, 0.3), false)
		line.name = "DistanceLine%dm" % distance
		var label := Label3D.new()
		label.name = "DistanceLabel%dm" % distance
		label.text = "%dm" % distance
		label.font_size = 64
		label.pixel_size = 0.035
		label.outline_size = 8
		label.position = Vector3(-8.0, 0.04, distance)
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		range_markings.add_child(label)


func _add_box_line(parent: Node3D, line_position: Vector3, line_size: Vector3, center_line: bool) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = line_size
	line.mesh = mesh
	line.position = line_position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.12, 0.08, 1.0) if center_line else Color(0.08, 0.08, 0.08, 1.0)
	## 只有主靶黑色格線半透明；紅色靶心與地面距離線維持不透明。
	if parent == target_grid and not center_line:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = material
	parent.add_child(line)
	return line


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.free()
