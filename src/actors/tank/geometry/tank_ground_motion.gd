## 單次快照上的地形位移查詢；不移動 Node、不排除地形 collider。
class_name TankGroundMotion
extends RefCounted

const MARGIN := 0.002
const EPSILON := 0.00001
const MAX_HITS := 32
const MAX_ARC := 0.02
const Grounding := preload("res://src/actors/tank/geometry/tank_grounding.gd")

var tank: Node3D
var space: PhysicsDirectSpaceState3D
var shapes: Array
var locals: Array
var excluded: Array[RID]
var radius := 0.0
var queries := 0
var at_cap := false
var query_limit := 4096
var deadline_usec := 0
var contact_policy := Callable()
var hull_shapes: Array[bool] = []
var bounds: Array[AABB] = []
var shape_radii: Array[float] = []
var part_bounds: Array[Dictionary] = []
var trace := false
var capture_blocker := false
var blocker: Dictionary = {}
var hull_vertices: Array[Vector3] = []
var hull_bounds := AABB()
var full_bounds := AABB()
var support_bounds := AABB()
var has_support_points := false
var _slope_cosine_squared := 1.0
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _bounds_query := PhysicsShapeQueryParameters3D.new()
var _bounds_box := BoxShape3D.new()
var _support_cache: Dictionary = {}
var _broad_cache: Dictionary = {}
var _plane_cache: Dictionary = {}
var _rigid_cache: Dictionary = {}
var _safe_pose_cache: Dictionary = {}

func set_contact_policy(policy: Callable) -> void:
	contact_policy = policy
	_safe_pose_cache.clear()

func setup(owner_tank: Node3D, snapshot: Dictionary) -> void:
	tank = owner_tank
	_slope_cosine_squared = pow(cos(deg_to_rad(tank.ground_max_slope_degrees)), 2.0)
	space = tank.get_world_3d().direct_space_state
	shapes = snapshot.shapes
	locals = snapshot.root_local_transforms
	excluded = [snapshot.self_rid as RID]
	_shape_query.margin = MARGIN
	_shape_query.collision_mask = tank.collision_mask
	_shape_query.exclude = excluded
	_bounds_query.shape = _bounds_box
	_bounds_query.collision_mask = tank.collision_mask
	_bounds_query.exclude = excluded
	hull_shapes.resize(shapes.size())
	for part in snapshot.part_ranges:
		for index in range(int(part.start), int(part.start) + int(part.count)):
			hull_shapes[index] = String(part.anchor) == "hull"
	for index in shapes.size():
		var minimum := Vector3(INF, INF, INF)
		var maximum := -minimum
		var shape_radius := 0.0
		var vertices: PackedVector3Array = snapshot.shape_vertices[index] if snapshot.has("shape_vertices") else (shapes[index] as ConvexPolygonShape3D).points
		for point in vertices:
			var local_point: Vector3 = (locals[index] as Transform3D) * point
			minimum = minimum.min(local_point)
			maximum = maximum.max(local_point)
			shape_radius = maxf(shape_radius, local_point.length())
			if hull_shapes[index]: hull_vertices.append(local_point)
		bounds.append(AABB(minimum, maximum - minimum))
		shape_radii.append(shape_radius)
		radius = maxf(radius, shape_radius)
	for part in snapshot.part_ranges:
		var first := int(part.start)
		var box := bounds[first]
		var part_radius := 0.0
		var indices: Array[int] = []
		for index in range(first, first + int(part.count)):
			box = box.merge(bounds[index])
			part_radius = maxf(part_radius, shape_radii[index])
			indices.append(index)
		part_bounds.append({"box": box, "radius": part_radius, "indices": indices})
	if not hull_vertices.is_empty(): hull_bounds = AABB(hull_vertices[0], Vector3.ZERO)
	for point in hull_vertices: hull_bounds = hull_bounds.expand(point)
	if not bounds.is_empty(): full_bounds = bounds[0]
	for box in bounds: full_bounds = full_bounds.merge(box)
	var support_points: Array = snapshot.get("ground_points", [])
	has_support_points = support_points.size() == 4
	if has_support_points:
		support_bounds = AABB(support_points[0], Vector3.ZERO)
		for point in support_points:
			support_bounds = support_bounds.expand(point)
			full_bounds = full_bounds.expand(point)

