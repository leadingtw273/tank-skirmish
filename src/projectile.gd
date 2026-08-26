extends Node3D
class_name TankProjectile

@export var speed := 120.0
@export var max_distance := 180.0
@export_flags_3d_physics var collision_mask := 129

var direction := Vector3.ZERO
var excluded_rids: Array[RID] = []
var distance_travelled := 0.0

signal hit_detected(hit_position: Vector3, hit_normal: Vector3)


func initialize(new_direction: Vector3, new_excluded_rids: Array) -> void:
	direction = new_direction.normalized()
	excluded_rids.assign(new_excluded_rids)


func _physics_process(delta: float) -> void:
	if direction.is_zero_approx() or speed <= 0.0 or max_distance <= 0.0:
		queue_free()
		return

	var remaining_distance := maxf(max_distance - distance_travelled, 0.0)
	var step_distance := minf(speed * maxf(delta, 0.0), remaining_distance)
	if step_distance <= 0.0:
		queue_free()
		return

	var start_position := global_position
	var end_position := start_position + direction * step_distance
	var hit := _collision_between(start_position, end_position)
	if not hit.is_empty():
		global_position = hit["position"]
		hit_detected.emit(hit["position"], hit.get("normal", Vector3.UP))
		queue_free()
		return

	global_position = end_position
	distance_travelled += step_distance
	if distance_travelled >= max_distance - 0.001:
		queue_free()


func _collision_between(start_position: Vector3, end_position: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		start_position,
		end_position,
		collision_mask,
		excluded_rids,
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)
