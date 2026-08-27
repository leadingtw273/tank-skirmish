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

@export_category("Visual Recoil")
@export var visual_recoil_distance := 0.36
@export var visual_recoil_kick_seconds := 0.04
@export var visual_recoil_return_seconds := 0.18

@export_category("Camera")
@export var max_camera_look_ahead_distance := 30.0

const MODEL_FORWARD_LOCAL_AXIS := Vector3.LEFT
const MIN_AIM_DISTANCE_SQUARED := 0.001
const TREAD_ANIMATION_BLEND_SECONDS := 0.12
const TREAD_ANIMATION_CLIPS := {
	"forward": &"Tank_Forward",
	"backwards": &"Tank_Backwards",
	"turning_left": &"Tank_TurningLeft",
	"turning_right": &"Tank_TurningRight",
}
const MUZZLE_FLASH_SCENE := preload("res://assets/BinbunVFX/muzzle_flash/effects/big_flash/big_flash_05.tscn")
const ShotEvent := preload("res://src/shot_event.gd")
const MUZZLE_FLASH_LIFETIME_SECONDS := 0.25
const MUZZLE_FLASH_SCALE := 4.0

@onready var visual_recoil_pivot: Node3D = $VisualRecoilPivot
@onready var tank_model: Node3D = $VisualRecoilPivot/Tank2
@onready var tank_scale_root: Node3D = $VisualRecoilPivot/Tank2/AgentTeamScaleRoot
@onready var tank_turret: MeshInstance3D = $VisualRecoilPivot/Tank2/AgentTeamScaleRoot/Tank_Turret
@onready var tank_gun: MeshInstance3D = $VisualRecoilPivot/Tank2/AgentTeamScaleRoot/Tank_Gun
@onready var tank_collision: CollisionShape3D = $CollisionShape3D
@onready var turret_pivot: Node3D = $VisualRecoilPivot/TurretPivot
@onready var gun_pitch_pivot: Node3D = $VisualRecoilPivot/TurretPivot/GunPitchPivot
@onready var muzzle_point: Marker3D = $VisualRecoilPivot/TurretPivot/GunPitchPivot/MuzzlePoint

# The legacy signal is retained only so the pre-contract smoke test can observe
# the same gameplay values. CombatRuntime listens only to shot_event_fired.
signal shot_fired(legacy_shot: Dictionary)
signal shot_event_fired(shot_event: ShotEvent)

var movement_command := 0.0
var turn_command := 0.0
var tread_animation_player: AnimationPlayer
var active_tread_animation := &""
var tread_animation_paused := true
var tread_animations_available := false
var visual_recoil_rest_local_position := Vector3.ZERO
var visual_recoil_tween: Tween


func _ready() -> void:
	visual_recoil_rest_local_position = visual_recoil_pivot.position
	# The imported turret and gun remain intact. Permanent scene pivots take ownership
	# at startup while preserving their authored world transforms.
	turret_pivot.global_position = tank_turret.global_position
	tank_turret.reparent(turret_pivot, true)
	gun_pitch_pivot.global_position = tank_gun.global_position
	tank_gun.reparent(gun_pitch_pivot, true)
	var gun_aabb := tank_gun.get_aabb()
	var local_muzzle := gun_aabb.get_center()
	local_muzzle.x = gun_aabb.position.x
	muzzle_point.global_transform = Transform3D(
		tank_gun.global_transform.basis,
		tank_gun.global_transform * local_muzzle,
	)
	_setup_tread_animations()


func _physics_process(delta: float) -> void:
	_update_tread_animation(_tread_animation_for_inputs(movement_command, turn_command))
	rotate_y(turn_command * turn_speed * delta)
	var forward_direction := transform.basis * MODEL_FORWARD_LOCAL_AXIS
	velocity = forward_direction * movement_command * movement_speed
	move_and_slide()


func set_movement_input(input_value: float) -> void:
	movement_command = clampf(input_value, -1.0, 1.0)


func set_turn_input(input_value: float) -> void:
	turn_command = clampf(input_value, -1.0, 1.0)


func get_max_camera_look_ahead_distance() -> float:
	return maxf(max_camera_look_ahead_distance, 0.0)


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


func aim_turret_at(target_position: Vector3, delta: float) -> void:
	if _is_target_inside_turret_dead_zone(target_position):
		return
	var target_direction := target_position - turret_pivot.global_position
	target_direction.y = 0.0
	if target_direction.length_squared() <= MIN_AIM_DISTANCE_SQUARED:
		return

	var target_yaw := atan2(target_direction.z, -target_direction.x)
	turret_pivot.global_rotation.y = rotate_toward(
		turret_pivot.global_rotation.y,
		target_yaw,
		turret_turn_speed * delta,
	)


