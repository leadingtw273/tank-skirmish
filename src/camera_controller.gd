## Follows the controlled Tank with cursor look-ahead and mouse-wheel orthographic zoom.
## It frames the world only; it does not resolve aiming, player input commands, or Tank movement.
extends Node3D

@export_category("Cursor Look-Ahead")
## Normalized cursor radius with no look-ahead, from 0 at screen centre to 1 at the edge.
@export_range(0.0, 1.0, 0.01) var look_ahead_dead_zone := 0.18
## Exponential interpolation rate in inverse seconds for the look-ahead offset.
@export var look_ahead_smoothing_speed := 8.0

@export_category("Orthographic Zoom")
## Change to Camera3D size per mouse-wheel step, in world metres.
@export var zoom_step := 5.0
## Smallest permitted Camera3D size in world metres.
@export var min_zoom_size := 25.0
## Largest permitted Camera3D size in world metres.
@export var max_zoom_size := 100.0

@onready var camera: Camera3D = $Camera3D

var follow_target: Node3D
var follow_target_offset := Vector3.ZERO
var look_ahead_offset := Vector3.ZERO


## Registers the node to follow immediately and resets any previous look-ahead offset.
func set_follow_target(target: Node3D) -> void:
	follow_target = target
	follow_target_offset = global_position - target.global_position
	look_ahead_offset = Vector3.ZERO


func _process(delta: float) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		return
	var desired_offset := _desired_look_ahead_offset()
	var interpolation := 1.0 - exp(-maxf(look_ahead_smoothing_speed, 0.0) * maxf(delta, 0.0))
	look_ahead_offset = look_ahead_offset.lerp(desired_offset, interpolation)
	global_position = follow_target.global_position + follow_target_offset + look_ahead_offset


func _unhandled_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera.size = maxf(min_zoom_size, camera.size - zoom_step)
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera.size = minf(max_zoom_size, camera.size + zoom_step)


func _desired_look_ahead_offset() -> Vector3:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector3.ZERO
	var viewport_center := viewport_size * 0.5
	var normalized_cursor := Vector2(
		(get_viewport().get_mouse_position().x - viewport_center.x) / viewport_center.x,
		(get_viewport().get_mouse_position().y - viewport_center.y) / viewport_center.y,
	)
	return calculate_look_ahead_offset(normalized_cursor)


## Converts a normalized cursor position into the bounded XZ follow offset for the current Tank.
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
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return ray_origin
	return ray_origin + ray_direction * ((plane_height - ray_origin.y) / ray_direction.y)
