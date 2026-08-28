extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"
const GRASS_IMPORT := "res://assets/BinbunGrass/texture/grass_basic_02.png.import"
const CONVERSION_MANIFEST := "res://docs/assets/conversion-manifest.json"
const TankProjectile := preload("res://src/projectile.gd")
const ShotEvent := preload("res://src/shot_event.gd")
const TANK_VISUAL_SCALE := 1.7466666
const BUILDING_MODELS := {
	"OneStoryNorthWest": "1story",
	"GableRoofNorthWest": "1story-gable-roof",
	"TwoStoryWideNorthWest": "2story-wide",
	"TwoStorySlimNorthWest": "2story-slim",
	"ThreeStorySmallNorthWest": "3story-small",
	"TwoStoryNorthWest": "2story",
	"FourStoryNorthEast": "4story",
	"SixStoryNorthEast": "6story-stack",
	"OneStoryNorthEast": "1story",
	"GableRoofNorthEast": "1story-gable-roof",
	"TwoStoryWideSouthWest": "2story-wide",
	"TwoStorySlimSouthWest": "2story-slim",
	"ThreeStorySmallSouthWest": "3story-small",
	"TwoStorySouthWest": "2story",
	"FourStorySouthWest": "4story",
	"SixStorySouthWest": "6story-stack",
	"OneStorySouthEast": "1story",
	"GableRoofSouthEast": "1story-gable-roof",
	"TwoStoryWideSouthEast": "2story-wide",
	"TwoStorySlimSouthEast": "2story-slim",
	"ThreeStorySmallSouthEast": "3story-small",
	"TwoStorySouthEast": "2story",
	"OneStorySouthWestInner": "1story",
	"GableRoofSouthWestInner": "1story-gable-roof",
	"TwoStoryWideSouthMiddle": "2story-wide",
	"TwoStorySlimSouthMiddle": "2story-slim",
	"ThreeStorySmallSouthMiddle": "3story-small",
	"TwoStorySouthMiddle": "2story",
	"FourStorySouthEastInner": "4story",
	"SixStorySouthEastInner": "6story-stack",
	"OneStorySouthEastInner": "1story",
	"GableRoofSouthEastInner": "1story-gable-roof",
	"OneStoryNorthWestWest": "1story",
	"GableRoofNorthWestEast": "1story-gable-roof",
	"OneStoryNorthMiddleWest": "1story",
	"GableRoofNorthMiddleEast": "1story-gable-roof",
	"OneStoryNorthEastWest": "1story",
	"GableRoofNorthEastEast": "1story-gable-roof",
	"OneStoryMiddleWestWest": "1story",
	"GableRoofMiddleWestEast": "1story-gable-roof",
	"OneStoryMiddleEastWest": "1story",
	"GableRoofMiddleEastEast": "1story-gable-roof",
	"OneStorySouthWestWest": "1story",
	"GableRoofSouthWestEast": "1story-gable-roof",
	"OneStorySouthMiddleWest": "1story",
	"GableRoofSouthMiddleEast": "1story-gable-roof",
	"OneStorySouthEastWest": "1story",
	"GableRoofSouthEastEast": "1story-gable-roof",
}

const GRID_ROAD_TILES := {
	"NorthWestEntrance": {"scene": "street_3way.glb", "position": Vector3(-30, 0, -82), "rotation_y": PI / 2.0},
	"SouthWestEntrance": {"scene": "street_3way.glb", "position": Vector3(-30, 0, 98), "rotation_y": -PI / 2.0},
	"WestSouthEntrance": {"scene": "street_3way.glb", "position": Vector3(-90, 0, 38), "rotation_y": PI},
	"EastSouthEntrance": {"scene": "street_3way.glb", "position": Vector3(90, 0, 38), "rotation_y": 0.0},
	"NorthWestCrossing": {"scene": "street_4way.glb", "position": Vector3(-30, 0, -22), "rotation_y": 0.0},
	"MainCrossing": {"scene": "street_4way.glb", "position": Vector3(30, 0, -22), "rotation_y": 0.0},
	"SouthWestCrossing": {"scene": "street_4way.glb", "position": Vector3(-30, 0, 38), "rotation_y": 0.0},
	"SouthEastCrossing": {"scene": "street_4way.glb", "position": Vector3(30, 0, 38), "rotation_y": 0.0},
	"WestNorthA": {"scene": "street_straight.glb", "position": Vector3(-30, 0, -62), "rotation_y": PI / 2.0},
	"WestNorthB": {"scene": "street_straight.glb", "position": Vector3(-30, 0, -42), "rotation_y": PI / 2.0},
	"WestSouthA": {"scene": "street_straight.glb", "position": Vector3(-30, 0, -2), "rotation_y": PI / 2.0},
	"WestSouthB": {"scene": "street_straight.glb", "position": Vector3(-30, 0, 18), "rotation_y": PI / 2.0},
	"WestSouthC": {"scene": "street_straight.glb", "position": Vector3(-30, 0, 58), "rotation_y": PI / 2.0},
	"WestSouthD": {"scene": "street_straight.glb", "position": Vector3(-30, 0, 78), "rotation_y": PI / 2.0},
	"SouthWestA": {"scene": "street_straight.glb", "position": Vector3(-70, 0, 38), "rotation_y": 0.0},
	"SouthWestB": {"scene": "street_straight.glb", "position": Vector3(-50, 0, 38), "rotation_y": 0.0},
	"SouthWestC": {"scene": "street_straight.glb", "position": Vector3(-10, 0, 38), "rotation_y": 0.0},
	"SouthWestD": {"scene": "street_straight.glb", "position": Vector3(10, 0, 38), "rotation_y": 0.0},
	"SouthEastA": {"scene": "street_straight.glb", "position": Vector3(50, 0, 38), "rotation_y": 0.0},
	"SouthEastB": {"scene": "street_straight.glb", "position": Vector3(70, 0, 38), "rotation_y": 0.0},
}

const BUILDING_X_COLUMNS := [-74.0, -70.0, -50.0, -46.0, -14.0, -10.0, 10.0, 14.0, 46.0, 50.0, 70.0, 74.0]
const BUILDING_Z_ROWS := [-66.0, -52.0, -38.0, -6.0, 8.0, 22.0, 54.0, 68.0, 82.0]
const MIN_ROAD_SETBACK := 1.0
const BLOCK_BUILDING_COUNTS := {
	"north_west": 6,
	"north_middle": 6,
	"north_east": 6,
	"middle_west": 6,
	"middle_east": 6,
	"south_west": 6,
	"south_middle": 6,
	"south_east": 6,
}
const ROAD_SCENE_NAMES := [
	"street_straight.glb",
	"street_curve.glb",
	"street_3way.glb",
	"street_4way.glb",
]
const SATELLITE_LAYOUTS := {
	"NorthDistrict": {"position": Vector3(0, 0, -292), "rotation_y": 0.0},
	"SouthDistrict": {"position": Vector3(0, 0, 308), "rotation_y": PI},
	"WestDistrict": {"position": Vector3(-300, 0, 8), "rotation_y": PI / 2.0},
	"EastDistrict": {"position": Vector3(300, 0, 8), "rotation_y": -PI / 2.0},
}
const CORRIDOR_LAYOUTS := {
	"NorthCorridor": {"position": Vector3(-28.49157, 0.01, -88.53653), "rotation_y": 1.3439975, "scale": Vector3(0.75, 1, 1)},
	"SouthCorridor": {"position": Vector3(-28.49157, 0.01, 104.53653), "rotation_y": -1.3439975, "scale": Vector3(0.75, 1, 1)},
	"WestCorridor": {"position": Vector3(-96.53653, 0.01, 36.49157), "rotation_y": 2.9147937, "scale": Vector3(0.75, 1, 1)},
	"EastCorridor": {"position": Vector3(96.53653, 0.01, 36.49157), "rotation_y": 0.22679885, "scale": Vector3(0.75, 1, 1)},
}
const APPROVED_CAMERA_BASIS_X := Vector3(0.71324474, 0, -0.7009151)
const APPROVED_CAMERA_BASIS_Y := Vector3(-0.3791764, 0.8410397, -0.3858464)
const APPROVED_CAMERA_BASIS_Z := Vector3(0.58949745, 0.5409734, 0.59986717)
const APPROVED_CAMERA_ORIGIN := Vector3(78.46123, 72.81983, 88.0357)


