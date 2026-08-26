extends Node

const AIM_MAX_DISTANCE := 180.0
const AIM_COLLISION_MASK := 129
var camera: Camera3D
var controlled_tank: CharacterBody3D
var world_target := Vector3.ZERO


func configure(camera_node: Camera3D, tank: CharacterBody3D) -> void:
	camera = camera_node
	controlled_tank = tank


func _ready() -> void:
	process_priority = -10


func _process(_delta: float) -> void:
	if camera == null or controlled_tank == null:
		return
	world_target = _resolve_mouse_world_target(get_viewport().get_mouse_position())
	controlled_tank.set_aim_target(world_target)


func _resolve_mouse_world_target(screen_position: Vector2) -> Vector3:
	return _resolve_world_target_from_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


func _resolve_world_target_from_ray(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	var direction := ray_direction.normalized()
	if direction.is_zero_approx():
		return ray_origin
	var fallback := ray_origin + direction * AIM_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_origin, fallback, AIM_COLLISION_MASK, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	return controlled_tank.get_world_3d().direct_space_state.intersect_ray(query).get("position", fallback) as Vector3