## 保留原本每一個偏航／平移子步；僅在完整平地覆蓋與無障礙證明成立時，
## 省略結果必為恆等的重複接地解算。不適用舊接觸、坡面、拼接地板或非 Box。
func flat_path_clear(start: Transform3D, path: Array[Transform3D]) -> bool:
	if contact_policy.is_valid() or not has_support_points or path.is_empty(): return false
	if not _rigid_pose(start) or start.basis.y != Vector3.UP: return false
	var volume := start * full_bounds
	var previous := start
	for pose in path:
		if not _rigid_pose(pose) or pose.basis.y != Vector3.UP or absf(pose.origin.y - start.origin.y) > EPSILON: return false
		var yaw := absf(atan2(previous.basis.x.cross(pose.basis.x).y, previous.basis.x.dot(pose.basis.x)))
		if radius * yaw > MAX_ARC + EPSILON: return false
		volume = volume.merge(pose * full_bounds)
		previous = pose
	var hits := _broad_hits(volume.grow(MAX_ARC + MARGIN), part_bounds.size() + shapes.size())
	if at_cap or hits.is_empty(): return false
	var covered := false
	var support := start * support_bounds
	var swept_parts: Array[AABB] = []
	var local_swept_parts: Array[AABB] = []
	var inverse_start := start.affine_inverse()
	for hit in hits:
		var plane := _box_plane(hit)
		if plane.is_empty(): return false
		var floor_y := (plane.point as Vector3).y
		var is_floor := (plane.normal as Vector3) == Vector3.UP \
			and volume.position.y - floor_y >= MARGIN - EPSILON \
			and support.position.y - floor_y >= MARGIN - EPSILON \
			and support.end.y - floor_y < 0.01 - EPSILON
		if not is_floor:
			# 全車大框含有砲管兩側的空白；用各完整部位的保守框再證一次。
			# 任一部位仍可能碰到就回完整解算，不能因有地板便略過同 RID 的牆。
			if swept_parts.is_empty():
				for part in part_bounds:
					var part_volume: AABB = start * (part.box as AABB)
					var local_volume: AABB = part.box
					for pose in path:
						part_volume = part_volume.merge(pose * (part.box as AABB))
						local_volume = local_volume.merge((inverse_start * pose) * (part.box as AABB))
					swept_parts.append(part_volume.grow(MAX_ARC + MARGIN))
					local_swept_parts.append(local_volume.grow(MAX_ARC + MARGIN))
			var obstacle: AABB = (plane.transform as Transform3D) * AABB(-(plane.size as Vector3) * 0.5, plane.size)
			var local_obstacle: AABB = (inverse_start * (plane.transform as Transform3D)) * AABB(-(plane.size as Vector3) * 0.5, plane.size)
			for part_index in swept_parts.size():
				if swept_parts[part_index].grow(EPSILON).intersects(obstacle) and local_swept_parts[part_index].grow(EPSILON).intersects(local_obstacle): return false
			continue
		var inverse := (plane.transform as Transform3D).affine_inverse()
		var half: Vector3 = (plane.size as Vector3) * 0.5
		var contains := true
		# coverage 連同 2cm 偏航弧也需包含於同一塊頂面，不能只用 world AABB。
		var footprint := volume.grow(MAX_ARC)
		for x in [footprint.position.x, footprint.end.x]:
			for z in [footprint.position.z, footprint.end.z]:
				var local: Vector3 = inverse * Vector3(x, floor_y, z)
				contains = contains and absf(local.x) < half.x - EPSILON and absf(local.z) < half.z - EPSILON
		covered = covered or contains
	return covered

