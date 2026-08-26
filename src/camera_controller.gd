extends Node

const ZOOM_STEP := 5.0
const MIN_SIZE := 25.0
const MAX_SIZE := 100.0
@export_range(0.0, 1.0, 0.01) var look_ahead_dead_zone := 0.2
@export var look_ahead_smoothing := 8.0

var camera: Camera3D
var camera_rig: Node3D
var follow_target: Node3D
var follow_offset := Vector3.ZERO
var look_ahead_offset := Vector3.ZERO


func configure(camera_node: Camera3D, target: Node3D) -> void:
	camera = camera_node
	camera_rig = camera.get_parent() as Node3D
	set_follow_target(target)


func set_follow_target(target: Node3D) -> void:
	follow_target = target
	if camera_rig != null and follow_target != null:
		follow_offset = camera_rig.global_position - follow_target.global_position


func _ready() -> void:
	process_priority = -20


func _process(delta: float) -> void:
	if camera == null or camera_rig == null or follow_target == null:
		return
	look_ahead_offset = look_ahead_offset.lerp(_target_look_ahead_offset(), clampf(delta * look_ahead_smoothing, 0.0, 1.0))
	camera_rig.global_position = follow_target.global_position + follow_offset + look_ahead_offset


func _target_look_ahead_offset() -> Vector3:
	var viewport_size := get_viewport().get_visible_rect().size
	return _target_look_ahead_offset_for_screen_position(get_viewport().get_mouse_position(), viewport_size)


func _target_look_ahead_offset_for_screen_position(screen_position: Vector2, viewport_size: Vector2) -> Vector3:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector3.ZERO
	var normalized_pointer := (screen_position - viewport_size * 0.5) / (viewport_size * 0.5)
	var distance := minf(normalized_pointer.length(), 1.0)
	if distance <= look_ahead_dead_zone:
		return Vector3.ZERO
	# Orthographic rays are parallel, so derive the direction from the camera's
	# screen plane instead of project_ray_normal(). Keep only XZ so look-ahead
	# never changes the approved camera height.
	var screen_plane_direction := camera.global_transform.basis.x * normalized_pointer.x \
			- camera.global_transform.basis.y * normalized_pointer.y
	var direction := Vector3(screen_plane_direction.x, 0.0, screen_plane_direction.z).normalized()
	if direction.is_zero_approx():
		return Vector3.ZERO
	var maximum_distance := float(follow_target.get_camera_look_ahead_distance())
	return direction * maximum_distance * (distance - look_ahead_dead_zone) / maxf(1.0 - look_ahead_dead_zone, 0.001)


func _unhandled_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if camera == null or mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera.size = maxf(MIN_SIZE, camera.size - ZOOM_STEP)
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera.size = minf(MAX_SIZE, camera.size + ZOOM_STEP)
