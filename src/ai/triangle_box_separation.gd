class_name TriangleBoxSeparation
extends RefCounted

## Conservative triangle/AABB SAT.  true means a strictly positive, numerically
## buffered separating gap was found; contact and uncertainty both return false.

const ABSOLUTE_MARGIN := 0.0000001
const RELATIVE_MARGIN := 0.000001
const DEGENERATE_AXIS_RELATIVE := 0.000000000001


static func separated(a: Vector3, b: Vector3, c: Vector3, box: AABB, budget: Callable = Callable()) -> bool:
	if not _has_budget(budget) or not a.is_finite() or not b.is_finite() or not c.is_finite() or not _valid_box(box):
		return false

	# Keep the projection arithmetic in scalar doubles after moving the box to
	# the origin.  Constructing a shifted Vector3 would reintroduce float32 loss.
	var center_x := float(box.position.x) + float(box.size.x) * 0.5
	var center_y := float(box.position.y) + float(box.size.y) * 0.5
	var center_z := float(box.position.z) + float(box.size.z) * 0.5
	if not is_finite(center_x) or not is_finite(center_y) or not is_finite(center_z):
		return false
	var points: Array[PackedFloat64Array] = [
		PackedFloat64Array([float(a.x) - center_x, float(a.y) - center_y, float(a.z) - center_z]),
		PackedFloat64Array([float(b.x) - center_x, float(b.y) - center_y, float(b.z) - center_z]),
		PackedFloat64Array([float(c.x) - center_x, float(c.y) - center_y, float(c.z) - center_z]),
	]
	var half := PackedFloat64Array([float(box.size.x) * 0.5, float(box.size.y) * 0.5, float(box.size.z) * 0.5])
	if not _finite_vector(half) or not _finite_points(points):
		return false
	var scale := _local_scale(points, half)
	if not is_finite(scale) or scale <= 0.0:
		return false
	var margin := maxf(ABSOLUTE_MARGIN, scale * RELATIVE_MARGIN)
	var axis_minimum := scale * DEGENERATE_AXIS_RELATIVE
	if not is_finite(margin) or not is_finite(axis_minimum):
		return false

	var edge_ab := _subtract(points[1], points[0])
	var edge_bc := _subtract(points[2], points[1])
	var edge_ca := _subtract(points[0], points[2])
	if not _finite_vector(edge_ab) or not _finite_vector(edge_bc) or not _finite_vector(edge_ca):
		return false
	var normal := _cross(edge_ab, edge_bc)
	# A zero-area triangle has no reliable triangle normal, so do not let its
	# remaining axes prove separation.
	var normalized_normal := _normalized_axis(normal, axis_minimum * scale)
	if not bool(normalized_normal.ok) or not bool(normalized_normal.usable):
		return false

	var axes: Array[PackedFloat64Array] = [
		PackedFloat64Array([1.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 1.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 1.0]),
		normal,
	]
	var edges: Array[PackedFloat64Array] = [edge_ab, edge_bc, edge_ca]
	for edge in edges:
		axes.append(_cross(edge, PackedFloat64Array([1.0, 0.0, 0.0])))
		axes.append(_cross(edge, PackedFloat64Array([0.0, 1.0, 0.0])))
		axes.append(_cross(edge, PackedFloat64Array([0.0, 0.0, 1.0])))

	# The three box axes, one triangle normal, and nine edge-cross-box axes are
	# the complete 13-axis SAT set for a triangle and an axis-aligned box.
	for axis in axes:
		if not _has_budget(budget):
			return false
		var normalized := _normalized_axis(axis, axis_minimum)
		if not bool(normalized.ok):
			return false
		if not bool(normalized.usable):
			continue
		if _separated_on_normalized_axis(points, half, normalized.axis as PackedFloat64Array, margin):
			return true
	return false


static func _separated_on_normalized_axis(points: Array[PackedFloat64Array], half: PackedFloat64Array, axis: PackedFloat64Array, margin: float) -> bool:
	var minimum := _dot(points[0], axis)
	var maximum := minimum
	for index in range(1, points.size()):
		var projection := _dot(points[index], axis)
		if not is_finite(projection):
			return false
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	var radius := half[0] * absf(axis[0]) + half[1] * absf(axis[1]) + half[2] * absf(axis[2])
	if not is_finite(minimum) or not is_finite(maximum) or not is_finite(radius):
		return false
	# Equality is contact; only a gap beyond the conservative margin separates.
	return minimum > radius + margin or maximum < -radius - margin


static func _normalized_axis(axis: PackedFloat64Array, minimum_length: float) -> Dictionary:
	if not _finite_vector(axis) or not is_finite(minimum_length) or minimum_length < 0.0:
		return {"ok": false, "usable": false}
	var length_squared := _dot(axis, axis)
	if not is_finite(length_squared) or length_squared < 0.0:
		return {"ok": false, "usable": false}
	var length := sqrt(length_squared)
	if not is_finite(length):
		return {"ok": false, "usable": false}
	if length <= minimum_length:
		return {"ok": true, "usable": false}
	var normalized := PackedFloat64Array([axis[0] / length, axis[1] / length, axis[2] / length])
	return {"ok": _finite_vector(normalized), "usable": true, "axis": normalized}


static func _valid_box(box: AABB) -> bool:
	return box.position.is_finite() and box.size.is_finite() and box.end.is_finite() \
		and box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0


static func _finite_points(points: Array[PackedFloat64Array]) -> bool:
	for point in points:
		if not _finite_vector(point):
			return false
	return true


static func _finite_vector(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and is_finite(value[0]) and is_finite(value[1]) and is_finite(value[2])


static func _local_scale(points: Array[PackedFloat64Array], half: PackedFloat64Array) -> float:
	var scale := maxf(1.0, maxf(half[0], maxf(half[1], half[2])))
	for point in points:
		for value in point:
			scale = maxf(scale, absf(value))
	return scale


static func _subtract(first: PackedFloat64Array, second: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([first[0] - second[0], first[1] - second[1], first[2] - second[2]])


static func _cross(first: PackedFloat64Array, second: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		first[1] * second[2] - first[2] * second[1],
		first[2] * second[0] - first[0] * second[2],
		first[0] * second[1] - first[1] * second[0],
	])


static func _dot(first: PackedFloat64Array, second: PackedFloat64Array) -> float:
	return first[0] * second[0] + first[1] * second[1] + first[2] * second[2]


static func _has_budget(budget: Callable) -> bool:
	return not budget.is_valid() or bool(budget.call())
