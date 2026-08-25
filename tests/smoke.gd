extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"
const CONVERSION_MANIFEST := "res://docs/assets/conversion-manifest.json"
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
	if not _validate_tread_animations(instance):
		quit(1)
		return
	if not await _validate_turret_aiming(instance):
		quit(1)
		return
	if not _validate_camera_zoom(instance):
		quit(1)
		return
	if not await _validate_projectile_firing(instance):
		quit(1)
		return
	if not _validate_collision_layout(instance):
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

	tank._update_tread_animation(&"Tank_Forward")
	if tank.active_tread_animation != &"Tank_Forward" or tank.tread_animation_paused:
		push_error("Tank forward tread animation did not start")
		return false
	tank._update_tread_animation(&"")
	if not tank.tread_animation_paused:
		push_error("Tank tread animation must pause when movement stops")
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
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	if tank == null:
		push_error("Tank must exist before turret aiming can be validated")
		return false
	if not is_equal_approx(tank.turret_turn_speed, 1.777778):
		push_error("Tank turret turn speed does not match the approved value")
		return false
	if not is_equal_approx(tank.gun_pitch_speed, 1.2) or not is_equal_approx(tank.gun_max_elevation_degrees, 20.0) or not is_equal_approx(tank.gun_max_depression_degrees, 8.0):
		push_error("Tank gun pitch exports do not match the approved MVP values")
		return false

	var scale_root := tank.get_node_or_null("Tank2/AgentTeamScaleRoot") as Node3D
	var turret_pivot := scale_root.get_node_or_null("TurretPivot") as Node3D if scale_root != null else null
	var gun_pitch_pivot := turret_pivot.get_node_or_null("GunPitchPivot") as Node3D if turret_pivot != null else null
	var turret := turret_pivot.get_node_or_null("Tank_Turret") as MeshInstance3D if turret_pivot != null else null
	var gun := gun_pitch_pivot.get_node_or_null("Tank_Gun") as MeshInstance3D if gun_pitch_pivot != null else null
	if turret_pivot == null or gun_pitch_pivot == null or turret == null or gun == null:
		push_error("Tank turret and gun must have separate runtime yaw and pitch pivots")
		return false
	if turret.get_parent() != turret_pivot or gun_pitch_pivot.get_parent() != turret_pivot or gun.get_parent() != gun_pitch_pivot:
		push_error("Tank gun pitch pivot must remain attached beneath the turret yaw pivot")
		return false
	if not gun.position.is_zero_approx() or not gun.global_position.is_equal_approx(gun_pitch_pivot.global_position):
		push_error("Tank gun must retain its authored origin when attached to the pitch pivot")
		return false

	await physics_frame
	var muzzle_position: Vector3 = tank._muzzle_global_position()
	if not is_zero_approx(tank._target_gun_pitch_for_world_target(muzzle_position + Vector3.LEFT * 20.0)) \
		or not is_equal_approx(tank._target_gun_pitch_for_world_target(muzzle_position + Vector3.LEFT * 20.0 + Vector3.UP * 20.0), deg_to_rad(20.0)) \
		or not is_equal_approx(tank._target_gun_pitch_for_world_target(muzzle_position + Vector3.LEFT * 20.0 + Vector3.DOWN * 20.0), deg_to_rad(-8.0)):
		push_error("World-space targets must map to bounded gun elevation and depression angles")
		return false

	var high_muzzle: Vector3 = tank._muzzle_global_position()
	tank._aim_gun_pitch_at_target(high_muzzle + Vector3.LEFT * 20.0 + Vector3.UP * 20.0, 10.0)
	var raised_muzzle_forward := -gun_pitch_pivot.global_transform.basis.x.normalized()
	if not is_equal_approx(gun_pitch_pivot.rotation.z, deg_to_rad(-20.0)) or raised_muzzle_forward.y < 0.33:
		push_error("A high world target must elevate the gun without exceeding 20 degrees")
		return false
	var low_muzzle: Vector3 = tank._muzzle_global_position()
	tank._aim_gun_pitch_at_target(low_muzzle + Vector3.LEFT * 20.0 + Vector3.DOWN * 20.0, 10.0)
	var lowered_muzzle_forward := -gun_pitch_pivot.global_transform.basis.x.normalized()
	if not is_equal_approx(gun_pitch_pivot.rotation.z, deg_to_rad(8.0)) or lowered_muzzle_forward.y > -0.13:
		push_error("A low world target must depress the gun without exceeding 8 degrees")
		return false
	var level_muzzle: Vector3 = tank._muzzle_global_position()
	tank._aim_gun_pitch_at_target(level_muzzle + Vector3.LEFT * 20.0, 10.0)
	if not is_zero_approx(gun_pitch_pivot.rotation.z):
		push_error("A level world target must return the gun to neutral pitch")
		return false

	var chassis_position := tank.global_position
	var chassis_rotation := tank.global_rotation
	var plus_z_target: Vector3 = turret_pivot.global_position + Vector3.BACK * 20.0
	tank._aim_turret_at(plus_z_target, 10.0)
	var muzzle_forward := -gun_pitch_pivot.global_transform.basis.x.normalized()
	if muzzle_forward.dot(Vector3.BACK) < 0.999:
		push_error("Tank local -X muzzle axis must rotate toward a +Z target")
		return false
	if not tank.global_position.is_equal_approx(chassis_position) or not tank.global_rotation.is_equal_approx(chassis_rotation):
		push_error("Turret aiming must not move or rotate the tank chassis")
		return false

	var held_yaw := turret_pivot.global_rotation.y
	tank._aim_turret_at(turret_pivot.global_position, 1.0)
	if not is_equal_approx(turret_pivot.global_rotation.y, held_yaw) or is_nan(turret_pivot.global_rotation.y):
		push_error("A near turret target must preserve the current yaw")
		return false

	var held_pitch := gun_pitch_pivot.rotation.z
	var dead_zone_target := turret_pivot.global_position + Vector3(2.0, 10.0, 0.0)
	tank._aim_turret_at(dead_zone_target, 10.0)
	tank._aim_gun_pitch_at_target(dead_zone_target, 10.0)
	if not is_equal_approx(turret_pivot.global_rotation.y, held_yaw) \
			or not is_equal_approx(gun_pitch_pivot.rotation.z, held_pitch):
		push_error("A target within the 3m turret-center dead zone must preserve yaw and pitch")
		return false

	var fallback_origin := Vector3(1000.0, 1000.0, 1000.0)
	var fallback_target: Vector3 = tank._resolve_world_target_from_ray(fallback_origin, Vector3.UP)
	if not fallback_target.is_equal_approx(fallback_origin + Vector3.UP * 180.0):
		push_error("A camera ray without a hit must fall back to its point 180m away")
		return false
	var ground_target: Vector3 = tank._resolve_world_target_from_ray(Vector3(110.0, 5.0, 110.0), Vector3.DOWN)
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
	var building_target: Vector3 = tank._resolve_world_target_from_ray(Vector3(1000.0, 5.0, 1000.0), Vector3.RIGHT)
	if building_target.distance_to(Vector3(1009.0, 5.0, 1000.0)) > 0.01:
		push_error("Mouse world targeting must use the first building collision")
		return false

	var actual_line := tank.actual_aim_line as MeshInstance3D
	var mouse_line := tank.mouse_aim_line as MeshInstance3D
	if actual_line == null or mouse_line == null or actual_line.name != "ActualAimLine" or mouse_line.name != "MouseAimLine":
		push_error("Tank must create white actual and red mouse aim line nodes")
		return false
	var actual_material := actual_line.material_override as StandardMaterial3D
	var mouse_material := mouse_line.material_override as StandardMaterial3D
	if actual_material == null or mouse_material == null \
			or not is_equal_approx(actual_material.albedo_color.a, 0.7) \
			or not is_equal_approx(mouse_material.albedo_color.a, 0.7) \
			or actual_material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA \
			or mouse_material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		push_error("Both aim lines must use alpha transparency at 0.7 opacity")
		return false
	tank._set_aim_line_segment(actual_line, Vector3.ZERO, Vector3.ZERO)
	if actual_line.visible:
		push_error("A degenerate aim line shorter than 0.05m must be hidden")
		return false
	tank._set_aim_line_segment(actual_line, Vector3.ZERO, Vector3.UP * 10.0)
	if not actual_line.visible or not actual_line.global_transform.is_finite():
		push_error("A near-vertical aim line must keep a finite transform")
		return false
	tank._set_aim_line_path(actual_line, Vector3.ZERO, Vector3.RIGHT * 3.0)
	if actual_line.visible:
		push_error("An aim path ending within the 3m tank clearance must be hidden")
		return false

	gun_pitch_pivot.rotation.z = 0.0
	var current_muzzle: Vector3 = tank._muzzle_global_position()
	var current_direction: Vector3 = tank._muzzle_global_direction()
	tank._update_aim_lines(current_muzzle + current_direction * 20.0)
	if mouse_line.visible or not actual_line.visible:
		push_error("Red mouse line must hide when it overlaps the white firing direction")
		return false
	var actual_line_start := actual_line.global_transform.origin - actual_line.global_transform.basis.y * 0.5
	if not actual_line_start.is_equal_approx(current_muzzle + current_direction * 3.0):
		push_error("White aim line must hide its first 3m from the muzzle")
		return false
	tank._update_aim_lines(current_muzzle + Vector3.RIGHT * 20.0)
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
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	var projectiles := instance.get_node_or_null("Projectiles") as Node3D
	if tank == null or tank.camera == null or projectiles == null:
		push_error("Camera zoom validation requires Tank, Camera3D, and Projectiles nodes")
		return false
	if ProjectSettings.get_setting("display/window/stretch/mode") != "canvas_items" \
			or instance.get_window().content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		push_error("The game window must use canvas-items scaling with runtime expand adaptation")
		return false
	if tank.camera.projection != Camera3D.PROJECTION_ORTHOGONAL \
			or tank.camera.keep_aspect != Camera3D.KEEP_HEIGHT:
		push_error("The orthogonal camera must preserve vertical framing across aspect ratios")
		return false

	var initial_size: float = tank.camera.size
	var projectile_count := projectiles.get_child_count()
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	tank._unhandled_input(wheel_up)
	if not is_equal_approx(tank.camera.size, maxf(25.0, initial_size - 5.0)) or projectiles.get_child_count() != projectile_count:
		push_error("Wheel-up press must zoom in by 5 without firing a projectile")
		return false

	var wheel_release := InputEventMouseButton.new()
	wheel_release.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_release.pressed = false
	var size_before_release: float = tank.camera.size
	tank._unhandled_input(wheel_release)
	if not is_equal_approx(tank.camera.size, size_before_release) or projectiles.get_child_count() != projectile_count:
		push_error("Wheel release must not change camera zoom or fire a projectile")
		return false

	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	tank._unhandled_input(wheel_down)
	if not is_equal_approx(tank.camera.size, minf(100.0, size_before_release + 5.0)) or projectiles.get_child_count() != projectile_count:
		push_error("Wheel-down press must zoom out by 5 without firing a projectile")
		return false

	tank.camera.size = 25.0
	tank._unhandled_input(wheel_up)
	if not is_equal_approx(tank.camera.size, 25.0):
		push_error("Wheel-up zoom must not go below the 25 camera-size minimum")
		return false
	tank.camera.size = 100.0
	tank._unhandled_input(wheel_down)
	if not is_equal_approx(tank.camera.size, 100.0):
		push_error("Wheel-down zoom must not exceed the 100 camera-size maximum")
		return false

	tank.camera.size = initial_size
	return true


