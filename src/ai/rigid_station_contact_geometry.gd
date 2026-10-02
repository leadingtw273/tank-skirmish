class_name RigidStationContactGeometry
extends RefCounted

## A geometric certificate only: it proves horizontal proximity to the supplied
## triangles.  It does not assert a physics contact, load-bearing support,
## dynamics, or that stopping is safe.

const Coverage := preload("res://src/ai/planar_triangle_coverage.gd")

# One source triangle produces at most ten fan triangles.  Keep well below the
# coverage helper's 512-triangle limit so preparation itself remains bounded.
const MAX_TRIANGLES := 48
const MAX_EXPANDED_TRIANGLES := 480


static func covers(rect: Rect2, triangles: Array[PackedVector2Array], sphere_radius: float, height_slack: float, budget: Callable = Callable()) -> bool:
	var retained := prefilter(rect, triangles, sphere_radius, height_slack, budget)
	if retained.is_empty():
		return false
	var prepared := prepare(retained, sphere_radius, height_slack, budget)
	return not prepared.is_empty() and covers_prepared(rect, prepared, budget)


## Returns only original triangles whose AABB is not strictly outside
## rect.grow(rho).  It validates every original input before filtering, so [] is
## fail-closed and cannot hide an invalid remote triangle.  Callers may record
## input.size(), result.size(), and prepare(result).size() as raw/retained/fan
## performance counters without changing covers' boolean API.
static func prefilter(rect: Rect2, triangles: Array[PackedVector2Array], sphere_radius: float, height_slack: float, budget: Callable = Callable()) -> Array[PackedVector2Array]:
	if not _valid_rect(rect) or triangles.is_empty() or triangles.size() > MAX_TRIANGLES:
		return []
	var rho := _rho(sphere_radius, height_slack)
	if not is_finite(rho) or rho <= 0.0:
		return []

	var retained: Array[PackedVector2Array] = []
	for triangle in triangles:
		if not _has_budget(budget) or not _valid_source_triangle(triangle):
			return []
		if not _strictly_outside_expanded_rect(rect, triangle, rho):
			retained.append(triangle)
	return retained


## Prepares a conservative Minkowski certificate that callers can reuse for
## several station rectangles in one evaluation.  Pass its result unchanged to
## covers_prepared; [] is always fail-closed.
static func prepare(triangles: Array[PackedVector2Array], sphere_radius: float, height_slack: float, budget: Callable = Callable()) -> Array[PackedVector2Array]:
	if triangles.is_empty() or triangles.size() > MAX_TRIANGLES:
		return []
	if not is_finite(sphere_radius) or not is_finite(height_slack) \
			or sphere_radius <= 0.0 or height_slack <= 0.0 or height_slack >= sphere_radius:
		return []

	# A horizontal miss rho lowers a sphere's contact height by at most slack.
	# h=rho/4 makes every ideal square-corner displacement rho/sqrt(8),
	# strictly inside rho; the actual float32 result is checked below as well.
	var rho_squared := 2.0 * sphere_radius * height_slack - height_slack * height_slack
	if not is_finite(rho_squared) or rho_squared <= 0.0:
		return []
	var rho := sqrt(rho_squared)
	var h := rho * 0.25
	if not is_finite(rho) or not is_finite(h) or h <= 0.0:
		return []

	var expanded: Array[PackedVector2Array] = []
	for triangle in triangles:
		if not _has_budget(budget):
			return []
		var hull := _expanded_hull(triangle, h, rho_squared, budget)
		if hull.size() < 3:
			return []
		for index in range(1, hull.size() - 1):
			if not _has_budget(budget) or expanded.size() >= MAX_EXPANDED_TRIANGLES:
				return []
			var fan_triangle := PackedVector2Array([hull[0], hull[index], hull[index + 1]])
			var area_twice := _side(fan_triangle[0], fan_triangle[1], fan_triangle[2])
			if not is_finite(area_twice) or area_twice == 0.0:
				return []
			expanded.append(fan_triangle)
	return expanded


static func covers_prepared(rect: Rect2, prepared: Array[PackedVector2Array], budget: Callable = Callable()) -> bool:
	if not _valid_rect(rect) or prepared.is_empty() or prepared.size() > MAX_EXPANDED_TRIANGLES:
		return false
	return Coverage.covers(rect, prepared, budget)


static func _rho(sphere_radius: float, height_slack: float) -> float:
	if not is_finite(sphere_radius) or not is_finite(height_slack) \
			or sphere_radius <= 0.0 or height_slack <= 0.0 or height_slack >= sphere_radius:
		return NAN
	var rho_squared := 2.0 * sphere_radius * height_slack - height_slack * height_slack
	return sqrt(rho_squared) if is_finite(rho_squared) and rho_squared > 0.0 else NAN


