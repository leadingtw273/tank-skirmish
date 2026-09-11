## 有限的三秒坦克駕駛預測器；只讀取當幀 snapshot，絕不寫入坦克或導航狀態。
class_name TankDrivingPredictor
extends RefCounted

const HORIZON_SECONDS := 3.0
const STEP_SECONDS := 0.1
const MAX_CANDIDATES := 12
const MAX_QUERIES := 4096
## 查詢上限是決定性主閘；時間閘只防止異常物理世界令單幀長卡。
const MAX_ELAPSED_USEC := 20000
const MAX_HITS := 32
const CONTACT_EPSILON := 0.001
const LOW_SPEED_METERS_PER_SECOND := 1.5
const FLOOR_RAY_HEIGHT := 1.0
const FLOOR_RAY_DEPTH := 6.0
const SUPPORT_NORMAL_MIN_Y := 0.7
const MAX_SWEEP_DISTANCE := 0.02

var _tank: Node3D
var _stats := _empty_stats(&"not-run")


func setup(tank: Node3D) -> void:
	_tank = tank
	reset()


func reset() -> void:
	_stats = _empty_stats(&"reset")


func get_stats() -> Dictionary:
	return _stats.duplicate(true)


## allow_adjustment=false 供既有 recovery 使用：只驗證原 command，不啟動另一套脫困候選。
func choose(movement: float, turn: float, goal: Vector3, delta: float, allow_reverse: bool = false, allow_adjustment: bool = true) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	_stats = _empty_stats(&"invalid")
	if _tank == null or not is_instance_valid(_tank) or _tank.get_world_3d() == null:
		return _result(0.0, 0.0, true, false, &"invalid", started_usec)
	var snapshot: Dictionary = _tank.call(&"predictive_driving_snapshot")
	if snapshot.is_empty() or not _valid_snapshot(snapshot):
		return _result(0.0, 0.0, true, false, &"invalid_snapshot", started_usec)
	## 凸形頂點只在本次最新 snapshot 建一次 part-local AABB，全部候選共用。
	var part_bounds := _part_local_bounds(snapshot.shapes as Array, snapshot.root_local_transforms as Array, snapshot.part_ranges as Array)
	if part_bounds.is_empty():
		return _result(0.0, 0.0, true, false, &"invalid_snapshot", started_usec)
	var snapshot_radius := _snapshot_radius(snapshot.shapes as Array, snapshot.transforms as Array, snapshot.root as Transform3D)
	var space := _tank.get_world_3d().direct_space_state
	var excluded := _supporting_floor_rids(space, snapshot, started_usec)
	if _budget_exhausted(started_usec):
		return _result(0.0, 0.0, true, false, &"budget", started_usec)
	var initial := _initial_contacts(space, snapshot, excluded, started_usec)
	if bool(initial.budget):
		return _result(0.0, 0.0, true, false, &"budget", started_usec)
	var contact := not (initial.contacts as Dictionary).is_empty()
	var nominal := _probe(space, snapshot, snapshot_radius, part_bounds, excluded, initial.contacts as Dictionary, movement, turn, started_usec)
	if bool(nominal.budget):
		return _result(0.0, 0.0, true, contact, &"budget", started_usec)
	if bool(nominal.safe) and not contact:
		return _result(movement, turn, false, false, &"clear", started_usec)
	if not allow_adjustment:
		return _result(movement, turn, false, contact, &"clear" if bool(nominal.safe) else &"blocked", started_usec) if bool(nominal.safe) else _result(0.0, 0.0, true, contact, &"blocked", started_usec)
	var candidates := _candidates(movement, turn, allow_reverse, contact)
	var best: Dictionary = {}
	for candidate in candidates:
		if _budget_exhausted(started_usec):
			return _result(0.0, 0.0, true, contact, &"budget", started_usec)
		var probe := nominal if is_equal_approx(float(candidate.movement), movement) and is_equal_approx(float(candidate.turn), turn) else _probe(
			space, snapshot, snapshot_radius, part_bounds, excluded, initial.contacts as Dictionary, float(candidate.movement), float(candidate.turn), started_usec)
		if bool(probe.budget):
			return _result(0.0, 0.0, true, contact, &"budget", started_usec)
		if not bool(probe.safe):
			continue
		## 三秒 probe 證明完整命令軌跡安全；選擇時只評分呼叫端本幀真正會執行的短段。
		var score := _score(_command_root(snapshot, float(candidate.movement), float(candidate.turn), delta), snapshot.root as Transform3D, goal, initial.contacts as Dictionary)
		if best.is_empty() or score > float(best.score):
			best = {"movement": float(candidate.movement), "turn": float(candidate.turn), "score": score}
			## 已找到安全、會往 route goal 或離開接觸面的選項，不需為同一次命令窮舉剩餘候選。
			if score > 0.0:
				return _result(float(best.movement), float(best.turn), true, contact, &"contact_escape" if contact else &"risk", started_usec)
	if best.is_empty():
		return _result(0.0, 0.0, true, contact, &"blocked", started_usec)
	var changed := not is_equal_approx(float(best.movement), movement) or not is_equal_approx(float(best.turn), turn)
	return _result(float(best.movement), float(best.turn), changed, contact, &"contact_escape" if contact else &"risk", started_usec)


