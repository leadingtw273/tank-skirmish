## 近似支撐＋低地形接觸辨識；候選姿態絕不寫回真實剛體。
extends "res://src/actors/tank/geometry/tank_ground_motion.gd"

const TerrainClassifier := preload("res://src/actors/rigid_tank/rigid_terrain_classifier.gd")
const TerrainSegment := preload("res://src/ai/rigid_terrain_segment.gd")
const MotionSupport := preload("res://src/ai/rigid_motion_support.gd")
const FlatGround := preload("res://src/actors/rigid_tank/rigid_flat_ground_prediction.gd")
## 使用者核可的素材建模容差，不改實體碰撞與跨階物理。
const TERRAIN_HEIGHT_TOLERANCE := 0.01
var diagnostic: Dictionary = {}
var _planar_mesh_cache: Dictionary = {}
var _station_support_cache: Dictionary = {}
var _terrain := TerrainClassifier.new()
var _drive_model := preload("res://src/actors/rigid_tank/rigid_tank_prediction.gd").new()
var _motion_support_cache: Dictionary = {}
var _exact_ceiling_cache: Dictionary = {}
var _initial_drift := Vector3.ZERO
var _drift := Vector3.ZERO
var _snapshot_root := Transform3D.IDENTITY
var _snapshot_grounded := false
var _measured_ceiling: Variant = null
var _ceiling_cache: Dictionary = {}
var _hull_terrain_cache: Dictionary = {}
var _low_terrain_volume: Dictionary = {}
var _obstacle_bounds_cache: Dictionary = {}
var _floor_bound: Dictionary = {}
var _floor_bound_checked := false

func setup(owner_tank: Node3D, snapshot: Dictionary) -> void:
	super.setup(owner_tank, snapshot)
	_drive_model.configure(owner_tank)
	_obstacle_bounds_cache.clear()
	_low_terrain_volume.clear()
	_motion_support_cache.clear()
	_exact_ceiling_cache.clear()
	_planar_mesh_cache.clear()
	_station_support_cache.clear()
	_floor_bound = {}
	_floor_bound_checked = false
	_snapshot_root = snapshot.root
	_snapshot_grounded = bool(snapshot.get("grounded", false))
	var forward := -(snapshot.root as Transform3D).basis.x.normalized()
	_initial_drift = (snapshot.get("linear_velocity", Vector3.ZERO) as Vector3) - forward * float(snapshot.forward_speed)
	_initial_drift.y = 0.0
	reset_prediction()

func reset_prediction() -> void:
	_drift = _initial_drift

func try_flat_segment(start: Transform3D, states: Array[Dictionary], dt: float) -> Dictionary:
	diagnostic["calls"] = int(diagnostic.get("calls", 0)) + 1
	var original := FlatGround.try_segment(self, start, states, dt)
	if not original.is_empty() or at_cap or contact_policy.is_valid(): return original
	var support := _support(start, 0.0)
	var hits: Array = support.get("raw_hits", [])
	if not bool(support.get("supported", false)) or hits.size() != 4: return {}
	var floors := PackedFloat64Array()
	for index in 4:
		var record: Dictionary = hits[index]
		if int(record.sample_index) != index: return {}
		var body := record.hit.get("collider") as StaticBody3D
		if body == null or body is AnimatableBody3D: return {}
		if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return {}
		if (record.hit.normal as Vector3).distance_to(Vector3.UP) > 0.000001: return {}
		floors.append((record.hit.position as Vector3).y)
	diagnostic["attempt"] = int(diagnostic.get("attempt", 0)) + 1
	var result := TerrainSegment.try_segment(self, start, states, dt, 0.0, true, INF, floors)
	if not result.is_empty(): diagnostic["accepted"] = int(diagnostic.get("accepted", 0)) + 1
	return result

func prediction_drift(delta: float) -> Vector3:
	var displacement := _drift * delta
	_drift *= exp(-tank.LATERAL_RATE * delta)
	return displacement

