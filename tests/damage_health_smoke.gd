extends SceneTree

const HealthComponent := preload("res://src/combat/damage/health_component.gd")
const DamageReceiver := preload("res://src/combat/damage/damage_receiver.gd")
const ShotEvent := preload("res://src/combat/shot_event.gd")
const TRAINING_TARGET_SCENE := "res://src/world/training_ground/training_target.tscn"


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	if not await _validate_damage_components() or not await _validate_training_target():
		quit(1)
		return
	print("Damage and training target smoke validation passed.")
	quit(0)


func _validate_damage_components() -> bool:
	var host := Node.new()
	var health := HealthComponent.new()
	var receiver := DamageReceiver.new()
	host.add_child(health)
	host.add_child(receiver)
	receiver.set("health_component", health)
	root.add_child(host)
	await process_frame

	var depleted_count := [0]
	health.depleted.connect(func() -> void: depleted_count[0] += 1)
	if not is_equal_approx(health.maximum_health, 100.0) \
			or not is_equal_approx(health.current_health, 100.0):
		host.queue_free()
		return _fail("HealthComponent must initialize at its 100-point maximum.")
	if receiver.receive_damage(0.0) or receiver.receive_damage(-25.0):
		host.queue_free()
		return _fail("DamageReceiver must reject non-positive damage.")
	for index in range(4):
		if not receiver.receive_damage(25.0) \
				or not is_equal_approx(health.current_health, 75.0 - 25.0 * index):
			host.queue_free()
			return _fail("Four 25-point hits must reduce health from 100 to zero.")
	if depleted_count[0] != 1 or receiver.receive_damage(25.0):
		host.queue_free()
		return _fail("A depleted HealthComponent must notify once and reject further damage.")
	receiver.enabled = false
	health.reset_to_maximum()
	if receiver.receive_damage(25.0) or not is_equal_approx(health.current_health, 100.0):
		host.queue_free()
		return _fail("A disabled DamageReceiver must not change health.")
	host.queue_free()

	var shot := ShotEvent.new(Transform3D.IDENTITY, Vector3.RIGHT, RID(), 25.0)
	if not is_equal_approx(shot.damage, 25.0):
		return _fail("ShotEvent must preserve the damage snapshot supplied at fire time.")
	return true


