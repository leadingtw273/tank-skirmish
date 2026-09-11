## 依可見目標、受擊查看、最後目擊位置決定追近／搜索；統一提交車身命令。
extends Node

const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const SEARCH_ARRIVAL_DISTANCE := 3.0
const HULL_FACING_TOLERANCE_DEGREES := 5.0
const BLOCKED_TARGET_RETRY_DISTANCE := 3.0

## 換車先清舊車命令與路徑，不把上一台車的記憶帶到新車。
@export var controlled_tank: Node3D:
	set(value):
		if controlled_tank == value:
			return
		_cancel_aim()
		_submit_body_commands(0.0, 0.0)
		_release_navigation()
		controlled_tank = value
		_inspection_direction = Vector3.ZERO
		_clear_last_seen_position()
		_reset_movement()
## 提供目標可見性與車體中心位置的共用視野元件。
@export var vision: Node
## 砲口方向與目標方向可允許的最大三維角度誤差，單位為度。
@export_range(0.0, 45.0, 0.1) var alignment_tolerance_degrees := 3.0

## 唯一追蹤目標；導航只收到可用位置，不持有或讀取這個目標節點。
var target: Node3D
## 場景協調器控制的戰鬥開關；關閉時停止追蹤與開火但保留目前砲塔姿態。
var combat_enabled := true
## 命中當下車體中心指向受擊點的世界水平方向；零代表沒有待完成的查看。
var _inspection_direction := Vector3.ZERO
## 最後實際目擊時的穩定車身中心世界座標；失視後不再讀取目標位置。
var _last_seen_position := Vector3.ZERO
## 世界原點亦為合法位置，記憶有效性不能由座標是否為零判斷。
var _has_last_seen_position := false
## 供測試／偵錯觀察的當前移動結果，不是另一套狀態權威。
var movement_status: StringName = &"idle"
var _navigation: RefCounted
var _navigation_generation := 0
var _was_visible := false
var _pursuing := false
var _blocked_goal := Vector3.ZERO
var _blocked_goal_valid := false


## 指定唯一戰鬥目標；第一版不執行敵我辨識或多目標選擇。
func set_target(next_target: Node3D) -> void:
	_inspection_direction = Vector3.ZERO
	_clear_last_seen_position()
	_reset_movement()
	_cancel_aim()
	_submit_body_commands(0.0, 0.0)
	target = next_target


## 由場景死亡／恢復協調器啟停戰鬥，不在 AI 內建立重生或計時規則。
func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	if not combat_enabled:
		_inspection_direction = Vector3.ZERO
		_clear_last_seen_position()
		_reset_movement()
		_cancel_aim()
		_submit_body_commands(0.0, 0.0)


## 只知道自己哪一側被打中，不使用彈道方向或攻擊者位置作為查看朝向。
func inspect_hit_position(hit_position: Vector3) -> void:
	if not _can_operate() or not hit_position.is_finite() or vision.call("can_see", target):
		return
	var hit_direction := hit_position - (vision.call("target_world_position", controlled_tank) as Vector3)
	hit_direction.y = 0.0
	var forward := _turret_forward()
	if hit_direction.is_zero_approx() or forward.is_zero_approx():
		return
	if forward.angle_to(hit_direction) <= deg_to_rad(float(vision.get("far_field_of_view_degrees")) * 0.5):
		return
	_clear_last_seen_position()
	_reset_movement()
	_inspection_direction = hit_direction.normalized()
	movement_status = &"inspection"
	_submit_body_commands(0.0, 0.0)


