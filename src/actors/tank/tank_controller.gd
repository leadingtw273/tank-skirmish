## 管理坦克移動、砲塔姿態、射擊事件、履帶動畫與視覺後座。
## 它不會實體化投射物或擁有世界戰鬥容器；CombatRuntime 消費其事件。
extends CharacterBody3D

@export_category("坦克移動")
## 滿輸入時車身前進或倒退的最高速度，單位為公尺／秒。
@export var movement_speed := 15.0
## 滿轉向輸入時車身偏航速度，單位為弧度／秒。
@export var turn_speed := 0.8
## 滿轉向輸入時保留的直線最高速度比例；0.5 代表降至原本的一半。
@export_range(0.0, 1.0, 0.05) var turning_movement_speed_ratio := 0.5
## 每次成功開砲時立即損失的目前前後移動速度比例；0.25 代表損失四分之一。
@export_range(0.0, 1.0, 0.05) var firing_movement_speed_loss_ratio := 0.25
## 坦克用於換算加速反應的質量，單位為公噸。
@export var tank_mass_tonnes := 60.0
## 引擎用於換算加速反應的額定輸出，單位為馬力。
@export var engine_horsepower := 1500.0
## 煞車系統用於換算減速度的最大制動力，單位為千牛頓。
@export var brake_force_kilonewtons := 240.0
## 將線性加減速換算為車身偏航反應的係數，單位為無單位倍率。
@export var turn_response := 0.4
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
const TREAD_ANIMATION_MOTION_THRESHOLD := 0.01
const TREAD_ANIMATION_REFERENCE_MODEL_SCALE := 1.7466666
const TREAD_ANIMATION_CLIPS := {
	"forward": &"Tank_Forward",
	"backwards": &"Tank_Backwards",
	"turning_left": &"Tank_TurningLeft",
	"turning_right": &"Tank_TurningRight",
}
const MUZZLE_FLASH_SCENE := preload("res://src/vfx/muzzle/muzzle_flash_vfx.tscn")
const TREAD_DUST_SCENE := preload("res://src/vfx/tread_dust/tread_dust_vfx.tscn")
const ShotEvent := preload("res://src/combat/shot_event.gd")
@export_category("砲口火焰")
## 已生成的砲口火焰在移除前的存活時間，單位為秒。
@export var muzzle_flash_lifetime_seconds := 0.25
## 套用至製作好的砲口火焰特效之等比縮放倍率。
@export var muzzle_flash_scale := 4.0

@export_category("履帶煙塵")
## 套用至左右履帶煙塵的等比粒子尺寸倍率。
@export_range(0.1, 4.0, 0.05) var tread_dust_scale := 0.85
## 履帶停止後，既有煙塵自然散去所需的秒數。
@export_range(0.1, 5.0, 0.05) var tread_dust_lifetime_seconds := 1.2
## 履帶全速移動時，每側煙塵來源維持的粒子數量。
@export_range(1, 128, 1) var tread_dust_emission_amount := 28
## 實際線速度或角速度達到此值時才開始產生煙塵。
@export_range(0.01, 5.0, 0.01) var tread_dust_activation_speed := 0.15

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
var forward_speed := 0.0
var angular_speed := 0.0
var tread_animation_player: AnimationPlayer
var active_tread_animation := &""
var tread_animation_paused := true
var tread_animations_available := false
var visual_recoil_rest_local_position := Vector3.ZERO
var visual_recoil_tween: Tween
var left_tread_dust: Node3D
var right_tread_dust: Node3D


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
	_setup_tread_dust()


func _physics_process(delta: float) -> void:
	## 以動力與煞車積分線／角速度，碰撞後讀回實際線速度，再讓履帶依實際動態更新。
	var engine_acceleration := _engine_acceleration()
	var brake_acceleration := _brake_acceleration()
	var movement_speed_limit := _movement_speed_limit_for_turn(turn_command)
	forward_speed = _approach_motion_speed(
		forward_speed,
		movement_command,
		movement_speed_limit,
		engine_acceleration,
		brake_acceleration,
		delta,
		true,
	)
	angular_speed = _approach_motion_speed(
		angular_speed,
		turn_command,
		turn_speed,
		engine_acceleration * turn_response,
		brake_acceleration * turn_response,
		delta,
	)
	rotate_y(angular_speed * delta)
	var forward_direction := transform.basis * MODEL_FORWARD_LOCAL_AXIS
	velocity = forward_direction * forward_speed
	move_and_slide()
	var actual_forward_speed := get_real_velocity().dot(forward_direction)
	if get_slide_collision_count() > 0:
		forward_speed = actual_forward_speed
	var next_tread_animation := _tread_animation_for_motion(actual_forward_speed, angular_speed)
	_update_tread_animation(
		next_tread_animation,
		_tread_animation_speed_scale(next_tread_animation, actual_forward_speed, angular_speed),
	)
	_update_tread_dust(actual_forward_speed, angular_speed)


## 儲存介於 -1 到 1 的前進／倒退指令，供下一個物理步驟使用。
func set_movement_input(input_value: float) -> void:
	movement_command = clampf(input_value, -1.0, 1.0)


## 儲存介於 -1 到 1 的車身轉向指令，供下一個物理步驟使用。
func set_turn_input(input_value: float) -> void:
	turn_command = clampf(input_value, -1.0, 1.0)


