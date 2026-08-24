extends CharacterBody3D

@export_category("Tank Movement")
@export var movement_speed := 15.0
@export var turn_speed := 0.8

@export_category("Tank Turret")
@export var turret_turn_speed := 1.777778

const MODEL_FORWARD_LOCAL_AXIS := Vector3.LEFT
const TURRET_PIVOT_NAME := "TurretPivot"
const MIN_AIM_DISTANCE_SQUARED := 0.001
const TREAD_ANIMATION_BLEND_SECONDS := 0.12
const TREAD_ANIMATION_CLIPS := {
	"forward": &"Tank_Forward",
	"backwards": &"Tank_Backwards",
	"turning_left": &"Tank_TurningLeft",
	"turning_right": &"Tank_TurningRight",
}

@onready var camera_rig: Node3D = $"../CameraRig"
@onready var camera: Camera3D = $"../CameraRig/Camera3D"
@onready var tank_model: Node3D = $Tank2
@onready var tank_scale_root: Node3D = $Tank2/AgentTeamScaleRoot
@onready var tank_turret: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Turret
@onready var tank_gun: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Gun

var camera_offset := Vector3.ZERO
var turret_pivot: Node3D
var tread_animation_player: AnimationPlayer
var active_tread_animation := &""
var tread_animation_paused := true
var tread_animations_available := false


func _ready() -> void:
	# Tank2's gun sits on the model's local -X end, so -X is its visual forward axis.
	camera_offset = camera_rig.position - position
	# The imported gun and turret are sibling meshes. Keep their global transforms while
	# regrouping them under one pivot at the turret center so they yaw as one assembly.
	turret_pivot = Node3D.new()
	turret_pivot.name = TURRET_PIVOT_NAME
	tank_scale_root.add_child(turret_pivot)
	turret_pivot.global_position = tank_turret.global_position
	tank_turret.reparent(turret_pivot, true)
	tank_gun.reparent(turret_pivot, true)
	_setup_tread_animations()


func _process(delta: float) -> void:
	var aim_plane := Plane(Vector3.UP, turret_pivot.global_position.y)
	var ray_origin := camera.project_ray_origin(get_viewport().get_mouse_position())
	var ray_direction := camera.project_ray_normal(get_viewport().get_mouse_position())
	var target_position: Variant = aim_plane.intersects_ray(ray_origin, ray_direction)
	if target_position == null:
		return
	_aim_turret_at(target_position, delta)


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
