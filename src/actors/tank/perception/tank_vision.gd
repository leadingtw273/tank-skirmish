## 提供坦克可共用的近距離全向與砲塔朝向遠距視線判定。
@tool
extends Node

@export var observer: Node3D
var near_radius: float:
	get: return maxf(float(observer.get("vision_near_radius")), 0.0) if is_instance_valid(observer) else 0.0
var far_radius: float:
	get: return maxf(float(observer.get("vision_far_radius")), 0.0) if is_instance_valid(observer) else 0.0
var far_field_of_view_degrees: float:
	get: return clampf(float(observer.get("vision_field_of_view_degrees")), 0.0, 360.0) if is_instance_valid(observer) else 0.0
@export_flags_3d_physics var collision_mask := 129


func can_see(target: Node3D) -> bool:
	return not visible_target_points(target).is_empty()


## 擷取一輪查詢所需的觀察者資料；預覽可用它維持整批一致的圓扇與射線起點。
func capture_visibility_state() -> Dictionary:
	if not is_instance_valid(observer):
		return {}
	return {
		"root_position": observer.global_position,
		"view_origin": _view_origin(),
		"forward": get_horizontal_forward(),
		"near_radius": near_radius,
		"far_radius": far_radius,
		"far_field_of_view_degrees": far_field_of_view_degrees,
		"collision_mask": collision_mask,
		"exclude": [observer.get_rid()],
	}


## 依快照逐點判定近圈／遠扇聯集；不可用目標中心先淘汰其他部位。
func point_in_visibility_range(point: Vector3, state: Dictionary) -> bool:
	if state.is_empty() or not state.has("root_position"):
		return false
	var horizontal_offset: Vector3 = point - state["root_position"]
	horizontal_offset.y = 0.0
	var near := maxf(float(state.get("near_radius", 0.0)), 0.0)
	var far := maxf(float(state.get("far_radius", 0.0)), 0.0)
	var distance := horizontal_offset.length()
	if distance > maxf(near, far):
		return false
	if distance <= near:
		return true
	var forward: Vector3 = state.get("forward", Vector3.ZERO)
	if forward.is_zero_approx() or horizontal_offset.is_zero_approx():
		return false
	var half_angle := deg_to_rad(clampf(float(state.get("far_field_of_view_degrees", 0.0)), 0.0, 360.0) * 0.5)
	return distance <= far and forward.angle_to(horizontal_offset.normalized()) <= half_angle


## 共用射線核心。target 非空時保留既有「第一個命中本目標即通過」語意。
func point_has_clear_line_of_sight(point: Vector3, state: Dictionary, space: PhysicsDirectSpaceState3D,
		target: Node3D = null) -> bool:
	if state.is_empty() or space == null:
		return false
	var origin: Vector3 = state.get("view_origin", Vector3.ZERO)
	if origin.distance_squared_to(point) <= 0.0001:
		return false
	var exclude: Array[RID] = []
	for rid in state.get("exclude", []):
		if rid is RID:
			exclude.append(rid)
	var query := PhysicsRayQueryParameters3D.create(origin, point, int(state.get("collision_mask", collision_mask)), exclude)
	var hit := space.intersect_ray(query)
	return hit.is_empty() or (target != null and hit.get("collider") == target)


func visible_target_points(target: Node3D) -> PackedVector3Array:
	var visible_points := PackedVector3Array()
	if not is_instance_valid(observer) or not is_instance_valid(target) or observer.get_world_3d() == null:
		return visible_points
	var state := capture_visibility_state()
	var space := observer.get_world_3d().direct_space_state
	var target_position := target_world_position(target)
	if point_in_visibility_range(target_position, state) and point_has_clear_line_of_sight(target_position, state, space, target):
		visible_points.append(target_position)
	if not target.has_method(&"part_world_surface_points"):
		return visible_points
	var surface_points: PackedVector3Array = target.call("part_world_surface_points") as PackedVector3Array
	for point in surface_points:
		if point_in_visibility_range(point, state) and point_has_clear_line_of_sight(point, state, space, target):
			visible_points.append(point)
	return visible_points


func target_world_position(target: Node3D) -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	return target.call("stable_world_center") as Vector3 if target.has_method("stable_world_center") else target.global_position


func get_horizontal_forward() -> Vector3:
	if not is_instance_valid(observer):
		return Vector3.ZERO
	var turret_pivot := observer.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret_pivot == null:
		return Vector3.ZERO
	var forward := -turret_pivot.global_basis.x
	forward.y = 0.0
	return Vector3.ZERO if forward.is_zero_approx() else forward.normalized()


func _view_origin() -> Vector3:
	var turret_pivot := observer.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	return turret_pivot.global_position if turret_pivot != null else observer.global_position
