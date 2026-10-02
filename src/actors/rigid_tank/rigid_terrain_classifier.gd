## 單一物理快照內的低地形證明。讀碰撞幾何，不讀 visual、不改碰撞層或 RID。
extends RefCounted

var _body_bounds: Dictionary = {}
var _shape_bounds: Dictionary = {}

func body_is_traversable(body: Node3D, maximum_y: float, reserve: Callable) -> bool:
	if not is_finite(maximum_y) or not bool(reserve.call(0)): return false
	if not body is StaticBody3D or body is AnimatableBody3D: return false
	var terrain := body as StaticBody3D
	if not terrain.constant_linear_velocity.is_zero_approx() or not terrain.constant_angular_velocity.is_zero_approx(): return false
	var id := terrain.get_instance_id()
	if not _body_bounds.has(id): _body_bounds[id] = _read_body_bounds(terrain, reserve)
	var result: Dictionary = _body_bounds[id]
	return not result.is_empty() and float(result.maximum_y) <= maximum_y

func _read_body_bounds(body: StaticBody3D, reserve: Callable) -> Dictionary:
	var highest := -INF
	for owner_id in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id): continue
		var transform := body.global_transform * body.shape_owner_get_transform(owner_id)
		if not transform.is_finite(): return {}
		for index in body.shape_owner_get_shape_count(owner_id):
			if not bool(reserve.call(1)): return {}
			var shape := body.shape_owner_get_shape(owner_id, index)
			var local := _local_bounds(shape, reserve)
			if local.is_empty(): return {}
			# Transform3D * AABB 包住完整旋轉及非等比縮放後的碰撞幾何。
			var world: AABB = transform * (local.bounds as AABB)
			if not world.position.is_finite() or not world.size.is_finite(): return {}
			highest = maxf(highest, world.end.y)
	return {"maximum_y": highest} if is_finite(highest) else {}

func _local_bounds(shape: Shape3D, reserve: Callable) -> Dictionary:
	if shape == null: return {}
	var id := shape.get_instance_id()
	if _shape_bounds.has(id): return _shape_bounds[id]
	var result: Dictionary = {}
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		if size.is_finite() and size.x > 0.0 and size.y > 0.0 and size.z > 0.0:
			result = {"bounds": AABB(-size * 0.5, size)}
	elif shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D:
		var vertices: PackedVector3Array = shape.points if shape is ConvexPolygonShape3D else shape.get_faces()
		if not vertices.is_empty():
			var bounds := AABB(vertices[0], Vector3.ZERO)
			for index in vertices.size():
				if index % 128 == 0 and not bool(reserve.call(1)): return {}
				if not vertices[index].is_finite(): return {}
				bounds = bounds.expand(vertices[index])
			result = {"bounds": bounds}
	_shape_bounds[id] = result
	return result