func _init() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		push_error("Unable to load main scene: %s" % MAIN_SCENE)
		quit(1)
		return

	var instance := packed_scene.instantiate()
	if instance == null:
		push_error("Unable to instantiate main scene: %s" % MAIN_SCENE)
		quit(1)
		return

	root.add_child(instance)
	call_deferred("_validate_instance", instance)


func _validate_instance(instance: Node) -> void:
	if not _validate_world_structure(instance):
		quit(1)
		return
	if not _validate_tread_animations(instance):
		quit(1)
		return
	if not await _validate_turret_aiming(instance):
		quit(1)
		return
	if not _validate_camera_zoom(instance):
		quit(1)
		return
	if not _validate_player_runtime_and_look_ahead(instance):
		quit(1)
		return
	if not await _validate_camera_shake(instance):
		quit(1)
		return
	if not await _validate_projectile_firing(instance):
		quit(1)
		return
	if not await _validate_visual_recoil(instance):
		quit(1)
		return
	if not _validate_collision_layout(instance):
		quit(1)
		return
	if not _validate_map_960(instance):
		quit(1)
		return
	if not _validate_grid_layout(instance):
		quit(1)
		return

	print("Tank Skirmish smoke validation passed.")
	quit(0)


func _validate_tread_animations(instance: Node) -> bool:
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	if tank == null:
		push_error("Tank must exist before tread animations can be validated")
		return false
	if not tank.tread_animations_available or tank.tread_animation_player == null:
		push_error("Tank tread AnimationPlayer and required clips must be available")
		return false

	for clip: StringName in [&"Tank_Forward", &"Tank_Backwards", &"Tank_TurningLeft", &"Tank_TurningRight"]:
		var animation: Animation = tank.tread_animation_player.get_animation(clip)
		if animation == null or animation.loop_mode != Animation.LOOP_LINEAR:
			push_error("Tank tread clip %s must exist and loop" % clip)
			return false
		if not _tread_clip_moves_track_bones(tank, animation, clip):
			return false
	if tank._tread_animation_for_inputs(1.0, 1.0) != &"Tank_TurningLeft" or tank._tread_animation_for_inputs(-1.0, -1.0) != &"Tank_TurningRight":
		push_error("Tank turning tread clips must take priority over movement clips")
		return false
	if tank._tread_animation_for_inputs(1.0, 0.0) != &"Tank_Forward" or tank._tread_animation_for_inputs(-1.0, 0.0) != &"Tank_Backwards" or not tank._tread_animation_for_inputs(0.0, 0.0).is_empty():
		push_error("Tank tread clip selection does not match movement input")
		return false

	var original_model_scale: Vector3 = tank.tank_model.scale
	tank.tread_animation_reference_speed = 15.0
	tank.tread_animation_speed_multiplier = 1.0
	if not is_equal_approx(tank._tread_animation_speed_scale(&"Tank_Forward", 15.0), 1.0) \
			or not is_equal_approx(tank._tread_animation_speed_scale(&"Tank_Backwards", -15.0), 1.0):
		push_error("Tank straight tread speed must use the absolute actual forward speed at the reference scale")
		return false
	tank.tank_model.scale = original_model_scale * 2.0
	if not is_equal_approx(tank._tread_animation_speed_scale(&"Tank_Forward", 15.0), 0.5):
		push_error("Tank tread speed must halve when the Tank2 model scale doubles")
		return false
	tank.tank_model.scale = original_model_scale
	tank.tread_animation_speed_multiplier = 0.8
	if not is_equal_approx(tank._tread_animation_speed_scale(&"Tank_Forward", 15.0), 0.8) \
			or not is_equal_approx(tank._tread_animation_speed_scale(&"Tank_TurningLeft", 15.0), 0.8):
		push_error("Tank tread animation speed multiplier must affect straight and turning clips")
		return false

	tank._update_tread_animation(&"Tank_Forward", 0.8)
	if tank.active_tread_animation != &"Tank_Forward" or tank.tread_animation_paused:
		push_error("Tank forward tread animation did not start")
		return false
	tank._update_tread_animation(&"")
	if not tank.tread_animation_paused:
		push_error("Tank tread animation must pause when movement stops")
		return false
	tank._update_tread_animation(&"Tank_Forward", 0.8)
	if not is_equal_approx(tank.tread_animation_player.speed_scale, 0.8):
		push_error("Tank resumed tread animation must apply its current playback speed")
		return false
	return true


