extends CharacterBody3D

@export_category("Tank Movement")
@export var movement_speed := 15.0
@export var turn_speed := 1.8

@export_category("Tank Turret")
@export var turret_turn_speed := 6.0

const MODEL_FORWARD_LOCAL_AXIS := Vector3.LEFT
const TURRET_PIVOT_NAME := "TurretPivot"
const MIN_AIM_DISTANCE_SQUARED := 0.001

@onready var camera_rig: Node3D = $"../CameraRig"
@onready var camera: Camera3D = $"../CameraRig/Camera3D"
@onready var tank_scale_root: Node3D = $Tank2/AgentTeamScaleRoot
@onready var tank_turret: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Turret
@onready var tank_gun: MeshInstance3D = $Tank2/AgentTeamScaleRoot/Tank_Gun

var camera_offset := Vector3.ZERO
var turret_pivot: Node3D


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

	rotate_y(turn_input * turn_speed * delta)
	var forward_direction := transform.basis * MODEL_FORWARD_LOCAL_AXIS
	velocity = forward_direction * movement_input * movement_speed
	move_and_slide()
	camera_rig.position = position + camera_offset


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
