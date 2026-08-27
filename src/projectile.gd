## Simulates one world-space Tank projectile and reports its first collision as an ImpactEvent.
## It does not create visual effects, choose targets, or decide when a Tank fires.
extends Node3D
class_name TankProjectile

const ShotEvent := preload("res://src/shot_event.gd")
const ImpactEvent := preload("res://src/impact_event.gd")

@export_category("Projectile Motion")
## Projectile travel speed in metres per second.
@export var speed := 120.0
## Maximum unobstructed travel distance in metres.
@export var max_distance := 180.0

@export_category("Projectile Collision")
## Physics layers the projectile ray can collide with.
@export_flags_3d_physics var collision_mask := 129

var shot_event: ShotEvent
var direction := Vector3.ZERO
var excluded_rids: Array[RID] = []
var distance_travelled := 0.0
var _impact_reported := false

## Legacy collision notification retained for the existing compatibility smoke test.
signal hit_detected(hit_position: Vector3, hit_normal: Vector3)
## Authoritative collision notification consumed by CombatRuntime.
signal impact_detected(impact_event: ImpactEvent)


## Configures this projectile from one ShotEvent; Vector3 input remains only for the legacy smoke test.
func initialize(new_shot_event: Variant, legacy_excluded_rids: Array = []) -> void:
	if new_shot_event is ShotEvent:
		shot_event = new_shot_event
		direction = shot_event.direction
		excluded_rids = [shot_event.shooter_rid]
		return

	# Compatibility for the pre-contract smoke test. Runtime production code always
	# provides a ShotEvent and never uses this branch.
	if new_shot_event is Vector3:
		direction = (new_shot_event as Vector3).normalized()
		excluded_rids.assign(legacy_excluded_rids)
		var legacy_rid := excluded_rids[0] if not excluded_rids.is_empty() else RID()
		shot_event = ShotEvent.new(Transform3D.IDENTITY, direction, legacy_rid)


func _physics_process(delta: float) -> void:
	if _impact_reported or shot_event == null or direction.is_zero_approx() or speed <= 0.0 or max_distance <= 0.0:
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
		var hit_position := hit["position"] as Vector3
		var hit_normal := hit.get("normal", Vector3.UP) as Vector3
		var hit_collider := hit.get("collider") as Object
		global_position = hit_position
		_emit_impact(hit_collider, hit_position, hit_normal)
		queue_free()
		return

	global_position = end_position
	distance_travelled += step_distance
	if distance_travelled >= max_distance - 0.001:
		queue_free()


func _emit_impact(hit_collider: Object, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _impact_reported:
		return
	_impact_reported = true
	var impact_event := ImpactEvent.new(shot_event, hit_collider, hit_position, hit_normal)
	if impact_event.is_valid():
		impact_detected.emit(impact_event)
	hit_detected.emit(hit_position, hit_normal)


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
