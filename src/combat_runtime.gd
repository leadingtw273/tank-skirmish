extends Node3D

const PROJECTILE_SCENE := preload("res://src/projectile.tscn")
const IMPACT_VFX_SCENE := preload("res://assets/GodotImpactVFX/effects/hit/vfx_hit_01.tscn")
const IMPACT_VFX_LIFETIME_SECONDS := 0.9

@export var projectiles: Node3D
@export var effects: Node3D


func set_shot_source(tank: Node3D) -> void:
	if tank == null or not is_instance_valid(tank) or not tank.has_signal("shot_fired"):
		push_error("CombatRuntime requires an active Tank shot_fired source.")
		return
	if projectiles == null or effects == null:
		push_error("CombatRuntime requires Projectiles and Effects containers.")
		return
	if not tank.is_connected("shot_fired", _on_shot_fired):
		tank.connect("shot_fired", _on_shot_fired)


func _on_shot_fired(shot_event: Dictionary) -> void:
	var muzzle_transform: Transform3D = shot_event.get("muzzle_transform", Transform3D.IDENTITY)
	var shooter_rid: RID = shot_event.get("shooter_rid", RID())
	if not shooter_rid.is_valid() or not muzzle_transform.is_finite():
		push_error("CombatRuntime rejected an invalid Shot Event.")
		return
	var direction := (-muzzle_transform.basis.x).normalized()
	if direction.is_zero_approx():
		push_error("CombatRuntime rejected a Shot Event without a muzzle direction.")
		return
	var projectile := PROJECTILE_SCENE.instantiate() as TankProjectile
	if projectile == null:
		push_error("CombatRuntime could not instantiate projectile.tscn.")
		return
	projectile.name = "Projectile"
	projectile.initialize(direction, [shooter_rid])
	projectile.hit_detected.connect(_on_projectile_hit)
	projectiles.add_child(projectile, true)
	projectile.global_transform = Transform3D(_basis_with_x_axis(direction), muzzle_transform.origin)


func _on_projectile_hit(hit_position: Vector3, hit_normal: Vector3) -> void:
	var impact := IMPACT_VFX_SCENE.instantiate() as Node3D
	impact.name = "ImpactVFX"
	impact.set("one_shot", true)
	impact.set("autoplay", true)
	effects.add_child(impact, true)
	impact.global_position = hit_position + hit_normal.normalized() * 0.05
	get_tree().create_timer(IMPACT_VFX_LIFETIME_SECONDS).timeout.connect(impact.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