## 回傳供 CameraController 使用且不為負值的鏡頭前視上限，單位為公尺。
func get_max_camera_look_ahead_distance() -> float:
	return maxf(max_camera_look_ahead_distance, 0.0)


func _engine_acceleration() -> float:
	## 依遊戲化馬力／質量換算直線加速度，單位為公尺／秒平方。
	return engine_horsepower / tank_mass_tonnes * 0.08


func _brake_acceleration() -> float:
	## 依制動力／質量換算煞車減速度，單位為公尺／秒平方。
	return brake_force_kilonewtons / tank_mass_tonnes


func _braking_distance(speed: float) -> float:
	## 回傳以目前煞車減速度估計的煞停距離，單位為公尺。
	return speed * speed / (2.0 * _brake_acceleration())


func _movement_speed_limit_for_turn(turn_input: float) -> float:
	## 依轉向輸入強度平滑降低直線速度上限；滿轉向時使用 Inspector 設定的保留比例。
	var turn_strength := clampf(absf(turn_input), 0.0, 1.0)
	return movement_speed * lerpf(1.0, turning_movement_speed_ratio, turn_strength)


func _apply_firing_movement_speed_loss() -> void:
	## 成功開砲的當下只削減線速度；保留前後方向，且不影響車身角速度。
	var retained_speed_ratio := 1.0 - clampf(firing_movement_speed_loss_ratio, 0.0, 1.0)
	forward_speed *= retained_speed_ratio
	velocity *= retained_speed_ratio


func _approach_motion_speed(
		current_speed: float,
		input_direction: float,
		maximum_speed: float,
	acceleration: float,
	braking_acceleration: float,
	delta: float,
	brake_when_above_limit: bool = false,
) -> float:
	## 依輸入漸進逼近目標；反向先煞停，線速度超過轉彎上限時可選擇以煞車反應降速。
	if is_zero_approx(input_direction) or (not is_zero_approx(current_speed) and signf(current_speed) != signf(input_direction)):
		return move_toward(current_speed, 0.0, braking_acceleration * delta)
	var target_speed := input_direction * maximum_speed
	var response := braking_acceleration if brake_when_above_limit and absf(current_speed) > absf(target_speed) else acceleration
	return move_toward(current_speed, target_speed, response * delta)


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


func _setup_tread_dust() -> void:
	## 在車身兩側、接近履帶接地處建立來源；粒子本身使用世界座標，故車輛駛離後會留在原處散去。
	left_tread_dust = _create_tread_dust(&"LeftTreadDust", Vector3(0.0, 0.15, 3.1))
	right_tread_dust = _create_tread_dust(&"RightTreadDust", Vector3(0.0, 0.15, -3.1))


func _create_tread_dust(dust_name: StringName, local_position: Vector3) -> Node3D:
	var tread_dust := TREAD_DUST_SCENE.instantiate() as Node3D
	tread_dust.name = dust_name
	add_child(tread_dust)
	tread_dust.position = local_position
	return tread_dust


func _update_tread_dust(actual_forward_speed: float, actual_angular_speed: float) -> void:
	## 只用物理步驟取得的實際線／角速度；直行、倒退與原地旋轉都會依速度強度調整發射量。
	var linear_motion := absf(actual_forward_speed)
	var angular_motion := absf(actual_angular_speed)
	var motion_speed := maxf(linear_motion, angular_motion)
	var speed_ratio := maxf(
		linear_motion / maxf(absf(movement_speed), 0.001),
		angular_motion / maxf(absf(turn_speed), 0.001),
	)
	var emission_intensity := speed_ratio if motion_speed >= tread_dust_activation_speed else 0.0
	for tread_dust in [left_tread_dust, right_tread_dust]:
		if tread_dust == null:
			continue
		tread_dust.set_dust_parameters(tread_dust_scale, tread_dust_lifetime_seconds, tread_dust_emission_amount)
		tread_dust.set_motion_intensity(emission_intensity)


func _find_animation_player(node: Node) -> AnimationPlayer:
	## 深度優先走訪匯入節點，因素材階層不保證 AnimationPlayer 位於固定 NodePath。
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _tread_animation_for_motion(actual_forward_speed: float, actual_angular_speed: float) -> StringName:
	## 以實際角速度優先選擇履帶片段，僅在線／角速度高於門檻時持續播放。
	if absf(actual_angular_speed) > TREAD_ANIMATION_MOTION_THRESHOLD:
		return TREAD_ANIMATION_CLIPS["turning_left"] if actual_angular_speed > 0.0 else TREAD_ANIMATION_CLIPS["turning_right"]
	if actual_forward_speed > TREAD_ANIMATION_MOTION_THRESHOLD:
		return TREAD_ANIMATION_CLIPS["forward"]
	if actual_forward_speed < -TREAD_ANIMATION_MOTION_THRESHOLD:
		return TREAD_ANIMATION_CLIPS["backwards"]
	return &""


func _tread_animation_speed_scale(next_animation: StringName, actual_forward_speed: float, actual_angular_speed: float = 0.0) -> float:
	## 直行依碰撞後線速度與模型縮放修正；轉向依實際角速度與最高偏航速度同步。
	if next_animation == TREAD_ANIMATION_CLIPS["turning_left"] or next_animation == TREAD_ANIMATION_CLIPS["turning_right"]:
		return absf(actual_angular_speed) / maxf(absf(turn_speed), 0.001) * tread_animation_speed_multiplier
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

	_apply_firing_movement_speed_loss()
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
