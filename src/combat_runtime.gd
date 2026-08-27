## Turns Tank shot events into projectiles and projectile impacts into transient world effects.
## It owns only runtime combat children; it does not decide when a Tank fires or control player input.
extends Node3D
class_name CombatRuntime

const PROJECTILE_SCENE := preload("res://src/projectile.tscn")
const IMPACT_VFX_SCENE := preload("res://assets/BinbunVFX/impact_explosions/effects/hit/vfx_hit_01.tscn")
const TankProjectile := preload("res://src/projectile.gd")
const ShotEvent := preload("res://src/shot_event.gd")
const ImpactEvent := preload("res://src/impact_event.gd")
@export_category("Scene Wiring")
## Nodes that emit the public shot_event_fired signal for this combat runtime to consume.
@export var shot_sources: Array[Node]
## Parent that receives runtime TankProjectile nodes.
@export var projectiles: Node3D
## Parent that receives transient impact visual-effect nodes.
@export var effects: Node3D

@export_category("Impact Presentation")
## Lifetime in seconds before an instantiated impact visual effect is removed.
@export var impact_vfx_lifetime_seconds := 0.9
## Offset in metres along an impact normal to prevent the visual effect clipping into the surface.
@export var impact_vfx_surface_offset := 0.05

var _registered_shot_sources: Array[Node] = []


func _ready() -> void:
	if projectiles == null or effects == null:
		push_error("CombatRuntime requires injected Projectiles and Effects containers.")
		return
	for shot_source in shot_sources:
		register_shot_source(shot_source)


func _exit_tree() -> void:
	for shot_source in _registered_shot_sources.duplicate():
		unregister_shot_source(shot_source)


## Connects one active shot_event_fired source; repeated registration is intentionally ignored.
func register_shot_source(shot_source: Node) -> void:
	if shot_source == null or not is_instance_valid(shot_source) or not shot_source.has_signal("shot_event_fired"):
		push_error("CombatRuntime requires an active shot_event_fired source.")
		return
	if _registered_shot_sources.has(shot_source):
		return
	if not shot_source.is_connected("shot_event_fired", _on_shot_fired):
		shot_source.connect("shot_event_fired", _on_shot_fired)
	var release_callback := _on_shot_source_tree_exiting.bind(shot_source)
	if not shot_source.tree_exiting.is_connected(release_callback):
		shot_source.tree_exiting.connect(release_callback)
	_registered_shot_sources.append(shot_source)


## Disconnects a previously registered shot source and releases its lifecycle callback.
func unregister_shot_source(shot_source: Node) -> void:
	if shot_source == null or not _registered_shot_sources.has(shot_source):
		return
	if is_instance_valid(shot_source):
		if shot_source.is_connected("shot_event_fired", _on_shot_fired):
			shot_source.disconnect("shot_event_fired", _on_shot_fired)
		var release_callback := _on_shot_source_tree_exiting.bind(shot_source)
		if shot_source.tree_exiting.is_connected(release_callback):
			shot_source.tree_exiting.disconnect(release_callback)
	_registered_shot_sources.erase(shot_source)


func _on_shot_source_tree_exiting(shot_source: Node) -> void:
	unregister_shot_source(shot_source)


func _on_shot_fired(shot_event: ShotEvent) -> void:
	if shot_event == null or not shot_event.is_valid():
		push_error("CombatRuntime rejected an invalid ShotEvent.")
		return
	var projectile := PROJECTILE_SCENE.instantiate() as TankProjectile
	if projectile == null:
		push_error("CombatRuntime could not instantiate projectile.tscn.")
		return
	projectile.name = "Projectile"
	projectile.initialize(shot_event)
	projectile.impact_detected.connect(_on_projectile_impact)
	projectiles.add_child(projectile, true)
	projectile.global_transform = Transform3D(_basis_with_x_axis(shot_event.direction), shot_event.muzzle_transform.origin)


func _on_projectile_impact(impact_event: ImpactEvent) -> void:
	if impact_event == null or not impact_event.is_valid():
		return
	var impact := IMPACT_VFX_SCENE.instantiate() as Node3D
	impact.name = "ImpactVFX"
	impact.set("one_shot", true)
	impact.set("autoplay", true)
	effects.add_child(impact, true)
	impact.global_position = impact_event.position + impact_event.normal * impact_vfx_surface_offset
	get_tree().create_timer(impact_vfx_lifetime_seconds).timeout.connect(impact.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