func _terrain_ceiling(pose: Transform3D) -> float:
	if _ceiling_cache.has(pose): return float(_ceiling_cache[pose])
	if _measured_ceiling == null:
		_measured_ceiling = _support_ceiling(_snapshot_root) if _snapshot_grounded else -INF
	if not _floor_bound_checked:
		_capture_floor_bound()
	var lower_bound := _floor_bound_ceiling(pose)
	if is_finite(lower_bound):
		_ceiling_cache[pose] = lower_bound
		return lower_bound
	var candidate_ceiling := _support_ceiling(pose)
	# 跨過路肩後，近似姿態可能暫時高於短射線窗口；不得把已辨識的
	# 同一低地形重新變回牆。只沿用本幀真車確實接地時量到的基準，
	# 不沿用上一個預測高度、不跨 frame、不憑空生成地板。
	var ceiling := candidate_ceiling if is_finite(candidate_ceiling) else float(_measured_ceiling)
	if not at_cap: _ceiling_cache[pose] = ceiling
	return ceiling

# The cached box floor is a lower bound, not the measured road surface. Refine
# only when that conservative bound cannot classify a swept low-terrain body.
func refined_terrain_ceiling(pose: Transform3D) -> float:
	if _exact_ceiling_cache.has(pose): return float(_exact_ceiling_cache[pose])
	var lower := _terrain_ceiling(pose)
	if at_cap: return lower
	var measured := _support_ceiling(pose)
	if at_cap or not is_finite(measured): return lower
	var result := maxf(lower, measured)
	_ceiling_cache[pose] = result
	_exact_ceiling_cache[pose] = result
	return result

func _support_ceiling(pose: Transform3D) -> float:
	# 只讀履帶點附近已存在的支撐，不向上尋找高牆頂當跨越基準。
	var support := _support(pose, 0.0)
	if at_cap or not bool(support.get("supported", false)): return -INF
	var floor_y := INF
	for record in support.get("raw_hits", []):
		var hit: Dictionary = record.hit
		if not hit.get("collider") is StaticBody3D: continue
		if (hit.normal as Vector3).y < cos(deg_to_rad(tank.ground_max_slope_degrees)): continue
		floor_y = minf(floor_y, (hit.position as Vector3).y)
	return floor_y + tank.ground_step_height + TERRAIN_HEIGHT_TOLERANCE if is_finite(floor_y) else -INF

func _only_low_terrain(index: int, start: Transform3D, finish: Transform3D, angle: float = 0.0) -> bool:
	if not hull_shapes[index] or at_cap: return false
	# 同段車身/左右履帶共用一個更保守的大框證明，不逐凸形重算相同地形。
	# 混有任何未知/高障礙就回各部位原本的完整窄相位，不能快放。
	var key := [start, finish, angle]
	if _hull_terrain_cache.has(key): return bool(_hull_terrain_cache[key]) and _reserve(0)
	var ceiling := minf(_terrain_ceiling(start), _terrain_ceiling(finish))
	if not is_finite(ceiling): return false
	var padding := radius * (1.0 - cos(angle * 0.5)) + MARGIN
	var volume := (start * hull_bounds).merge(finish * hull_bounds).grow(padding)
	# Reuse only a complete all-low proof within this synchronous snapshot.
	if not _low_terrain_volume.is_empty() and ceiling >= float(_low_terrain_volume.ceiling) and (_low_terrain_volume.volume as AABB).encloses(volume):
		return _reserve(0)
	var proof_volume := volume.grow(0.25)
	# Query the proof volume explicitly: an older broad cache may only enclose volume.
	var hits := _broad_hits(proof_volume, part_bounds.size() + shapes.size() + 1)
	if at_cap: return false
	var all_low := true
	for hit in hits:
		if not _terrain.body_is_traversable(hit.get("collider") as Node3D, ceiling, _reserve):
			all_low = false
			if _outside_hull_sweep(hit, start, finish, padding): continue
			if not at_cap: _hull_terrain_cache[key] = false
			return false
	if not at_cap:
		_hull_terrain_cache[key] = true
		if all_low: _low_terrain_volume = {"volume": proof_volume, "ceiling": ceiling}
	return not at_cap

