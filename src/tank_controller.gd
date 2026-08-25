extends CharacterBody3D

@export_category("Tank Movement")
@export var movement_speed := 15.0
@export var turn_speed := 0.8

@export_category("Tank Turret")
@export var turret_turn_speed := 1.777778

@export_category("Tank Gun")
@export var gun_pitch_speed := 1.2
@export_range(0.0, 45.0, 0.5) var gun_max_elevation_degrees := 20.0
@export_range(0.0, 45.0, 0.5) var gun_max_depression_degrees := 8.0

const MODEL_FORWARD_LOCAL_AXIS := Vector3.LEFT
const TURRET_PIVOT_NAME := "TurretPivot"
const GUN_PITCH_PIVOT_NAME := "GunPitchPivot"
const MIN_AIM_DISTANCE_SQUARED := 0.001
const TREAD_ANIMATION_BLEND_SECONDS := 0.12
const TREAD_ANIMATION_CLIPS := {
	"forward": &"Tank_Forward",
	"backwards": &"Tank_Backwards",
	"turning_left": &"Tank_TurningLeft",
	"turning_right": &"Tank_TurningRight",
}
const PROJECTILE_SCENE := preload("res://src/projectile.tscn")
const MUZZLE_FLASH_SCENE := preload("res://assets/BinbunVFX/muzzle_flash/effects/big_flash/big_flash_01.tscn")
const MUZZLE_FLASH_LIFETIME_SECONDS := 0.25
const MUZZLE_FLASH_SCALE := 2.0
const AIM_MAX_DISTANCE := 180.0
const AIM_COLLISION_MASK := 129
const AIM_TARGET_DEAD_ZONE_DISTANCE_SQUARED := 9.0
const AIM_LINE_RADIUS := 0.04
const AIM_LINE_MIN_LENGTH := 0.05
const AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE := 3.0
const AIM_LINE_ALPHA := 0.7
const AIM_ALIGNED_ANGLE_RADIANS := 0.004363323
const AIM_VERTICAL_BASIS_THRESHOLD := 0.999
const CAMERA_ZOOM_STEP := 5.0
const CAMERA_MIN_SIZE := 25.0
const CAMERA_MAX_SIZE := 100.0

@onready var camera_rig: Node3D = $"../CameraRig"
@onready var camera: Camera3D = $"../CameraRig/Camera3D"
@onready var tank_model: Node3D = $Tank2
@onready var tank_scale_root: Node3D = $Tank2/AgentTeamScaleRoot
@onready var tank_turret: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Turret
@onready var tank_gun: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Gun
@onready var tank_collision: CollisionShape3D = $CollisionShape3D
@onready var projectile_container: Node3D = $"../Projectiles"

var camera_offset := Vector3.ZERO
var turret_pivot: Node3D
var gun_pitch_pivot: Node3D
var tread_animation_player: AnimationPlayer
var active_tread_animation := &""
var tread_animation_paused := true
var tread_animations_available := false
var actual_aim_line: MeshInstance3D
var mouse_aim_line: MeshInstance3D


func _ready() -> void:
	# Tank2's gun sits on the model's local -X end, so -X is its visual forward axis.
	camera_offset = camera_rig.position - position
	# The imported gun and turret are sibling meshes. The outer pivot yaws the assembly;
	# the inner pivot sits at the authored gun origin so only the barrel pitches.
	turret_pivot = Node3D.new()
	turret_pivot.name = TURRET_PIVOT_NAME
	tank_scale_root.add_child(turret_pivot)
	turret_pivot.global_position = tank_turret.global_position
	tank_turret.reparent(turret_pivot, true)
	gun_pitch_pivot = Node3D.new()
	gun_pitch_pivot.name = GUN_PITCH_PIVOT_NAME
	turret_pivot.add_child(gun_pitch_pivot)
	gun_pitch_pivot.global_position = tank_gun.global_position
	tank_gun.reparent(gun_pitch_pivot, true)
	_setup_tread_animations()
	actual_aim_line = _create_aim_line("ActualAimLine", Color.WHITE)
	mouse_aim_line = _create_aim_line("MouseAimLine", Color.RED)


func _process(delta: float) -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var target_position := _resolve_mouse_world_target(mouse_position)
	_aim_turret_at(target_position, delta)
	_aim_gun_pitch_at_target(target_position, delta)
	_update_aim_lines(target_position)


func _unhandled_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_fire_projectile()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera.size = maxf(CAMERA_MIN_SIZE, camera.size - CAMERA_ZOOM_STEP)
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera.size = minf(CAMERA_MAX_SIZE, camera.size + CAMERA_ZOOM_STEP)


func _physics_process(delta: float) -> void:
	var movement_input := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	var turn_input := float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D))

	_update_tread_animation(_tread_animation_for_inputs(movement_input, turn_input))
	rotate_y(turn_input * turn_speed * delta)
	var forward_direction := transform.basis * MODEL_FORWARD_LOCAL_AXIS
	velocity = forward_direction * movement_input * movement_speed
	move_and_slide()
	camera_rig.position = position + camera_offset


