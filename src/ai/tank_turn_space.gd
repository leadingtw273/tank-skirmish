## Conservative, incremental turn-space hints for the main-world Tank2 route.
## This object never changes vehicle physics and treats every incomplete query as unsafe.
extends RefCounted

const MIN_CORNER_DEGREES := 20.0
const ARC_SAMPLE := 4.0
const CORNER_SAMPLE := 8.0
const NMS_METRES := 6.0
const FLOOR_SPREAD := 0.015
const NAV_EPSILON := 0.5
const MAX_HITS := 64
const YAW_STEP := 15.0
const MAX_EVENTS := 64

var _tank: Node3D
var _world: Node3D
var _roads: Node
var _ground: Node
var _path := PackedVector3Array()
var _raw_path := PackedVector3Array()
var _arc: Array[float] = []
var _corners: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _map := RID()
var _radius := 0.0
var _floor_offset := NAN
var _snapshot: Dictionary = {}
var _state: StringName = &"idle"
var _disabled := false
var _reason: StringName = &""
var _cursor := 0
var _candidate_corner: Dictionary = {}
var _candidate_points: Array[Vector3] = []
var _candidate_cursor := 0
var _candidate_accepted: Array[Dictionary] = []
var _candidate_original_pending := false
var _prepare_cursor := 0
var _last_passed_arc := -INF
var _events: Array[Dictionary] = []

func setup(tank: Node3D) -> void:
	_tank = tank
	reset(false, &"setup")

func reset(disable: bool = false, reason: StringName = &"") -> void:
	_path = PackedVector3Array(); _raw_path = PackedVector3Array()
	_arc.clear(); _corners.clear(); _queue.clear()
	_map = RID(); _radius = 0.0; _floor_offset = NAN; _snapshot = {}
	_cursor = 0; _prepare_cursor = 0; _candidate_corner = {}; _candidate_points.clear(); _candidate_cursor = 0; _candidate_accepted.clear(); _candidate_original_pending = false; _last_passed_arc = -INF
	_disabled = disable
	_reason = reason
	_state = &"recovery" if disable else &"idle"
	_event(&"reset", {"disable": disable, "reason": reason})

## Capture exactly the first native route for this goal.  A refresh must start a new helper.
func capture(path: PackedVector3Array, map: RID) -> void:
	if _disabled or not _raw_path.is_empty() or path.size() < 3:
		return
	_raw_path = path.duplicate()
	_map = map
	_state = &"captured"
	_event(&"captured", {"points": _raw_path.size()})

func has_plan() -> bool:
	return not _raw_path.is_empty()

func is_disabled() -> bool:
	return _disabled

