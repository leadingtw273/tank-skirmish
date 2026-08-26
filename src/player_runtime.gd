extends Node

@onready var controlled_tank: CharacterBody3D = get_node("../Tank") as CharacterBody3D
@onready var camera_rig: Node3D = get_node("../CameraRig") as Node3D
@onready var camera: Camera3D = camera_rig.get_node("Camera3D") as Camera3D
@onready var projectile_container: Node3D = get_node("../Projectiles") as Node3D


func _ready() -> void:
	if controlled_tank == null or camera == null or projectile_container == null:
		push_error("PlayerRuntime requires Tank, CameraRig/Camera3D, and Projectiles siblings.")
		return
	controlled_tank.set_projectile_container(projectile_container)
	$CameraController.configure(camera, controlled_tank)
	$PlayerAimController.configure(camera, controlled_tank)
	$AimPresentation.configure(controlled_tank, projectile_container)
	controlled_tank.set_aim_services($PlayerAimController, $AimPresentation)