## 同一快照的舊接觸檢查也沿用這批幾何界限，不再走訪全部頂點。
func prediction_bounds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in part_bounds:
		var children: Array[Dictionary] = []
		for index in part.indices:
			children.append({"index": index, "aabb": bounds[index], "pivot_radius": shape_radii[index]})
		result.append({"start": part.indices[0], "count": part.indices.size(),
			"aabb": part.box, "pivot_radius": part.radius, "children": children})
	return result

## 包住端點與旋轉外弧的部位寬相位；空集合才可略過該部位所有凸形。
func _active(start: Transform3D, finish: Transform3D, angle: float = 0.0) -> Array[int]:
	var active: Array[int] = []
	for part_index in part_bounds.size():
		var part := part_bounds[part_index]
		# 固定軸最短旋轉的弧到弦最大偏離；端點 AABB union 已包住弦。
		var swept: AABB = (start * (part.box as AABB)).merge(finish * (part.box as AABB)).grow(float(part.radius) * (1.0 - cos(angle * 0.5)) + MARGIN)
		var hull_part := hull_shapes[int(part.indices[0])]
		var hits := _broad_hits(swept, part_index)
		if at_cap: return []
		if hits.is_empty(): continue
		if hull_part:
			if _above_box_hits(part.box, float(part.radius), start, finish, angle, hits): continue
		if angle <= EPSILON or (part.indices as Array).size() == 1:
			active.append_array(part.indices)
			continue
		for index in part.indices:
			var child_swept := (start * bounds[index]).merge(finish * bounds[index]).grow(shape_radii[index] * (1.0 - cos(angle * 0.5)) + MARGIN)
			var child_hits := _broad_hits(child_swept, part_bounds.size() + index)
			if at_cap: return []
			if not child_hits.is_empty(): active.append(index)
	return active

## 快照內保留「較大區域的完整命中集合」；只有查詢完全在其中時才可重用。
## 此集合是保守超集，不跨 physics frame，不快取只有第一個命中的結果。
func _broad_hits(volume: AABB, key: int) -> Array:
	if not _reserve(0): return []
	var cached: Dictionary = _broad_cache.get(key, {})
	if not cached.is_empty() and (cached.volume as AABB).encloses(volume): return cached.hits
	if not _reserve(): return []
	var expanded := volume.grow(0.25)
	_bounds_box.size = expanded.size
	_bounds_query.transform = Transform3D(Basis.IDENTITY, expanded.get_center())
	var hits := space.intersect_shape(_bounds_query, 128)
	if hits.size() >= 128:
		at_cap = true
		return []
	_broad_cache[key] = {"volume": expanded, "hits": hits}
	return hits

func _reserve(count: int = 1) -> bool:
	if queries + count > query_limit or (deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec):
		at_cap = true
		return false
	queries += count
	return true

func _support(pose: Transform3D, step_height: float = 0.0) -> Dictionary:
	# solver 僅活於同一個同步快照查詢；相同姿態／高度窗口的射線結果可共用。
	# 不跨 physics frame 保存，也不把相近姿態量化成同一筆。
	var poses: Dictionary = _support_cache.get(step_height, {})
	if poses.has(pose): return poses[pose]
	if not _reserve(4): return {}
	var result: Dictionary = tank.ground_support_at(pose, step_height)
	poses[pose] = result
	_support_cache[step_height] = poses
	return result

func _query(index: int, pose: Transform3D) -> PhysicsShapeQueryParameters3D:
	_shape_query.exclude = excluded
	_shape_query.shape = shapes[index]
	_shape_query.transform = pose * (locals[index] as Transform3D)
	_shape_query.motion = Vector3.ZERO
	return _shape_query

func clear_pose(pose: Transform3D, active: Array[int] = []) -> bool:
	# 只保存本次策略下「所有形狀皆安全」的精確姿態；不同候選策略先清空。
	# 子集合、失敗、額度中止不存，亦不跨同步 snapshot 使用。
	if active.is_empty() and _safe_pose_cache.has(pose):
		return _reserve(0) and not at_cap
	var indices := active
	if indices.is_empty():
		indices = _active(pose, pose)
	for index in indices:
		if not _clear_shape(index, pose): return false
	if active.is_empty() and not at_cap: _safe_pose_cache[pose] = true
	return not at_cap

