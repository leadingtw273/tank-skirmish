## 以離線凸形部位做旋轉掃掠的純物理查詢支援；不會寫入任何場景節點。
class_name TankMotionGuard
extends RefCounted

const MAX_OUTER_ARC := 0.02
const QUERY_MARGIN := 0.002
const EPSILON := 0.000001
const MAX_CONTACT_POINTS := 256

var _space: PhysicsDirectSpaceState3D
var _self_rid: RID
var _collision_mask := 1
var _scene_node_count := 1


func configure(
	space: PhysicsDirectSpaceState3D,
	self_rid: RID,
	collision_mask: int,
	scene_node_count: int,
) -> void:
	_space = space
	_self_rid = self_rid
	_collision_mask = collision_mask
	_scene_node_count = maxi(1, scene_node_count)


## shapes 每項包含 shape、start_transform、radius；transforms_at_fraction 回傳同序候選 Transform3D。
func attempt(angle_delta: float, shapes: Array[Dictionary], transforms_at_fraction: Callable) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if _space == null or shapes.is_empty() or not transforms_at_fraction.is_valid():
		return _result(0.0, angle_delta, false, "invalid-snapshot", 0, 0, shapes.size(), started_usec)
	var max_radius := 0.0
	for item in shapes:
		if not item.has("shape") or not item.has("start_transform") or not item.has("radius") \
				or not (item.shape is Shape3D) or not (item.start_transform is Transform3D):
			return _result(0.0, angle_delta, false, "invalid-shape-input", 0, 0, shapes.size(), started_usec)
		max_radius = maxf(max_radius, float(item.radius))
	var substeps := maxi(1, ceili(max_radius * absf(angle_delta) / MAX_OUTER_ARC))
	var query_count := 0
	var current_fraction := 0.0
	var initial_transforms: Array = []
	for item in shapes:
		initial_transforms.append(item.start_transform)
	var snapshots := _snapshot_all(shapes, initial_transforms)
	query_count += int(snapshots.query_count)
	if snapshots.bad:
		return _result(0.0, angle_delta, false, "initial-" + String(snapshots.reason), query_count, substeps, shapes.size(), started_usec)
	for step in range(1, substeps + 1):
		var candidate_fraction := float(step) / float(substeps)
		var candidate_transforms: Array = transforms_at_fraction.call(candidate_fraction)
		if candidate_transforms.size() != shapes.size() or not _all_finite(candidate_transforms):
			return _result(current_fraction, angle_delta, false, "invalid-candidate-snapshot", query_count, substeps, shapes.size(), started_usec)
		for shape_index in shapes.size():
			var candidate_overlap := _overlaps(shapes[shape_index].shape, candidate_transforms[shape_index])
			query_count += 1
			if candidate_overlap.bad:
				return _result(current_fraction, angle_delta, false, String(candidate_overlap.reason), query_count, substeps, shapes.size(), started_usec)
			var known: Dictionary = snapshots.items[shape_index].by_rid
			for rid in candidate_overlap.rids:
				if not known.has(rid.get_id()):
					return _result(current_fraction, angle_delta, false, "new-collider:%s" % rid.get_id(), query_count, substeps, shapes.size(), started_usec)
			for rid_id in known:
				var old: Dictionary = known[rid_id]
				var pairs := _pairs_for_rid(shapes[shape_index].shape, candidate_transforms[shape_index], old.rid, candidate_overlap.rids)
				query_count += 1
				if pairs.bad:
					return _result(current_fraction, angle_delta, false, String(pairs.reason), query_count, substeps, shapes.size(), started_usec)
				if not _old_contact_is_safe(old, pairs, candidate_transforms[shape_index]):
					return _result(current_fraction, angle_delta, false, "old-contact-inward:%s" % rid_id, query_count, substeps, shapes.size(), started_usec)
		var refreshed_snapshots := _snapshot_all(shapes, candidate_transforms)
		query_count += int(refreshed_snapshots.query_count)
		if refreshed_snapshots.bad:
			return _result(current_fraction, angle_delta, false, "accepted-" + String(refreshed_snapshots.reason), query_count, substeps, shapes.size(), started_usec)
		current_fraction = candidate_fraction
		snapshots = refreshed_snapshots
	return _result(1.0, angle_delta, true, "clear", query_count, substeps, shapes.size(), started_usec)


