extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"
const ShotEvent := preload("res://src/shot_event.gd")
const ImpactEvent := preload("res://src/impact_event.gd")
const CombatRuntime := preload("res://src/combat_runtime.gd")
const TankProjectile := preload("res://src/projectile.gd")


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
	if observed_shots.size() != 1 or projectiles.get_child_count() != 1:
		_fail("Duplicate shot-source registration must not duplicate the shot connection.")
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

	var source := TestShotSource.new()
	instance.add_child(source)
	runtime.register_shot_source(source)
	runtime.register_shot_source(source)
	var source_shot := ShotEvent.new(Transform3D(Basis.IDENTITY, Vector3(500, 2, 500)), Vector3.RIGHT, tank.get_rid())
	source.publish(source_shot)
	if projectiles.get_child_count() != 2:
		_fail("A registered source must connect exactly once.")
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
	var impact_event := impact_events[0]
	var impact_vfx := effects.get_node_or_null("ImpactVFX") as Node3D
	if impact_event.shot_event != shot_event or impact_event.collider != target or impact_vfx == null \
			or not impact_vfx.global_position.is_equal_approx(impact_event.position + impact_event.normal * 0.05) \
			or not impact_vfx.get("one_shot") or not impact_vfx.get("autoplay") \
			or impact_vfx.get_node_or_null("Core") == null or impact_vfx.get_node_or_null("Smoke") == null \
			or impact_vfx.get_node_or_null("Sparks") == null or impact_vfx.get_node_or_null("Decal") == null \
			or impact_vfx.get_node_or_null("Light") == null or impact_vfx.get_node_or_null("AnimationPlayer") == null:
		_fail("CombatRuntime must consume ImpactEvent once and play Explosion 05 under Effects using its normal.")
		return
	if runtime.impact_vfx_lifetime_seconds <= 1.2:
		_fail("Explosion 05 must remain alive beyond its 1.2-second main animation.")
		return
	await create_timer(1.21).timeout
	if effects.get_node_or_null("ImpactVFX") == null:
		_fail("Explosion 05 must remain in Effects until its main animation completes.")
		return
	await create_timer(runtime.impact_vfx_lifetime_seconds - 1.2).timeout
	await process_frame
	if effects.get_node_or_null("ImpactVFX") != null:
		_fail("Explosion 05 must clear from Effects after its configured lifetime.")
		return

	var ranged_projectile := load("res://src/projectile.tscn").instantiate() as TankProjectile
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
