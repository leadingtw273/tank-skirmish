## 原地坦克可受擊轉向查看；目標可見才瞄準開火，固定砲塔沿用車體輔助轉向。
extends Node

## 由此 AI 控制砲塔、砲管、原地輔助轉向與開火請求的完整坦克。
@export var controlled_tank: Node3D
## 提供目標可見性與車體中心位置的共用視野元件。
@export var vision: Node
## 砲口方向與目標方向可允許的最大三維角度誤差，單位為度。
@export_range(0.0, 45.0, 0.1) var alignment_tolerance_degrees := 3.0

## 此固定位置 AI 目前唯一追蹤的目標，可由場景協調器在換車後更新。
var target: Node3D
## 場景協調器控制的戰鬥開關；關閉時停止追蹤與開火但保留目前砲塔姿態。
var combat_enabled := true
## 命中當下車體中心指向受擊點的世界水平方向；零代表沒有待完成的查看。
var _inspection_direction := Vector3.ZERO


## 指定唯一戰鬥目標；第一版不執行敵我辨識或多目標選擇。
func set_target(next_target: Node3D) -> void:
	_inspection_direction = Vector3.ZERO
	_cancel_aim()
	target = next_target


## 由場景死亡／恢復協調器啟停戰鬥，不在 AI 內建立重生或計時規則。
func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	if not combat_enabled:
		_inspection_direction = Vector3.ZERO
		_cancel_aim()


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
	_inspection_direction = hit_direction.normalized()


func _physics_process(delta: float) -> void:
	if not _can_operate():
		_inspection_direction = Vector3.ZERO
		_cancel_aim()
		return
	var visible_points: PackedVector3Array = vision.call("visible_target_points", target) as PackedVector3Array
	if visible_points.is_empty():
		if not _inspection_direction.is_zero_approx():
			_turn_to_inspection(delta)
		else:
			_cancel_aim()
		return
	## 正常視野優先；一旦看見目標，就不再保留先前受擊側的查看意圖。
	_inspection_direction = Vector3.ZERO
	var selected_aim: Dictionary = _select_aim_target(visible_points)
	var selected_point: Vector3 = selected_aim.get("position", Vector3.ZERO) as Vector3
	var can_fire: bool = bool(selected_aim.get("can_fire", false))
	controlled_tank.call("aim_turret_at", selected_point, delta)
	controlled_tank.call("aim_gun_pitch_at_target", selected_point, delta)
	_apply_hull_aim_assist()
	if can_fire and _is_muzzle_aligned_and_clear(selected_point):
		controlled_tank.call("request_fire")


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


func _apply_hull_aim_assist() -> void:
	## 車型自己判斷是否需要轉車體；一般旋轉砲塔車型會回傳 0，不以型號寫特例。
	controlled_tank.call("set_movement_input", 0.0)
	var turn_input := clampf(float(controlled_tank.call("get_hull_aim_turn_input")), -1.0, 1.0)
	if is_zero_approx(turn_input):
		## 對齊就清除既有旋轉慣性，與玩家輔助瞄準使用同一個停止介面。
		controlled_tank.call("stop_hull_aim_turn")
	else:
		controlled_tank.call("set_turn_input", turn_input)


func _turn_to_inspection(delta: float) -> void:
	var turret := controlled_tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret == null:
		_inspection_direction = Vector3.ZERO
		_cancel_aim()
		return
	## 朝固定方向的遠處虛擬點偏航，避免把車身受擊點直接交給近距瞄準死區。
	controlled_tank.call("aim_turret_at", turret.global_position + _inspection_direction * 100.0, delta)
	if _turret_forward().angle_to(_inspection_direction) <= deg_to_rad(maxf(alignment_tolerance_degrees, 0.0)):
		_inspection_direction = Vector3.ZERO
		_cancel_aim()
	else:
		_apply_hull_aim_assist()


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
		## 沒有查看意圖、死亡或被停用時也須清除車體轉向，不能只取消砲管瞄準。
		if controlled_tank.has_method(&"set_movement_input"):
			controlled_tank.call("set_movement_input", 0.0)
		if controlled_tank.has_method(&"stop_hull_aim_turn"):
			controlled_tank.call("stop_hull_aim_turn")