func _active(start: Transform3D, finish: Transform3D, angle: float = 0.0) -> Array[int]:
	var hull_index := hull_shapes.find(true)
	if hull_index < 0 or not _only_low_terrain(hull_index, start, finish, angle):
		if at_cap: return []
		return super._active(start, finish, angle)
	var result: Array[int] = []
	# 整個 hull 已被更大的框證明只會碰到低地形，無須先對每個凸形
	# 跑同一輪 broadphase 再刪掉結果；砲塔/砲管仍查完整旋轉弧大框。
	for part_index in part_bounds.size():
		var part: Dictionary = part_bounds[part_index]
		if hull_shapes[int(part.indices[0])]: continue
		var padding := float(part.radius) * (1.0 - cos(angle * 0.5)) + MARGIN
		var volume := (start * (part.box as AABB)).merge(finish * (part.box as AABB)).grow(padding)
		var hits := _broad_hits(volume, part_index)
		if at_cap: return []
		if not hits.is_empty(): result.append_array(part.indices)
	return result

func _clear_shape(index: int, pose: Transform3D) -> bool:
	if _only_low_terrain(index, pose, pose): return true
	return false if at_cap else super._clear_shape(index, pose)

func is_traversable_contact(record: Dictionary, pose: Transform3D) -> bool:
	var index := int(record.get("shape_index", -1))
	if index < 0 or index >= hull_shapes.size() or not hull_shapes[index]: return false
	var rid: RID = record.get("rid", RID())
	if not rid.is_valid(): return false
	var body := instance_from_id(PhysicsServer3D.body_get_object_instance_id(rid)) as Node3D
	return _terrain.body_is_traversable(body, _terrain_ceiling(pose), _reserve)

func advance(start: Transform3D, motion: Vector3, delta: float, vertical_speed: float, _was_grounded: bool = false, _require_step: bool = false) -> Dictionary:
	var candidate := start.translated(motion)
	var support := _motion_support(candidate, tank.ground_step_height)
	var grounded := bool(support.get("supported", false)) and not bool(support.get("too_steep", false))
	var path: Array[Transform3D] = []
	if grounded:
		# 選擇履帶支撐面的近似候選；低地形分類以外仍查完整部位。
		var rise := float(support.get("height_delta", 0.0)) + MARGIN * 2.0
		if rise > tank.ground_step_height + MARGIN * 2.0: return {"safe": false}
		candidate.origin.y += rise
		candidate.basis = Grounding.aligned_basis(candidate.basis, support.normal, delta, tank.ground_alignment_rate)
		var aligned := _motion_support(candidate, tank.ground_step_height)
		candidate.origin.y += maxf(float(aligned.get("height_delta", 0.0)), 0.0)
		vertical_speed = 0.0
	else:
		vertical_speed -= tank.ground_gravity * delta
		candidate.origin.y += vertical_speed * delta
	var raised := start
	raised.origin.y = maxf(start.origin.y, candidate.origin.y)
	# 不整體排除任何地形 RID；護欄/橋底/砲管仍能阻擋候選。
	if translation_fraction(start, raised.origin - start.origin) < 1.0 - EPSILON or not clear_pose(raised):
		return {"safe": false}
	path.append(raised)
	var across := raised
	across.origin.x = candidate.origin.x
	across.origin.z = candidate.origin.z
	if translation_fraction(raised, across.origin - raised.origin) < 1.0 - EPSILON or not clear_pose(across):
		return {"safe": false}
	path.append(across)
	# 混合高低平台不能把端點擬合平面直接當作中段底盤高度：
	# 前進與下降分開掃掠，下降遇到承托就停在實際接觸上方，不斜插台階側面。
	var descent := Vector3(0.0, candidate.origin.y - across.origin.y, 0.0)
	var fraction := translation_fraction(across, descent)
	if at_cap: return {"safe": false}
	var landed := across.translated(descent * maxf(0.0, fraction - MARGIN / maxf(descent.length(), MARGIN)))
	if not clear_pose(landed): return {"safe": false}
	# 姿態變化也逐段檢查完整形狀；安全前綴可供下一幀真實姿態重新估算。
	var angle := landed.basis.get_rotation_quaternion().angle_to(candidate.basis.get_rotation_quaternion())
	var count := maxi(1, ceili(radius * angle / MAX_ARC))
	var basis_start := landed.basis
	for index in count:
		var next := landed
		next.basis = basis_start.slerp(candidate.basis, float(index + 1) / count).orthonormalized()
		if not clear_pose(next): break
		landed = next
	if at_cap: return {"safe": false}
	path.append(landed)
	candidate = landed
	return {"safe": not at_cap, "root": candidate, "vertical_speed": vertical_speed,
		"grounded": grounded, "path": path}


