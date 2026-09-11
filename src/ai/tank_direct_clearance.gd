## 純唯讀的直線通行／車身轉向幾何 gate；不會寫入坦克姿態或控制命令。
extends RefCounted

const COLLISION_MASK := 1
const CLEARANCE := 1.15
const MAX_TURN_STEP_RADIANS := deg_to_rad(2.0)
const MOTION_EPSILON := 0.0001

var _tank: Node3D
var _turret_pivot: Node3D
var _gun_pitch_pivot: Node3D
var _geometry: Resource
var _shapes: Array[ConvexPolygonShape3D] = []
var _queries: Array[PhysicsShapeQueryParameters3D] = []


func setup(tank: Node3D) -> void:
	_tank = tank
	_turret_pivot = null
	_gun_pitch_pivot = null
	_geometry = null
	_shapes.clear()
	_queries.clear()
	if _tank == null or not _tank.has_method(&"candidate_part_shape_world_transforms"):
		return
	_geometry = _tank.get("part_geometry") as Resource
	if _geometry == null:
		return
	_turret_pivot = _tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	_gun_pitch_pivot = _tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	if _turret_pivot == null or _gun_pitch_pivot == null:
		_shapes.clear()
		return
	var parts: Variant = _geometry.get("parts")
	if not (parts is Array):
		_shapes.clear()
		return
	for part in parts:
		if part == null:
			_shapes.clear()
			return
		var convex_shapes: Variant = part.get("convex_shapes")
		if not (convex_shapes is Array):
			_shapes.clear()
			return
		for shape in convex_shapes:
			if not (shape is ConvexPolygonShape3D) or shape.points.is_empty():
				_shapes.clear()
				return
			_shapes.append(shape)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.collision_mask = COLLISION_MASK
			query.collide_with_bodies = true
			query.collide_with_areas = false
			_queries.append(query)
	if _shapes.is_empty():
		_queries.clear()


## 以目前砲塔／砲管相對車身姿態，檢查 root 繞本地 UP 的最短完整轉向掃掠。
func can_turn(angle: float) -> bool:
	var space := _space_state()
	if space == null or not _ready_for_query():
		return false
	var turn_angle := angle_difference(0.0, angle)
	var steps := maxi(1, ceili(absf(turn_angle) / MAX_TURN_STEP_RADIANS))
	var step_angle := absf(turn_angle) / float(steps)
	var current_root := _tank.global_transform
	var current_transforms := _candidate_transforms(current_root, _turret_pivot.rotation.y, -_gun_pitch_pivot.rotation.z)
	if not _valid_transforms(current_transforms):
		return false
	var margins := _turn_margins(current_transforms, current_root.origin, step_angle)
	if margins.is_empty() or not _pose_is_clear(space, current_transforms, margins):
		return false
	for step in range(1, steps + 1):
		var root := current_root.rotated_local(Vector3.UP, turn_angle * float(step) / float(steps))
		var transforms := _candidate_transforms(root, _turret_pivot.rotation.y, -_gun_pitch_pivot.rotation.z)
		if not _valid_transforms(transforms) or not _pose_is_clear(space, transforms, margins):
			return false
	return true


## 檢查候選 root／砲塔姿態從穩定中心朝 goal 的完整水平直線掃掠。
func can_travel(goal: Vector3, stop_distance: float, root_angle: float = 0.0, straighten_turret: bool = false) -> bool:
	var space := _space_state()
	if space == null or not _ready_for_query():
		return false
	var stable_center_local: Variant = _geometry.get("stable_center")
	if not (stable_center_local is Vector3):
		return false
	var candidate_root := _tank.global_transform.rotated_local(Vector3.UP, angle_difference(0.0, root_angle))
	var turret_yaw := 0.0 if straighten_turret else _turret_pivot.rotation.y
	var transforms := _candidate_transforms(candidate_root, turret_yaw, -_gun_pitch_pivot.rotation.z)
	if not _valid_transforms(transforms) or not _pose_is_clear(space, transforms, _clearance_margins()):
		return false
	var start: Vector3 = candidate_root * (stable_center_local as Vector3)
	var toward_goal := goal - start
	toward_goal.y = 0.0
	var distance := toward_goal.length()
	var travel := Vector3.ZERO
	var end_distance := maxf(stop_distance - 0.2, 0.0)
	if distance > end_distance and distance > MOTION_EPSILON:
		travel = toward_goal / distance * (distance - end_distance)
	return _translation_is_clear(space, transforms, travel)


func _ready_for_query() -> bool:
	return _tank != null and is_instance_valid(_tank) and _geometry != null and _shapes.size() == _queries.size() and not _shapes.is_empty()


func _space_state() -> PhysicsDirectSpaceState3D:
	if _tank == null or not is_instance_valid(_tank):
		return null
	var world := _tank.get_world_3d()
	return world.direct_space_state if world != null else null


func _candidate_transforms(root: Transform3D, turret_yaw: float, gun_pitch: float) -> Array:
	var transforms: Variant = _tank.call(&"candidate_part_shape_world_transforms", root, turret_yaw, gun_pitch)
	return transforms if transforms is Array else []


func _valid_transforms(transforms: Array) -> bool:
	if transforms.size() != _shapes.size():
		return false
	for transform in transforms:
		if not (transform is Transform3D) or not transform.is_finite():
			return false
	return true


func _clearance_margins() -> Array[float]:
	var margins: Array[float] = []
	for unused in _shapes:
		margins.append(CLEARANCE)
	return margins


func _turn_margins(transforms: Array, root: Vector3, step_angle: float) -> Array[float]:
	var margins: Array[float] = []
	for index in _shapes.size():
		var radius := 0.0
		for point in _shapes[index].points:
			radius = maxf(radius, root.distance_to(transforms[index] * point))
		## 將取樣間的最壞弧長納入每一形狀的 query margin，避免端點漏碰。
		margins.append(CLEARANCE + radius * step_angle)
	return margins


func _pose_is_clear(space: PhysicsDirectSpaceState3D, transforms: Array, margins: Array[float]) -> bool:
	var self_rid := _self_rid()
	if not self_rid.is_valid() or margins.size() != _queries.size():
		return false
	for index in _queries.size():
		var query := _queries[index]
		_configure_query(query, transforms[index], margins[index], self_rid)
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true


func _translation_is_clear(space: PhysicsDirectSpaceState3D, transforms: Array, motion: Vector3) -> bool:
	var self_rid := _self_rid()
	if not self_rid.is_valid():
		return false
	for index in _queries.size():
		var query := _queries[index]
		_configure_query(query, transforms[index], CLEARANCE, self_rid)
		## 零位移仍已在前置 intersect_shape 驗過候選姿態，無須依賴 cast 的未定義結果。
		if motion.length_squared() <= MOTION_EPSILON * MOTION_EPSILON:
			continue
		query.motion = motion
		var cast := space.cast_motion(query)
		if cast.size() < 2 or cast[0] < 1.0 - MOTION_EPSILON:
			return false
	return true


func _self_rid() -> RID:
	if _tank == null or not _tank.has_method(&"get_rid"):
		return RID()
	var rid: Variant = _tank.call(&"get_rid")
	return rid if rid is RID else RID()


func _configure_query(query: PhysicsShapeQueryParameters3D, transform: Transform3D, margin: float, self_rid: RID) -> void:
	query.transform = transform
	query.motion = Vector3.ZERO
	query.margin = margin
	query.collision_mask = COLLISION_MASK
	query.exclude = [self_rid]
	query.collide_with_bodies = true
	query.collide_with_areas = false
