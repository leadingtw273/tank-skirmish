extends Node

@export_flags_3d_physics var aim_collision_mask := 129
@export var max_aim_distance := 180.0
@export var aim_presentation: Node

var controlled_tank: Node3D
var camera: Camera3D


func set_controlled_tank(tank: Node3D) -> void:
	controlled_tank = tank


func set_camera(next_camera: Camera3D) -> void:
	camera = next_camera


func _process(delta: float) -> void:
	if controlled_tank == null or camera == null:
		return
	var target_position := resolve_mouse_world_target(get_viewport().get_mouse_position())
	controlled_tank.call("_aim_turret_at", target_position, delta)
	controlled_tank.call("_aim_gun_pitch_at_target", target_position, delta)
	if aim_presentation != null:
		aim_presentation.call("set_world_target", target_position)


func resolve_mouse_world_target(screen_position: Vector2) -> Vector3:
	return resolve_world_target_from_ray(
		camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position),
	)


func resolve_world_target_from_ray(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	var normalized_direction := ray_direction.normalized()
	if normalized_direction.is_zero_approx():
		return ray_origin
	var fallback_target := ray_origin + normalized_direction * maxf(max_aim_distance, 0.0)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, fallback_target, aim_collision_mask, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	var collision := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	return collision.get("position", fallback_target) as Vector3