func _setup_tread_animations() -> void:
	tread_animation_player = _find_animation_player(tank_model)
	if tread_animation_player == null:
		push_error("Tank tread animation setup failed: no AnimationPlayer found beneath Tank2.")
		return

	for clip: StringName in TREAD_ANIMATION_CLIPS.values():
		var animation: Animation = tread_animation_player.get_animation(clip)
		if animation == null:
			push_error("Tank tread animation setup failed: missing clip %s." % clip)
			return
		animation.loop_mode = Animation.LOOP_LINEAR

	tread_animations_available = true


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _tread_animation_for_inputs(movement_input: float, turn_input: float) -> StringName:
	if not is_zero_approx(turn_input):
		return TREAD_ANIMATION_CLIPS["turning_left"] if turn_input > 0.0 else TREAD_ANIMATION_CLIPS["turning_right"]
	if movement_input > 0.0:
		return TREAD_ANIMATION_CLIPS["forward"]
	if movement_input < 0.0:
		return TREAD_ANIMATION_CLIPS["backwards"]
	return &""


func _update_tread_animation(next_animation: StringName) -> void:
	if not tread_animations_available or tread_animation_player == null:
		return
	if next_animation.is_empty():
		if not tread_animation_paused:
			tread_animation_player.pause()
			tread_animation_paused = true
		return
	if next_animation == active_tread_animation:
		if tread_animation_paused:
			tread_animation_player.play()
			tread_animation_paused = false
		return

	tread_animation_player.play(next_animation, TREAD_ANIMATION_BLEND_SECONDS)
	active_tread_animation = next_animation
	tread_animation_paused = false


func _aim_turret_at(target_position: Vector3, delta: float) -> void:
	if _is_target_inside_turret_dead_zone(target_position):
		return
	var target_direction := target_position - turret_pivot.global_position
	target_direction.y = 0.0
	if target_direction.length_squared() <= MIN_AIM_DISTANCE_SQUARED:
		return

	# Godot's default forward is -Z, but this model's muzzle points along local -X.
	var target_yaw := atan2(target_direction.z, -target_direction.x)
	turret_pivot.global_rotation.y = rotate_toward(
		turret_pivot.global_rotation.y,
		target_yaw,
		turret_turn_speed * delta,
	)


func _target_gun_pitch_for_world_target(target_position: Vector3) -> float:
	if _is_target_inside_turret_dead_zone(target_position):
		return -gun_pitch_pivot.rotation.z if gun_pitch_pivot != null else 0.0
	var target_direction := target_position - _muzzle_global_position()
	var horizontal_distance := Vector2(target_direction.x, target_direction.z).length()
	if horizontal_distance * horizontal_distance + target_direction.y * target_direction.y <= MIN_AIM_DISTANCE_SQUARED:
		return -gun_pitch_pivot.rotation.z if gun_pitch_pivot != null else 0.0
	var target_pitch := atan2(target_direction.y, horizontal_distance)
	return clampf(
		target_pitch,
		-deg_to_rad(maxf(gun_max_depression_degrees, 0.0)),
		deg_to_rad(maxf(gun_max_elevation_degrees, 0.0)),
	)


func _is_target_inside_turret_dead_zone(target_position: Vector3) -> bool:
	var offset := target_position - turret_pivot.global_position
	return Vector2(offset.x, offset.z).length_squared() <= AIM_TARGET_DEAD_ZONE_DISTANCE_SQUARED


func _aim_gun_pitch_at_target(target_position: Vector3, delta: float) -> void:
	if gun_pitch_pivot == null:
		return
	var minimum_pitch := -deg_to_rad(maxf(gun_max_depression_degrees, 0.0))
	var maximum_pitch := deg_to_rad(maxf(gun_max_elevation_degrees, 0.0))
	var current_pitch := -gun_pitch_pivot.rotation.z
	var target_pitch := _target_gun_pitch_for_world_target(target_position)
	var next_pitch := move_toward(current_pitch, target_pitch, maxf(gun_pitch_speed, 0.0) * maxf(delta, 0.0))
	gun_pitch_pivot.rotation.z = -clampf(next_pitch, minimum_pitch, maximum_pitch)


func _resolve_mouse_world_target(screen_position: Vector2) -> Vector3:
	return _resolve_world_target_from_ray(
		camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position),
	)


