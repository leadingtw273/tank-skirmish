extends SceneTree

const TANK_BASE_SCENE := "res://src/actors/tank/tank_base.tscn"
const VARIANTS := {
	"tank1": {"scene": "res://src/actors/tank/variants/tank1/tank1.tscn", "collision": Vector3(6.972327, 3.039192, 4.087467), "damage": "Tank1DamageVisuals"},
	"tank2": {"scene": "res://src/actors/tank/variants/tank2/tank2.tscn", "collision": Vector3(7.955370303640, 2.079210193863, 4.541630211513), "damage": "Tank2DamageVisuals"},
	"tank3": {"scene": "res://src/actors/tank/variants/tank3/tank3.tscn", "collision": Vector3(7.36285, 3.346332, 5.21862), "damage": "Tank3DamageVisuals"},
	"tank4": {"scene": "res://src/actors/tank/variants/tank4/tank4.tscn", "collision": Vector3(7.272, 2.69882, 4.4904), "damage": "Tank4DamageVisuals"},
}
const DAMAGE_STAGE_NAMES := [&"Damage75", &"Damage50", &"Damage25", &"Depleted"]
const VARIANT_DAMAGE_EFFECT_COUNTS := {
	"tank1": {"hull": [0, 1, 2, 4], "turret": [1, 1, 1, 2]},
	"tank3": {"hull": [0, 1, 2, 4], "turret": [1, 1, 1, 3]},
	"tank4": {"hull": [1, 2, 3, 6], "turret": [0, 0, 0, 0]},
}


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	if not await _validate_base_scene():
		quit(1)
		return
	for tank_id: String in VARIANTS:
		if not await _validate_variant(tank_id, VARIANTS[tank_id]):
			quit(1)
			return
	print("Tank variant refactor smoke validation passed.")
	quit(0)


func _validate_base_scene() -> bool:
	var packed := load(TANK_BASE_SCENE) as PackedScene
	var tank_base := packed.instantiate() as CharacterBody3D if packed != null else null
	if tank_base == null:
		return _fail("TankBase must load as a CharacterBody3D.")
	root.add_child(tank_base)
	await process_frame
	var valid: bool = (
		not bool(tank_base.variant_interface_enabled)
		and not tank_base.is_physics_processing()
		and tank_base.get_node_or_null("VisualRecoilPivot/TankVisualSlot/HullVisual") != null
		and tank_base.get_node_or_null("VisualRecoilPivot/TurretPivot/TurretVisual") != null
		and tank_base.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot/GunVisual") != null
		and tank_base.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot/MuzzlePoint") != null
		and tank_base.get_node_or_null("HealthComponent") != null
		and tank_base.get_node_or_null("DamageReceiver") != null
		and tank_base.get_node_or_null("TrackContactEffects") != null
	)
	tank_base.queue_free()
	await process_frame
	if not valid:
		return _fail("TankBase must expose the stable visual, combat, and track-contact interface without acting as a playable variant.")
	return true