func _valid_snapshot(snapshot: Dictionary) -> bool:
	return snapshot.get("root") is Transform3D and (snapshot.get("root") as Transform3D).is_finite() \
		and snapshot.get("transforms") is Array and snapshot.get("root_local_transforms") is Array and snapshot.get("shapes") is Array \
		and (snapshot.transforms as Array).size() == (snapshot.shapes as Array).size() \
		and (snapshot.root_local_transforms as Array).size() == (snapshot.shapes as Array).size() \
		and snapshot.get("part_ranges") is Array and not (snapshot.part_ranges as Array).is_empty() and not (snapshot.shapes as Array).is_empty()


func _supporting_floor_rids(space: PhysicsDirectSpaceState3D, snapshot: Dictionary, started_usec: int) -> Array[RID]:
	var excludes: Array[RID] = [snapshot.self_rid as RID]
	var root: Transform3D = snapshot.root
	var probes := [root.origin, root.origin + root.basis * Vector3.LEFT * 1.0, root.origin - root.basis * Vector3.LEFT * 1.0]
	for point in probes:
		if _budget_exhausted(started_usec):
			break
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * FLOOR_RAY_HEIGHT, point - Vector3.UP * FLOOR_RAY_DEPTH, int(snapshot.collision_mask), excludes)
		ray.collide_with_bodies = true
		ray.collide_with_areas = false
		var hit := space.intersect_ray(ray)
		_stats.query_count = int(_stats.query_count) + 1
		var normal := hit.get("normal", Vector3.ZERO) as Vector3
		var hit_position := hit.get("position", root.origin) as Vector3
		## 只排除車底向上的承載面；牆面／高處物不會因同層 static body 被一併略過。
		if hit.has("rid") and normal.y >= SUPPORT_NORMAL_MIN_Y and hit_position.y <= root.origin.y + CONTACT_EPSILON and not excludes.has(hit.rid as RID):
			excludes.append(hit.rid as RID)
	return excludes


func _initial_contacts(space: PhysicsDirectSpaceState3D, snapshot: Dictionary, excluded: Array[RID], started_usec: int) -> Dictionary:
	var contacts: Dictionary = {}
	for record in snapshot.get("contacts", []):
		if record is Dictionary and record.get("rid") is RID:
			var known_normal := record.get("normal", Vector3.ZERO) as Vector3
			contacts[(record.rid as RID).get_id()] = {"rid": record.rid as RID, "normal": known_normal.normalized() if not known_normal.is_zero_approx() else Vector3.ZERO}
	var shapes: Array = snapshot.shapes
	var transforms: Array = snapshot.transforms
	for index in shapes.size():
		if _budget_exhausted(started_usec):
			return {"contacts": contacts, "budget": true}
		for hit in _hits(space, shapes[index] as Shape3D, transforms[index] as Transform3D, excluded, &"narrow"):
			var rid: RID = hit.rid
			var normal := _contact_normal(hit, snapshot.root as Transform3D)
			contacts[rid.get_id()] = {"rid": rid, "normal": normal}
	return {"contacts": contacts, "budget": false}


