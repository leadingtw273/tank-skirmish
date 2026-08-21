extends Node3D

@export_category("Tank Movement")
@export var movement_speed := 7.5
@export var turn_speed := 1.8

const MODEL_FORWARD_LOCAL_AXIS := Vector3.LEFT

@onready var tank: Node3D = $Tank
@onready var camera_rig: Node3D = $CameraRig

var camera_offset := Vector3.ZERO


func _ready() -> void:
	# Tank2's gun sits on the model's local -X end, so -X is its visual forward axis.
	camera_offset = camera_rig.position - tank.position


func _process(delta: float) -> void:
	var movement_input := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	var turn_input := float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D))

	tank.rotate_y(turn_input * turn_speed * delta)
	var forward_direction := tank.transform.basis * MODEL_FORWARD_LOCAL_AXIS
	tank.position += forward_direction * movement_input * movement_speed * delta
	camera_rig.position = tank.position + camera_offset
