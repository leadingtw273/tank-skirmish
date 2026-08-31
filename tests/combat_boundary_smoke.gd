extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"
const MUZZLE_SMOKE_VFX_PATH := "res://src/vfx/muzzle/muzzle_smoke_vfx.tscn"
const ShotEvent := preload("res://src/combat/shot_event.gd")
const ImpactEvent := preload("res://src/combat/impact_event.gd")
const CombatRuntime := preload("res://src/combat/combat_runtime.gd")
const TankProjectile := preload("res://src/combat/projectile.gd")


class TestShotSource extends Node3D:
	signal shot_event_fired(shot_event: ShotEvent)

	func publish(shot_event: ShotEvent) -> void:
		shot_event_fired.emit(shot_event)


func _init() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Combat boundary smoke could not load the main scene.")
		return
	var instance := packed_scene.instantiate()
	root.add_child(instance)
	call_deferred("_validate", instance)


func _validate(instance: Node) -> void:
	var runtime := instance.get_node_or_null("CombatRuntime") as CombatRuntime
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	var player_runtime := instance.get_node_or_null("PlayerRuntime")
	var projectiles := instance.get_node_or_null("CombatRuntime/Projectiles") as Node3D
	var effects := instance.get_node_or_null("CombatRuntime/Effects") as Node3D
	if runtime == null or tank == null or player_runtime == null or projectiles == null or effects == null:
		_fail("Combat boundary smoke requires the composed main-scene dependencies.")
		return
	for property in player_runtime.get_property_list():
		if property.get("name") == &"combat_runtime":
			_fail("PlayerRuntime must not retain a CombatRuntime reference.")
			return
	if runtime.shot_sources.size() != 1 or runtime.shot_sources[0] != tank:
		_fail("Main scene must explicitly inject the Tank shot source into CombatRuntime.")
		return

	var observed_shots: Array[ShotEvent] = []
	tank.shot_event_fired.connect(func(shot_event: ShotEvent) -> void: observed_shots.append(shot_event))
	runtime.register_shot_source(tank)
	tank.request_fire()
	if observed_shots.size() != 1 or projectiles.get_child_count() != 1 or _count_named_children(effects, &"MuzzleSmokeVFX") != 1:
		_fail("Each valid ShotEvent must create exactly one projectile and one MuzzleSmokeVFX.")
		return
	var shot_event := observed_shots[0]
	if not shot_event.is_valid() or not shot_event.direction.is_normalized() \
			or not shot_event.muzzle_transform.is_equal_approx(tank.muzzle_point.global_transform) \
			or shot_event.shooter_rid != tank.get_rid():
		_fail("Tank must publish one closed ShotEvent with its final muzzle transform, direction, and RID.")
		return
	var projectile := projectiles.get_child(0) as TankProjectile
	if projectile == null or projectile.shot_event != shot_event \
			or not projectile.global_position.is_equal_approx(shot_event.muzzle_transform.origin) \
			or not projectile.direction.is_equal_approx(shot_event.direction) \
			or not projectile.excluded_rids.has(shot_event.shooter_rid):
		_fail("CombatRuntime must create a projectile from the ShotEvent without consulting Tank.")
		return
	projectile.set_physics_process(false)
	var muzzle_smoke := effects.get_node_or_null("MuzzleSmokeVFX") as Node3D
	var smoke_particles := muzzle_smoke.get_node_or_null("SmokeBigVFX_01/Smoke") as GPUParticles3D if muzzle_smoke != null else null
	var smoke_process_material := smoke_particles.process_material as ParticleProcessMaterial if smoke_particles != null else null
	var expected_smoke_position := shot_event.muzzle_transform.origin + shot_event.direction * runtime.muzzle_smoke_forward_offset
	if muzzle_smoke == null or muzzle_smoke.scene_file_path != MUZZLE_SMOKE_VFX_PATH \
			or smoke_particles == null or not smoke_particles.one_shot or not smoke_particles.emitting \
			or smoke_particles.transform_align != GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD \
			or smoke_particles.local_coords or smoke_process_material == null \
			or not muzzle_smoke.global_position.is_equal_approx(expected_smoke_position) \
			or not is_equal_approx(muzzle_smoke.global_transform.basis.x.length(), runtime.muzzle_smoke_scale) \
			or not smoke_process_material.direction.is_equal_approx(shot_event.direction):
		_fail("CombatRuntime must restart one scaled, one-shot, camera-facing MuzzleSmokeVFX whose private process material emits along the world shot direction.")
		return
	var smoke_world_position := muzzle_smoke.global_position
	tank.global_position += Vector3(10, 0, 0)
	await process_frame
	if not muzzle_smoke.global_position.is_equal_approx(smoke_world_position):
		_fail("A generated MuzzleSmokeVFX must remain at its world position after the tank moves.")
		return
	await create_timer(runtime.muzzle_smoke_lifetime_seconds + 0.1).timeout
	await process_frame
	if _count_named_children(effects, &"MuzzleSmokeVFX") != 0:
		_fail("MuzzleSmokeVFX must clean itself up after its configured lifetime.")
		return

	var source := TestShotSource.new()
	instance.add_child(source)
	runtime.register_shot_source(source)
	runtime.register_shot_source(source)
	var source_shot := ShotEvent.new(Transform3D(Basis.IDENTITY, Vector3(500, 2, 500)), Vector3.RIGHT, tank.get_rid())
	source.publish(source_shot)
	if projectiles.get_child_count() != 2 or _count_named_children(effects, &"MuzzleSmokeVFX") != 1:
		_fail("A registered source must connect exactly once and create one projectile plus one MuzzleSmokeVFX.")
		return
	runtime.unregister_shot_source(source)
	source.publish(source_shot)
	if projectiles.get_child_count() != 2:
		_fail("Unregistering a source must remove its shot callback.")
		return
	runtime.unregister_shot_source(source)
	runtime.register_shot_source(source)
	source.queue_free()
	await process_frame
	if runtime._registered_shot_sources.size() != 1:
		_fail("A released source must leave no CombatRuntime callback registration.")
		return

	var target := StaticBody3D.new()
	var target_collision := CollisionShape3D.new()
	var target_shape := BoxShape3D.new()
	target_shape.size = Vector3(2, 2, 2)
	target_collision.shape = target_shape
	target.add_child(target_collision)
	target.position = Vector3(300, 2, 300)
	instance.add_child(target)
	await physics_frame
	var impact_events: Array[ImpactEvent] = []
	projectile.impact_detected.connect(func(impact_event: ImpactEvent) -> void: impact_events.append(impact_event))
	projectile.global_position = Vector3(295, 2, 300)
	projectile.direction = Vector3.RIGHT
	projectile._physics_process(0.2)
	projectile._physics_process(0.2)
	if impact_events.size() != 1 or not projectile.is_queued_for_deletion():
		_fail("The first projectile collision must publish exactly one ImpactEvent and clear the projectile.")
		return
	var impact_event := impact_events[0] as ImpactEvent
	var impact_vfx := effects.get_node_or_null("ImpactVFX") as Node3D
	if impact_event.shot_event != shot_event or impact_event.collider != target or impact_vfx == null \
			or impact_vfx.scene_file_path != "res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_05.tscn" \
			or not bool(impact_vfx.get("one_shot")) or not bool(impact_vfx.get("autoplay")) \
			or not impact_vfx.global_position.is_equal_approx(impact_event.position + impact_event.normal * 0.05):
		_fail("CombatRuntime must consume ImpactEvent once, play Explosion 05, and place it under Effects using its normal.")
		return
	await create_timer(1.2).timeout
	if effects.get_node_or_null("ImpactVFX") == null:
		_fail("Explosion 05 must remain alive long enough to play its 1.2-second main animation.")
		return
	await create_timer(0.11).timeout
	await process_frame
	if effects.get_node_or_null("ImpactVFX") != null:
		_fail("Explosion 05 must clean itself up after its configured lifetime.")
		return

	var ranged_projectile := load("res://src/combat/projectile.tscn").instantiate() as TankProjectile
	var ranged_shot := ShotEvent.new(Transform3D(Basis.IDENTITY, Vector3(500, 2, 500)), Vector3.RIGHT, tank.get_rid())
	var ranged_impacts: Array[ImpactEvent] = []
	ranged_projectile.initialize(ranged_shot)
	ranged_projectile.impact_detected.connect(func(impact_event: ImpactEvent) -> void: ranged_impacts.append(impact_event))
	projectiles.add_child(ranged_projectile)
	ranged_projectile.global_position = ranged_shot.muzzle_transform.origin
	ranged_projectile._physics_process(10.0)
	if not ranged_projectile.is_queued_for_deletion() or not ranged_impacts.is_empty():
		_fail("A projectile that reaches max distance must clear without an ImpactEvent.")
		return

	print("Combat boundary smoke validation passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _count_named_children(parent: Node, name_to_match: StringName) -> int:
	var count := 0
	for child in parent.get_children():
		if child.name == name_to_match:
			count += 1
	return count