func _validate_variant(tank_id: String, contract: Dictionary) -> bool:
	var scene_path: String = contract.scene
	var packed := load(scene_path) as PackedScene
	var tank := packed.instantiate() as CharacterBody3D if packed != null else null
	if tank == null:
		return _fail("%s variant must load as a CharacterBody3D." % tank_id)
	root.add_child(tank)
	await process_frame
	await process_frame
	var hull_visual := tank.get_node_or_null("VisualRecoilPivot/TankVisualSlot/HullVisual") as Node3D
	var turret_visual := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/TurretVisual") as Node3D
	var gun_visual := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot/GunVisual") as Node3D
	var muzzle_point := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot/MuzzlePoint") as Marker3D
	var collision := tank.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var collision_shape := collision.shape as BoxShape3D if collision != null else null
	var health := tank.get_node_or_null("HealthComponent") as HealthComponent
	var receiver := tank.get_node_or_null("DamageReceiver") as DamageReceiver
	var contact_effects := tank.get_node_or_null("TrackContactEffects") as Node3D
	var damage_visuals := tank.get_node_or_null(contract.damage)
	var clips := [
		tank.tread_forward_animation,
		tank.tread_backwards_animation,
		tank.tread_turning_left_animation,
		tank.tread_turning_right_animation,
	]
	var valid: bool = (
		bool(tank.variant_interface_enabled)
		and tank.scene_file_path == scene_path
		and tank.tank_model != null
		and tank.tank_model.is_ancestor_of(tank.tread_animation_player)
		and tank.tank_turret != null
		and tank.tank_turret.get_parent() == turret_visual
		and (float(tank.turret_max_yaw_degrees) < 180.0 or _has_visible_geometry(tank.tank_turret))
		and tank.tank_gun != null
		and tank.tank_gun.get_parent() == gun_visual
		and hull_visual != null
		and turret_visual != null
		and gun_visual != null
		and muzzle_point != null
		and tank.muzzle_global_direction().dot(Vector3.LEFT) > 0.999
		and collision_shape != null
		and collision_shape.size.is_equal_approx(contract.collision)
		and is_equal_approx(collision.position.y, contract.collision.y * 0.5)
		and health != null
		and receiver != null
		and contact_effects != null
		and contact_effects.get_child_count() == 4
		and damage_visuals != null
	)
	if valid and VARIANT_DAMAGE_EFFECT_COUNTS.has(tank_id):
		valid = _validate_variant_damage_effects(tank, tank_id)
	if valid and tank_id == "tank1":
		var fixed_body := tank.tank_model.find_child("Tank_body", true, false) as MeshInstance3D
		var tank1_damage_visuals := tank.get_node_or_null("Tank1DamageVisuals")
		var tank1_hull_fire := tank.get_node_or_null(
			"VisualRecoilPivot/HullDamageVFXAnchor/Depleted/HullFireCriticalPrimary"
		) as Node3D
		var tank1_turret_fire := tank.get_node_or_null(
			"VisualRecoilPivot/TurretPivot/TurretDamageVFXAnchor/Depleted/TurretFireCritical"
		) as Node3D
		var fixed_body_basis_before := fixed_body.global_basis if fixed_body != null else Basis()
		var gun_basis_before: Basis = (tank.tank_gun as Node3D).global_basis
		var turret_pivot := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
		tank.aim_turret_at(turret_pivot.global_position + Vector3.FORWARD * 100.0, 10.0)
		var gun_pitch_pivot := tank.get_node("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
		tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-100.0, 100.0, 0.0), 10.0)
		var elevation_degrees := -rad_to_deg(gun_pitch_pivot.rotation.z)
		tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-100.0, -100.0, 0.0), 10.0)
		var depression_degrees := -rad_to_deg(gun_pitch_pivot.rotation.z)
		valid = tank.scale.is_equal_approx(Vector3.ONE) \
			and tank.tank_model.scale.is_equal_approx(Vector3.ONE * 0.9) \
			and collision_shape.size.is_equal_approx(Vector3(6.972327, 3.039192, 4.087467)) \
			and contact_effects.scale.is_equal_approx(Vector3.ONE * 0.9) \
			and is_equal_approx(float(tank.muzzle_flash_scale), 1.145038211643) \
			and tank1_damage_visuals != null \
			and tank1_damage_visuals.depleted_explosion_local_offset.is_equal_approx(Vector3(0, 1.08, 0)) \
			and is_equal_approx(float(tank1_damage_visuals.depleted_explosion_scale), 1.5) \
			and tank1_hull_fire != null \
			and tank1_hull_fire.scale.is_equal_approx(Vector3.ONE * 1.505) \
			and tank1_hull_fire.position.is_equal_approx(Vector3(2.1782592, -1.69863849, -0.4243023)) \
			and tank1_turret_fire != null \
			and tank1_turret_fire.scale.is_equal_approx(Vector3.ONE * 2.0) \
			and tank1_turret_fire.position.is_equal_approx(Vector3(0.93263283, -0.329704002, 0.087042618)) \
			and fixed_body != null \
			and fixed_body.global_basis.is_equal_approx(fixed_body_basis_before) \
			and not tank.tank_gun.global_basis.is_equal_approx(gun_basis_before) \
			and is_equal_approx(absf(rad_to_deg(turret_pivot.rotation.y)), 8.0) \
			and is_equal_approx(elevation_degrees, 10.0) \
			and is_equal_approx(depression_degrees, -5.0)
	if valid and tank_id == "tank3":
		var tank3_damage_visuals := tank.get_node_or_null("Tank3DamageVisuals")
		var tank3_hull_fire := tank.get_node_or_null(
			"VisualRecoilPivot/HullDamageVFXAnchor/Depleted/HullFireCriticalPrimary"
		) as Node3D
		var tank3_turret_fire := tank.get_node_or_null(
			"VisualRecoilPivot/TurretPivot/TurretDamageVFXAnchor/Depleted/TurretFireCriticalSecondary"
		) as Node3D
		valid = tank.scale.is_equal_approx(Vector3.ONE) \
			and tank.tank_model.scale.is_equal_approx(Vector3.ONE * 1.1) \
			and collision_shape.size.is_equal_approx(Vector3(7.36285, 3.346332, 5.21862)) \
			and contact_effects.scale.is_equal_approx(Vector3.ONE * 1.1) \
			and is_equal_approx(float(tank.muzzle_flash_scale), 1.145038211643) \
			and tank3_damage_visuals != null \
			and tank3_damage_visuals.depleted_explosion_local_offset.is_equal_approx(Vector3(0, 1.32, 0)) \
			and is_equal_approx(float(tank3_damage_visuals.depleted_explosion_scale), 1.5) \
			and tank3_hull_fire != null \
			and tank3_hull_fire.scale.is_equal_approx(Vector3.ONE * 1.505) \
			and tank3_hull_fire.position.is_equal_approx(Vector3(2.6623168, -2.07611371, -0.5185917)) \
			and tank3_turret_fire != null \
			and tank3_turret_fire.scale.is_equal_approx(Vector3.ONE * 2.0) \
			and tank3_turret_fire.position.is_equal_approx(Vector3(-0.33295746, 0.240035444, 0.0476411815))
	if valid:
		for clip: StringName in clips:
			if clip.is_empty() or not tank.tread_animation_player.has_animation(clip):
				valid = false
				break
	if valid:
		var reverse_speed_scale: float = tank.call("_tread_animation_speed_scale", tank.tread_backwards_animation, -1.0, 0.0)
		valid = reverse_speed_scale < 0.0 if tank_id == "tank1" else reverse_speed_scale > 0.0
	if valid:
		var shots: Array = []
		tank.shot_event_fired.connect(func(event: Variant) -> void: shots.append(event))
		tank.request_fire()
		valid = shots.size() == 1 and shots[0].is_valid() \
			and is_equal_approx(float(shots[0].damage), float(tank.shell_damage)) \
			and shots[0].direction.is_equal_approx(tank.muzzle_global_direction()) \
			and receiver.receive_damage(health.maximum_health * 0.25) \
			and is_equal_approx(health.current_health, health.maximum_health * 0.75) \
			and int(damage_visuals.active_damage_stage) == 75
	tank.queue_free()
	await process_frame
	if not valid:
		return _fail("%s must provide the shared interface, collision, tread mapping, fire event, health, and vehicle-specific damage visuals." % tank_id)
	return true