## 旋轉 guard 只詢問 hull 是否為合法承托；其他部位保持既有完整接觸規則。
func guard_ground_contact(world_shape: Transform3D, index: int) -> Dictionary:
	var before := queries
	var root := world_shape * (locals[index] as Transform3D).affine_inverse()
	var safe := hull_shapes[index] and _clear_shape(index, root)
	return {"safe": safe, "queries": queries - before, "bad": at_cap}

func _clear_shape(index: int, pose: Transform3D) -> bool:
	if hull_shapes[index]:
		if _outside_walkable_boxes(index, pose): return true
		if at_cap: return false
	if not _reserve(): return false
	var pairs := space.collide_shape(_query(index, pose), 128)
	if pairs.size() >= 256 or pairs.size() % 2 != 0:
		at_cap = true
		return false
	if pairs.is_empty(): return true
	if _ground_pairs(index, pairs): return true
	if not contact_policy.is_valid():
		_record_blocker(&"collide_shape", index)
		return false
	# 僅固定終點分類需辨識 RID；整段 cast 始終保留全部外部物件。
	if not _reserve(): return false
	var hits := space.intersect_shape(_query(index, pose), 128)
	if hits.is_empty() or hits.size() >= 128:
		at_cap = true
		return false
	var rids: Array[RID] = []
	for hit in hits:
		if not rids.has(hit.rid): rids.append(hit.rid)
	for rid in rids:
		if not _reserve(): return false
		var classification_excluded: Array[RID] = excluded.duplicate()
		for other in rids:
			if other != rid: classification_excluded.append(other)
		var query := _query(index, pose)
		query.exclude = classification_excluded
		var target_pairs := space.collide_shape(query, 128)
		if target_pairs.size() >= 256 or target_pairs.size() % 2 != 0:
			at_cap = true
			return false
		if target_pairs.is_empty() or _ground_pairs(index, target_pairs): continue
		if not bool(contact_policy.call(index, pose * (locals[index] as Transform3D), rid, target_pairs)):
			_record_blocker(&"collide_shape", index)
			return false
	return true

## 只記錄既有查詢提供的證據；collide_shape／cast_motion 沒有 collider ID，不能猜。
func _record_blocker(source: StringName, index: int, fraction: Variant = null) -> void:
	if capture_blocker:
		blocker = {"source": source, "shape_index": index, "safe_fraction": fraction}

## 對實際 box 的分離平面證明：整個凸形 AABB 都在可行走頂面之上才可快放。
## 未能證明就回完整接觸對；不適用砲管、不略過 RID，也不更動位移 cast。
func _outside_walkable_boxes(index: int, pose: Transform3D) -> bool:
	# 查詢凸形的保守世界 AABB，避免在取得候選地面時又做一次昂貴的凸形接觸。
	var world_bounds := (pose * bounds[index]).grow(MARGIN)
	var hits := _broad_hits(world_bounds, part_bounds.size() + index)
	if at_cap: return false
	return _above_box_hits(bounds[index], shape_radii[index], pose, pose, 0.0, hits)

