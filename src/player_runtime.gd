extends Node

@export var controlled_tank: Node3D
@export var camera_controller: Node3D
@export var player_controller: Node
@export var player_aim_controller: Node
@export var aim_presentation: Node


func _ready() -> void:
	if controlled_tank == null or camera_controller == null or player_controller == null \
			or player_aim_controller == null or aim_presentation == null:
		push_error("PlayerRuntime requires controlled_tank, CameraRig, PlayerController, PlayerAimController, and AimPresentation wiring.")
		return
	var camera := camera_controller.get("camera") as Camera3D
	if camera == null:
		push_error("PlayerRuntime requires CameraRig to expose a Camera3D.")
		return
	camera_controller.call("set_follow_target", controlled_tank)
	player_controller.call("set_controlled_tank", controlled_tank)
	player_aim_controller.call("set_controlled_tank", controlled_tank)
	player_aim_controller.call("set_camera", camera)
	aim_presentation.call("set_controlled_tank", controlled_tank)
	aim_presentation.call("initialize_presentation")


func _process(_delta: float) -> void:
	if controlled_tank == null or not is_instance_valid(controlled_tank):
		push_error("PlayerRuntime lost its controlled_tank; player controls are disabled.")
		set_process(false)