## 大框的空角可能碰到鄰近建築；僅以完整 hull 掃掠包絡證明它實際分離。
func _outside_hull_sweep(hit: Dictionary, start: Transform3D, finish: Transform3D, padding: float) -> bool:
	var body := hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return false
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
	var by_shape: Dictionary = _obstacle_bounds_cache.get(hit.rid, {})
	var index := int(hit.shape)
	var obstacle: Dictionary = by_shape.get(index, {})
	if not by_shape.has(index):
		var node := body.shape_owner_get_owner(body.shape_find_owner(index)) as CollisionShape3D
		if node == null: return false
		var shape := node.shape
		var box := AABB()
		if shape is BoxShape3D:
			box = AABB(-shape.size * 0.5, shape.size)
		elif shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D:
			var points: PackedVector3Array = shape.points if shape is ConvexPolygonShape3D else shape.get_faces()
			if points.is_empty(): return false
			box = AABB(points[0], Vector3.ZERO)
			for i in points.size():
				if i % 64 == 0 and not _reserve(0): return false
				if not points[i].is_finite(): return false
				box = box.expand(points[i])
		else: return false
		var transform := node.global_transform
		if not transform.is_finite() or absf(transform.basis.determinant()) < EPSILON: return false
		obstacle = {"box": box.grow(maxf(shape.margin, MARGIN)), "transform": transform}
		by_shape[index] = obstacle
		_obstacle_bounds_cache[hit.rid] = by_shape
	var swept := hull_bounds.merge((start.affine_inverse() * finish) * hull_bounds).grow(padding + MARGIN)
	var other: AABB = obstacle.box
	var transform: Transform3D = obstacle.transform
	var offset := transform * other.get_center() - start * swept.get_center()
	var axes: Array[Vector3] = [start.basis.x, start.basis.y, start.basis.z, transform.basis.x, transform.basis.y, transform.basis.z]
	for i in 3:
		for j in 3: axes.append(start.basis[i].cross(transform.basis[j]))
	for axis in axes:
		if not _reserve(0): return false
		if axis.length_squared() < 0.00000001: continue
		axis = axis.normalized()
		var extent := 0.0
		for i in 3:
			extent += absf(axis.dot(start.basis[i])) * swept.size[i] * 0.5
			extent += absf(axis.dot(transform.basis[i])) * other.size[i] * 0.5
		if absf(offset.dot(axis)) > extent + EPSILON: return true
	# 與 mesh 的包圍盒重疊仍不等於碰到三角形；以完整掃掠包絡做一次原生查詢。
	if not _reserve(): return false
	var envelope := BoxShape3D.new()
	envelope.size = swept.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope
	query.transform = start * Transform3D(Basis.IDENTITY, swept.get_center())
	query.margin = MARGIN
	query.collision_mask = tank.collision_mask
	query.exclude = excluded
	var overlaps := space.intersect_shape(query, 128)
	if overlaps.size() >= 128:
		at_cap = true
		return false
	for found in overlaps:
		if found.rid == hit.rid and int(found.shape) == index: return false
	return _reserve(0)