## Caller supplies its remaining predictor budget.  We process at most one corner here.
func step(deadline_usec: int, max_queries: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var budget := {"count": 0, "max": maxi(0, max_queries), "deadline": deadline_usec}
	if _disabled or _raw_path.is_empty() or max_queries <= 0 or _expired(budget):
		return _step_result(started, budget)
	if _state == &"captured":
		if not _initialise(budget): return _step_result(started, budget)
		if _disabled: return _step_result(started, budget)
		var found := _find_corners(budget)
		if _expired(budget): return _step_result(started, budget)
		_corners = _nms(found, budget)
		if _expired(budget): return _step_result(started, budget)
		_state = &"evaluating"
		_event(&"corners", {"count": _corners.size()})
		if _expired(budget): return _step_result(started, budget)
	if _state == &"evaluating":
		if _candidate_corner.is_empty() and _cursor >= _corners.size():
			_state = &"ready"; _event(&"ready", {"guides": _queue.size()})
			return _step_result(started, budget)
		if _candidate_corner.is_empty():
			var corner: Dictionary = _corners[_cursor]
			_cursor += 1
			var rise_state := _corner_has_high_rise(corner, budget)
			if rise_state < 0:
				_cursor -= 1
				return _step_result(started, budget)
			if rise_state > 0:
				_event(&"skip_high_rise", {"arc": corner.arc})
			else:
				_candidate_corner = corner
				_candidate_points = _candidate_points_for(corner)
				_candidate_cursor = 0; _candidate_accepted.clear(); _candidate_original_pending = true
		if not _candidate_corner.is_empty() and _candidate_original_pending and not _expired(budget):
			var original_floor := _floor_at(_candidate_corner.point, budget)
			_candidate_original_pending = false
			var original_flat := _flat_support(_candidate_corner.point, original_floor, budget)
			if bool(budget.get("exhausted", false)):
				_candidate_original_pending = true
			elif bool(original_flat.get("flat", false)):
				_candidate_points.clear(); _candidate_cursor = 0
		elif not _candidate_corner.is_empty() and _candidate_cursor < _candidate_points.size() and not _expired(budget):
			var result := _evaluate_candidate(_candidate_points[_candidate_cursor], _candidate_corner, budget)
			if not bool(budget.get("exhausted", false)): _candidate_cursor += 1
			if not result.is_empty() and not bool(budget.get("exhausted", false)): _candidate_accepted.append(result)
		if not _candidate_corner.is_empty() and not _candidate_original_pending and _candidate_cursor >= _candidate_points.size():
			_finish_corner_candidates()
	return _step_result(started, budget)

## Do not expose later corners while an earlier original-route corner remains.
func take_next(position: Vector3) -> Dictionary:
	if _state not in [&"evaluating", &"ready"] or _queue.is_empty(): return {}
	var projected := _project_arc(_xz(position))
	while not _queue.is_empty() and float(_queue[0].arc) <= maxf(_last_passed_arc, projected - 0.8):
		_event(&"skipped_passed", {"arc": _queue[0].arc}); _queue.pop_front()
	if _queue.is_empty(): return {}
	var next: Dictionary = _queue.pop_front()
	_last_passed_arc = maxf(_last_passed_arc, float(next.arc) - 0.001)
	next["ready_frame"] = Engine.get_physics_frames()
	return next

func note_passed(hint: Dictionary) -> void:
	if hint.has("arc"):
		_last_passed_arc = maxf(_last_passed_arc, float(hint.arc))
	_event(&"passed", {"arc": hint.get("arc", -1.0)})

func get_trace() -> Dictionary:
	return {"state": _state, "disabled": _disabled, "reason": _reason, "captured": _raw_path.size(),
		"corners": _corners.size(), "remaining": _queue.size(), "events": _events.duplicate(true)}

func _initialise(budget: Dictionary) -> bool:
	if _tank == null or not is_instance_valid(_tank) or not _map.is_valid():
		_disable(&"unknown_world"); return false
	if not _prepare_path(budget): return false
	var node: Node = _tank
	while node != null and _world == null:
		_world = node.get_node_or_null("World") as Node3D
		node = node.get_parent()
	if _world == null:
		_disable(&"world_missing"); return false
	_roads = _world.get_node_or_null("Roads")
	_ground = _world.get_node_or_null("Ground")
	if _roads == null or _ground == null:
		_disable(&"world_geometry_missing"); return false
	if not _claim_query(budget): return false
	var region: RID = NavigationServer3D.map_get_closest_point_owner(_map, _raw_path[0])
	var owner_id := NavigationServer3D.region_get_owner_id(region) if region.is_valid() else 0
	var region_node := instance_from_id(owner_id) as NavigationRegion3D
	if region_node != null and region_node.navigation_mesh != null:
		_radius = region_node.navigation_mesh.agent_radius
	if _radius <= 0.0:
		_disable(&"baked_radius_unknown"); return false
	if not _tank.has_method(&"predictive_driving_snapshot"):
		_disable(&"snapshot_missing"); return false
	_snapshot = _tank.call(&"predictive_driving_snapshot") as Dictionary
	if not _valid_snapshot(_snapshot):
		_disable(&"snapshot_not_30_shapes"); return false
	if not bool(_snapshot.get("grounded", false)):
		_event(&"waiting_ground", {}); return false
	var floor := _floor_at(_tank.global_position, budget)
	## Spawn settling can lag capture by several physics frames.  This is unknown,
	## not a permanent negative capability: keep the source route and retry later.
	if not bool(floor.get("known", false)) or not bool(_flat_support(_tank.global_position, floor, budget).get("flat", false)):
		_event(&"waiting_ground", {}); return false
	_floor_offset = _tank.global_position.y - float(floor.height)
	if not is_finite(_floor_offset): _disable(&"floor_offset_unknown"); return false
	return true

func _candidate_points_for(corner: Dictionary) -> Array[Vector3]:
	var original: Vector3 = corner.point
	var raw: Array[Vector3] = []
	var incoming: Vector3 = corner.incoming
	var outgoing: Vector3 = corner.outgoing
	for direction: Vector3 in [_perp(incoming), -_perp(incoming), _perp(outgoing), -_perp(outgoing), (_perp(incoming)+_perp(outgoing)).normalized(), (-_perp(incoming)-_perp(outgoing)).normalized()]:
		if direction.is_zero_approx(): continue
		var base := original + direction * _radius
		raw.append(base); raw.append(base - incoming * _radius); raw.append(base + incoming * _radius)
	return raw

func _finish_corner_candidates() -> void:
	if _candidate_accepted.is_empty():
		_candidate_corner = {}; _candidate_points.clear(); _candidate_original_pending = false; return
	_candidate_accepted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var qa := _height_bucket(float(a.height_delta))
		var qb := _height_bucket(float(b.height_delta))
		return qa < qb or (qa == qb and float(a.score) < float(b.score)))
	var selected: Dictionary = _candidate_accepted[0]
	_queue.append(selected); _queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.arc) < float(b.arc))
	_event(&"ready_guide", {"arc": selected.arc})
	_candidate_corner = {}; _candidate_points.clear(); _candidate_accepted.clear(); _candidate_cursor = 0; _candidate_original_pending = false