func _validate_training_target() -> bool:
	var packed_scene := load(TRAINING_TARGET_SCENE) as PackedScene
	var target := packed_scene.instantiate() as Node3D if packed_scene != null else null
	if target == null:
		return _fail("TrainingTarget scene must load.")
	root.add_child(target)
	await process_frame
	await process_frame
	var tank := target.get_node_or_null("SubjectSlot/Tank") as CharacterBody3D
	var health := target.get_node_or_null("SubjectSlot/Tank/HealthComponent") as HealthComponent
	var receiver := target.get_node_or_null("SubjectSlot/Tank/DamageReceiver") as DamageReceiver
	var label := target.get_node_or_null("HealthLabel3D") as Label3D
	var controller := target.get_node_or_null("TrainingTargetController")
	var damage_visuals := target.get_node_or_null("SubjectSlot/Tank/Tank2DamageVisuals")
	var hull_vfx_anchor := target.get_node_or_null("SubjectSlot/Tank/VisualRecoilPivot/HullDamageVFXAnchor") as Node3D
	var turret_vfx_anchor := target.get_node_or_null("SubjectSlot/Tank/VisualRecoilPivot/TurretPivot/TurretDamageVFXAnchor") as Node3D
	if tank == null or health == null or receiver == null or label == null or controller == null \
			or damage_visuals == null or hull_vfx_anchor == null or turret_vfx_anchor == null \
			or target.get_node_or_null("PlayerRuntime") != null:
		target.queue_free()
		return _fail("TrainingTarget must wrap one complete, uncontrolled Tank with health UI and damage visuals.")
	if hull_vfx_anchor.get_node_or_null("Damage25/HullSmokeLeft") == null \
			or hull_vfx_anchor.get_node_or_null("Depleted/HullFireRight") == null \
			or turret_vfx_anchor.get_node_or_null("Damage75/TurretSmokeLight") == null \
			or turret_vfx_anchor.get_node_or_null("Depleted/TurretFire") == null:
		target.queue_free()
		return _fail("Tank2 damage visuals must preserve the approved hull/turret effect roles and readable names.")
	if label.text != "100 / 100" or not is_equal_approx(float(controller.reset_delay_seconds), 3.0):
		target.queue_free()
		return _fail("TrainingTarget must begin at 100 / 100 and use a three-second reset delay.")
	controller.reset_delay_seconds = 0.01
	damage_visuals.damage_transition_seconds = 0.01
	receiver.receive_damage(25.0)
	var light_smoke_particles := turret_vfx_anchor.get_node("Damage75/TurretSmokeLight/Smoke") as GPUParticles3D
	if int(damage_visuals.active_damage_stage) != 75 or not is_zero_approx(light_smoke_particles.amount_ratio):
		target.queue_free()
		return _fail("A new damage stage must begin its particle emission gradually.")
	await create_timer(0.02).timeout
	if light_smoke_particles.amount_ratio < 0.99:
		target.queue_free()
		return _fail("A new damage stage must reach its authored particle amount after the transition.")
	var retired_stage := turret_vfx_anchor.get_node("Damage75") as Node3D
	for node: Node in retired_stage.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		particles.lifetime = 0.1
		particles.speed_scale = 0.5
	receiver.receive_damage(25.0)
	if int(damage_visuals.active_damage_stage) != 50:
		target.queue_free()
		return _fail("Tank2 damage visuals must switch from 75 to 50 percent health.")
	await create_timer(0.12).timeout
	if not retired_stage.visible:
		target.queue_free()
		return _fail("Retired smoke must remain visible for its speed-adjusted particle lifetime.")
	await create_timer(0.12).timeout
	if retired_stage.visible:
		target.queue_free()
		return _fail("Retired smoke must be hidden after its particles finish naturally.")
	receiver.receive_damage(25.0)
	if int(damage_visuals.active_damage_stage) != 25:
		target.queue_free()
		return _fail("Tank2 damage visuals must switch from 50 to 25 percent health.")
	var turret_pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var gun_pitch_pivot := turret_pivot.get_node("GunPitchPivot") as Node3D
	var turret_yaw_before_depletion := 0.73
	var gun_pitch_before_depletion := -0.04
	turret_pivot.rotation.y = turret_yaw_before_depletion
	gun_pitch_pivot.rotation.z = gun_pitch_before_depletion
	receiver.receive_damage(25.0)
	var expected_depleted_pitch := deg_to_rad(float(damage_visuals.depleted_gun_depression_degrees))
	var depleted_explosion := root.find_child("TankDepletedExplosion", true, false) as Node3D
	var explosion_core := depleted_explosion.get_node_or_null("Core") as MeshInstance3D if depleted_explosion != null else null
	var explosion_decal := depleted_explosion.get_node_or_null("Decal") as Decal if depleted_explosion != null else null
	if label.text != "0 / 100" or receiver.enabled or int(damage_visuals.active_damage_stage) != 0 \
			or not is_equal_approx(turret_pivot.rotation.y, turret_yaw_before_depletion) \
			or not is_equal_approx(gun_pitch_pivot.rotation.z, expected_depleted_pitch) \
			or depleted_explosion == null \
			or depleted_explosion.scene_file_path != "res://src/vfx/damage/tank_depleted_explosion_vfx.tscn" \
			or not depleted_explosion.scale.is_equal_approx(Vector3.ONE * 1.5) \
			or explosion_core == null or not explosion_core.scale.is_equal_approx(Vector3.ONE) \
			or explosion_decal == null or not explosion_decal.size.is_equal_approx(Vector3(10, 5, 10)):
		target.queue_free()
		return _fail("The fourth hit must explode, preserve turret yaw, and lower only the gun.")
	if receiver.receive_damage(25.0) or not is_zero_approx(health.current_health):
		target.queue_free()
		return _fail("TrainingTarget must ignore damage while waiting to reset.")
	await create_timer(0.02).timeout
	await process_frame
	var reset_is_valid := label.text == "100 / 100" and receiver.enabled \
		and is_equal_approx(health.current_health, 100.0) \
		and int(damage_visuals.active_damage_stage) == 100 \
		and is_equal_approx(turret_pivot.rotation.y, turret_yaw_before_depletion) \
		and is_equal_approx(gun_pitch_pivot.rotation.z, gun_pitch_before_depletion)
	target.queue_free()
	if not reset_is_valid:
		return _fail("TrainingTarget must restore only health and damage reception after its delay.")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