## 同時證明整段剛體運動在 box 頂面上方；旋轉弓高只投影到平面法線方向。
## 像水平地面的原地偏航，弧線沒有垂直位移，不必把合法地板當成待查障礙。
func _above_box_hits(box_bounds: AABB, sweep_radius: float, start: Transform3D, finish: Transform3D, angle: float, hits: Array) -> bool:
	# 原生道路多為 concave：先確認此快判適用，避免每次 fallback 前
	# 仍重算反矩陣與旋轉弧。拒絕快判不代表拒絕通行，後續仍查完整形狀。
	for hit in hits:
		if _box_plane(hit).is_empty(): return false
	if not _rigid_pose(start) or not _rigid_pose(finish) or not is_finite(angle) \
			or not is_finite(sweep_radius) or sweep_radius < 0.0 or angle < 0.0 or angle >= PI - EPSILON \
			or not box_bounds.position.is_finite() or not box_bounds.size.is_finite(): return false
	var axis := Vector3.ZERO
	if angle > EPSILON:
		if start.origin.distance_to(finish.origin) > EPSILON: return false
		var actual_angle := start.basis.get_rotation_quaternion().angle_to(finish.basis.get_rotation_quaternion())
		if absf(actual_angle - angle) > 0.0001: return false
		axis = (finish.basis * start.basis.inverse()).get_rotation_quaternion().get_axis().normalized()
		if not axis.is_finite() or axis.length_squared() < 0.99: return false
	elif not start.basis.is_equal_approx(finish.basis): return false
	# 快取命中是放大的保守超集；可在世界或車身起始座標中證明分離。
	# 兩者都包住完整凸形與旋轉弧，不用「可能碰到」的大框代替實際接觸。
	var arc_padding := sweep_radius * (1.0 - cos(angle * 0.5)) + MARGIN
	var swept := (start * box_bounds).merge(finish * box_bounds).grow(arc_padding)
	var inverse_start := start.affine_inverse()
	var local_swept := box_bounds.merge((inverse_start * finish) * box_bounds).grow(arc_padding)
	for hit in hits:
		var plane := _box_plane(hit)
		if plane.is_empty(): return false
		var obstacle_bounds := AABB(-(plane.size as Vector3) * 0.5, plane.size)
		if not swept.grow(EPSILON).intersects((plane.transform as Transform3D) * obstacle_bounds): continue
		if not local_swept.grow(EPSILON).intersects((inverse_start * (plane.transform as Transform3D)) * obstacle_bounds): continue
		var normal: Vector3 = plane.normal
		var point: Vector3 = plane.point
		var minimum := minf(_plane_minimum(box_bounds, start, normal, point), _plane_minimum(box_bounds, finish, normal, point))
		var arc_margin := sweep_radius * (1.0 - cos(angle * 0.5)) * sqrt(maxf(0.0, 1.0 - pow(clampf(normal.dot(axis), -1.0, 1.0), 2.0)))
		if minimum - arc_margin < 0.000001: return false
	return true

func _rigid_pose(pose: Transform3D) -> bool:
	if _rigid_cache.has(pose): return bool(_rigid_cache[pose])
	var rigid := pose.is_finite() and pose.basis.determinant() > 0.0 \
		and pose.basis.is_equal_approx(pose.basis.orthonormalized())
	_rigid_cache[pose] = rigid
	return rigid

func _box_plane(hit: Dictionary) -> Dictionary:
	var body_planes: Dictionary = _plane_cache.get(hit.rid, {})
	var shape_index := int(hit.shape)
	if body_planes.has(shape_index): return body_planes[shape_index]
	var plane := _read_box_plane(hit)
	body_planes[shape_index] = plane
	_plane_cache[hit.rid] = body_planes
	return plane

func _read_box_plane(hit: Dictionary) -> Dictionary:
	var body := hit.get("collider") as StaticBody3D
	if body == null: return {}
	var shape_node := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D: return {}
	var box := shape_node.shape as BoxShape3D
	if not box.size.is_finite() or box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0: return {}
	var transform := shape_node.global_transform
	if not transform.is_finite() or absf(transform.basis.determinant()) < EPSILON: return {}
	var normal := (transform.basis.inverse().transposed() * Vector3.UP).normalized()
	if not normal.is_finite() or normal.y <= 0.0 or normal.y * normal.y < _slope_cosine_squared: return {}
	return {"normal": normal, "point": transform * Vector3(0.0, box.size.y * 0.5, 0.0), "transform": transform, "size": box.size}