func _tread_clip_moves_track_bones(tank: Node, animation: Animation, clip: StringName) -> bool:
	var skeleton := _find_skeleton(tank)
	if skeleton == null:
		push_error("Tank tread animation validation requires a Skeleton3D")
		return false

	var track_bones: Array[int] = []
	for bone_id in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(bone_id)).contains("Track"):
			track_bones.append(bone_id)
	if track_bones.is_empty():
		push_error("Tank tread animation validation requires Track bones")
		return false

	tank.tread_animation_player.play(clip)
	tank.tread_animation_player.seek(0.0, true)
	tank.tread_animation_player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var baseline: Array[Transform3D] = []
	for bone_id in track_bones:
		baseline.append(skeleton.get_bone_pose(bone_id))

	for fraction in [0.25, 0.5, 0.75]:
		tank.tread_animation_player.seek(animation.length * fraction, true)
		tank.tread_animation_player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		for index in range(track_bones.size()):
			if not baseline[index].is_equal_approx(skeleton.get_bone_pose(track_bones[index])):
				return true

	push_error("Tank tread clip %s contains no visible Track bone motion" % clip)
	return false


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _validate_turret_aiming(instance: Node) -> bool:
	var tank = instance.get_node_or_null("Tank")
	if tank == null:
		push_error("Tank must exist before turret aiming can be validated")
		return false
	if not is_equal_approx(tank.turret_turn_speed, 1.777778):
		push_error("Tank turret turn speed does not match the approved value")
		return false
	if not is_equal_approx(tank.gun_pitch_speed, 1.2) or not is_equal_approx(tank.gun_max_elevation_degrees, 20.0) or not is_equal_approx(tank.gun_max_depression_degrees, 8.0):
		push_error("Tank gun pitch exports do not match the approved MVP values")
		return false

	var turret_pivot := tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	var gun_pitch_pivot := turret_pivot.get_node_or_null("GunPitchPivot") as Node3D if turret_pivot != null else null
	var muzzle_point := gun_pitch_pivot.get_node_or_null("MuzzlePoint") as Marker3D if gun_pitch_pivot != null else null
	var turret := turret_pivot.get_node_or_null("Tank_Turret") as MeshInstance3D if turret_pivot != null else null
	var gun := gun_pitch_pivot.get_node_or_null("Tank_Gun") as MeshInstance3D if gun_pitch_pivot != null else null
	if turret_pivot == null or gun_pitch_pivot == null or muzzle_point == null or turret == null or gun == null:
		push_error("Tank scene must retain permanent turret, gun, and muzzle pivots")
		return false
	if turret.get_parent() != turret_pivot or gun_pitch_pivot.get_parent() != turret_pivot or gun.get_parent() != gun_pitch_pivot:
		push_error("Tank gun pitch pivot must remain attached beneath the turret yaw pivot")
		return false
	if not gun.position.is_zero_approx() or not gun.global_position.is_equal_approx(gun_pitch_pivot.global_position):
		push_error("Tank gun must retain its authored origin when attached to the pitch pivot")
		return false

	await physics_frame
	var muzzle_position: Vector3 = tank.muzzle_global_position()
	if not is_zero_approx(tank._target_gun_pitch_for_world_target(muzzle_position + Vector3.LEFT * 20.0)) \
		or not is_equal_approx(tank._target_gun_pitch_for_world_target(muzzle_position + Vector3.LEFT * 20.0 + Vector3.UP * 20.0), deg_to_rad(20.0)) \
		or not is_equal_approx(tank._target_gun_pitch_for_world_target(muzzle_position + Vector3.LEFT * 20.0 + Vector3.DOWN * 20.0), deg_to_rad(-8.0)):
		push_error("World-space targets must map to bounded gun elevation and depression angles")
		return false

	var high_muzzle: Vector3 = tank.muzzle_global_position()
	tank.aim_gun_pitch_at_target(high_muzzle + Vector3.LEFT * 20.0 + Vector3.UP * 20.0, 10.0)
	var raised_muzzle_forward := -gun_pitch_pivot.global_transform.basis.x.normalized()
	if not is_equal_approx(gun_pitch_pivot.rotation.z, deg_to_rad(-20.0)) or raised_muzzle_forward.y < 0.33:
		push_error("A high world target must elevate the gun without exceeding 20 degrees")
		return false
	var low_muzzle: Vector3 = tank.muzzle_global_position()
	tank.aim_gun_pitch_at_target(low_muzzle + Vector3.LEFT * 20.0 + Vector3.DOWN * 20.0, 10.0)
	var lowered_muzzle_forward := -gun_pitch_pivot.global_transform.basis.x.normalized()
	if not is_equal_approx(gun_pitch_pivot.rotation.z, deg_to_rad(8.0)) or lowered_muzzle_forward.y > -0.13:
		push_error("A low world target must depress the gun without exceeding 8 degrees")
		return false
	var level_muzzle: Vector3 = tank.muzzle_global_position()
	tank.aim_gun_pitch_at_target(level_muzzle + Vector3.LEFT * 20.0, 10.0)
	if not is_zero_approx(gun_pitch_pivot.rotation.z):
		push_error("A level world target must return the gun to neutral pitch")
		return false

	var chassis_position: Vector3 = tank.global_position
	var chassis_rotation: Vector3 = tank.global_rotation
	var plus_z_target: Vector3 = turret_pivot.global_position + Vector3.BACK * 20.0
	tank.aim_turret_at(plus_z_target, 10.0)
	var muzzle_forward := -gun_pitch_pivot.global_transform.basis.x.normalized()
	if muzzle_forward.dot(Vector3.BACK) < 0.999:
		push_error("Tank local -X muzzle axis must rotate toward a +Z target")
		return false
	if not tank.global_position.is_equal_approx(chassis_position) or not tank.global_rotation.is_equal_approx(chassis_rotation):
		push_error("Turret aiming must not move or rotate the tank chassis")
		return false

	var held_yaw := turret_pivot.global_rotation.y
	tank.aim_turret_at(turret_pivot.global_position, 1.0)
	if not is_equal_approx(turret_pivot.global_rotation.y, held_yaw) or is_nan(turret_pivot.global_rotation.y):
		push_error("A near turret target must preserve the current yaw")
		return false

	var held_pitch := gun_pitch_pivot.rotation.z
	var dead_zone_target := turret_pivot.global_position + Vector3(2.0, 10.0, 0.0)
	tank.aim_turret_at(dead_zone_target, 10.0)
	tank.aim_gun_pitch_at_target(dead_zone_target, 10.0)
	if not is_equal_approx(turret_pivot.global_rotation.y, held_yaw) \
			or not is_equal_approx(gun_pitch_pivot.rotation.z, held_pitch):
		push_error("A target within the 3m turret-center dead zone must preserve yaw and pitch")
		return false

	var fallback_origin := Vector3(1000.0, 1000.0, 1000.0)
	var aim_controller = instance.get_node_or_null("PlayerRuntime/PlayerAimController")
	var presentation = instance.get_node_or_null("PlayerRuntime/AimPresentation")
	if aim_controller == null or presentation == null:
		push_error("Player aim controller and presentation must exist")
		return false
	var fallback_target: Vector3 = aim_controller.resolve_world_target_from_ray(fallback_origin, Vector3.UP)
	if not fallback_target.is_equal_approx(fallback_origin + Vector3.UP * 180.0):
		push_error("A camera ray without a hit must fall back to its point 180m away")
		return false
	var ground_target: Vector3 = aim_controller.resolve_world_target_from_ray(Vector3(110.0, 5.0, 110.0), Vector3.DOWN)
	if not is_zero_approx(ground_target.y):
		push_error("Mouse world targeting must use the first ground collision")
		return false

	var aim_target := StaticBody3D.new()
	aim_target.name = "AimSmokeTarget"
	aim_target.position = Vector3(1010.0, 5.0, 1000.0)
	var aim_target_collision := CollisionShape3D.new()
	var aim_target_shape := BoxShape3D.new()
	aim_target_shape.size = Vector3(2.0, 2.0, 2.0)
	aim_target_collision.shape = aim_target_shape
	aim_target.add_child(aim_target_collision)
	instance.add_child(aim_target)
	await physics_frame
	var building_target: Vector3 = aim_controller.resolve_world_target_from_ray(Vector3(1000.0, 5.0, 1000.0), Vector3.RIGHT)
	if building_target.distance_to(Vector3(1009.0, 5.0, 1000.0)) > 0.01:
		push_error("Mouse world targeting must use the first building collision")
		return false

	var actual_line := presentation.actual_aim_line as MeshInstance3D
	var mouse_line := presentation.mouse_aim_line as MeshInstance3D
	if actual_line == null or mouse_line == null or actual_line.name != "ActualAimLine" or mouse_line.name != "MouseAimLine":
		push_error("Tank must create white actual and red mouse aim line nodes")
		return false
	var actual_material := actual_line.material_override as StandardMaterial3D
	var mouse_material := mouse_line.material_override as StandardMaterial3D
	if actual_material == null or mouse_material == null \
			or not is_equal_approx(actual_material.albedo_color.a, 0.7) \
			or not is_equal_approx(mouse_material.albedo_color.a, 0.7) \
			or actual_material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA \
			or mouse_material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA \
			or not actual_material.no_depth_test \
			or not mouse_material.no_depth_test \
			or actual_material.render_priority != Material.RENDER_PRIORITY_MAX \
			or mouse_material.render_priority != Material.RENDER_PRIORITY_MAX:
		push_error("Both aim lines must use maximum render priority, disable depth testing, and use 0.7 alpha transparency")
		return false
	presentation._set_aim_line_segment(actual_line, Vector3.ZERO, Vector3.ZERO)
	if actual_line.visible:
		push_error("A degenerate aim line shorter than 0.05m must be hidden")
		return false
	presentation._set_aim_line_segment(actual_line, Vector3.ZERO, Vector3.UP * 10.0)
	if not actual_line.visible or not actual_line.global_transform.is_finite():
		push_error("A near-vertical aim line must keep a finite transform")
		return false
	presentation._set_aim_line_path(actual_line, Vector3.ZERO, Vector3.RIGHT * 3.0)
	if actual_line.visible:
		push_error("An aim path ending within the 3m tank clearance must be hidden")
		return false

	gun_pitch_pivot.rotation.z = 0.0
	var current_muzzle: Vector3 = tank.muzzle_global_position()
	var current_direction: Vector3 = tank.muzzle_global_direction()
	presentation.set_world_target(current_muzzle + current_direction * 20.0)
	if mouse_line.visible or not actual_line.visible:
		push_error("Red mouse line must hide when it overlaps the white firing direction")
		return false
	var actual_line_start := actual_line.global_transform.origin - actual_line.global_transform.basis.y * 0.5
	if not actual_line_start.is_equal_approx(current_muzzle + current_direction * 3.0):
		push_error("White aim line must hide its first 3m from the muzzle")
		return false
	presentation.set_world_target(current_muzzle + Vector3.RIGHT * 20.0)
	if not mouse_line.visible:
		push_error("Red mouse line must show while the gun is still turning toward the target")
		return false
	var mouse_line_start := mouse_line.global_transform.origin - mouse_line.global_transform.basis.y * 0.5
	var mouse_line_direction := (current_muzzle + Vector3.RIGHT * 20.0 - turret_pivot.global_position).normalized()
	var tank_collision := tank.get_node("CollisionShape3D") as CollisionShape3D
	var tank_collision_box := tank_collision.shape as BoxShape3D
	var tank_collision_half_size := tank_collision_box.size * 0.5
	var tank_corner_radius := 0.0
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var corner := tank_collision.global_transform * Vector3(
					tank_collision_half_size.x * x_sign,
					tank_collision_half_size.y * y_sign,
					tank_collision_half_size.z * z_sign,
				)
				tank_corner_radius = maxf(tank_corner_radius, turret_pivot.global_position.distance_to(corner))
	var mouse_clearance_distance := tank_corner_radius + 3.0
	if not mouse_line_start.is_equal_approx(turret_pivot.global_position + mouse_line_direction * mouse_clearance_distance):
		push_error("Red mouse line must clear the tank and another 3m before becoming visible")
		return false

	aim_target.queue_free()
	await physics_frame

	return true