func _validate_projectile_firing(instance: Node) -> bool:
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	var projectiles := instance.get_node_or_null("Projectiles") as Node3D
	var ground_collision := instance.get_node_or_null("GroundCollision") as StaticBody3D
	if tank == null or projectiles == null or ground_collision == null:
		push_error("Tank firing requires Tank, Projectiles, and GroundCollision nodes")
		return false
	if ground_collision.collision_layer != 128 or ground_collision.collision_mask != 0:
		push_error("Ground collision must stay isolated on physics layer 8")
		return false
	if tank.collision_layer != 1 or tank.collision_mask != 1:
		push_error("Tank physics layers must remain unchanged")
		return false

	var gun := tank.tank_gun as MeshInstance3D
	var gun_aabb := gun.get_aabb()
	var expected_local_muzzle := gun_aabb.get_center()
	expected_local_muzzle.x = gun_aabb.position.x
	var expected_muzzle := gun.global_transform * expected_local_muzzle
	var muzzle_position: Vector3 = tank._muzzle_global_position()
	var muzzle_direction: Vector3 = tank._muzzle_global_direction()
	if not muzzle_position.is_equal_approx(expected_muzzle):
		push_error("Projectile origin must use the Tank_Gun local -X endpoint")
		return false
	if not is_equal_approx(muzzle_direction.length(), 1.0) or muzzle_direction.dot((-gun.global_transform.basis.x).normalized()) < 0.999:
		push_error("Projectile direction must use the normalized Tank_Gun world -X axis")
		return false

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	tank._unhandled_input(release_event)
	if projectiles.get_child_count() != 2:
		push_error("Mouse release must not fire a projectile")
		return false
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	tank._unhandled_input(right_click)
	if projectiles.get_child_count() != 2:
		push_error("Non-left mouse buttons must not fire a projectile")
		return false

	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	tank._unhandled_input(press_event)
	var projectile := projectiles.get_node_or_null("Projectile") as Node3D
	var muzzle_flash := tank.gun_pitch_pivot.get_node_or_null("MuzzleFlash") as Node3D
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
	if not bool(muzzle_flash.get("one_shot")):
		push_error("Muzzle flash must play once per shot")
		return false
	if not muzzle_flash.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE * 2.0):
		push_error("Muzzle flash acceptance scale must remain 2x")
		return false
	var flash_start := muzzle_flash.global_position
	var projectile_start := projectile.global_position
	var tank_start := tank.global_position
	var tank_motion := Vector3(2.0, 0.0, -1.0)
	tank.global_position += tank_motion
	if not muzzle_flash.global_position.is_equal_approx(flash_start + tank_motion):
		push_error("Muzzle flash must follow tank and gun movement during its lifetime")
		return false
	if not projectile.global_position.is_equal_approx(projectile_start):
		push_error("A fired projectile must remain in world space when the tank moves")
		return false
	tank.global_position = tank_start

	await physics_frame
	var self_hit: Dictionary = projectile._collision_between(Vector3(-15.0, 1.8, 8.0), Vector3(15.0, 1.8, 8.0))
	if not self_hit.is_empty():
		push_error("Projectile sweep must not hit the firing tank")
		return false
	var ground_hit: Dictionary = projectile._collision_between(Vector3(110.0, 5.0, 110.0), Vector3(110.0, -5.0, 110.0))
	if ground_hit.is_empty() or ground_hit.get("collider") != ground_collision:
		push_error("Projectile sweep must detect the isolated ground collider")
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
	projectile.global_position = Vector3(295.0, 2.0, 300.0)
	projectile.direction = Vector3.RIGHT
	projectile._physics_process(0.2)
	if not projectile.is_queued_for_deletion() or projectiles.get_node_or_null("ImpactVFX") == null:
		push_error("Building collision must remove the projectile and create impact VFX")
		return false

	var ranged_projectile := load("res://src/projectile.tscn").instantiate() as Node3D
	ranged_projectile.name = "RangeTestProjectile"
	ranged_projectile.initialize(Vector3.RIGHT, [tank.get_rid()], projectiles)
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
	if tank.gun_pitch_pivot.get_node_or_null("MuzzleFlash") != null or projectiles.get_node_or_null("ImpactVFX") != null:
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
		var building := instance.get_node_or_null("Buildings/%s" % building_name) as StaticBody3D
		if building == null:
			push_error("Building %s must be a StaticBody3D" % building_name)
			return false
		if not _validate_box_collision(building, manifest[BUILDING_MODELS[building_name]]):
			push_error("Building %s collision shape is missing, disabled, or incorrectly sized" % building_name)
			return false
		if not is_equal_approx(building.rotation.y, 0.0) and not is_equal_approx(building.rotation.y, PI / 2.0):
			push_error("Building %s must use an orthogonal rotation" % building_name)
			return false

	if instance.get_node("Buildings").get_child_count() != BUILDING_MODELS.size():
		push_error("Building count does not match the approved town layout")
		return false

	return true


func _validate_grid_layout(instance: Node) -> bool:
	var roads := instance.get_node_or_null("Roads") as Node
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
	for building in instance.get_node("Buildings").get_children():
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
	if not _validate_building_footprints(instance.get_node("Buildings")):
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