func _plane_minimum(box_bounds: AABB, pose: Transform3D, normal: Vector3, point: Vector3) -> float:
	var local_normal := pose.basis.transposed() * normal
	return local_normal.dot(box_bounds.get_center()) - local_normal.abs().dot(box_bounds.size * 0.5) + normal.dot(pose.origin - point)

func _ground_pairs(index: int, pairs: PackedVector3Array) -> bool:
	if not hull_shapes[index]: return false
	for pair_index in range(0, pairs.size(), 2):
		var separation: Vector3 = pairs[pair_index + 1] - pairs[pair_index]
		var distance_squared := separation.length_squared()
		if distance_squared < 0.000000000001 or distance_squared > 0.000225 \
				or separation.y <= 0.0 or separation.y * separation.y < _slope_cosine_squared * distance_squared:
			return false
	return true

## cast_motion 掃完整平移；起始接觸另外由 clear_pose／舊接觸處理，不靠 cast 忽略。
func translation_fraction(start: Transform3D, motion: Vector3) -> float:
	if motion.length_squared() < 0.0000000001: return 1.0
	var fraction := 1.0
	for index in _active(start, start.translated(motion)):
		if not _reserve(): return 0.0
		var query := _query(index, start)
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions.size() != 2:
			at_cap = true
			return 0.0
		if float(fractions[0]) < fraction:
			fraction = float(fractions[0])
			_record_blocker(&"cast_motion", index, fraction)
	return 0.0 if at_cap else fraction

func step(start: Transform3D, motion: Vector3) -> Dictionary:
	var lift: Vector3 = Vector3.UP * tank.ground_step_height
	var raised := start.translated(lift)
	if translation_fraction(start, lift) < 1.0 - EPSILON or not clear_pose(raised):
		return {"safe": false}
	var across := raised.translated(motion)
	if translation_fraction(raised, motion) < 1.0 - EPSILON or not clear_pose(across):
		return {"safe": false}
	var down: Vector3 = Vector3.DOWN * (tank.ground_step_height + tank.ground_snap_distance)
	var fraction := translation_fraction(across, down)
	if at_cap or fraction >= 1.0 - EPSILON:
		return {"safe": false}
	# 停在已驗證掃掠的安全側，保留查詢皮層；不把下一幀起點放回接觸邊界。
	var landed := across.translated(down * maxf(0.0, fraction - MARGIN / maxf(down.length(), EPSILON)))
	var support := _support(landed)
	# 從完全無重疊的 across 向下掃到安全分率，已證明整車不穿透。
	# 凸形斜切邊接觸路肩時的分離法線不等於地形法線；承托由 ray 面法線驗證。
	if not bool(support.get("supported", false)):
		return {"safe": false}
	# 舊接觸分離策略可能允許 across 還保有接觸，這時不能只靠 down cast。
	if contact_policy.is_valid() and not clear_pose(landed):
		return {"safe": false}
	return {"safe": true, "root": landed, "path": [raised, across, landed]}

