extends SceneTree

const TANK_BASE_SCENE := "res://src/actors/tank/tank_base.tscn"
const DAMAGE_LAB_SCENE := "res://tmp/tank_damage_vfx_lab/tank_damage_vfx_lab.tscn"
const VARIANTS := {
	"tank1": {"scene": "res://src/actors/tank/variants/tank1/tank1.tscn", "collision": Vector3(7.74703, 3.37688, 4.54163), "damage": "Tank1DamageVisuals"},
	"tank2": {"scene": "res://src/actors/tank/variants/tank2/tank2.tscn", "collision": Vector3(7.955370303640, 2.079210193863, 4.541630211513), "damage": "Tank2DamageVisuals"},
	"tank3": {"scene": "res://src/actors/tank/variants/tank3/tank3.tscn", "collision": Vector3(6.6935, 3.04212, 4.7442), "damage": "Tank3DamageVisuals"},
	"tank4": {"scene": "res://src/actors/tank/variants/tank4/tank4.tscn", "collision": Vector3(7.272, 2.69882, 4.4904), "damage": "Tank4DamageVisuals"},
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
	if not await _validate_damage_lab():
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


func _validate_damage_lab() -> bool:
	var packed := load(DAMAGE_LAB_SCENE) as PackedScene
	var lab := packed.instantiate() as Node3D if packed != null else null
	if lab == null:
		return _fail("The four-tank damage lab must load.")
	root.add_child(lab)
	await process_frame
	await process_frame
	var valid := true
	for tank_number in range(1, 5):
		var row := lab.get_node_or_null("Displays/Tank%d" % tank_number)
		if row == null or row.get_child_count() != 5:
			valid = false
			break
		for health_percent in [100, 75, 50, 25, 0]:
			var tank := row.get_node_or_null("Health%d/Tank" % health_percent) as CharacterBody3D
			var health := tank.get_node_or_null("HealthComponent") as HealthComponent if tank != null else null
			if tank == null or health == null \
					or not is_equal_approx(health.current_health, float(health_percent)) \
					or tank.is_physics_processing() or tank.collision_layer != 0 or tank.collision_mask != 0:
				valid = false
				break
		if not valid:
			break
	lab.queue_free()
	await process_frame
	if not valid:
		return _fail("The damage lab must contain four complete variants at 100/75/50/25/0 health with physics and collision disabled.")
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
		and tank.tank_gun != null
		and tank.tank_gun.get_parent() == gun_visual
		and hull_visual != null
		and turret_visual != null
		and gun_visual != null
		and muzzle_point != null
		and collision_shape != null
		and collision_shape.size.is_equal_approx(contract.collision)
		and is_equal_approx(collision.position.y, contract.collision.y * 0.5)
		and health != null
		and receiver != null
		and contact_effects != null
		and contact_effects.get_child_count() == 4
		and tank.get_node_or_null(contract.damage) != null
	)
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
			and is_equal_approx(float(shots[0].damage), 25.0) \
			and shots[0].direction.is_equal_approx(tank.muzzle_global_direction()) \
			and receiver.receive_damage(25.0) \
			and is_equal_approx(health.current_health, 75.0)
	tank.queue_free()
	await process_frame
	if not valid:
		return _fail("%s must provide the shared interface, collision, tread mapping, fire event, health, and vehicle-specific damage visuals." % tank_id)
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