func _evaluate_candidate(point: Vector3, corner: Dictionary, budget: Dictionary) -> Dictionary:
	if not _claim_query(budget): return {}
	var closest := NavigationServer3D.map_get_closest_point(_map, point)
	if _xz(closest - point).length() > NAV_EPSILON: return {}
	var floor := _floor_at(point, budget)
	if not bool(floor.get("known", false)) or not bool(_flat_support(point, floor, budget).get("flat", false)): return {}
	var upstream := _point_at(maxf(0.0, float(corner.arc) - CORNER_SAMPLE), budget)
	var downstream := _point_at(minf(_arc.back(), float(corner.arc) + CORNER_SAMPLE), budget)
	if _expired(budget) or not _claim_query(budget): return {}
	var first := NavigationServer3D.map_get_path(_map, upstream, point, true, 1)
	if _expired(budget) or not _claim_query(budget): return {}
	var second := NavigationServer3D.map_get_path(_map, point, downstream, true, 1)
	if not _path_reaches(first, point) or not _path_reaches(second, downstream): return {}
	var upstream_floor := _floor_at(upstream, budget)
	if bool(budget.get("exhausted", false)): return {}
	if not bool(upstream_floor.get("known", false)): return {}
	if not _yaw_clear(point, float(floor.height), corner.incoming, corner.outgoing, budget): return {}
	return {"point": Vector3(point.x, float(floor.height) + _floor_offset, point.z), "arc": float(corner.arc),
		"score": _path_length(first, budget) + _path_length(second, budget), "height_delta": float(floor.height) - float(upstream_floor.height)}

func _floor_at(point: Vector3, budget: Dictionary) -> Dictionary:
	if not _claim_query(budget): return {"known": false}
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP * 2.0)
	query.collision_mask = int(_snapshot.get("collision_mask", _tank.collision_mask)); query.exclude = [_tank.get_rid()]
	var hit := _tank.get_world_3d().direct_space_state.intersect_ray(query)
	return {"known": not hit.is_empty() and _is_support(hit) and (hit.normal as Vector3).y >= 0.999, "height": (hit.position as Vector3).y if not hit.is_empty() else 0.0}

func _flat_support(point: Vector3, floor: Dictionary, budget: Dictionary) -> Dictionary:
	if not bool(floor.get("known", false)): return {"flat": false}
	var heights: Array[float] = []
	for sample: Vector3 in _support_samples(point):
		var hit_floor := _floor_at(sample, budget)
		if not bool(hit_floor.get("known", false)) or _expired(budget): return {"flat": false}
		# A second ray is deliberately avoided: floor support classification includes normal below.
		heights.append(float(hit_floor.height))
	return {"flat": not heights.is_empty() and (heights.max() - heights.min()) <= FLOOR_SPREAD}

func _yaw_clear(point: Vector3, floor: float, incoming: Vector3, outgoing: Vector3, budget: Dictionary) -> bool:
	var start := atan2(incoming.z, -incoming.x)
	var delta := wrapf(atan2(outgoing.z, -outgoing.x) - start, -PI, PI)
	var steps := maxi(1, ceili(absf(rad_to_deg(delta)) / YAW_STEP))
	var merged: AABB; var set := false; var radius := 0.0
	for index: int in range(steps + 1):
		if _expired(budget): return false
		var box_data := _merged_aabb(Transform3D(Basis(Vector3.UP, start + delta * float(index) / float(steps)), Vector3(point.x, floor + _floor_offset, point.z)), budget)
		if box_data.is_empty(): return false
		radius = maxf(radius, float(box_data.radius))
		merged = merged.merge(box_data.aabb) if set else box_data.aabb; set = true
	if not set or not _claim_query(budget): return false
	merged = merged.grow(radius * (1.0 - cos(deg_to_rad(YAW_STEP * 0.5))) + 0.02)
	var box := BoxShape3D.new(); box.size = merged.size
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = box; query.transform = Transform3D(Basis.IDENTITY, merged.get_center())
	query.collision_mask = int(_snapshot.get("collision_mask", _tank.collision_mask)); query.exclude = [_tank.get_rid()]
	var hits: Array = _tank.get_world_3d().direct_space_state.intersect_shape(query, MAX_HITS)
	if hits.size() >= MAX_HITS: return false
	for hit: Dictionary in hits:
		if not _is_support(hit): return false
	return true

