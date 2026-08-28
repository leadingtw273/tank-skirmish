## 以游標前視與滑鼠滾輪正交投影縮放跟隨目前控制的坦克。
## 它只負責框取世界畫面；不會處理瞄準、玩家輸入指令或坦克移動。
extends Node3D

@export_category("游標前視")
## 不套用前視的正規化游標半徑，畫面中心為 0，邊緣為 1。
@export_range(0.0, 1.0, 0.01) var look_ahead_dead_zone := 0.18
## 前視偏移量的指數插值速率，單位為每秒。
@export var look_ahead_smoothing_speed := 8.0

@export_category("正交投影縮放")
## 每一格滑鼠滾輪對 Camera3D size 的變化量，單位為世界公尺。
@export var zoom_step := 5.0
## 允許的最小 Camera3D size，單位為世界公尺。
@export var min_zoom_size := 25.0
## 允許的最大 Camera3D size，單位為世界公尺。
@export var max_zoom_size := 100.0

@onready var camera: Camera3D = $Camera3D

var follow_target: Node3D
var follow_target_offset := Vector3.ZERO
var look_ahead_offset := Vector3.ZERO


## 立即註冊要跟隨的節點，並重設先前的前視偏移量。
func set_follow_target(target: Node3D) -> void:
	follow_target = target
	follow_target_offset = global_position - target.global_position
	look_ahead_offset = Vector3.ZERO


func _process(delta: float) -> void:
	## 以與影格率無關的指數插值平滑前視，並保留註冊當下的相對高度與構圖偏移。
	if follow_target == null or not is_instance_valid(follow_target):
		return
	var desired_offset := _desired_look_ahead_offset()
	var interpolation := 1.0 - exp(-maxf(look_ahead_smoothing_speed, 0.0) * maxf(delta, 0.0))
	look_ahead_offset = look_ahead_offset.lerp(desired_offset, interpolation)
	global_position = follow_target.global_position + follow_target_offset + look_ahead_offset


func _unhandled_input(event: InputEvent) -> void:
	## 只消費按下的滾輪事件，並在既有正交 Camera3D size 範圍內調整縮放。
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera.size = maxf(min_zoom_size, camera.size - zoom_step)
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera.size = minf(max_zoom_size, camera.size + zoom_step)


func _desired_look_ahead_offset() -> Vector3:
	## 將螢幕游標換成以畫面中心為原點的 -1 到 1 座標，交由可測試的純計算路徑處理。
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector3.ZERO
	var viewport_center := viewport_size * 0.5
	var normalized_cursor := Vector2(
		(get_viewport().get_mouse_position().x - viewport_center.x) / viewport_center.x,
		(get_viewport().get_mouse_position().y - viewport_center.y) / viewport_center.y,
	)
	return calculate_look_ahead_offset(normalized_cursor)


## 將正規化游標位置轉換為目前坦克受限的 XZ 跟隨偏移量。
func calculate_look_ahead_offset(normalized_cursor: Vector2) -> Vector3:
	var cursor_distance := normalized_cursor.length()
	if cursor_distance <= look_ahead_dead_zone:
		return Vector3.ZERO
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector3.ZERO
	var viewport_center := viewport_size * 0.5
	var center_world := _ray_plane_intersection(viewport_center, follow_target.global_position.y)
	var cursor_world := _ray_plane_intersection(viewport_center + normalized_cursor * viewport_center, follow_target.global_position.y)
	var world_direction := cursor_world - center_world
	world_direction.y = 0.0
	if world_direction.is_zero_approx():
		return Vector3.ZERO
	var extent := clampf(
		(cursor_distance - look_ahead_dead_zone) / maxf(1.0 - look_ahead_dead_zone, 0.001),
		0.0,
		1.0,
	)
	var max_distance := float(follow_target.call("get_max_camera_look_ahead_distance")) if follow_target.has_method("get_max_camera_look_ahead_distance") else 0.0
	return world_direction.normalized() * max_distance * extent


func _ray_plane_intersection(screen_position: Vector2, plane_height: float) -> Vector3:
	## 將螢幕點投影出的相機射線與坦克所在高度的水平平面相交，供 XZ 前視使用。
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return ray_origin
	return ray_origin + ray_direction * ((plane_height - ray_origin.y) / ray_direction.y)