func _physics_process(delta: float) -> void:
	if not _can_operate():
		_inspection_direction = Vector3.ZERO
		_clear_last_seen_position()
		_reset_movement()
		_cancel_aim()
		_submit_body_commands(0.0, 0.0)
		return
	_ensure_navigation()
	var visible_points: PackedVector3Array = vision.call("visible_target_points", target) as PackedVector3Array
	if visible_points.is_empty():
		if _was_visible:
			_was_visible = false
			_pursuing = false
			_new_navigation_goal()
		if not _inspection_direction.is_zero_approx():
			_turn_to_inspection(delta)
		elif _has_last_seen_position:
			_aim_at_position(_last_seen_position, delta)
			var search_intent: Dictionary = _navigation.call("drive", _last_seen_position,
				_navigation_generation, SEARCH_ARRIVAL_DISTANCE, delta)
			_submit_navigation_intent(search_intent, _last_seen_position)
		else:
			movement_status = &"idle"
			_cancel_aim()
			_submit_body_commands(0.0, 0.0)
		return
	## 正常視野優先；一旦看見目標，就不再保留先前受擊側的查看意圖。
	_inspection_direction = Vector3.ZERO
	## 只露出部位時第一個可見點未必是車身中心，必須分開取得中心快照。
	_last_seen_position = vision.call("target_world_position", target) as Vector3
	_has_last_seen_position = true
	var center := controlled_tank.call("stable_world_center") as Vector3
	var distance := _horizontal_distance(center, _last_seen_position)
	var stop_distance := maxf(float(controlled_tank.get("ai_stop_distance")), 0.1)
	var resume_distance := maxf(float(controlled_tank.get("ai_resume_distance")), stop_distance + 0.1)
	if not _was_visible:
		_new_navigation_goal()
		_pursuing = distance > resume_distance
	elif not _pursuing and distance > resume_distance:
		_new_navigation_goal()
		_pursuing = true
	elif _pursuing and distance <= stop_distance:
		_pursuing = false
		_new_navigation_goal()
	_was_visible = true
	var selected_aim: Dictionary = _select_aim_target(visible_points)
	var selected_point: Vector3 = selected_aim.get("position", Vector3.ZERO) as Vector3
	var can_fire: bool = bool(selected_aim.get("can_fire", false))
	## 姿態依原目標更新後才做通道安全檢查；不鎖砲塔、不放寬射擊門檻。
	_aim_at_position(selected_point, delta)
	var move_intent := {"movement": 0.0, "turn": 0.0, "status": &"holding"}
	if _pursuing:
		## 停止後同一目標不能每幀重啟；只有可見位置確實改變才重試。
		if _blocked_goal_valid and _horizontal_distance(_blocked_goal, _last_seen_position) >= BLOCKED_TARGET_RETRY_DISTANCE:
			_new_navigation_goal()
		move_intent = _navigation.call("drive", _last_seen_position, _navigation_generation, stop_distance, delta)
		var status: StringName = move_intent.get("status", &"idle")
		if status == &"arrived":
			_pursuing = false
		elif status in [&"partial_end", &"no_path", &"stuck"] and not _blocked_goal_valid:
			_blocked_goal = _last_seen_position
			_blocked_goal_valid = true
	_submit_navigation_intent(move_intent, _last_seen_position)
	if can_fire and _is_muzzle_aligned_and_clear(selected_point):
		controlled_tank.call("request_fire")


func _clear_last_seen_position() -> void:
	_has_last_seen_position = false
	_last_seen_position = Vector3.ZERO


func _aim_at_position(position: Vector3, delta: float) -> void:
	controlled_tank.call("aim_turret_at", position, delta)
	controlled_tank.call("aim_gun_pitch_at_target", position, delta)


func _select_aim_target(visible_points: PackedVector3Array) -> Dictionary:
	## 候選順序由 Vision 決定：可射時取第一個，全部被砲口遮擋時仍瞄準第一個可見點。
	var selection: Dictionary = {"position": visible_points[0], "can_fire": false}
	for point in visible_points:
		if _has_ideal_muzzle_line_of_fire(point):
			selection["position"] = point
			selection["can_fire"] = true
			break
	return selection


func _has_ideal_muzzle_line_of_fire(point: Vector3) -> bool:
	## 這只供候選排序；最後開火仍由實際砲口方向、角度與首命中 gate 驗證。
	var muzzle_position := controlled_tank.call("muzzle_global_position") as Vector3
	if muzzle_position.distance_squared_to(point) <= 0.0001 or controlled_tank.get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(muzzle_position, point, 129, [controlled_tank.get_rid()])
	var hit := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == target


func _submit_navigation_intent(intent: Dictionary, facing_position: Vector3) -> void:
	movement_status = intent.get("status", &"idle")
	var moving := movement_status == &"moving"
	var turn := float(intent.get("turn", 0.0)) if moving else _stationary_facing_input(facing_position)
	_submit_body_commands(float(intent.get("movement", 0.0)) if moving else 0.0, turn)


func _stationary_facing_input(position: Vector3) -> float:
	var direction := position - (controlled_tank.call("stable_world_center") as Vector3)
	direction.y = 0.0
	if not direction.is_zero_approx():
		var forward := -controlled_tank.global_basis.x
		forward.y = 0.0
		var error := forward.normalized().signed_angle_to(direction.normalized(), Vector3.UP)
		if absf(error) > deg_to_rad(HULL_FACING_TOLERANCE_DEGREES):
			return clampf(error / deg_to_rad(20.0), -1.0, 1.0)
	## 固定砲塔仍可依原機械精度微調，不把車頭5度容差當成射擊資格。
	return clampf(float(controlled_tank.call("get_hull_aim_turn_input")), -1.0, 1.0)