func _snapshot_all(shapes: Array[Dictionary], transforms: Array) -> Dictionary:
	if transforms.size() != shapes.size() or not _all_finite(transforms):
		return {"bad": true, "reason": "invalid-candidate-snapshot", "query_count": 0}
	var items: Array[Dictionary] = []
	var query_count := 0
	for index in shapes.size():
		var snapshot := _snapshot_contacts(shapes[index].shape, transforms[index])
		query_count += int(snapshot.query_count)
		if snapshot.bad:
			return {"bad": true, "reason": snapshot.reason, "query_count": query_count}
		items.append(snapshot)
	return {"bad": false, "items": items, "query_count": query_count}


func _query(shape: Shape3D, transform: Transform3D, excluded: Array[RID]) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = transform
	query.margin = QUERY_MARGIN
	query.collision_mask = _collision_mask
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return query


func _overlaps(shape: Shape3D, transform: Transform3D) -> Dictionary:
	var hits := _space.intersect_shape(_query(shape, transform, [_self_rid]), _scene_node_count)
	if hits.size() >= _scene_node_count:
		return {"bad": true, "reason": "overlap-results-at-cap:%d" % _scene_node_count, "rids": []}
	var rids: Array[RID] = []
	for hit in hits:
		var rid: RID = hit.rid
		if not rids.has(rid):
			rids.append(rid)
	return {"bad": false, "rids": rids}


func _snapshot_contacts(shape: Shape3D, transform: Transform3D) -> Dictionary:
	var overlap := _overlaps(shape, transform)
	if overlap.bad:
		return {"bad": true, "reason": overlap.reason, "query_count": 1}
	var by_rid := {}
	var query_count := 1
	for rid in overlap.rids:
		var pairs := _pairs_for_rid(shape, transform, rid, overlap.rids)
		query_count += 1
		if pairs.bad:
			return {"bad": true, "reason": pairs.reason, "query_count": query_count}
		by_rid[rid.get_id()] = pairs
	return {"bad": false, "by_rid": by_rid, "query_count": query_count}


func _pairs_for_rid(shape: Shape3D, transform: Transform3D, only_rid: RID, all_rids: Array[RID]) -> Dictionary:
	var excluded: Array[RID] = [_self_rid]
	for rid in all_rids:
		if rid != only_rid:
			excluded.append(rid)
	var raw := _space.collide_shape(_query(shape, transform, excluded), MAX_CONTACT_POINTS)
	if raw.size() % 2 != 0:
		return {"bad": true, "reason": "odd-contact-points"}
	if raw.size() >= MAX_CONTACT_POINTS * 2:
		return {"bad": true, "reason": "contact-results-at-cap"}
	var entries: Array[Dictionary] = []
	var depth := 0.0
	for index in range(0, raw.size(), 2):
		var point0: Vector3 = raw[index]
		var point1: Vector3 = raw[index + 1]
		var normal_vector := point1 - point0
		if normal_vector.length_squared() <= EPSILON * EPSILON:
			return {"bad": true, "reason": "zero-normal-contact"}
		depth = maxf(depth, normal_vector.length())
		entries.append({
			"world_point": point0,
			"local_point": transform.affine_inverse() * point0,
			"normal": normal_vector.normalized(),
		})
	return {"bad": false, "rid": only_rid, "entries": entries, "depth": depth}


func _old_contact_is_safe(old: Dictionary, candidate: Dictionary, candidate_transform: Transform3D) -> bool:
	var minimum_dot := INF
	for entry in old.entries:
		var projected_displacement: float = entry.normal.dot((candidate_transform * entry.local_point) - entry.world_point)
		minimum_dot = minf(minimum_dot, projected_displacement)
		if projected_displacement < -EPSILON:
			return false
	return candidate.entries.is_empty() or candidate.depth <= old.depth + EPSILON


func _all_finite(transforms: Array) -> bool:
	for transform in transforms:
		if not (transform is Transform3D) or not transform.is_finite():
			return false
	return true


func _result(
	accepted_fraction: float,
	angle_delta: float,
	clear: bool,
	blocked_reason: String,
	query_count: int,
	substeps: int,
	shape_count: int,
	started_usec: int,
) -> Dictionary:
	var accepted_substeps := roundi(accepted_fraction * substeps)
	return {
		"clear": clear,
		"accepted_fraction": accepted_fraction,
		"actual_angle": angle_delta * accepted_fraction,
		"blocked_reason": blocked_reason,
		"stats": {
			"query_count": query_count,
			"substeps": substeps,
			"accepted_substeps": accepted_substeps,
			"shape_count": shape_count,
			"blocked_reason": blocked_reason,
			"elapsed_usec": Time.get_ticks_usec() - started_usec,
		},
	}
