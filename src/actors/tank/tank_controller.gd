## 管理坦克移動、砲塔姿態、射擊事件、履帶動畫與視覺後座。
## 它不會實體化投射物或擁有世界戰鬥容器；CombatRuntime 消費其事件。
extends CharacterBody3D

@export_category("坦克移動")
## 滿輸入時車身前進或倒退的最高速度，單位為公尺／秒。
@export var movement_speed := 15.0
## 滿轉向輸入時車身偏航速度，單位為弧度／秒。
@export var turn_speed := 0.8
## 在製作好的履帶動畫片段之間混合所用的秒數。
@export var tread_animation_blend_seconds := 0.12
## 履帶動畫以 1 倍速播放時所對應的坦克前後線速度，單位為公尺／秒。
@export_range(0.01, 100.0, 0.01) var tread_animation_reference_speed := 15.0
## 套用於履帶動畫最終播放倍率的微調係數。
@export_range(0.0, 4.0, 0.01) var tread_animation_speed_multiplier := 1.0

@export_category("坦克砲塔")
## 追蹤目標時砲塔的偏航速度，單位為弧度／秒。
@export var turret_turn_speed := 1.777778

@export_category("坦克砲管")
## 砲管仰角與俯角的追蹤速度，單位為弧度／秒。
@export var gun_pitch_speed := 1.2
## 砲管向上的最大仰角，單位為度。
@export_range(0.0, 45.0, 0.5) var gun_max_elevation_degrees := 20.0
## 砲管向下的最大俯角，單位為度。
@export_range(0.0, 45.0, 0.5) var gun_max_depression_degrees := 8.0

@export_category("視覺後座")
## 僅供視覺呈現、與射擊方向相反的最大後座位移，單位為公尺。
@export var visual_recoil_distance := 0.36
## 視覺坦克模型到達後座位移所需的秒數。
@export var visual_recoil_kick_seconds := 0.04
## 視覺坦克模型回到製作時靜止位置所需的秒數。
@export var visual_recoil_return_seconds := 0.18

@export_category("鏡頭")
## CameraController 可要求的最大游標前視距離，單位為公尺。
@export var max_camera_look_ahead_distance := 30.0

const MODEL_FORWARD_LOCAL_AXIS := Vector3.LEFT
const MIN_AIM_DISTANCE_SQUARED := 0.001
const TREAD_ANIMATION_REFERENCE_MODEL_SCALE := 1.7466666
const TREAD_ANIMATION_CLIPS := {
	"forward": &"Tank_Forward",
	"backwards": &"Tank_Backwards",
	"turning_left": &"Tank_TurningLeft",
	"turning_right": &"Tank_TurningRight",
}
const MUZZLE_FLASH_SCENE := preload("res://assets/BinbunVFX/muzzle_flash/effects/big_flash/big_flash_05.tscn")
const ShotEvent := preload("res://src/combat/shot_event.gd")
@export_category("砲口火焰")
## 已生成的砲口火焰在移除前的存活時間，單位為秒。
@export var muzzle_flash_lifetime_seconds := 0.25
## 套用至製作好的砲口火焰特效之等比縮放倍率。
@export var muzzle_flash_scale := 4.0

@onready var visual_recoil_pivot: Node3D = $VisualRecoilPivot
@onready var tank_model: Node3D = $VisualRecoilPivot/Tank2
@onready var tank_scale_root: Node3D = $VisualRecoilPivot/Tank2/AgentTeamScaleRoot
@onready var tank_turret: MeshInstance3D = $VisualRecoilPivot/Tank2/AgentTeamScaleRoot/Tank_Turret
@onready var tank_gun: MeshInstance3D = $VisualRecoilPivot/Tank2/AgentTeamScaleRoot/Tank_Gun
@onready var tank_collision: CollisionShape3D = $CollisionShape3D
@onready var turret_pivot: Node3D = $VisualRecoilPivot/TurretPivot
@onready var gun_pitch_pivot: Node3D = $VisualRecoilPivot/TurretPivot/GunPitchPivot
@onready var muzzle_point: Marker3D = $VisualRecoilPivot/TurretPivot/GunPitchPivot/MuzzlePoint

## 為既有冒煙測試承載舊版 Dictionary 資料載荷的相容性通知。
signal shot_fired(legacy_shot: Dictionary)
## 每次有效開火請求時，供 CombatRuntime 消費的權威射擊通知。
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
	## 將匯入模型的砲塔與砲管轉交給常駐樞紐且保持世界姿態，之後才能獨立套用偏航與俯仰。
	visual_recoil_rest_local_position = visual_recoil_pivot.position
	# 匯入的砲塔與砲管保持原樣；常駐場景樞紐在啟動時接手，並保留製作時的世界座標轉換。
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
	## 以模型定義的本地 -X 前方換算車身世界速度並交給碰撞滑動，再依實際前後線速度更新履帶呈現。
	rotate_y(turn_command * turn_speed * delta)
	var forward_direction := transform.basis * MODEL_FORWARD_LOCAL_AXIS
	velocity = forward_direction * movement_command * movement_speed
	move_and_slide()
	var next_tread_animation := _tread_animation_for_inputs(movement_command, turn_command)
	var actual_forward_speed := get_real_velocity().dot(forward_direction)
	_update_tread_animation(next_tread_animation, _tread_animation_speed_scale(next_tread_animation, actual_forward_speed))


## 儲存介於 -1 到 1 的前進／倒退指令，供下一個物理步驟使用。
func set_movement_input(input_value: float) -> void:
	movement_command = clampf(input_value, -1.0, 1.0)