func _validate_camera_zoom(instance: Node) -> bool:
	var camera_controller = instance.get_node_or_null("CameraRig")
	var projectiles := instance.get_node_or_null("CombatRuntime/Projectiles") as Node3D
	if camera_controller == null or camera_controller.camera == null or projectiles == null:
		push_error("Camera zoom validation requires CameraRig, Camera3D, and Projectiles nodes")
		return false
	if ProjectSettings.get_setting("display/window/stretch/mode") != "canvas_items" \
			or instance.get_window().content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		push_error("The game window must use canvas-items scaling with runtime expand adaptation")
		return false
	if camera_controller.camera.projection != Camera3D.PROJECTION_ORTHOGONAL \
			or camera_controller.camera.keep_aspect != Camera3D.KEEP_HEIGHT:
		push_error("The orthogonal camera must preserve vertical framing across aspect ratios")
		return false

	var initial_size: float = camera_controller.camera.size
	var projectile_count := projectiles.get_child_count()
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	camera_controller._unhandled_input(wheel_up)
	if not is_equal_approx(camera_controller.camera.size, maxf(25.0, initial_size - 5.0)) or projectiles.get_child_count() != projectile_count:
		push_error("Wheel-up press must zoom in by 5 without firing a projectile")
		return false

	var wheel_release := InputEventMouseButton.new()
	wheel_release.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_release.pressed = false
	var size_before_release: float = camera_controller.camera.size
	camera_controller._unhandled_input(wheel_release)
	if not is_equal_approx(camera_controller.camera.size, size_before_release) or projectiles.get_child_count() != projectile_count:
		push_error("Wheel release must not change camera zoom or fire a projectile")
		return false

	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	camera_controller._unhandled_input(wheel_down)
	if not is_equal_approx(camera_controller.camera.size, minf(100.0, size_before_release + 5.0)) or projectiles.get_child_count() != projectile_count:
		push_error("Wheel-down press must zoom out by 5 without firing a projectile")
		return false

	camera_controller.camera.size = 25.0
	camera_controller._unhandled_input(wheel_up)
	if not is_equal_approx(camera_controller.camera.size, 25.0):
		push_error("Wheel-up zoom must not go below the 25 camera-size minimum")
		return false
	camera_controller.camera.size = 100.0
	camera_controller._unhandled_input(wheel_down)
	if not is_equal_approx(camera_controller.camera.size, 100.0):
		push_error("Wheel-down zoom must not exceed the 100 camera-size maximum")
		return false

	camera_controller.camera.size = initial_size
	return true


func _validate_player_runtime_and_look_ahead(instance: Node) -> bool:
	var runtime = instance.get_node_or_null("PlayerRuntime")
	var tank = instance.get_node_or_null("Tank")
	var camera_controller = instance.get_node_or_null("CameraRig")
	var player_controller = instance.get_node_or_null("PlayerRuntime/PlayerController")
	var aim_controller = instance.get_node_or_null("PlayerRuntime/PlayerAimController")
	var presentation = instance.get_node_or_null("PlayerRuntime/AimPresentation")
	var combat_runtime = instance.get_node_or_null("CombatRuntime")
	if runtime == null or tank == null or camera_controller == null or player_controller == null or aim_controller == null or presentation == null or combat_runtime == null:
		push_error("PlayerRuntime must contain player input, aim, and presentation while CombatRuntime owns world combat.")
		return false
	if runtime.controlled_tank != tank or camera_controller.follow_target != tank \
			or player_controller.controlled_tank != tank or aim_controller.controlled_tank != tank \
			or aim_controller.camera != camera_controller.camera or presentation.controlled_tank != tank:
		push_error("PlayerRuntime must be the authoritative controlled_tank registration point")
		return false
	if instance.get_node_or_null("PlayerAimController") != null or instance.get_node_or_null("AimPresentation") != null:
		push_error("Player aim and presentation must only exist beneath PlayerRuntime")
		return false
	if tank.has_method("set_projectile_container"):
		push_error("Tank must not retain world projectile container dependencies")
		return false
	player_controller.apply_commands(1.0, -1.0, false)
	if not is_equal_approx(tank.movement_command, 1.0) or not is_equal_approx(tank.turn_command, -1.0):
		push_error("Composed PlayerController movement and turn commands must reach Tank unchanged")
		return false
	tank.set_movement_input(-1.0)
	tank.set_turn_input(1.0)
	if not is_equal_approx(tank.movement_command, -1.0) or not is_equal_approx(tank.turn_command, 1.0):
		push_error("Direct Tank movement and turn commands must retain the same command contract")
		return false
	tank.set_movement_input(0.0)
	tank.set_turn_input(0.0)
	var aim_target: Vector3 = tank.turret_pivot.global_position + Vector3.BACK * 20.0 + Vector3.UP * 8.0
	var yaw_before: float = tank.turret_pivot.global_rotation.y
	var pitch_before: float = tank.gun_pitch_pivot.rotation.z
	tank.aim_turret_at(aim_target, 10.0)
	tank.aim_gun_pitch_at_target(aim_target, 10.0)
	var direct_yaw: float = tank.turret_pivot.global_rotation.y
	var direct_pitch: float = tank.gun_pitch_pivot.rotation.z
	tank.turret_pivot.global_rotation.y = yaw_before
	tank.gun_pitch_pivot.rotation.z = pitch_before
	aim_controller.apply_aim(aim_target, 10.0)
	if not is_equal_approx(tank.turret_pivot.global_rotation.y, direct_yaw) or not is_equal_approx(tank.gun_pitch_pivot.rotation.z, direct_pitch):
		push_error("Composed PlayerAimController and direct Tank aim commands must have identical results")
		return false
	var center_offset: Vector3 = camera_controller.calculate_look_ahead_offset(Vector2(0.1, 0.1))
	var right_offset: Vector3 = camera_controller.calculate_look_ahead_offset(Vector2.RIGHT)
	var bottom_offset: Vector3 = camera_controller.calculate_look_ahead_offset(Vector2.DOWN)
	var corner_offset: Vector3 = camera_controller.calculate_look_ahead_offset(Vector2.ONE)
	if not center_offset.is_zero_approx() or right_offset.is_zero_approx() or bottom_offset.is_zero_approx() or corner_offset.is_zero_approx() \
			or right_offset.y != 0.0 or bottom_offset.y != 0.0 or corner_offset.y != 0.0 \
			or right_offset.length() > tank.get_max_camera_look_ahead_distance() + 0.001 \
			or bottom_offset.length() > tank.get_max_camera_look_ahead_distance() + 0.001 \
			or corner_offset.length() > tank.get_max_camera_look_ahead_distance() + 0.001:
		push_error("Camera look-ahead must be continuous, XZ-only, and bounded by the Tank authority")
		return false
	var baseline_offset: Vector3 = camera_controller.follow_target_offset
	tank.global_position += Vector3(4.0, 0.0, -3.0)
	camera_controller._process(0.0)
	if not camera_controller.global_position.is_equal_approx(tank.global_position + baseline_offset):
		push_error("Tank follow must be immediate while only look-ahead smoothing is deferred")
		return false
	tank.global_position -= Vector3(4.0, 0.0, -3.0)
	return true


