class_name PlanarTriangleCoverage
extends RefCounted

## Conservative proof that finite triangles cover an entire finite rectangle.
## Each remaining polygon is an uncovered region.  A triangle removes only its
## intersection from that region; any numerical failure leaves the answer false.

const MAX_TRIANGLES := 512
const MAX_PIECES := 2048


static func covers(rect: Rect2, triangles: Array[PackedVector2Array], budget: Callable = Callable()) -> bool:
	if not _valid_rect(rect) or triangles.is_empty() or triangles.size() > MAX_TRIANGLES:
		return false

	var normalized_triangles: Array[Array] = []
	for triangle in triangles:
		var normalized := _normalize_triangle(triangle)
		if normalized.is_empty():
			return false
		normalized_triangles.append(normalized)
	# Remove exact internal edges before clipping. Recomputing the same diagonal
	# from opposite directions can otherwise create float32 slivers in a tiled plane.
	normalized_triangles = _merge_exact_convex(normalized_triangles, budget)
	if normalized_triangles.is_empty(): return false
	# A convex polygon containing all four corners contains the whole rectangle.
	# Strict interior only; seams and numerical boundary cases retain the exact subtraction below.
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x,rect.position.y), rect.end, Vector2(rect.position.x,rect.end.y)]
	for triangle in normalized_triangles:
		if budget.is_valid() and not budget.call(): return false
		var inside := true
		for edge in triangle.size():
			for corner in corners:
				var side := _side(triangle[edge], triangle[(edge+1)%triangle.size()], corner)
				if not is_finite(side) or side <= 0.00000001:
					inside = false
					break
			if not inside: break
		if inside: return true

	var uncovered: Array = [[
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]]

	for triangle in normalized_triangles:
		if budget.is_valid() and not budget.call():
			return false
		var next_uncovered: Array = []
		for polygon_value in uncovered:
			if budget.is_valid() and not budget.call():
				return false
			var remainder: Array = polygon_value
			for edge_index in range(triangle.size()):
				if remainder.is_empty():
					break
				var outside_result := _clip_halfplane(
					remainder,
					triangle[edge_index],
					triangle[(edge_index + 1) % triangle.size()],
					false
				)
				if not outside_result.ok:
					return false
				var outside: Array = outside_result.polygon
				var outside_status := _area_status(outside)
				if not outside_status.ok:
					return false
				if outside_status.positive:
					next_uncovered.append(outside)
					if next_uncovered.size() > MAX_PIECES:
						return false

				var inside_result := _clip_halfplane(
					remainder,
					triangle[edge_index],
					triangle[(edge_index + 1) % triangle.size()],
					true
				)
				if not inside_result.ok:
					return false
				remainder = inside_result.polygon

		uncovered = next_uncovered
		if uncovered.is_empty():
			return true

	return false


static func _merge_exact_convex(polygons: Array[Array], budget: Callable) -> Array[Array]:
	var changed := true
	while changed:
		changed = false
		for i in polygons.size():
			if changed: break
			for j in range(i + 1, polygons.size()):
				if budget.is_valid() and not budget.call(): return []
				var joined := _join_exact_convex(polygons[i], polygons[j])
				if joined.is_empty(): continue
				polygons[i] = joined
				polygons.remove_at(j)
				changed = true
				break
	return polygons


static func _join_exact_convex(a: Array, b: Array) -> Array:
	if a.size() + b.size() > 66: return []
	for i in a.size():
		for j in b.size():
			if a[i] != b[(j + 1) % b.size()] or a[(i + 1) % a.size()] != b[j]: continue
			var joined: Array = []
			for k in a.size(): joined.append(a[(i + 1 + k) % a.size()])
			for k in range(2, b.size()): joined.append(b[(j + k) % b.size()])
			var positive := false
			for edge in joined.size():
				if joined.count(joined[edge]) != 1: return []
				for point in joined:
					# Scalar float math retains double precision; no interpolated vertices.
					var first: Vector2 = joined[edge]
					var last: Vector2 = joined[(edge + 1) % joined.size()]
					var side: float = (float(last.x)-float(first.x)) * (float(point.y)-float(first.y)) - (float(last.y)-float(first.y)) * (float(point.x)-float(first.x))
					if not is_finite(side) or side < 0.0: return []
					positive = positive or side > 0.0
			return joined if positive else []
	return []


static func _valid_rect(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.end.is_finite() \
		and rect.size.x > 0.0 and rect.size.y > 0.0


static func _normalize_triangle(triangle: PackedVector2Array) -> Array:
	if triangle.size() != 3:
		return []
	var points: Array[Vector2] = [triangle[0], triangle[1], triangle[2]]
	if not points[0].is_finite() or not points[1].is_finite() or not points[2].is_finite():
		return []
	var area_twice := _side(points[0], points[1], points[2])
	if not is_finite(area_twice) or area_twice == 0.0:
		return []
	if area_twice < 0.0:
		var swap := points[1]
		points[1] = points[2]
		points[2] = swap
	return points


static func _clip_halfplane(
		polygon: Array,
		edge_start: Vector2,
		edge_end: Vector2,
		keep_inside: bool
	) -> Dictionary:
	if polygon.is_empty():
		return {"ok": true, "polygon": []}

	var output: Array = []
	var previous: Vector2 = polygon[polygon.size() - 1]
	var previous_side := _side(edge_start, edge_end, previous)
	if not is_finite(previous_side):
		return {"ok": false}
	var previous_kept := previous_side >= 0.0 if keep_inside else previous_side <= 0.0

	for current in polygon:
		var current_side := _side(edge_start, edge_end, current)
		if not is_finite(current_side):
			return {"ok": false}
		var current_kept := current_side >= 0.0 if keep_inside else current_side <= 0.0
		if current_kept != previous_kept:
			var denominator := previous_side - current_side
			if not is_finite(denominator) or denominator == 0.0:
				return {"ok": false}
			var interpolation := previous_side / denominator
			if not is_finite(interpolation) or interpolation < 0.0 or interpolation > 1.0:
				return {"ok": false}
			var intersection := previous.lerp(current, interpolation)
			if not intersection.is_finite():
				return {"ok": false}
			_append_distinct(output, intersection)
		if current_kept:
			_append_distinct(output, current)
		previous = current
		previous_side = current_side
		previous_kept = current_kept

	return {"ok": true, "polygon": output}


static func _append_distinct(points: Array, point: Vector2) -> void:
	if points.is_empty() or points[points.size() - 1] != point:
		points.append(point)


static func _area_status(polygon: Array) -> Dictionary:
	if polygon.size() < 3:
		return {"ok": true, "positive": false}
	var origin: Vector2 = polygon[0]
	for index in range(1, polygon.size() - 1):
		var side := _side(origin, polygon[index], polygon[index + 1])
		if not is_finite(side):
			return {"ok": false}
		if side != 0.0:
			return {"ok": true, "positive": true}
	return {"ok": true, "positive": false}


static func _side(edge_start: Vector2, edge_end: Vector2, point: Vector2) -> float:
	var edge := edge_end - edge_start
	var offset := point - edge_start
	return edge.x * offset.y - edge.y * offset.x
