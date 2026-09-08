extends Node

@export_flags_3d_physics var aim_collision_mask := 129
## 滑鼠未命中任何碰撞時的備用距離；不是砲彈射程或可見地面的偵測上限。
@export var max_aim_distance := 180.0
@export var aim_presentation: Node

var controlled_tank: Node3D
var camera: Camera3D
var controls_enabled := true


## 暫停滑鼠追蹤，不把恢復計時或訓練場規則放在輸入控制器。
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled and is_instance_valid(controlled_tank):
		controlled_tank.call("cancel_aim")


func set_controlled_tank(tank: Node3D) -> void:
	controlled_tank = tank


func set_camera(next_camera: Camera3D) -> void:
	camera = next_camera


func _process(delta: float) -> void:
	if not controls_enabled:
		return
	if controlled_tank == null or not is_instance_valid(controlled_tank) or camera == null or not is_instance_valid(camera):
		push_error("PlayerAimController requires an active controlled_tank and Camera3D.")
		set_process(false)
		return
	apply_aim(resolve_mouse_world_target(get_viewport().get_mouse_position()), delta)


func apply_aim(target_position: Vector3, delta: float) -> void:
	if not controls_enabled:
		return
	if controlled_tank == null or not is_instance_valid(controlled_tank):
		push_error("PlayerAimController requires an active controlled_tank.")
		set_process(false)
		return
	controlled_tank.call("aim_turret_at", target_position, delta)
	controlled_tank.call("aim_gun_pitch_at_target", target_position, delta)
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
	## 射線從攝影機出發，需涵蓋可見範圍，避免尚未碰到遠處地板就截斷。
	var query_distance := maxf(max_aim_distance, 0.0)
	if is_instance_valid(camera):
		query_distance = maxf(query_distance, camera.far)
	var query_end := ray_origin + normalized_direction * query_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, query_end, aim_collision_mask, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	var collision := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	return collision.get("position", fallback_target) as Vector3