## 當真實支撐 Box 完整涵蓋候選足跡，它提供不高於實際支撐的地面下界。
## 只用於更保守的低地形高度分類；不代替姿態解算的支撐射線。
func _capture_floor_bound() -> void:
	_floor_bound_checked = true
	if not _snapshot_grounded: return
	var support := _support(_snapshot_root, 0.0)
	var hits: Array = support.get("raw_hits", [])
	if at_cap or not bool(support.get("supported", false)) or hits.size() != 4: return
	for sample in hits:
		var body := sample.hit.get("collider") as StaticBody3D
		if body == null or body is AnimatableBody3D: return
		if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return
	var first: Dictionary = hits[0].hit
	var plane := _box_plane(first)
	if not plane.is_empty() and (plane.normal as Vector3) == Vector3.UP:
		_floor_bound = plane
		return
	# 路面可能遮住同一塊較低的靜態地板；只取已查到的幾何下界。
	var omit: Array[RID] = excluded.duplicate()
	var from := _snapshot_root.origin + Vector3.UP * 0.05
	var to: Vector3 = from - Vector3.UP * (tank.ground_step_height + tank.ground_snap_distance + 0.2)
	for unused in 4:
		if not _reserve(): return
		var query := PhysicsRayQueryParameters3D.create(from, to, tank.collision_mask, omit)
		var hit := space.intersect_ray(query)
		if hit.is_empty(): return
		var body := hit.get("collider") as StaticBody3D
		if body == null or body is AnimatableBody3D: return
		if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return
		plane = _box_plane(hit)
		if not plane.is_empty() and (plane.normal as Vector3) == Vector3.UP:
			_floor_bound = plane
			return
		omit.append(hit.rid)

func _floor_bound_ceiling(pose: Transform3D) -> float:
	if _floor_bound.is_empty() or not has_support_points or not _reserve(0): return -INF
	var volume := pose * support_bounds
	var floor_y: float = _floor_bound.point.y
	# 向下查詢的起點必須在這塊實際地板之上，不能把較低支撐提升。
	if volume.position.y < floor_y: return -INF
	var inverse: Transform3D = (_floor_bound.transform as Transform3D).affine_inverse()
	var half: Vector3 = (_floor_bound.size as Vector3) * 0.5
	for x in [volume.position.x, volume.end.x]:
		for z in [volume.position.z, volume.end.z]:
			var local := inverse * Vector3(x, floor_y, z)
			if absf(local.x) >= half.x - MARGIN or absf(local.z) >= half.z - MARGIN: return -INF
	return floor_y + tank.ground_step_height + TERRAIN_HEIGHT_TOLERANCE

func predictive_driving_step(speed: float, angular: float, movement: float, turn: float, delta: float) -> Dictionary:
	return _drive_model.step_cached(speed, angular, movement, turn, delta)

func _motion_support(pose: Transform3D, step_height: float) -> Dictionary:
	var full: Dictionary = _support_cache.get(step_height, {})
	if full.has(pose): return full[pose]
	if _motion_support_cache.has(pose): return _motion_support_cache[pose]
	if not _reserve(4): return {}
	var result := MotionSupport.sample(space, pose, tank._prediction_support_points, excluded,
		tank.collision_mask, step_height, tank.ground_snap_distance + tank.ground_step_height, tank.ground_max_slope_degrees)
	_motion_support_cache[pose] = result
	var floor_y: float = result.get("step_zero_floor_y", -INF)
	if is_finite(floor_y) and bool(result.get("supported", false)):
		var ceiling: float = floor_y + tank.ground_step_height + TERRAIN_HEIGHT_TOLERANCE
		_exact_ceiling_cache[pose] = ceiling
		_ceiling_cache[pose] = ceiling
	return result

func try_terrain_segment(start: Transform3D, states: Array[Dictionary], dt: float, vertical: float, grounded: bool) -> Dictionary:
	return TerrainSegment.try_segment(self, start, states, dt, vertical, grounded)