## 所有正常物理更新與生命週期停止都經過這個唯一命令出口。
func _submit_body_commands(movement: float, turn: float) -> void:
	if not is_instance_valid(controlled_tank):
		return
	if controlled_tank.has_method(&"set_movement_input"):
		controlled_tank.call("set_movement_input", clampf(movement, 0.0, 1.0))
	if is_zero_approx(turn) and controlled_tank.has_method(&"stop_hull_aim_turn"):
		controlled_tank.call("stop_hull_aim_turn")
	elif controlled_tank.has_method(&"set_turn_input"):
		controlled_tank.call("set_turn_input", clampf(turn, -1.0, 1.0))


func _ensure_navigation() -> void:
	if _navigation == null:
		_navigation = TankNavigation.new()
		_navigation.call("setup", controlled_tank)


func _new_navigation_goal() -> void:
	_navigation_generation += 1
	_blocked_goal_valid = false
	if _navigation != null:
		_navigation.call("clear")


func _reset_movement() -> void:
	_new_navigation_goal()
	_was_visible = false
	_pursuing = false
	movement_status = &"idle"


func _release_navigation() -> void:
	if _navigation != null:
		_navigation.call("dispose")
		_navigation = null


func _exit_tree() -> void:
	_cancel_aim()
	_submit_body_commands(0.0, 0.0)
	_release_navigation()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _turn_to_inspection(delta: float) -> void:
	var turret := controlled_tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret == null:
		_inspection_direction = Vector3.ZERO
		_cancel_aim()
		_submit_body_commands(0.0, 0.0)
		return
	## 朝固定方向的遠處虛擬點偏航，避免把車身受擊點直接交給近距瞄準死區。
	controlled_tank.call("aim_turret_at", turret.global_position + _inspection_direction * 100.0, delta)
	if _turret_forward().angle_to(_inspection_direction) <= deg_to_rad(maxf(alignment_tolerance_degrees, 0.0)):
		_inspection_direction = Vector3.ZERO
		movement_status = &"idle"
		_cancel_aim()
		_submit_body_commands(0.0, 0.0)
	else:
		movement_status = &"inspection"
		_submit_body_commands(0.0, float(controlled_tank.call("get_hull_aim_turn_input")))


func _turret_forward() -> Vector3:
	var turret := controlled_tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret == null:
		return Vector3.ZERO
	var forward := -turret.global_basis.x
	forward.y = 0.0
	return forward.normalized()


func _can_operate() -> bool:
	## 任何前置條件在同一物理更新不成立就停發命令，避免失聯後殘留瞄準與開火。
	return (
		combat_enabled
		and controlled_tank != null
		and target != null
		and vision != null
		and is_instance_valid(controlled_tank)
		and is_instance_valid(target)
		and controlled_tank.has_method(&"aim_turret_at")
		and controlled_tank.has_method(&"aim_gun_pitch_at_target")
		and controlled_tank.has_method(&"muzzle_global_position")
		and controlled_tank.has_method(&"muzzle_global_direction")
		and controlled_tank.has_method(&"request_fire")
		and controlled_tank.has_method(&"get_hull_aim_turn_input")
		and controlled_tank.has_method(&"set_movement_input")
		and controlled_tank.has_method(&"set_turn_input")
		and controlled_tank.has_method(&"stop_hull_aim_turn")
		and controlled_tank.has_method(&"stable_world_center")
		and vision.has_method(&"can_see")
		and vision.has_method(&"visible_target_points")
		and vision.has_method(&"target_world_position")
		and _is_alive(controlled_tank)
		and _is_alive(target)
	)


func _is_alive(subject: Node3D) -> bool:
	## HealthComponent 是 Tank 的直屬元件；不存在或未初始化時視為不可戰鬥，避免猜測其他生命值模型。
	var health_component := subject.get_node_or_null("HealthComponent")
	return health_component != null and float(health_component.get("current_health")) > 0.0


func _is_muzzle_aligned_and_clear(target_position: Vector3) -> bool:
	## 開火同時要求實際砲口方向在容差內，且沿該方向的首個物理命中確實是唯一目標。
	var muzzle_position := controlled_tank.call("muzzle_global_position") as Vector3
	var muzzle_direction := controlled_tank.call("muzzle_global_direction") as Vector3
	var to_target := target_position - muzzle_position
	if muzzle_direction.is_zero_approx() or to_target.is_zero_approx():
		return false
	if muzzle_direction.normalized().angle_to(to_target.normalized()) > deg_to_rad(maxf(alignment_tolerance_degrees, 0.0)):
		return false
	if controlled_tank.get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		muzzle_position,
		muzzle_position + muzzle_direction.normalized() * to_target.length(),
		129,
		[controlled_tank.get_rid()],
	)
	var hit := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == target


func _cancel_aim() -> void:
	## Tank 的取消介面只清除持續瞄準輸入，不重設已保留的砲塔與砲管姿態。
	if controlled_tank != null and is_instance_valid(controlled_tank) and controlled_tank.has_method(&"cancel_aim"):
		controlled_tank.call(&"cancel_aim")