func _merged_aabb(root: Transform3D, budget: Dictionary) -> Dictionary:
	var shapes: Array = _snapshot.shapes as Array; var locals: Array = _snapshot.root_local_transforms as Array
	if shapes.size() != 30 or locals.size() != 30: return {}
	var merged: AABB; var set := false; var radius := 0.0
	for index: int in 30:
		if _expired(budget): return {}
		var shape := shapes[index] as Shape3D; var local := locals[index] as Transform3D
		if shape == null or not local.is_finite(): return {}
		var mesh := shape.get_debug_mesh()
		if mesh == null: return {}
		var part := _transform_aabb(mesh.get_aabb(), root * local)
		for corner: Vector3 in _corners_of(part): radius = maxf(radius, _xz(corner - root.origin).length())
		merged = merged.merge(part) if set else part; set = true
	return {"aabb": merged, "radius": radius} if set else {}

func _corner_has_high_rise(corner: Dictionary, budget: Dictionary) -> int:
	for index: int in range(1, _path.size()):
		if _expired(budget): return -1
		var end := _rise_end(index, budget)
		if bool(budget.get("exhausted", false)): return -1
		if end >= 0 and _arc[end] >= float(corner.arc) - 4.0 and _arc[index - 1] <= float(corner.arc) + 4.0: return 1
	return 0

func _rise_end(index: int, budget: Dictionary = {}) -> int:
	if index < 1 or index >= _path.size() or _path[index].y <= _path[index - 1].y: return -1
	if _path[index].y - _path[index - 1].y > 0.3: return index
	var length := 0.0
	for end: int in range(index, _path.size()):
		if _expired(budget): return -1
		length += _xz(_path[end] - _path[end - 1]).length()
		if length > 3.0 or _path[end].y < _path[end - 1].y - 0.01: break
		if _path[end].y - _path[index - 1].y > 0.3: return end
	return -1

func _find_corners(budget: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(1, _path.size() - 1):
		if _expired(budget): return result
		var here := _arc[index]
		if here < ARC_SAMPLE or _arc.back() - here < ARC_SAMPLE: continue
		var before := _point_at(here - ARC_SAMPLE, budget); var after := _point_at(here + ARC_SAMPLE, budget)
		if _expired(budget): return result
		var incoming := _xz(_path[index] - before).normalized(); var outgoing := _xz(after - _path[index]).normalized()
		if incoming.is_zero_approx() or outgoing.is_zero_approx(): continue
		var angle := rad_to_deg(acos(clampf(incoming.dot(outgoing), -1.0, 1.0)))
		if angle >= MIN_CORNER_DEGREES: result.append({"arc": here, "point": _path[index], "incoming": incoming, "outgoing": outgoing, "angle": angle})
	return result

func _nms(raw: Array[Dictionary], budget: Dictionary = {}) -> Array[Dictionary]:
	if _expired(budget): return []
	var sorted := raw.duplicate(); sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.angle) > float(b.angle))
	var kept: Array[Dictionary] = []
	for candidate: Dictionary in sorted:
		if _expired(budget): return []
		var suppress := false
		for chosen: Dictionary in kept:
			if _expired(budget): return []
			if absf(float(candidate.arc) - float(chosen.arc)) < NMS_METRES: suppress = true; break
		if not suppress: kept.append(candidate)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.arc) < float(b.arc))
	return kept

func _support_samples(point: Vector3) -> Array[Vector3]:
	var samples: Array[Vector3] = [point]
	for index: int in 8: samples.append(point + Vector3(cos(TAU * index / 8.0), 0.0, sin(TAU * index / 8.0)) * _radius)
	return samples

func _is_support(hit: Dictionary) -> bool:
	var collider := hit.get("collider") as Node
	if not collider is StaticBody3D: return false
	return _roads.is_ancestor_of(collider) or collider == _ground or _ground.is_ancestor_of(collider)