func _probe(space: PhysicsDirectSpaceState3D, snapshot: Dictionary, radius: float, part_bounds: Array[Dictionary], excluded: Array[RID], old_contacts: Dictionary, movement: float, turn: float, started_usec: int) -> Dictionary:
	var root: Transform3D = snapshot.root
	var speed := float(snapshot.forward_speed)
	var angular := float(snapshot.angular_speed)
	var shapes: Array = snapshot.shapes
	var local_transforms: Array = snapshot.root_local_transforms
	if is_zero_approx(movement) and is_zero_approx(turn) and is_zero_approx(speed) and is_zero_approx(angular):
		## 形狀固定不動時，initial full-shape query 已是整段三秒的同一姿態證明。
		return {"safe": old_contacts.is_empty(), "budget": false, "final_root": root}
	for outer_step in range(ceili(HORIZON_SECONDS / STEP_SECONDS)):
		var preview: Dictionary = _tank.call(&"predictive_driving_step", speed, angular, movement, turn, STEP_SECONDS)
		if not preview.has("angular_speed"):
			return {"safe": false, "budget": false, "final_root": root}
		## 平移由 cast_motion 完整掃掠；只有旋轉外弧才需把 0.1 秒段再切細。
		var angular_sweep := radius * maxf(absf(angular), absf(float(preview.angular_speed))) * STEP_SECONDS
		var substeps := maxi(1, ceili(angular_sweep / MAX_SWEEP_DISTANCE))
		var sub_delta := STEP_SECONDS / float(substeps)
		var segment_roots: Array[Transform3D] = []
		var segment_start := root
		for unused_substep in substeps:
			if _budget_exhausted(started_usec):
				return {"safe": false, "budget": true, "final_root": root}
			var state: Dictionary = _tank.call(&"predictive_driving_step", speed, angular, movement, turn, sub_delta)
			if not state.has("forward_speed") or not state.has("angular_speed"):
				return {"safe": false, "budget": false, "final_root": root}
			speed = float(state.forward_speed)
			angular = float(state.angular_speed)
			root = root.rotated_local(Vector3.UP, angular * sub_delta)
			root.origin += root.basis * Vector3.LEFT * speed * sub_delta
			segment_roots.append(root)
		var gap_metrics := _segment_gap_metrics(segment_start, segment_roots)
		var active_parts: Array[Dictionary] = []
		for part_bound in part_bounds:
			var bound := _segment_bound(part_bound, segment_start, segment_roots, float(gap_metrics.translation), float(gap_metrics.half_sine))
			if not _hits(space, bound.shape as Shape3D, bound.transform as Transform3D, excluded, &"broad").is_empty():
				active_parts.append(part_bound)
		if active_parts.is_empty():
			continue
		var active_shapes: Array[int] = []
		for part_bound in active_parts:
			if int(part_bound.count) == 1:
				active_shapes.append(int(part_bound.start))
				continue
			for child_bound in part_bound.children as Array:
				var child_segment_bound := _segment_bound(child_bound as Dictionary, segment_start, segment_roots, float(gap_metrics.translation), float(gap_metrics.half_sine))
				if not _hits(space, child_segment_bound.shape as Shape3D, child_segment_bound.transform as Transform3D, excluded, &"broad").is_empty():
					active_shapes.append(int((child_bound as Dictionary).index))
		if active_shapes.is_empty():
			continue
		var previous_root := segment_start
		for candidate_root in segment_roots:
			if _budget_exhausted(started_usec):
				return {"safe": false, "budget": true, "final_root": root}
			for index in active_shapes:
				var previous_transform: Transform3D = previous_root * (local_transforms[index] as Transform3D)
				var transform: Transform3D = candidate_root * (local_transforms[index] as Transform3D)
				## 命中的 child 維持原本完整 sweep 加 endpoint，沒有降低形狀精度。
				if old_contacts.is_empty() and _sweep_hits(space, shapes[index] as Shape3D, previous_transform, transform, excluded):
					return {"safe": false, "budget": false, "final_root": root}
				for hit in _hits(space, shapes[index] as Shape3D, transform, excluded, &"narrow"):
					var rid: RID = hit.rid
					var old: Dictionary = old_contacts.get(rid.get_id(), {})
					if old.is_empty() or not _old_contact_separates(old, shapes[index] as Shape3D, snapshot.transforms[index] as Transform3D, transform):
						return {"safe": false, "budget": false, "final_root": root}
			previous_root = candidate_root
	# 最後一段的查詢也可能用盡額度；不能把未完成查詢回傳的空集合當成安全。
	var exhausted := _budget_exhausted(started_usec)
	return {"safe": not exhausted, "budget": exhausted, "final_root": root}