## 儲存介於 -1 到 1 的車身轉向指令，供下一個物理步驟使用。
func set_turn_input(input_value: float) -> void:
	turn_command = clampf(input_value, -1.0, 1.0)


## 回傳供 CameraController 使用且不為負值的鏡頭前視上限，單位為公尺。
func get_max_camera_look_ahead_distance() -> float:
	return maxf(max_camera_look_ahead_distance, 0.0)


func _setup_tread_animations() -> void:
	## 在匯入模型子樹尋找單一播放器，確認所有必要片段後才啟用，避免部分可用的狀態誤播放。
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
	## 深度優先走訪匯入節點，因素材階層不保證 AnimationPlayer 位於固定 NodePath。
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _tread_animation_for_inputs(movement_input: float, turn_input: float) -> StringName:
	## 轉向優先於前後移動，確保同時輸入時履帶呈現原地／轉彎動畫而非直行動畫。
	if not is_zero_approx(turn_input):
		return TREAD_ANIMATION_CLIPS["turning_left"] if turn_input > 0.0 else TREAD_ANIMATION_CLIPS["turning_right"]
	if movement_input > 0.0:
		return TREAD_ANIMATION_CLIPS["forward"]
	if movement_input < 0.0:
		return TREAD_ANIMATION_CLIPS["backwards"]
	return &""


func _tread_animation_speed_scale(next_animation: StringName, actual_forward_speed: float) -> float:
	## 直行以碰撞後的前後線速度和 Tank2 的等比縮放修正；原地轉向維持素材速度。
	if next_animation == TREAD_ANIMATION_CLIPS["turning_left"] or next_animation == TREAD_ANIMATION_CLIPS["turning_right"]:
		return tread_animation_speed_multiplier
	var model_scale := maxf(absf(tank_model.scale.x), 0.001)
	return absf(actual_forward_speed) / tread_animation_reference_speed * TREAD_ANIMATION_REFERENCE_MODEL_SCALE / model_scale * tread_animation_speed_multiplier


func _update_tread_animation(next_animation: StringName, animation_speed_scale: float = 1.0) -> void:
	## 只在狀態改變時交給播放器混合；靜止則暫停而不重設目前影格，恢復時可延續既有片段。
	if not tread_animations_available or tread_animation_player == null:
		return
	tread_animation_player.speed_scale = animation_speed_scale
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

	tread_animation_player.play(next_animation, tread_animation_blend_seconds)
	active_tread_animation = next_animation
	tread_animation_paused = false


## 在此影格中只將砲塔偏航轉向世界座標目標。
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
	## 以砲口到目標的水平距離和高度差求仰角，再限制在製作時設定的俯仰範圍。
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
	## 只比較水平 XZ 距離；目標太靠近砲塔時不更新姿態，避免方位與仰角在零向量附近跳動。
	var offset := target_position - turret_pivot.global_position
	return Vector2(offset.x, offset.z).length_squared() <= 9.0


## 在仰角限制內，只將砲管俯仰轉向世界座標目標。
func aim_gun_pitch_at_target(target_position: Vector3, delta: float) -> void:
	var minimum_pitch := -deg_to_rad(maxf(gun_max_depression_degrees, 0.0))
	var maximum_pitch := deg_to_rad(maxf(gun_max_elevation_degrees, 0.0))
	var current_pitch := -gun_pitch_pivot.rotation.z
	var target_pitch := _target_gun_pitch_for_world_target(target_position)
	var next_pitch := move_toward(current_pitch, target_pitch, maxf(gun_pitch_speed, 0.0) * maxf(delta, 0.0))
	gun_pitch_pivot.rotation.z = -clampf(next_pitch, minimum_pitch, maximum_pitch)


## 回傳 MuzzlePoint 目前的世界座標投射物起點。
func muzzle_global_position() -> Vector3:
	return muzzle_point.global_position


## 回傳沿 MuzzlePoint 本地 -X 軸的正規化世界座標射擊方向。
func muzzle_global_direction() -> Vector3:
	return (-muzzle_point.global_transform.basis.x).normalized()


## 當連接有效時，發出一個 ShotEvent、舊版相容性資料載荷、砲口火焰與視覺後座。
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
	## 將世界座標的反射擊方向轉回車身本地座標，使後座會隨車身朝向移動且不影響實際碰撞。
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
	## Tween 被中斷或完成後都回寫製作時的本地靜止位置，避免視覺模型累積偏移。
	visual_recoil_pivot.position = visual_recoil_rest_local_position


func _spawn_muzzle_flash(muzzle_position: Vector3, muzzle_direction: Vector3) -> void:
	## 將一次性特效掛到砲口以承接生命週期，仍以世界座標快照定位並由計時器在壽命結束後釋放。
	var muzzle_flash := MUZZLE_FLASH_SCENE.instantiate() as Node3D
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.set("one_shot", true)
	muzzle_flash.set("autoplay", true)
	muzzle_point.add_child(muzzle_flash, true)
	var flash_basis := _basis_with_x_axis(muzzle_direction).scaled(Vector3.ONE * muzzle_flash_scale)
	muzzle_flash.global_transform = Transform3D(flash_basis, muzzle_position)
	get_tree().create_timer(muzzle_flash_lifetime_seconds).timeout.connect(muzzle_flash.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	## 讓素材的本地 X 軸對齊砲口方向；接近垂直時改用後方軸建立穩定的正交座標系。
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
