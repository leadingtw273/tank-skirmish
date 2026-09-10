extends Node

const ShotEvent := preload("res://src/combat/shot_event.gd")

## 換車後讓場景組裝層更新觀察／攻擊對象，不需要全域玩家登錄器。
signal controlled_tank_changed(tank: Node3D)

var controls_enabled := true


## 統一切換移動、射擊與瞄準輸入；恢復時機由所在場景決定。
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	player_controller.call("set_controls_enabled", enabled)
	player_aim_controller.call("set_controls_enabled", enabled)

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


## 將玩家輸入、瞄準、攝影機與開砲後座重新綁定至新的完整坦克實例；null 為死亡清除期間的正常暫時空綁。
func set_controlled_tank(next_tank: Node3D) -> bool:
	if next_tank == null:
		set_controls_enabled(false)
		_disconnect_controlled_tank()
		controlled_tank = null
		player_controller.call("set_controlled_tank", null)
		player_aim_controller.call("set_controlled_tank", null)
		player_aim_controller.call("set_camera", null)
		aim_presentation.call("set_controlled_tank", null)
		aim_presentation.call("hide_presentation")
		camera_controller.call("set_follow_target", null)
		set_process(false)
		controlled_tank_changed.emit(null)
		return true
	if not is_instance_valid(next_tank) or not next_tank.has_signal("shot_event_fired"):
		push_error("PlayerRuntime requires its controlled_tank to emit shot_event_fired.")
		return false
	var camera := camera_controller.get("camera") as Camera3D
	if camera == null:
		push_error("PlayerRuntime requires CameraRig to expose a Camera3D.")
		return false
	_disconnect_controlled_tank()
	controlled_tank = next_tank
	camera_controller.call("set_follow_target", controlled_tank)
	if not controlled_tank.is_connected("shot_event_fired", _on_controlled_tank_shot_event_fired):
		controlled_tank.connect("shot_event_fired", _on_controlled_tank_shot_event_fired)
	if not controlled_tank.tree_exiting.is_connected(_on_controlled_tank_tree_exiting):
		controlled_tank.tree_exiting.connect(_on_controlled_tank_tree_exiting)
	player_controller.call("set_controlled_tank", controlled_tank)
	player_aim_controller.call("set_controlled_tank", controlled_tank)
	player_aim_controller.call("set_camera", camera)
	aim_presentation.call("set_controlled_tank", controlled_tank)
	aim_presentation.call("initialize_presentation")
	set_process(true)
	set_controls_enabled(controls_enabled)
	controlled_tank_changed.emit(controlled_tank)
	return true


func _disconnect_controlled_tank() -> void:
	if controlled_tank == null or not is_instance_valid(controlled_tank):
		return
	if controlled_tank.is_connected("shot_event_fired", _on_controlled_tank_shot_event_fired):
		controlled_tank.disconnect("shot_event_fired", _on_controlled_tank_shot_event_fired)
	if controlled_tank.tree_exiting.is_connected(_on_controlled_tank_tree_exiting):
		controlled_tank.tree_exiting.disconnect(_on_controlled_tank_tree_exiting)


func _on_controlled_tank_tree_exiting() -> void:
	## CombatRuntime 已有自己的來源解除接線；這裡只撤除玩家輸入與呈現參考。
	set_controlled_tank(null)


func _on_controlled_tank_shot_event_fired(shot_event: ShotEvent) -> void:
	if shot_event == null or not shot_event.is_valid():
		return
	camera_controller.call("play_shot_recoil", shot_event)


func _process(_delta: float) -> void:
	if controlled_tank == null or not is_instance_valid(controlled_tank):
		## null 是殘骸被區域規則清除前的正常狀態；tree_exiting 會先完成空綁。
		set_process(false)
