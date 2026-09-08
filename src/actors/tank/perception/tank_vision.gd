## 提供坦克可共用的近距離全向與砲塔朝向遠距視線判定。
@tool
extends Node

## 視野所屬的坦克；其砲塔高度是遠距與遮擋射線的起點。
@export var observer: Node3D
## 數值由觀察坦克提供，不在視野元件內保存另一份設定。
var near_radius: float:
	get:
		return maxf(float(observer.get("vision_near_radius")), 0.0) if is_instance_valid(observer) else 0.0
var far_radius: float:
	get:
		return maxf(float(observer.get("vision_far_radius")), 0.0) if is_instance_valid(observer) else 0.0
var far_field_of_view_degrees: float:
	get:
		return clampf(float(observer.get("vision_field_of_view_degrees")), 0.0, 360.0) if is_instance_valid(observer) else 0.0
## 視線射線要查詢的物理碰撞層遮罩。
@export_flags_3d_physics var collision_mask := 129


## 回傳 target 是否位於近圈或遠扇形，且觀察者到目標車體中心沒有遮擋。
func can_see(target: Node3D) -> bool:
	if observer == null or target == null or not is_instance_valid(observer) or not is_instance_valid(target):
		return false
	var target_position := target_world_position(target)
	var horizontal_offset := target_position - observer.global_position
	horizontal_offset.y = 0.0
	var horizontal_distance := horizontal_offset.length()
	if horizontal_distance > maxf(near_radius, far_radius):
		return false
	if horizontal_distance > maxf(near_radius, 0.0) and not _is_inside_far_field_of_view(horizontal_offset):
		return false
	return _has_clear_line_of_sight(_view_origin(), target_position, target)


## 回傳目標直屬 CollisionShape3D 的世界位置，作為第一版車體中心取樣點。
func target_world_position(target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	var collision_shape := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return collision_shape.global_position if collision_shape != null else target.global_position


## 回傳砲塔本地 -X 投影到水平面的正規化前方；無有效砲塔時回傳零向量。
func get_horizontal_forward() -> Vector3:
	if not is_instance_valid(observer):
		return Vector3.ZERO
	var turret_pivot := observer.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret_pivot == null:
		return Vector3.ZERO
	var forward := -turret_pivot.global_basis.x
	forward.y = 0.0
	return Vector3.ZERO if forward.is_zero_approx() else forward.normalized()


func _is_inside_far_field_of_view(horizontal_offset: Vector3) -> bool:
	## 砲塔以本地 -X 為水平前方；只比較 XZ 平面避免高低差影響扇形。
	if horizontal_offset.is_zero_approx() or horizontal_offset.length() > maxf(far_radius, 0.0):
		return false
	var forward := get_horizontal_forward()
	if forward.is_zero_approx():
		return false
	var half_angle := deg_to_rad(clampf(far_field_of_view_degrees, 0.0, 360.0) * 0.5)
	return forward.angle_to(horizontal_offset.normalized()) <= half_angle


func _view_origin() -> Vector3:
	## 將視線抬到砲塔中心，近圈也沿用同一高度以確保兩種範圍都受真實遮擋約束。
	var turret_pivot := observer.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	return turret_pivot.global_position if turret_pivot != null else observer.global_position


func _has_clear_line_of_sight(origin: Vector3, target_position: Vector3, target: Node3D) -> bool:
	## 射線第一個命中必須是目標本體；排除觀察者自身碰撞，避免坦克車體遮住自己的視線。
	if origin.distance_squared_to(target_position) <= 0.0001 or observer.get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target_position, collision_mask, [observer.get_rid()])
	var hit := observer.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == target
