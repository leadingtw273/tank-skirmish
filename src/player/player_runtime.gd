extends Node

const ShotEvent := preload("res://src/combat/shot_event.gd")

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
	set_controlled_tank(controlled_tank)


## 將玩家輸入、瞄準、攝影機與開砲後座重新綁定至新的完整坦克實例。
func set_controlled_tank(next_tank: Node3D) -> bool:
	if next_tank == null or not is_instance_valid(next_tank) or not next_tank.has_signal("shot_event_fired"):
		push_error("PlayerRuntime requires its controlled_tank to emit shot_event_fired.")
		return false
	var camera := camera_controller.get("camera") as Camera3D
	if camera == null:
		push_error("PlayerRuntime requires CameraRig to expose a Camera3D.")
		return false
	if controlled_tank != null and is_instance_valid(controlled_tank) \
			and controlled_tank.is_connected("shot_event_fired", _on_controlled_tank_shot_event_fired):
		controlled_tank.disconnect("shot_event_fired", _on_controlled_tank_shot_event_fired)
	controlled_tank = next_tank
	camera_controller.call("set_follow_target", controlled_tank)
	if not controlled_tank.is_connected("shot_event_fired", _on_controlled_tank_shot_event_fired):
		controlled_tank.connect("shot_event_fired", _on_controlled_tank_shot_event_fired)
	player_controller.call("set_controlled_tank", controlled_tank)
	player_aim_controller.call("set_controlled_tank", controlled_tank)
	player_aim_controller.call("set_camera", camera)
	aim_presentation.call("set_controlled_tank", controlled_tank)
	aim_presentation.call("initialize_presentation")
	set_process(true)
	return true


func _on_controlled_tank_shot_event_fired(shot_event: ShotEvent) -> void:
	if shot_event == null or not shot_event.is_valid():
		return
	camera_controller.call("play_shot_recoil", shot_event)


func _process(_delta: float) -> void:
	if controlled_tank == null or not is_instance_valid(controlled_tank):
		push_error("PlayerRuntime lost its controlled_tank; player controls are disabled.")
		set_process(false)