func _validate_camera_shake(instance: Node) -> bool:
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	var camera_controller := instance.get_node_or_null("CameraRig") as Node3D
	var shake_pivot := instance.get_node_or_null("CameraRig/CameraShakePivot") as Node3D
	var camera := instance.get_node_or_null("CameraRig/CameraShakePivot/Camera3D") as Camera3D
	var projectiles := instance.get_node_or_null("CombatRuntime/Projectiles") as Node3D
	if tank == null or camera_controller == null or shake_pivot == null or camera == null or projectiles == null:
		push_error("Camera shake requires the CameraRig/CameraShakePivot/Camera3D wiring and Tank shot source")
		return false
	if not shake_pivot.position.is_zero_approx() or not shake_pivot.rotation.is_zero_approx() \
			or not _has_approved_camera_transform(camera) or camera.projection != Camera3D.PROJECTION_ORTHOGONAL \
			or not is_equal_approx(camera.size, 100.0) or camera.keep_aspect != Camera3D.KEEP_HEIGHT or not camera.current:
		push_error("CameraShakePivot must begin at identity without changing Camera3D's approved local settings")
		return false

	var shot_events: Array[ShotEvent] = []
	tank.shot_event_fired.connect(func(shot_event: ShotEvent) -> void: shot_events.append(shot_event))
	tank.request_fire()
	if shot_events.size() != 1 or shake_pivot.position.is_zero_approx() or is_zero_approx(shake_pivot.rotation.z):
		push_error("Each valid controlled-tank ShotEvent must immediately start exactly one positional and roll camera shake")
		return false
	var expected_local_recoil := camera_controller.global_transform.basis.inverse() * -shot_events[0].direction
	expected_local_recoil.y = 0.0
	if expected_local_recoil.is_zero_approx() or shake_pivot.position.normalized().dot(expected_local_recoil.normalized()) < 0.999 \
			or shake_pivot.position.length() > 0.451:
		push_error("Camera shake must use the ShotEvent horizontal world-opposite direction within its local bound")
		return false

	camera_controller._process(0.08)
	tank.turret_pivot.rotation.y += PI / 2.0
	tank.request_fire()
	if shot_events.size() != 2 or shake_pivot.position.length() > 0.451 or shake_pivot.rotation.length() > deg_to_rad(1.501):
		push_error("Repeated controlled-tank shots must replace the prior bounded camera shake")
		return false
	for _frame in range(5):
		camera_controller._process(0.05)
	if not shake_pivot.position.is_zero_approx() or not shake_pivot.rotation.is_zero_approx():
		push_error("Camera shake must return its pivot to identity without local drift")
		return false

	camera_controller.play_shot_recoil(ShotEvent.new(Transform3D.IDENTITY, Vector3.ZERO, tank.get_rid()))
	camera_controller.play_shot_recoil(ShotEvent.new(Transform3D.IDENTITY, Vector3(INF, 0.0, 0.0), tank.get_rid()))
	if not shake_pivot.position.is_zero_approx() or not shake_pivot.rotation.is_zero_approx():
		push_error("Invalid, near-zero, or non-finite shot directions must not start camera shake")
		return false
	for projectile in projectiles.get_children():
		projectile.queue_free()
	for child in tank.muzzle_point.get_children():
		if child.name == "MuzzleFlash":
			child.queue_free()
	await process_frame
	return projectiles.get_child_count() == 0


func _validate_visual_recoil(instance: Node) -> bool:
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	var projectiles := instance.get_node_or_null("CombatRuntime/Projectiles") as Node3D
	if tank == null or projectiles == null:
		push_error("Visual recoil validation requires Tank and the Projectiles container")
		return false
	var recoil_pivot := tank.get_node_or_null("VisualRecoilPivot") as Node3D
	var collision := tank.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if recoil_pivot == null or collision == null \
			or recoil_pivot.get_node_or_null("Tank2") == null \
			or recoil_pivot.get_node_or_null("TurretPivot/GunPitchPivot/MuzzlePoint") == null \
			or collision.get_parent() != tank:
		push_error("Tank visual recoil pivot must own all visible tank nodes while collision stays at the physics root")
		return false
	if not is_equal_approx(tank.visual_recoil_distance, 0.36) \
			or not is_equal_approx(tank.visual_recoil_kick_seconds, 0.04) \
			or not is_equal_approx(tank.visual_recoil_return_seconds, 0.18):
		push_error("Tank visual recoil exports must retain the approved defaults")
		return false

	var rest_position := recoil_pivot.position
	var root_transform := tank.global_transform
	var collision_transform := collision.global_transform
	var initial_velocity := tank.velocity
	var first_direction: Vector3 = tank.muzzle_global_direction()
	tank.request_fire()
	if projectiles.get_child_count() != 1:
		push_error("A valid Tank fire request must create exactly one projectile while starting visual recoil")
		return false
	await create_timer(tank.visual_recoil_kick_seconds + 0.01).timeout
	await process_frame
	var first_offset := recoil_pivot.global_position - tank.to_global(rest_position)
	if first_offset.length() <= 0.001 or first_offset.normalized().dot(-first_direction) < 0.999 \
			or first_offset.length() > tank.visual_recoil_distance + 0.001:
		push_error("Visual recoil must move opposite the firing MuzzlePoint direction within its configured bound")
		return false
	if not tank.global_transform.is_equal_approx(root_transform) \
			or not collision.global_transform.is_equal_approx(collision_transform) \
			or not tank.velocity.is_equal_approx(initial_velocity):
		push_error("Visual recoil must not move Tank physics, collision, or velocity")
		return false
	await create_timer(tank.visual_recoil_kick_seconds + tank.visual_recoil_return_seconds + 0.02).timeout
	await process_frame
	if not recoil_pivot.position.is_equal_approx(rest_position):
		push_error("Visual recoil must return exactly to its original local position")
		return false

	tank.request_fire()
	await create_timer(tank.visual_recoil_kick_seconds + 0.01).timeout
	await process_frame
	tank.turret_pivot.rotation.y += PI / 2.0
	var latest_direction: Vector3 = tank.muzzle_global_direction()
	tank.request_fire()
	await create_timer(tank.visual_recoil_kick_seconds + 0.01).timeout
	await process_frame
	var latest_offset := recoil_pivot.global_position - tank.to_global(rest_position)
	if latest_offset.length() <= 0.001 or latest_offset.normalized().dot(-latest_direction) < 0.999 \
			or latest_offset.length() > tank.visual_recoil_distance + 0.001:
		push_error("Repeated fire must restart bounded recoil using the latest MuzzlePoint direction")
		return false
	await create_timer(tank.visual_recoil_kick_seconds + tank.visual_recoil_return_seconds + 0.02).timeout
	await process_frame
	if not recoil_pivot.position.is_equal_approx(rest_position):
		push_error("Repeated visual recoil must not accumulate local-position drift")
		return false

	for projectile in projectiles.get_children():
		projectile.queue_free()
	for child in tank.muzzle_point.get_children():
		if child.name == "MuzzleFlash":
			child.queue_free()
	await process_frame
	if projectiles.get_child_count() != 0:
		push_error("Visual recoil validation must clean up its test projectiles")
		return false
	return true