func _valid_snapshot(snapshot: Dictionary) -> bool:
	return snapshot.get("root") is Transform3D and snapshot.get("shapes") is Array and snapshot.get("root_local_transforms") is Array and (snapshot.shapes as Array).size() == 30 and (snapshot.root_local_transforms as Array).size() == 30

func _claim_query(budget: Dictionary) -> bool:
	if _expired(budget) or int(budget.count) >= int(budget.max): budget["exhausted"] = true; return false
	budget.count = int(budget.count) + 1; return true

func _expired(budget: Dictionary) -> bool:
	var expired := int(budget.get("deadline", 0)) > 0 and Time.get_ticks_usec() >= int(budget.deadline)
	if expired: budget["exhausted"] = true
	return expired

func _height_bucket(height_delta: float) -> int:
	return int(floor(absf(height_delta) / FLOOR_SPREAD + 0.5))

func _step_result(started: int, budget: Dictionary) -> Dictionary:
	return {"elapsed_usec": Time.get_ticks_usec() - started, "query_count": int(budget.count), "state": _state}

func _dedupe(source: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point: Vector3 in source:
		if result.is_empty() or not point.is_equal_approx(result[-1]): result.append(point)
	return result

func _arc_lengths(points: PackedVector3Array) -> Array[float]:
	var result: Array[float] = [0.0]
	for index: int in range(1, points.size()): result.append(result.back() + _xz(points[index] - points[index - 1]).length())
	return result

func _prepare_path(budget: Dictionary) -> bool:
	if _prepare_cursor == 0 and _path.is_empty(): _arc = [0.0]
	while _prepare_cursor < _raw_path.size():
		if _expired(budget): return false
		var point := _raw_path[_prepare_cursor]
		_prepare_cursor += 1
		if _path.is_empty() or not point.is_equal_approx(_path[-1]):
			if not _path.is_empty(): _arc.append(_arc.back() + _xz(point - _path[-1]).length())
			_path.append(point)
	if _path.size() < 3:
		_disable(&"path_too_short"); return false
	return true

func _point_at(distance: float, budget: Dictionary) -> Vector3:
	var target := clampf(distance, 0.0, _arc.back())
	for index: int in range(1, _path.size()):
		if _expired(budget): return Vector3.INF
		if _arc[index] >= target:
			var span := _arc[index] - _arc[index - 1]
			return _path[index - 1].lerp(_path[index], 0.0 if is_zero_approx(span) else (target - _arc[index - 1]) / span)
	return _path[-1]

func _project_arc(position: Vector3) -> float:
	var best := 0.0; var best_distance := INF
	for index: int in range(1, _path.size()):
		var a := _xz(_path[index - 1]); var b := _xz(_path[index]); var delta := b - a
		var ratio := clampf((position - a).dot(delta) / maxf(delta.length_squared(), 0.000001), 0.0, 1.0)
		var projected := a.lerp(b, ratio); var distance := projected.distance_to(position)
		if distance < best_distance: best_distance = distance; best = _arc[index - 1] + (_arc[index] - _arc[index - 1]) * ratio
	return best

func _path_height_at(distance: float) -> float: return _point_at(distance, {}).y
func _path_reaches(path: PackedVector3Array, target: Vector3) -> bool: return path.size() >= 2 and _xz(path[-1] - target).length() <= NAV_EPSILON
func _path_length(path: PackedVector3Array, budget: Dictionary = {}) -> float:
	var length := 0.0
	for index: int in range(1, path.size()):
		if _expired(budget): return INF
		length += path[index].distance_to(path[index - 1])
	return length
func _perp(value: Vector3) -> Vector3: return Vector3(-value.z, 0.0, value.x).normalized()
func _xz(value: Vector3) -> Vector3: return Vector3(value.x, 0.0, value.z)
func _corners_of(box: AABB) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for x: float in [0.0, 1.0]:
		for y: float in [0.0, 1.0]:
			for z: float in [0.0, 1.0]:
				result.append(box.position + box.size * Vector3(x, y, z))
	return result
func _transform_aabb(box: AABB, transform: Transform3D) -> AABB:
	var points := _corners_of(box); var result := AABB(transform * points[0], Vector3.ZERO)
	for index: int in range(1, points.size()): result = result.expand(transform * points[index])
	return result
func _disable(reason: StringName) -> void:
	_disabled = true; _reason = reason; _state = &"recovery"; _queue.clear(); _event(&"disabled", {"reason": reason})
func _event(kind: StringName, data: Dictionary = {}) -> void:
	_events.append({"frame": Engine.get_physics_frames(), "kind": kind, "data": data.duplicate(true)})
	if _events.size() > MAX_EVENTS: _events.pop_front()