static func _strictly_outside_expanded_rect(rect: Rect2, triangle: PackedVector2Array, rho: float) -> bool:
	# Scalar comparisons avoid Rect2 float32 grow rounding.  Strict inequalities
	# preserve every touch boundary as a candidate for the continuous proof.
	var minimum_x := minf(float(triangle[0].x), minf(float(triangle[1].x), float(triangle[2].x)))
	var maximum_x := maxf(float(triangle[0].x), maxf(float(triangle[1].x), float(triangle[2].x)))
	var minimum_y := minf(float(triangle[0].y), minf(float(triangle[1].y), float(triangle[2].y)))
	var maximum_y := maxf(float(triangle[0].y), maxf(float(triangle[1].y), float(triangle[2].y)))
	var grown_minimum_x := float(rect.position.x) - rho
	var grown_maximum_x := float(rect.end.x) + rho
	var grown_minimum_y := float(rect.position.y) - rho
	var grown_maximum_y := float(rect.end.y) + rho
	if not is_finite(minimum_x) or not is_finite(maximum_x) or not is_finite(minimum_y) or not is_finite(maximum_y) \
			or not is_finite(grown_minimum_x) or not is_finite(grown_maximum_x) or not is_finite(grown_minimum_y) or not is_finite(grown_maximum_y):
		return false
	return maximum_x < grown_minimum_x or minimum_x > grown_maximum_x \
		or maximum_y < grown_minimum_y or minimum_y > grown_maximum_y


static func _expanded_hull(triangle: PackedVector2Array, h: float, rho_squared: float, budget: Callable) -> Array[Vector2]:
	if not _valid_source_triangle(triangle):
		return []
	var source: Array[Vector2] = [triangle[0], triangle[1], triangle[2]]

	var corners: Array[Vector2] = [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
	var candidates: Array[Vector2] = []
	for point in source:
		for corner in corners:
			if not _has_budget(budget):
				return []
			var candidate := point + corner
			# Vector2 storage is float32.  Validate the rounded coordinate, rather
			# than trusting the double-precision expression that constructed it.
			if not candidate.is_finite() or not _strictly_within_physical_radius(candidate, source, rho_squared):
				return []
			candidates.append(candidate)

	var hull := _convex_hull(candidates)
	for point in hull:
		# The hull algorithm returns only candidate vertices, but repeat the check
		# at the emitted-geometry boundary to keep that physical invariant local.
		if not _strictly_within_physical_radius(point, source, rho_squared):
			return []
	return hull


static func _valid_source_triangle(triangle: PackedVector2Array) -> bool:
	if triangle.size() != 3 or not triangle[0].is_finite() or not triangle[1].is_finite() or not triangle[2].is_finite():
		return false
	var area_twice := _side(triangle[0], triangle[1], triangle[2])
	return is_finite(area_twice) and area_twice != 0.0


static func _convex_hull(points: Array[Vector2]) -> Array[Vector2]:
	points.sort_custom(func(first: Vector2, second: Vector2) -> bool:
		return first.x < second.x or (first.x == second.x and first.y < second.y)
	)
	var unique: Array[Vector2] = []
	for point in points:
		if unique.is_empty() or unique[-1] != point:
			unique.append(point)
	if unique.size() < 3:
		return []

	var lower: Array[Vector2] = []
	for point in unique:
		while lower.size() >= 2 and _side(lower[-2], lower[-1], point) <= 0.0:
			lower.pop_back()
		lower.append(point)
	var upper: Array[Vector2] = []
	for index in range(unique.size() - 1, -1, -1):
		var point := unique[index]
		while upper.size() >= 2 and _side(upper[-2], upper[-1], point) <= 0.0:
			upper.pop_back()
		upper.append(point)
	if lower.size() < 2 or upper.size() < 2:
		return []
	lower.pop_back()
	upper.pop_back()
	lower.append_array(upper)
	return lower if lower.size() >= 3 else []


static func _strictly_within_physical_radius(point: Vector2, source: Array[Vector2], rho_squared: float) -> bool:
	for original in source:
		var dx := float(point.x) - float(original.x)
		var dy := float(point.y) - float(original.y)
		var distance_squared := dx * dx + dy * dy
		if is_finite(distance_squared) and distance_squared < rho_squared:
			return true
	return false


static func _valid_rect(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.end.is_finite() \
		and rect.size.x > 0.0 and rect.size.y > 0.0


static func _side(first: Vector2, second: Vector2, point: Vector2) -> float:
	return (float(second.x) - float(first.x)) * (float(point.y) - float(first.y)) \
		- (float(second.y) - float(first.y)) * (float(point.x) - float(first.x))


static func _has_budget(budget: Callable) -> bool:
	return not budget.is_valid() or bool(budget.call())
