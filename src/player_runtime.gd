extends Node

@export var controlled_tank: Node3D
@export var camera_controller: Node3D
@export var player_aim_controller: Node
@export var aim_presentation: Node
@export var projectile_container: Node3D


func _ready() -> void:
	if controlled_tank == null:
		push_error("PlayerRuntime requires a controlled_tank.")
		return
	if camera_controller != null:
		camera_controller.call("set_follow_target", controlled_tank)
	if player_aim_controller != null:
		player_aim_controller.call("set_controlled_tank", controlled_tank)
		player_aim_controller.call("set_camera", camera_controller.get("camera") as Camera3D if camera_controller != null else null)
	if aim_presentation != null:
		aim_presentation.call("set_controlled_tank", controlled_tank)
		aim_presentation.call("set_effects_container", projectile_container)
	if controlled_tank.has_method("set_projectile_container"):
		controlled_tank.call("set_projectile_container", projectile_container)