func _validate_projectile_firing(instance: Node) -> bool:
	var tank = instance.get_node_or_null("Tank")
	var player_controller = instance.get_node_or_null("PlayerRuntime/PlayerController")
	var projectiles := instance.get_node_or_null("CombatRuntime/Projectiles") as Node3D
	var effects := instance.get_node_or_null("CombatRuntime/Effects") as Node3D
	var ground_collision := instance.get_node_or_null("World/Ground") as StaticBody3D
	if tank == null or player_controller == null or projectiles == null or effects == null or ground_collision == null:
		push_error("Tank firing requires PlayerController, CombatRuntime containers, and World/Ground nodes")
		return false
	if projectiles.get_child_count() != 0 or effects.get_child_count() != 0:
		push_error("Projectiles and Effects must begin as separate, empty runtime containers")
		return false
	if ground_collision.collision_layer != 128 or ground_collision.collision_mask != 0:
		push_error("Ground collision must stay isolated on physics layer 8")
		return false
	if tank.collision_layer != 1 or tank.collision_mask != 1:
		push_error("Tank physics layers must remain unchanged")
		return false

	var expected_muzzle: Vector3 = tank.muzzle_point.global_position
	var muzzle_position: Vector3 = tank.muzzle_global_position()
	var muzzle_direction: Vector3 = tank.muzzle_global_direction()
	if not muzzle_position.is_equal_approx(expected_muzzle):
		push_error("Projectile origin must use the Tank_Gun local -X endpoint")
		return false
	if not is_equal_approx(muzzle_direction.length(), 1.0) or muzzle_direction.dot((-tank.muzzle_point.global_transform.basis.x).normalized()) < 0.999:
		push_error("Projectile direction must use the MuzzlePoint world -X axis")
		return false

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	player_controller._unhandled_input(release_event)
	if projectiles.get_child_count() != 0:
		push_error("Mouse release must not fire a projectile")
		return false
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	player_controller._unhandled_input(right_click)
	if projectiles.get_child_count() != 0:
		push_error("Non-left mouse buttons must not fire a projectile")
		return false

	var shot_events: Array[Dictionary] = []
	tank.shot_fired.connect(func(shot_event: Dictionary) -> void: shot_events.append(shot_event))
	tank.request_fire()
	if shot_events.size() != 1 or projectiles.get_child_count() != 1:
		push_error("Each valid direct Tank request_fire must emit one Shot Event and create one projectile")
		return false
	var first_shot: Dictionary = shot_events[0]
	var shot_transform: Transform3D = first_shot.get("muzzle_transform", Transform3D.IDENTITY)
	var shot_rid: RID = first_shot.get("shooter_rid", RID())
	if not shot_transform.is_equal_approx(tank.muzzle_point.global_transform) or shot_rid != tank.get_rid():
		push_error("Shot Event must carry the authoritative MuzzlePoint transform and shooter collision RID")
		return false
	var direct_projectile := projectiles.get_child(0) as TankProjectile
	if direct_projectile == null:
		push_error("Projectiles may only contain TankProjectile instances")
		return false

	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	player_controller._unhandled_input(press_event)
	if shot_events.size() != 2 or projectiles.get_child_count() != 2:
		push_error("Each PlayerController fire request must emit one Shot Event and create one projectile")
		return false
	var projectile := projectiles.get_child(1) as TankProjectile
	var muzzle_flash := tank.muzzle_point.get_node_or_null("MuzzleFlash") as Node3D
	if projectile == null or muzzle_flash == null:
		push_error("Left mouse press must create one projectile and one muzzle flash")
		return false
	if not projectile.global_position.is_equal_approx(muzzle_position) or not projectile.direction.is_equal_approx(muzzle_direction):
		push_error("Projectile must start at the current muzzle transform")
		return false
	if not is_equal_approx(projectile.speed, 120.0) or not is_equal_approx(projectile.max_distance, 180.0) or projectile.collision_mask != 129:
		push_error("Projectile MVP speed, range, or collision mask changed")
		return false
	if not projectile.excluded_rids.has(tank.get_rid()):
		push_error("Projectile ray must exclude the firing tank RID")
		return false
	var javelin_vfx := projectile.get_node_or_null("JavelinVFX") as Node3D
	var javelin_head := javelin_vfx.get_node_or_null("Head") as Node3D if javelin_vfx != null else null
	if javelin_vfx == null or javelin_vfx.scene_file_path != "res://assets/BinbunVFX/magic_projectiles/effects/mprojectile_javelin/mprojectile_javelin_vfx_01.tscn" \
			or projectile.get_node_or_null("Mesh") != null or javelin_head == null \
			or (javelin_head.global_position - projectile.global_position).dot(projectile.direction) <= 0.0:
		push_error("Projectile must instance the forward-facing Javelin VFX without the legacy CapsuleMesh")
		return false
	if not bool(muzzle_flash.get("one_shot")):
		push_error("Muzzle flash must play once per shot")
		return false
	if not muzzle_flash.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE * 4.0):
		push_error("Muzzle flash acceptance scale must remain 4x")
		return false
	var flash_start := muzzle_flash.global_position
	var projectile_start := projectile.global_position
	var tank_start: Vector3 = tank.global_position
	var tank_motion := Vector3(2.0, 0.0, -1.0)
	tank.global_position += tank_motion
	if not muzzle_flash.global_position.is_equal_approx(flash_start + tank_motion):
		push_error("Muzzle flash must follow tank and gun movement during its lifetime")
		return false
	if not projectile.global_position.is_equal_approx(projectile_start):
		push_error("A fired projectile must remain in world space when the tank moves")
		return false
	tank.global_position = tank_start

	var self_hit: Dictionary = projectile._collision_between(Vector3(-15.0, 1.8, 8.0), Vector3(15.0, 1.8, 8.0))
	if not self_hit.is_empty():
		push_error("Projectile sweep must not hit the firing tank")
		return false
	var ground_hit: Dictionary = projectile._collision_between(Vector3(110.0, 5.0, 110.0), Vector3(110.0, -5.0, 110.0))
	if ground_hit.is_empty() or ground_hit.get("collider") != ground_collision:
		push_error("Projectile sweep must detect the isolated ground collider")
		return false
	var ground_hit_position := ground_hit.get("position", Vector3.INF) as Vector3
	if not is_equal_approx(ground_hit_position.y, 0.0) or not is_equal_approx(tank.global_position.y, 0.0):
		push_error("Ground ray height and stationary tank height must remain unchanged")
		return false
	projectile.queue_free()
	direct_projectile.queue_free()
	await process_frame
	if projectiles.get_child_count() != 0 or effects.get_child_count() != 0:
		push_error("Queued shots must not create impact effects before a collision")
		return false

	var target := StaticBody3D.new()
	target.name = "ProjectileSmokeTarget"
	target.position = Vector3(300.0, 2.0, 300.0)
	var target_collision := CollisionShape3D.new()
	var target_shape := BoxShape3D.new()
	target_shape.size = Vector3(2.0, 2.0, 2.0)
	target_collision.shape = target_shape
	target.add_child(target_collision)
	instance.add_child(target)
	await physics_frame
	tank.request_fire()
	if shot_events.size() != 3:
		push_error("A later valid Tank request_fire must still emit exactly one additional Shot Event")
		return false
	var collision_projectile := projectiles.get_child(projectiles.get_child_count() - 1) as TankProjectile
	if collision_projectile == null:
		push_error("CombatRuntime must add every Shot Event projectile to Projectiles")
		return false
	var hit_events: Array[Vector3] = []
	collision_projectile.hit_detected.connect(func(hit_position: Vector3, _hit_normal: Vector3) -> void: hit_events.append(hit_position))
	collision_projectile.global_position = Vector3(295.0, 2.0, 300.0)
	collision_projectile.direction = Vector3.RIGHT
	collision_projectile._physics_process(0.2)
	if hit_events.size() != 1 or not collision_projectile.is_queued_for_deletion() or effects.get_node_or_null("ImpactVFX") == null:
		push_error("A projectile collision must emit one hit, remove itself, and create one Effect")
		return false
	if projectiles.get_node_or_null("ImpactVFX") != null:
		push_error("Projectiles must never contain ImpactVFX nodes")
		return false

	var ranged_projectile := load("res://src/projectile.tscn").instantiate() as Node3D
	ranged_projectile.name = "RangeTestProjectile"
	ranged_projectile.initialize(Vector3.RIGHT, [tank.get_rid()])
	projectiles.add_child(ranged_projectile)
	ranged_projectile.global_position = Vector3(500.0, 2.0, 500.0)
	ranged_projectile._physics_process(10.0)
	if not ranged_projectile.is_queued_for_deletion() or ranged_projectile.distance_travelled > 180.001:
		push_error("Unobstructed projectiles must stop at the 180m range")
		return false

	target.queue_free()
	await process_frame
	await create_timer(1.0).timeout
	await process_frame
	if tank.muzzle_point.get_node_or_null("MuzzleFlash") != null or effects.get_node_or_null("ImpactVFX") != null:
		push_error("Transient firing VFX must clean themselves up")
		return false
	return true