## 傾斜由四點支撐決定；平移與完整姿態各自檢查，不只驗終點。
func align_pose(start: Transform3D, delta: float) -> Transform3D:
	var support := _support(start, tank.ground_step_height)
	if not bool(support.get("supported", false)): return start
	var target := start
	target.basis = Grounding.aligned_basis(start.basis, support.normal, delta, tank.ground_alignment_rate)
	var angle := start.basis.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion())
	# 四點同屬一個實際平面時，傾斜高度須承托完整 hull，而非只承托取樣點。
	var plane_normal: Vector3 = support.normal
	var hits: Array = support.get("raw_hits", [])
	var same_plane := hits.size() >= 2
	var plane_point: Vector3 = hits[0].hit.position if not hits.is_empty() else start.origin
	for hit in hits:
		if (hit.hit.normal as Vector3).dot(plane_normal) < 0.999 \
				or absf(plane_normal.dot((hit.hit.position as Vector3) - plane_point)) > 0.005:
			same_plane = false
	if same_plane and plane_normal.y > 0.0:
		var lift := 0.0
		var local_normal := target.basis.transposed() * plane_normal
		var plane_offset := plane_normal.dot(target.origin - plane_point)
		var box_minimum := local_normal.dot(hull_bounds.get_center()) - local_normal.abs().dot(hull_bounds.size * 0.5) + plane_offset
		if box_minimum < MARGIN:
			for point in hull_vertices:
				lift = maxf(lift, (MARGIN - local_normal.dot(point) - plane_offset) / plane_normal.y)
		target.origin.y += lift
	var adjusted := _support(target, tank.ground_step_height)
	if not bool(adjusted.get("supported", false)) and not same_plane:
		return start
	target.origin.y += maxf(0.0, float(adjusted.get("height_delta", 0.0)))
	# 即使不需 pitch/roll，也要先解決原生接地留下的微小向下沉入；否則
	# 下一次合法偏航可能被誤判為新的 floor 接觸。
	if angle < EPSILON and target.origin.distance_to(start.origin) < EPSILON: return start
	# 先驗完整抬升，再原地旋轉；不在每個小角度重新掃一次同一段抬升。
	var lifted := start.translated(target.origin - start.origin)
	if translation_fraction(start, lifted.origin - start.origin) < 1.0 - EPSILON or not clear_pose(lifted):
		if trace: print("ALIGN lift blocked ",lifted.origin-start.origin)
		return start
	var active := _active(lifted, target, angle)
	if at_cap: return lifted
	if active.is_empty(): return target
	# 寬相位已證明其餘部位整段無碰撞；有效部位各守 2cm 外弧上限。
	var active_radius := 0.0
	for index in active:
		active_radius = maxf(active_radius, shape_radii[index])
	var count := maxi(1, ceili(active_radius * angle / MAX_ARC))
	var previous := lifted
	for index in range(1, count + 1):
		var candidate := lifted.interpolate_with(target, float(index) / count)
		if not clear_pose(candidate, active): return previous
		previous = candidate
	return previous

func advance(start: Transform3D, motion: Vector3, delta: float, vertical_speed: float, was_grounded: bool = false, require_step: bool = false) -> Dictionary:
	var support := _support(start)
	var grounded := bool(support.get("supported", false)) and (was_grounded or float(support.get("height_delta", -INF)) >= -0.01)
	var path: Array[Transform3D] = []
	if grounded:
		vertical_speed = 0.0
	else:
		vertical_speed -= tank.ground_gravity * delta
		motion.y += vertical_speed * delta
	var fraction := 1.0 if require_step else translation_fraction(start, motion)
	var candidate := start.translated(motion)
	if require_step or fraction < 1.0 - EPSILON or not clear_pose(candidate):
		if grounded and Vector3(motion.x, 0, motion.z).length() > EPSILON:
			var stepped := step(start, Vector3(motion.x, 0, motion.z))
			if not bool(stepped.get("safe", false)): return {"safe": false}
			candidate = stepped.root
			path.assign(stepped.path)
			grounded = true
		else:
			candidate = start.translated(motion * fraction)
			var landing := _support(candidate)
			if not bool(landing.get("supported", false)) or not clear_pose(candidate): return {"safe": false}
			vertical_speed = 0.0
			grounded = true
	path.append(candidate)
	if grounded and float(_support(candidate).get("height_delta", 0.0)) < -0.01:
		var down: Vector3 = Vector3.DOWN * tank.ground_snap_distance
		var snap_fraction := translation_fraction(candidate, down)
		if snap_fraction < 1.0 - EPSILON:
			var snapped := candidate.translated(down * maxf(0.0, snap_fraction - MARGIN / maxf(down.length(), EPSILON)))
			if bool(_support(snapped).get("supported", false)) and clear_pose(snapped): candidate = snapped
	candidate = align_pose(candidate, delta)
	path.append(candidate)
	grounded = grounded and bool(_support(candidate).get("supported", false))
	return {"safe": not at_cap, "root": candidate, "vertical_speed": vertical_speed, "grounded": grounded, "path": path}