func _resolve_world_target_from_ray(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	var normalized_direction := ray_direction.normalized()
	if normalized_direction.is_zero_approx():
		return ray_origin
	var fallback_target := ray_origin + normalized_direction * AIM_MAX_DISTANCE
	var collision := _aim_collision_between(ray_origin, fallback_target)
	return collision.get("position", fallback_target) as Vector3


func _aim_collision_between(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, AIM_COLLISION_MASK, [get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _create_aim_line(line_name: String, color: Color) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	line.name = line_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = AIM_LINE_RADIUS
	cylinder.bottom_radius = AIM_LINE_RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	line.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = Color(color.r, color.g, color.b, AIM_LINE_ALPHA)
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	projectile_container.add_child(line)
	return line


func _aim_line_end(origin: Vector3, direction: Vector3) -> Vector3:
	var normalized_direction := direction.normalized()
	if normalized_direction.is_zero_approx():
		return origin
	var fallback_end := origin + normalized_direction * AIM_MAX_DISTANCE
	var collision := _aim_collision_between(origin, fallback_end)
	return collision.get("position", fallback_end) as Vector3


func _set_aim_line_segment(line: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var segment := end - start
	var length := segment.length()
	if length < AIM_LINE_MIN_LENGTH:
		line.visible = false
		return
	var direction := segment / length
	var reference_axis := Vector3.UP
	if absf(direction.dot(Vector3.UP)) >= AIM_VERTICAL_BASIS_THRESHOLD:
		reference_axis = Vector3.FORWARD
	var x_axis := reference_axis.cross(direction).normalized()
	var z_axis := x_axis.cross(direction).normalized()
	line.global_transform = Transform3D(
		Basis(x_axis, direction * length, z_axis),
		start + segment * 0.5,
	)
	line.visible = true


func _set_aim_line_path(
	line: MeshInstance3D,
	origin: Vector3,
	end: Vector3,
	hidden_distance := AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE,
) -> void:
	var path := end - origin
	var length := path.length()
	var safe_hidden_distance := maxf(hidden_distance, 0.0)
	if length <= safe_hidden_distance:
		line.visible = false
		return
	var visible_start := origin + path / length * safe_hidden_distance
	_set_aim_line_segment(line, visible_start, end)


func _tank_aim_line_clearance_distance(origin: Vector3) -> float:
	var collision_box := tank_collision.shape as BoxShape3D
	if collision_box == null:
		return origin.distance_to(_muzzle_global_position()) + AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE
	var half_size := collision_box.size * 0.5
	var farthest_corner_distance := 0.0
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var corner := tank_collision.global_transform * Vector3(
					half_size.x * x_sign,
					half_size.y * y_sign,
					half_size.z * z_sign,
				)
				farthest_corner_distance = maxf(farthest_corner_distance, origin.distance_to(corner))
	return farthest_corner_distance + AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE


func _update_aim_lines(world_target: Vector3) -> void:
	if actual_aim_line == null or mouse_aim_line == null:
		return
	var muzzle_position := _muzzle_global_position()
	var actual_direction := _muzzle_global_direction()
	_set_aim_line_path(actual_aim_line, muzzle_position, _aim_line_end(muzzle_position, actual_direction))

	var firing_target_offset := world_target - muzzle_position
	if firing_target_offset.length_squared() <= MIN_AIM_DISTANCE_SQUARED:
		mouse_aim_line.visible = false
		return
	var firing_target_direction := firing_target_offset.normalized()
	if actual_direction.angle_to(firing_target_direction) <= AIM_ALIGNED_ANGLE_RADIANS:
		mouse_aim_line.visible = false
		return

	var mouse_line_origin := turret_pivot.global_position
	var mouse_line_offset := world_target - mouse_line_origin
	if mouse_line_offset.length_squared() <= MIN_AIM_DISTANCE_SQUARED:
		mouse_aim_line.visible = false
		return
	var mouse_line_direction := mouse_line_offset.normalized()
	_set_aim_line_path(
		mouse_aim_line,
		mouse_line_origin,
		_aim_line_end(mouse_line_origin, mouse_line_direction),
		_tank_aim_line_clearance_distance(mouse_line_origin),
	)


func _muzzle_global_position() -> Vector3:
	var gun_aabb := tank_gun.get_aabb()
	var local_muzzle := gun_aabb.get_center()
	local_muzzle.x = gun_aabb.position.x
	return tank_gun.global_transform * local_muzzle


func _muzzle_global_direction() -> Vector3:
	return (-tank_gun.global_transform.basis.x).normalized()


func _fire_projectile() -> void:
	if projectile_container == null or gun_pitch_pivot == null:
		return
	var muzzle_position := _muzzle_global_position()
	var muzzle_direction := _muzzle_global_direction()
	if muzzle_direction.is_zero_approx():
		return

	var projectile := PROJECTILE_SCENE.instantiate() as Node3D
	projectile.name = "Projectile"
	projectile.initialize(muzzle_direction, [get_rid()], projectile_container)
	projectile_container.add_child(projectile, true)
	projectile.global_transform = Transform3D(_basis_with_x_axis(muzzle_direction), muzzle_position)
	_spawn_muzzle_flash(muzzle_position, muzzle_direction)


func _spawn_muzzle_flash(muzzle_position: Vector3, muzzle_direction: Vector3) -> void:
	var muzzle_flash := MUZZLE_FLASH_SCENE.instantiate() as Node3D
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.set("one_shot", true)
	muzzle_flash.set("autoplay", true)
	gun_pitch_pivot.add_child(muzzle_flash, true)
	var flash_basis := _basis_with_x_axis(muzzle_direction).scaled(Vector3.ONE * MUZZLE_FLASH_SCALE)
	muzzle_flash.global_transform = Transform3D(flash_basis, muzzle_position)
	get_tree().create_timer(MUZZLE_FLASH_LIFETIME_SECONDS).timeout.connect(muzzle_flash.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