func _validate_collision_layout(instance: Node) -> bool:
	var manifest := _load_manifest_dimensions()
	if manifest.is_empty():
		return false

	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	if tank == null:
		push_error("Tank must be a CharacterBody3D")
		return false
	if not is_equal_approx(tank.movement_speed, 15.0) or not is_equal_approx(tank.turn_speed, 0.8):
		push_error("Tank movement exports do not match the approved values")
		return false
	if not _validate_box_collision(tank, manifest["tank2"] * TANK_VISUAL_SCALE):
		push_error("Tank collision shape is missing, disabled, or incorrectly sized")
		return false

	for building_name: String in BUILDING_MODELS:
		var building := instance.get_node_or_null("World/Buildings/%s" % building_name) as StaticBody3D
		if building == null:
			push_error("Building %s must be a StaticBody3D" % building_name)
			return false
		if not _validate_box_collision(building, manifest[BUILDING_MODELS[building_name]]):
			push_error("Building %s collision shape is missing, disabled, or incorrectly sized" % building_name)
			return false
		if not is_equal_approx(building.rotation.y, 0.0) and not is_equal_approx(building.rotation.y, PI / 2.0):
			push_error("Building %s must use an orthogonal rotation" % building_name)
			return false

	if instance.get_node("World/Buildings").get_child_count() != BUILDING_MODELS.size():
		push_error("Building count does not match the approved town layout")
		return false

	return true


func _validate_map_960(instance: Node) -> bool:
	var ground := instance.get_node_or_null("World/Ground") as StaticBody3D
	var ground_visual := ground.get_node_or_null("Visual") as MeshInstance3D if ground != null else null
	var ground_mesh := ground_visual.mesh as BoxMesh if ground_visual != null else null
	var ground_collision := instance.get_node_or_null("World/Ground/CollisionShape3D") as CollisionShape3D
	var ground_shape := ground_collision.shape as BoxShape3D if ground_collision != null else null
	if ground_mesh == null or not ground_mesh.size.is_equal_approx(Vector3(960, 0.2, 960)) \
			or ground_shape == null or not ground_shape.size.is_equal_approx(Vector3(960, 0.2, 960)):
		push_error("Ground visual and collision must both be exactly 960m by 960m")
		return false

	var camera := instance.get_node_or_null("CameraRig/CameraShakePivot/Camera3D") as Camera3D
	if camera == null or not _has_approved_camera_transform(camera) \
			or camera.projection != Camera3D.PROJECTION_ORTHOGONAL or camera.keep_aspect != Camera3D.KEEP_HEIGHT \
			or not camera.current or not is_equal_approx(camera.size, 100.0):
		push_error("Camera3D must retain the approved orthogonal gameplay transform and size")
		return false

	var grass_field := instance.get_node_or_null("World/GrassField") as MultiMeshInstance3D
	if grass_field == null or grass_field.multimesh == null or grass_field.multimesh.instance_count != 480000:
		push_error("GrassField must contain the approved 480000 non-road, non-building instances")
		return false

	var roads := instance.get_node_or_null("World/Roads") as Node3D
	if roads == null:
		push_error("960m map requires the Roads root")
		return false
	for district_name: String in SATELLITE_LAYOUTS:
		if not _validate_layout_instance(roads, district_name, SATELLITE_LAYOUTS[district_name], "satellite_district.tscn"):
			return false
	for corridor_name: String in CORRIDOR_LAYOUTS:
		if not _validate_layout_instance(roads, corridor_name, CORRIDOR_LAYOUTS[corridor_name], "arterial_corridor.tscn"):
			return false

	var road_count := _collect_road_modules(instance).size()
	if road_count < 220 or road_count > 280:
		push_error("960m map road-module count must remain between 220 and 280, found %d" % road_count)
		return false
	var buildings := _collect_buildings(instance)
	if buildings.size() != 144:
		push_error("960m map must contain exactly 144 collision-enabled buildings, found %d" % buildings.size())
		return false
	for building in buildings:
		if building.get_node_or_null("Model") == null or not _has_enabled_box_collision(building):
			push_error("Building %s must retain its model and BoxShape3D collision" % building.name)
			return false
	for corridor_name: String in CORRIDOR_LAYOUTS:
		var corridor := roads.get_node(corridor_name) as Node3D
		if not _corridor_clears_buildings(corridor, buildings):
			return false
	return true


func _validate_layout_instance(parent: Node3D, name: String, requirement: Dictionary, scene_name: String) -> bool:
	var instance := parent.get_node_or_null(name) as Node3D
	if instance == null or instance.scene_file_path.get_file() != scene_name \
			or not instance.position.is_equal_approx(requirement["position"]) \
			or not is_equal_approx(instance.rotation.y, requirement["rotation_y"]):
		push_error("%s must keep its approved scene instance and transform" % name)
		return false
	if requirement.has("scale") and not instance.scale.is_equal_approx(requirement["scale"]):
		push_error("%s must keep its approved corridor scale" % name)
		return false
	return true


func _collect_road_modules(node: Node) -> Array[Node3D]:
	var roads: Array[Node3D] = []
	if node is Node3D and ROAD_SCENE_NAMES.has((node as Node3D).scene_file_path.get_file()):
		roads.append(node as Node3D)
	for child in node.get_children():
		roads.append_array(_collect_road_modules(child))
	return roads


func _collect_buildings(node: Node) -> Array[StaticBody3D]:
	var buildings: Array[StaticBody3D] = []
	if node is StaticBody3D and node.get_node_or_null("Model") != null:
		buildings.append(node as StaticBody3D)
	for child in node.get_children():
		buildings.append_array(_collect_buildings(child))
	return buildings


func _has_enabled_box_collision(building: StaticBody3D) -> bool:
	var collision := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return collision != null and not collision.disabled and collision.shape is BoxShape3D


func _has_approved_camera_transform(camera: Camera3D) -> bool:
	return camera.transform.basis.x.is_equal_approx(APPROVED_CAMERA_BASIS_X) \
		and camera.transform.basis.y.is_equal_approx(APPROVED_CAMERA_BASIS_Y) \
		and camera.transform.basis.z.is_equal_approx(APPROVED_CAMERA_BASIS_Z) \
		and camera.transform.origin.is_equal_approx(APPROVED_CAMERA_ORIGIN)


func _corridor_clears_buildings(corridor: Node3D, buildings: Array[StaticBody3D]) -> bool:
	var direction := corridor.global_transform.basis.x.normalized()
	var lateral := Vector3(-direction.z, 0, direction.x)
	var segment_length := 160.0 * corridor.global_transform.basis.x.length()
	var road_half_length := 10.0 * corridor.global_transform.basis.x.length()
	const ROAD_HALF_WIDTH := 10.0
	for building in buildings:
		var collision := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var shape := collision.shape as BoxShape3D if collision != null else null
		if shape == null:
			continue
		var delta := collision.global_position - corridor.global_position
		var along := delta.dot(direction)
		if along < -road_half_length or along > segment_length + road_half_length:
			continue
		var half_size := shape.size * 0.5
		var basis := collision.global_transform.basis
		var lateral_radius: float = abs(basis.x.dot(lateral)) * half_size.x \
				+ abs(basis.z.dot(lateral)) * half_size.z
		if abs(delta.dot(lateral)) < ROAD_HALF_WIDTH + lateral_radius + MIN_ROAD_SETBACK:
			push_error("Corridor %s overlaps building %s" % [corridor.name, building.name])
			return false
	return true


func _validate_grid_layout(instance: Node) -> bool:
	var roads := instance.get_node_or_null("World/Roads") as Node
	if roads == null:
		push_error("Roads node is missing")
		return false

	for road_name: String in GRID_ROAD_TILES:
		var requirement: Dictionary = GRID_ROAD_TILES[road_name]
		var road := roads.get_node_or_null(road_name) as Node3D
		if road == null:
			push_error("Required grid road %s is missing" % road_name)
			return false
		if road.scene_file_path.get_file() != requirement["scene"]:
			push_error("Grid road %s must use %s" % [road_name, requirement["scene"]])
			return false
		if not road.position.is_equal_approx(requirement["position"]) or not is_equal_approx(road.rotation.y, requirement["rotation_y"]):
			push_error("Grid road %s has an unexpected transform" % road_name)
			return false

	var block_counts := {}
	var block_edge_counts := {}
	for block_name: String in BLOCK_BUILDING_COUNTS:
		block_counts[block_name] = 0
		block_edge_counts[block_name] = {"north": 0, "south": 0, "west": 0, "east": 0}
	for building in instance.get_node("World/Buildings").get_children():
		var static_building := building as StaticBody3D
		if static_building == null:
			push_error("Buildings may only contain StaticBody3D nodes")
			return false
		if not _matches_grid_coordinate(static_building.position.x, BUILDING_X_COLUMNS) or not _matches_grid_coordinate(static_building.position.z, BUILDING_Z_ROWS):
			push_error("Building %s is not on the regular street grid" % static_building.name)
			return false
		if not _clears_road_axes(static_building):
			push_error("Building %s overlaps a road axis" % static_building.name)
			return false
		var block_name := _town_block_for(static_building.position)
		if block_name == "center":
			push_error("The tank spawn block must remain clear")
			return false
		block_counts[block_name] += 1
		for edge: String in _block_edges_for(static_building.position):
			block_edge_counts[block_name][edge] += 1

	for block_name: String in BLOCK_BUILDING_COUNTS:
		if block_counts[block_name] != BLOCK_BUILDING_COUNTS[block_name]:
			push_error("Block %s does not contain six aligned buildings" % block_name)
			return false
		for edge: String in ["north", "south", "west", "east"]:
			if block_edge_counts[block_name][edge] == 0:
				push_error("Block %s is missing buildings along its %s street edge" % [block_name, edge])
				return false
	if not _validate_building_footprints(instance.get_node("World/Buildings")):
		return false
	return true