func _hits(space: PhysicsDirectSpaceState3D, shape: Shape3D, transform: Transform3D, excluded: Array[RID], kind: StringName = &"narrow") -> Array:
	if int(_stats.query_count) >= MAX_QUERIES:
		_stats.at_cap = true
		return []
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = transform
	query.margin = 0.002
	query.collision_mask = int(_tank.collision_mask)
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits := space.intersect_shape(query, MAX_HITS)
	_stats.query_count = int(_stats.query_count) + 1
	_stats["broad_queries" if kind == &"broad" else "narrow_queries"] = int(_stats.get("broad_queries" if kind == &"broad" else "narrow_queries", 0)) + 1
	if hits.size() >= MAX_HITS:
		_stats.at_cap = true
	return hits


func _sweep_hits(space: PhysicsDirectSpaceState3D, shape: Shape3D, from: Transform3D, to: Transform3D, excluded: Array[RID]) -> bool:
	if int(_stats.query_count) >= MAX_QUERIES:
		_stats.at_cap = true
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = from
	query.motion = to.origin - from.origin
	query.margin = 0.002
	query.collision_mask = int(_tank.collision_mask)
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var fractions := space.cast_motion(query)
	_stats.query_count = int(_stats.query_count) + 1
	_stats.narrow_queries = int(_stats.narrow_queries) + 1
	return fractions.size() >= 1 and float(fractions[0]) < 1.0 - CONTACT_EPSILON


func _old_contact_separates(old: Dictionary, shape: Shape3D, initial: Transform3D, candidate: Transform3D) -> bool:
	var normal: Vector3 = old.normal
	var convex := shape as ConvexPolygonShape3D
	if not normal.is_finite() or convex == null or convex.points.is_empty():
		return false
	## 不能只看 shape origin：所有凸形頂點都須往接觸法線外側，避免車尾旋入同一 body。
	for point in convex.points:
		if normal.dot(candidate * point - initial * point) <= CONTACT_EPSILON:
			return false
	return true


func _contact_normal(hit: Dictionary, root: Transform3D) -> Vector3:
	var collider := hit.get("collider") as Node3D
	if collider != null:
		var normal := root.origin - collider.global_position
		normal.y = 0.0
		if not normal.is_zero_approx():
			return normal.normalized()
	return Vector3.ZERO


func _snapshot_radius(shapes: Array, transforms: Array, root: Transform3D) -> float:
	var radius := 0.1
	for index in shapes.size():
		var convex := shapes[index] as ConvexPolygonShape3D
		if convex == null:
			return 1000.0
		for point in convex.points:
			radius = maxf(radius, root.origin.distance_to((transforms[index] as Transform3D) * point))
	return radius + 0.01


func _root_transforms(root: Transform3D, local_transforms: Array) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for local_transform in local_transforms:
		transforms.append(root * (local_transform as Transform3D))
	return transforms


