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

@onready var camera_rig: Node3D = $"../CameraRig"
@onready var camera: Camera3D = $"../CameraRig/Camera3D"
@onready var tank_model: Node3D = $Tank2
@onready var tank_scale_root: Node3D = $Tank2/AgentTeamScaleRoot
@onready var tank_turret: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Turret
@onready var tank_gun: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Gun
@onready var projectile_container: Node3D = $"../Projectiles"

var camera_offset := Vector3.ZERO
var turret_pivot: Node3D
var gun_pitch_pivot: Node3D
var tread_animation_player: AnimationPlayer
var active_tread_animation := &""
var tread_animation_paused := true
var tread_animations_available := false


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


func _process(delta: float) -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var viewport_height := get_viewport().get_visible_rect().size.y
	_aim_gun_pitch_at_mouse(mouse_position.y, viewport_height, delta)

	var aim_plane := Plane(Vector3.UP, turret_pivot.global_position.y)
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var target_position: Variant = aim_plane.intersects_ray(ray_origin, ray_direction)
	if target_position == null:
		return
	_aim_turret_at(target_position, delta)


func _unhandled_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_fire_projectile()


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


func _target_gun_pitch_for_mouse_y(mouse_y: float, viewport_height: float) -> float:
	if viewport_height <= 0.0:
		return 0.0
	var center_y := viewport_height * 0.5
	var clamped_y := clampf(mouse_y, 0.0, viewport_height)
	if clamped_y <= center_y:
		var elevation_weight := 1.0 - clamped_y / center_y
		return deg_to_rad(maxf(gun_max_elevation_degrees, 0.0)) * elevation_weight
	var depression_weight := (clamped_y - center_y) / center_y
	return -deg_to_rad(maxf(gun_max_depression_degrees, 0.0)) * depression_weight


func _aim_gun_pitch_at_mouse(mouse_y: float, viewport_height: float, delta: float) -> void:
	if gun_pitch_pivot == null or viewport_height <= 0.0:
		return
	var minimum_pitch := -deg_to_rad(maxf(gun_max_depression_degrees, 0.0))
	var maximum_pitch := deg_to_rad(maxf(gun_max_elevation_degrees, 0.0))
	var current_pitch := -gun_pitch_pivot.rotation.z
	var target_pitch := _target_gun_pitch_for_mouse_y(mouse_y, viewport_height)
	var next_pitch := move_toward(current_pitch, target_pitch, maxf(gun_pitch_speed, 0.0) * maxf(delta, 0.0))
	gun_pitch_pivot.rotation.z = -clampf(next_pitch, minimum_pitch, maximum_pitch)


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
	projectile_container.add_child(muzzle_flash, true)
	muzzle_flash.global_transform = Transform3D(_basis_with_x_axis(muzzle_direction), muzzle_position)
	get_tree().create_timer(MUZZLE_FLASH_LIFETIME_SECONDS).timeout.connect(muzzle_flash.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