func _validate_world_structure(instance: Node) -> bool:
	var expected_root_children := [&"CameraRig", &"Tank", &"PlayerRuntime", &"CombatRuntime", &"World"]
	if instance.get_child_count() != expected_root_children.size():
		push_error("Main scene must contain CameraRig, Tank, PlayerRuntime, CombatRuntime, and World")
		return false
	for index: int in expected_root_children.size():
		if instance.get_child(index).name != expected_root_children[index]:
			push_error("Main scene root child order must retain runtime ownership before World")
			return false
	var combat_runtime := instance.get_node_or_null("CombatRuntime") as Node3D
	var projectiles := instance.get_node_or_null("CombatRuntime/Projectiles") as Node3D
	var effects := instance.get_node_or_null("CombatRuntime/Effects") as Node3D
	if combat_runtime == null or projectiles == null or effects == null:
		push_error("CombatRuntime must inline separate Projectiles and Effects containers")
		return false

	var world := instance.get_node_or_null("World") as Node3D
	if world == null or world.scene_file_path.get_file() != "world.tscn":
		push_error("World must be an instance of world.tscn")
		return false
	for child_name: StringName in [&"Ground", &"GrassField", &"Roads", &"Buildings", &"Lighting"]:
		if world.get_node_or_null(NodePath(child_name)) == null:
			push_error("World must contain %s" % child_name)
			return false

	var ground := world.get_node_or_null("Ground") as StaticBody3D
	var visual := world.get_node_or_null("Ground/Visual") as MeshInstance3D
	var collision := world.get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as BoxShape3D if collision != null else null
	if ground == null or visual == null or collision == null or shape == null:
		push_error("Ground must be a StaticBody3D with Visual and CollisionShape3D children")
		return false
	if ground.collision_layer != 128 or ground.collision_mask != 0 or ground.physics_material_override != null:
		push_error("Ground physics properties must remain exactly equivalent")
		return false
	if not ground.global_transform.origin.is_equal_approx(Vector3(0, -0.1, 8)) or not visual.global_transform.is_equal_approx(ground.global_transform) \
			or not collision.global_transform.basis.is_equal_approx(Basis.IDENTITY) \
			or not collision.global_transform.origin.is_equal_approx(Vector3(0, -0.1, 8)) or not shape.size.is_equal_approx(Vector3(960, 0.2, 960)):
		push_error("Ground transform and collision extents must remain exactly equivalent")
		return false

	var lighting := world.get_node_or_null("Lighting") as Node3D
	var environment := lighting.get_node_or_null("WorldEnvironment") as WorldEnvironment if lighting != null else null
	if lighting == null or (lighting.get_node_or_null("Sun") as DirectionalLight3D) == null or environment == null \
			or environment.environment == null or not environment.environment.background_color.is_equal_approx(Color(0.24, 0.4, 0.56, 1)):
		push_error("Lighting must retain Sun, WorldEnvironment, and the approved background color")
		return false

	var import_file := FileAccess.open(GRASS_IMPORT, FileAccess.READ)
	if import_file == null:
		push_error("Grass texture import metadata is missing")
		return false
	var import_text := import_file.get_as_text()
	if not "\"vram_texture\": true" in import_text or not "mipmaps/generate=true" in import_text:
		push_error("Grass texture import must retain VRAM compression and mipmaps")
		return false
	return true


func _matches_grid_coordinate(value: float, allowed_values: Array) -> bool:
	for allowed_value: float in allowed_values:
		if is_equal_approx(value, allowed_value):
			return true
	return false


func _clears_road_axes(building: StaticBody3D) -> bool:
	var collision := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as BoxShape3D
	var footprint := shape.size
	if is_equal_approx(building.rotation.y, PI / 2.0):
		footprint = Vector3(footprint.z, footprint.y, footprint.x)
	for road_x: float in [-90.0, -30.0, 30.0, 90.0]:
		if absf(building.position.x - road_x) - 10.0 - footprint.x / 2.0 < MIN_ROAD_SETBACK:
			return false
	for road_z: float in [-82.0, -22.0, 38.0, 98.0]:
		if absf(building.position.z - road_z) - 10.0 - footprint.z / 2.0 < MIN_ROAD_SETBACK:
			return false
	return true


func _block_edges_for(position: Vector3) -> Array[String]:
	var edges: Array[String] = []
	var x_near_west_road := is_equal_approx(fposmod(position.x + 14.0, 60.0), 0.0)
	var x_near_east_road := is_equal_approx(fposmod(position.x - 14.0, 60.0), 0.0)
	var z_near_north_road := is_equal_approx(fposmod(position.z + 66.0, 60.0), 0.0)
	var z_near_south_road := is_equal_approx(fposmod(position.z + 38.0, 60.0), 0.0)
	if x_near_west_road:
		edges.append("west")
	if x_near_east_road:
		edges.append("east")
	if z_near_north_road:
		edges.append("north")
	if z_near_south_road:
		edges.append("south")
	return edges


func _validate_building_footprints(buildings: Node) -> bool:
	var placed_buildings := buildings.get_children()
	for first_index in range(placed_buildings.size()):
		var first := placed_buildings[first_index] as StaticBody3D
		for second_index in range(first_index + 1, placed_buildings.size()):
			var second := placed_buildings[second_index] as StaticBody3D
			if _footprints_overlap(first, second):
				push_error("Building footprints overlap: %s and %s" % [first.name, second.name])
				return false
	return true


func _footprints_overlap(first: StaticBody3D, second: StaticBody3D) -> bool:
	var first_footprint := _footprint_for(first)
	var second_footprint := _footprint_for(second)
	return absf(first.position.x - second.position.x) < (first_footprint.x + second_footprint.x) / 2.0 and absf(first.position.z - second.position.z) < (first_footprint.z + second_footprint.z) / 2.0


func _footprint_for(building: StaticBody3D) -> Vector3:
	var shape := (building.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var footprint := shape.size
	if is_equal_approx(building.rotation.y, PI / 2.0):
		footprint = Vector3(footprint.z, footprint.y, footprint.x)
	return footprint


func _town_block_for(position: Vector3) -> String:
	var column := ""
	if position.x < -30.0:
		column = "west"
	elif position.x < 30.0:
		column = "middle"
	else:
		column = "east"
	if position.z < -22.0:
		return "north_%s" % column
	if position.z < 38.0:
		return "center" if column == "middle" else "middle_%s" % column
	return "south_%s" % column


func _load_manifest_dimensions() -> Dictionary:
	var file := FileAccess.open(CONVERSION_MANIFEST, FileAccess.READ)
	if file == null:
		push_error("Unable to open conversion manifest")
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Unable to parse conversion manifest")
		return {}

	var dimensions := {}
	for model: Dictionary in json.data.models:
		var size: Array = model.measuredGodotXyz
		dimensions[model.id] = Vector3(size[0], size[1], size[2])
	return dimensions


func _validate_box_collision(body: CollisionObject3D, expected_size: Vector3) -> bool:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled:
		return false
	var shape := collision.shape as BoxShape3D
	return shape != null and shape.size.is_equal_approx(expected_size)