func _part_local_bounds(shapes: Array, local_transforms: Array, part_ranges: Array) -> Array[Dictionary]:
	var bounds: Array[Dictionary] = []
	for part_range in part_ranges:
		var has_point := false
		var minimum := Vector3.ZERO
		var maximum := Vector3.ZERO
		var start := int(part_range.get("start", 0))
		var count := int(part_range.get("count", 0))
		var children: Array[Dictionary] = []
		for index in range(start, start + count):
			var convex := shapes[index] as ConvexPolygonShape3D
			var child_minimum := Vector3.ZERO
			var child_maximum := Vector3.ZERO
			var child_has_point := false
			for point in convex.points:
				var local_point := (local_transforms[index] as Transform3D) * point
				minimum = local_point if not has_point else minimum.min(local_point)
				maximum = local_point if not has_point else maximum.max(local_point)
				has_point = true
				child_minimum = local_point if not child_has_point else child_minimum.min(local_point)
				child_maximum = local_point if not child_has_point else child_maximum.max(local_point)
				child_has_point = true
			if child_has_point:
				var child_aabb := AABB(child_minimum, child_maximum - child_minimum)
				var child_radius := 0.0
				for endpoint in 8:
					child_radius = maxf(child_radius, child_aabb.get_endpoint(endpoint).length())
				children.append({"index": index, "aabb": child_aabb, "pivot_radius": child_radius})
		if has_point:
			var aabb := AABB(minimum, maximum - minimum)
			var pivot_radius := 0.0
			for endpoint in 8:
				pivot_radius = maxf(pivot_radius, aabb.get_endpoint(endpoint).length())
			bounds.append({"start": start, "count": count, "aabb": aabb, "pivot_radius": pivot_radius, "children": children})
	return bounds


func _segment_gap_metrics(segment_start: Transform3D, segment_roots: Array[Transform3D]) -> Dictionary:
	var previous := segment_start
	var maximum_translation := 0.0
	var maximum_half_sine := 0.0
	for pose in segment_roots:
		maximum_translation = maxf(maximum_translation, pose.origin.distance_to(previous.origin))
		var cosine := clampf(previous.basis.x.dot(pose.basis.x), -1.0, 1.0)
		maximum_half_sine = maxf(maximum_half_sine, sin(acos(cosine) * 0.5))
		previous = pose
	return {"translation": maximum_translation, "half_sine": maximum_half_sine}


func _segment_bound(part_bound: Dictionary, segment_start: Transform3D, segment_roots: Array[Transform3D], maximum_translation: float, maximum_half_sine: float) -> Dictionary:
	var swept: AABB = segment_start * (part_bound.aabb as AABB)
	for pose in segment_roots:
		swept = swept.merge(pose * (part_bound.aabb as AABB))
	var margin := maximum_translation + 2.0 * float(part_bound.pivot_radius) * maximum_half_sine + 0.002
	## union 含所有端點；此 grow 包住端點間的平移與 root yaw 弧，另加 shape query margin。
	var size := swept.size + Vector3.ONE * margin * 2.0
	var shape := BoxShape3D.new()
	shape.size = size
	return {"shape": shape, "transform": Transform3D(Basis.IDENTITY, swept.get_center())}