func _has_visible_geometry(root_node: Node3D) -> bool:
	## 砲塔介面必須真的包含可見 Mesh；空 Adapter 雖會旋轉，畫面上的砲塔仍不會動。
	return root_node is MeshInstance3D \
		or not root_node.find_children("*", "MeshInstance3D", true, false).is_empty()


func _validate_variant_damage_effects(tank: CharacterBody3D, tank_id: String) -> bool:
	var hull_anchor := tank.get_node_or_null("VisualRecoilPivot/HullDamageVFXAnchor") as Node3D
	var turret_anchor := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/TurretDamageVFXAnchor") as Node3D
	if hull_anchor == null or turret_anchor == null:
		return false
	var expected: Dictionary = VARIANT_DAMAGE_EFFECT_COUNTS[tank_id]
	for index in DAMAGE_STAGE_NAMES.size():
		var stage_name: StringName = DAMAGE_STAGE_NAMES[index]
		var hull_stage := hull_anchor.get_node_or_null(NodePath(stage_name)) as Node3D
		var turret_stage := turret_anchor.get_node_or_null(NodePath(stage_name)) as Node3D
		if hull_stage == null or turret_stage == null \
				or hull_stage.get_child_count() != int(expected.hull[index]) \
				or turret_stage.get_child_count() != int(expected.turret[index]):
			return false
		for effect: Node in hull_stage.get_children():
			if not effect.name.begins_with("Hull"):
				return false
		for effect: Node in turret_stage.get_children():
			if not effect.name.begins_with("Turret"):
				return false
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