func _target_gun_pitch_for_world_target(target_position: Vector3) -> float:
	if _is_target_inside_turret_dead_zone(target_position):
		return -gun_pitch_pivot.rotation.z
	var target_direction := target_position - muzzle_global_position()
	var horizontal_distance := Vector2(target_direction.x, target_direction.z).length()
	if horizontal_distance * horizontal_distance + target_direction.y * target_direction.y <= MIN_AIM_DISTANCE_SQUARED:
		return -gun_pitch_pivot.rotation.z
	var target_pitch := atan2(target_direction.y, horizontal_distance)
	return clampf(
		target_pitch,
		-deg_to_rad(maxf(gun_max_depression_degrees, 0.0)),
		deg_to_rad(maxf(gun_max_elevation_degrees, 0.0)),
	)


func _is_target_inside_turret_dead_zone(target_position: Vector3) -> bool:
	var offset := target_position - turret_pivot.global_position
	return Vector2(offset.x, offset.z).length_squared() <= 9.0


func aim_gun_pitch_at_target(target_position: Vector3, delta: float) -> void:
	var minimum_pitch := -deg_to_rad(maxf(gun_max_depression_degrees, 0.0))
	var maximum_pitch := deg_to_rad(maxf(gun_max_elevation_degrees, 0.0))
	var current_pitch := -gun_pitch_pivot.rotation.z
	var target_pitch := _target_gun_pitch_for_world_target(target_position)
	var next_pitch := move_toward(current_pitch, target_pitch, maxf(gun_pitch_speed, 0.0) * maxf(delta, 0.0))
	gun_pitch_pivot.rotation.z = -clampf(next_pitch, minimum_pitch, maximum_pitch)


func muzzle_global_position() -> Vector3:
	return muzzle_point.global_position


func muzzle_global_direction() -> Vector3:
	return (-muzzle_point.global_transform.basis.x).normalized()


func request_fire() -> void:
	if gun_pitch_pivot == null or muzzle_point == null:
		push_error("Tank cannot fire: MuzzlePoint wiring is missing.")
		return
	var muzzle_position := muzzle_global_position()
	var muzzle_direction := muzzle_global_direction()
	if muzzle_direction.is_zero_approx():
		push_error("Tank cannot fire: MuzzlePoint has no valid forward direction.")
		return

	_spawn_muzzle_flash(muzzle_position, muzzle_direction)
	var shot_muzzle_transform := muzzle_point.global_transform
	var shot_event := ShotEvent.new(shot_muzzle_transform, muzzle_direction, get_rid())
	shot_event_fired.emit(shot_event)
	shot_fired.emit(shot_event.to_legacy_dictionary())
	_play_visual_recoil(muzzle_direction)


func _play_visual_recoil(muzzle_direction: Vector3) -> void:
	if visual_recoil_pivot == null:
		push_error("Tank visual recoil requires a VisualRecoilPivot.")
		return
	if visual_recoil_tween != null and visual_recoil_tween.is_valid():
		visual_recoil_tween.kill()
	visual_recoil_pivot.position = visual_recoil_rest_local_position
	var local_recoil_direction := global_transform.basis.inverse() * -muzzle_direction.normalized()
	var recoil_target := visual_recoil_rest_local_position + local_recoil_direction * maxf(visual_recoil_distance, 0.0)
	visual_recoil_tween = create_tween()
	visual_recoil_tween.tween_property(visual_recoil_pivot, "position", recoil_target, maxf(visual_recoil_kick_seconds, 0.0))
	visual_recoil_tween.tween_property(visual_recoil_pivot, "position", visual_recoil_rest_local_position, maxf(visual_recoil_return_seconds, 0.0))
	visual_recoil_tween.tween_callback(_reset_visual_recoil)


func _reset_visual_recoil() -> void:
	visual_recoil_pivot.position = visual_recoil_rest_local_position


func _spawn_muzzle_flash(muzzle_position: Vector3, muzzle_direction: Vector3) -> void:
	var muzzle_flash := MUZZLE_FLASH_SCENE.instantiate() as Node3D
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.set("one_shot", true)
	muzzle_flash.set("autoplay", true)
	muzzle_point.add_child(muzzle_flash, true)
	var flash_basis := _basis_with_x_axis(muzzle_direction).scaled(Vector3.ONE * MUZZLE_FLASH_SCALE)
	muzzle_flash.global_transform = Transform3D(flash_basis, muzzle_position)
	get_tree().create_timer(MUZZLE_FLASH_LIFETIME_SECONDS).timeout.connect(muzzle_flash.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
