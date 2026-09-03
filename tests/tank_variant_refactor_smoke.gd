extends SceneTree

const TANK_BASE_SCENE := "res://src/actors/tank/tank_base.tscn"
const TANK2_SCENE := "res://src/actors/tank/variants/tank2/tank2.tscn"


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	if not await _validate_base_scene() or not await _validate_tank2_variant():
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


func _validate_tank2_variant() -> bool:
	var packed := load(TANK2_SCENE) as PackedScene
	var tank := packed.instantiate() as CharacterBody3D if packed != null else null
	if tank == null:
		return _fail("Tank2 variant must load as a CharacterBody3D.")
	root.add_child(tank)
	await process_frame
	await process_frame
	var hull_visual := tank.get_node_or_null("VisualRecoilPivot/TankVisualSlot/HullVisual") as Node3D
	var turret_visual := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/TurretVisual") as Node3D
	var gun_visual := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot/GunVisual") as Node3D
	var muzzle_point := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot/MuzzlePoint") as Marker3D
	var collision := tank.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var collision_shape := collision.shape as BoxShape3D if collision != null else null
	var clips := [
		tank.tread_forward_animation,
		tank.tread_backwards_animation,
		tank.tread_turning_left_animation,
		tank.tread_turning_right_animation,
	]
	var valid: bool = (
		bool(tank.variant_interface_enabled)
		and tank.scene_file_path == TANK2_SCENE
		and tank.tank_model != null
		and tank.tank_model.is_ancestor_of(tank.tread_animation_player)
		and tank.tank_turret != null
		and tank.tank_turret.get_parent() == turret_visual
		and tank.tank_gun != null
		and tank.tank_gun.get_parent() == gun_visual
		and hull_visual != null
		and turret_visual != null
		and gun_visual != null
		and muzzle_point != null
		and collision_shape != null
		and collision_shape.size.is_equal_approx(Vector3(7.955370303640, 2.079210193863, 4.541630211513))
		and collision.position.is_equal_approx(Vector3(0, 1.039605154183, 0))
		and tank.get_node_or_null("Tank2DamageVisuals") != null
	)
	if valid:
		for clip: StringName in clips:
			if clip.is_empty() or not tank.tread_animation_player.has_animation(clip):
				valid = false
				break
	tank.queue_free()
	await process_frame
	if not valid:
		return _fail("Tank2 must provide the stable interface, original collision, four tread clips, and vehicle-specific damage visuals.")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