func _candidates(movement: float, turn: float, allow_reverse: bool, contact: bool) -> Array[Dictionary]:
	var low_forward := minf(LOW_SPEED_METERS_PER_SECOND / maxf(float(_tank.movement_speed), 0.01), 1.0)
	var low_movement := signf(movement) * low_forward
	var candidates: Array[Dictionary] = [{"movement": movement, "turn": turn}, {"movement": low_movement, "turn": turn * 0.5}, {"movement": low_movement, "turn": 0.0}]
	if contact:
		candidates.append({"movement": low_forward, "turn": 0.0})
	candidates.append_array([{"movement": low_forward, "turn": -0.4}, {"movement": low_forward, "turn": 0.4}, {"movement": 0.0, "turn": -0.4}, {"movement": 0.0, "turn": 0.4}, {"movement": 0.0, "turn": 0.0}])
	if allow_reverse:
		candidates.append({"movement": -minf(LOW_SPEED_METERS_PER_SECOND / maxf(float(_tank.reverse_movement_speed), 0.01), 1.0), "turn": 0.0})
	var unique: Array[Dictionary] = []
	for candidate in candidates:
		if unique.size() >= MAX_CANDIDATES:
			break
		if not is_finite(float(candidate.movement)) or not is_finite(float(candidate.turn)):
			continue
		var duplicate := false
		for prior in unique:
			duplicate = duplicate or (is_equal_approx(float(prior.movement), float(candidate.movement)) and is_equal_approx(float(prior.turn), float(candidate.turn)))
		if not duplicate:
			unique.append({"movement": clampf(float(candidate.movement), -1.0, 1.0), "turn": clampf(float(candidate.turn), -1.0, 1.0)})
	return unique


func _score(final_root: Transform3D, initial_root: Transform3D, goal: Vector3, contacts: Dictionary) -> float:
	var progress := Vector2(goal.x - initial_root.origin.x, goal.z - initial_root.origin.z).length() - Vector2(goal.x - final_root.origin.x, goal.z - final_root.origin.z).length()
	var separation := 0.0
	for item in contacts.values():
		var normal: Vector3 = item.normal
		separation += normal.dot(final_root.origin - initial_root.origin)
	var initial_to_goal := goal - initial_root.origin
	initial_to_goal.y = 0.0
	var final_to_goal := goal - final_root.origin
	final_to_goal.y = 0.0
	var initial_forward := initial_root.basis * Vector3.LEFT
	initial_forward.y = 0.0
	var final_forward := final_root.basis * Vector3.LEFT
	final_forward.y = 0.0
	var initial_heading := initial_forward.normalized().dot(initial_to_goal.normalized()) if not initial_forward.is_zero_approx() and not initial_to_goal.is_zero_approx() else 0.0
	var final_heading := final_forward.normalized().dot(final_to_goal.normalized()) if not final_forward.is_zero_approx() and not final_to_goal.is_zero_approx() else 0.0
	## 行程進展與接觸分離優先；朝向只取相對初姿態的改善，靜止煞車不會憑絕對朝向得分。
	return progress + separation * 4.0 + (final_heading - initial_heading) * 0.05


func _command_root(snapshot: Dictionary, movement: float, turn: float, delta: float) -> Transform3D:
	var root: Transform3D = snapshot.root
	var execution_delta := clampf(delta, 0.0, STEP_SECONDS)
	if is_zero_approx(execution_delta):
		return root
	var state: Dictionary = _tank.call(&"predictive_driving_step", float(snapshot.forward_speed), float(snapshot.angular_speed), movement, turn, execution_delta)
	if not state.has("forward_speed") or not state.has("angular_speed"):
		return root
	root = root.rotated_local(Vector3.UP, float(state.angular_speed) * execution_delta)
	root.origin += root.basis * Vector3.LEFT * float(state.forward_speed) * execution_delta
	return root


func _budget_exhausted(started_usec: int) -> bool:
	if int(_stats.query_count) >= MAX_QUERIES or bool(_stats.at_cap):
		return true
	return started_usec > 0 and Time.get_ticks_usec() - started_usec >= MAX_ELAPSED_USEC


func _result(movement: float, turn: float, intervened: bool, contact: bool, reason: StringName, started_usec: int) -> Dictionary:
	_stats.reason = reason
	_stats.elapsed_usec = Time.get_ticks_usec() - started_usec
	return {"movement": movement, "turn": turn, "intervened": intervened, "contact": contact, "reason": reason, "stats": get_stats()}


func _empty_stats(reason: StringName) -> Dictionary:
	return {"query_count": 0, "broad_queries": 0, "narrow_queries": 0, "elapsed_usec": 0, "reason": reason, "at_cap": false, "horizon_seconds": HORIZON_SECONDS, "step_seconds": STEP_SECONDS}
