extends Node3D
class_name TankProjectile

@export var speed := 80.0
@export var max_distance := 180.0
@export_flags_3d_physics var collision_mask := 129

const IMPACT_VFX_SCENE := preload("res://assets/GodotImpactVFX/effects/hit/vfx_hit_01.tscn")
const IMPACT_VFX_LIFETIME_SECONDS := 0.9

var direction := Vector3.ZERO
var excluded_rids: Array[RID] = []
var effects_parent: Node3D
var distance_travelled := 0.0


func initialize(new_direction: Vector3, new_excluded_rids: Array, new_effects_parent: Node3D) -> void:
	direction = new_direction.normalized()
	excluded_rids.assign(new_excluded_rids)
	effects_parent = new_effects_parent


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
		_spawn_impact_vfx(hit["position"], hit.get("normal", Vector3.UP))
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


func _spawn_impact_vfx(hit_position: Vector3, hit_normal: Vector3) -> void:
	if effects_parent == null or not is_instance_valid(effects_parent):
		return
	var impact := IMPACT_VFX_SCENE.instantiate() as Node3D
	impact.name = "ImpactVFX"
	impact.set("one_shot", true)
	impact.set("autoplay", true)
	effects_parent.add_child(impact, true)
	impact.global_position = hit_position + hit_normal.normalized() * 0.05
	get_tree().create_timer(IMPACT_VFX_LIFETIME_SECONDS).timeout.connect(impact.queue_free)
