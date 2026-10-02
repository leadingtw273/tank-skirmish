## Exact local horizontal support domain; uncertainty returns to terrain queries.
extends RefCounted

const Coverage := preload("res://src/ai/planar_triangle_coverage.gd")
const TriangleBox := preload("res://src/ai/triangle_box_separation.gd")
const HEIGHT_EPS := 0.00001
const MAX_FACES := 512

static func read(solver: RefCounted, hit: Dictionary, samples: Array) -> Dictionary:
	var body := hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return {}
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return {}
	var node := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as CollisionShape3D
	if node == null or not node.shape is ConcavePolygonShape3D: return {}
	if not solver._rigid_pose(node.global_transform): return {}
	var floor_y := float((hit.position as Vector3).y)
	for sample: Dictionary in samples:
		var raw: Dictionary = sample.hit
		if raw.rid != hit.rid or int(raw.shape) != int(hit.shape): return {}
		if (raw.normal as Vector3).distance_to(Vector3.UP) > 0.000001: return {}
		if absf((raw.position as Vector3).y - floor_y) > HEIGHT_EPS: return {}
	var faces: PackedVector3Array = node.shape.get_faces()
	if faces.is_empty() or faces.size() % 3 != 0 or faces.size() > MAX_FACES * 3: return {}
	var triangles: Array[PackedVector2Array] = []
	var other_bounds: Array[AABB] = []
	var other_max_y: Array[float] = []
	var other_faces: Array[PackedVector3Array] = []
	var minimum_support_height := INF
	for index in range(0, faces.size(), 3):
		if index % 48 == 0 and not solver._reserve(0): return {}
		var a := node.global_transform * faces[index]
		var b := node.global_transform * faces[index + 1]
		var c := node.global_transform * faces[index + 2]
		if not a.is_finite() or not b.is_finite() or not c.is_finite(): return {}
		if maxf(maxf(absf(a.y-floor_y), absf(b.y-floor_y)), absf(c.y-floor_y)) <= HEIGHT_EPS:
			# Godot Concave front faces use clockwise winding (verified by native rays).
			if node.shape.backface_collision or (b-a).cross(c-a).y < 0.0:
				minimum_support_height = minf(minimum_support_height, minf(a.y, minf(b.y, c.y)))
				triangles.append(PackedVector2Array([Vector2(a.x,a.z), Vector2(b.x,b.z), Vector2(c.x,c.z)]))
		else:
			other_bounds.append(AABB(a,Vector3.ZERO).expand(b).expand(c))
			other_max_y.append(maxf(a.y, maxf(b.y, c.y)))
			other_faces.append(PackedVector3Array([a,b,c]))
	if triangles.is_empty(): return {}
	return {"normal": Vector3.UP, "point": Vector3(0,floor_y,0), "mesh": true,
		"triangles": triangles, "other_bounds": other_bounds, "other_max_y": other_max_y, "other_faces": other_faces, "minimum_support_height": minimum_support_height}

static func covers(solver: RefCounted, plane: Dictionary, volume: AABB, parts: Array[AABB], support_floor_y: float = -INF, start: Transform3D = Transform3D.IDENTITY, oriented_parts: Array[AABB] = []) -> bool:
	solver.diagnostic.erase("mesh_support_failure")
	solver.diagnostic.erase("mesh_oriented_failure")
	for key in ["other_faces", "other_max_y"]:
		if plane.has(key) and (not plane[key] is Array or plane[key].size() != plane.other_bounds.size()):
			solver.diagnostic["mesh_support_failure"] = {"reason": "mesh_metadata"}
			return false
	if not oriented_parts.is_empty() and oriented_parts.size() != solver.bounds.size():
		solver.diagnostic["mesh_support_failure"] = {"reason": "mesh_metadata"}
		return false
	if not solver._reserve(0): return false
	for index: int in plane.other_bounds.size():
		var triangle_box: AABB = plane.other_bounds[index]
		# A complete top-plane coverage proof below makes buried tile sides part
		# of the supporting floor. Above-floor triangles remain full-part obstacles.
		# Compare original vertex heights, not rounded ray hit / AABB endpoint heights.
		# The minimum of all accepted top vertices is a lower bound on every covered floor.
		var top: float = plane.other_max_y[index] if plane.has("other_max_y") else triangle_box.end.y
		var bottom_of_support: float = plane.get("minimum_support_height", support_floor_y)
		if is_finite(support_floor_y) and is_finite(bottom_of_support) and top <= bottom_of_support: continue
		for part: AABB in parts:
			# AABB separation is sufficient, never necessary; shared-shape walls remain obstacles.
			if part.grow(solver.MARGIN).intersects(triangle_box.grow(HEIGHT_EPS)):
				if not oriented_parts.is_empty() and plane.has("other_faces") and index < plane.other_faces.size() and plane.other_faces[index] is PackedVector3Array:
					if _outside_oriented(solver, plane.other_faces[index], start, oriented_parts):
						break
				solver.diagnostic["mesh_support_failure"] = {"reason": "nonplane_intersection", "triangle": str(triangle_box), "part": str(part)}
				return false
	var rect := Rect2(Vector2(volume.position.x,volume.position.z),Vector2(volume.size.x,volume.size.z))
	var covered := Coverage.covers(rect, plane.triangles, Callable(solver,"_reserve").bind(0))
	if not covered: solver.diagnostic["mesh_support_failure"] = {"reason": "uncovered_rectangle", "rect": str(rect), "triangles": plane.triangles}
	return covered and solver._reserve(0)


static func _outside_oriented(solver: RefCounted, triangle: PackedVector3Array, start: Transform3D, parts: Array[AABB]) -> bool:
	if triangle.size() != 3 or not solver._rigid_pose(start): return false
	var inverse := start.affine_inverse()
	var a := inverse * triangle[0]
	var b := inverse * triangle[1]
	var c := inverse * triangle[2]
	if not a.is_finite() or not b.is_finite() or not c.is_finite(): return false
	# Most pieces are nowhere near this triangle. A padded local AABB separation
	# is already a complete proof; reserve the 13-axis test for overlapping boxes.
	var triangle_scale := maxf(1.0, maxf(a.length(), maxf(b.length(), c.length())))
	if not is_finite(triangle_scale): return false
	var triangle_pad := maxf(HEIGHT_EPS, triangle_scale * 0.000001)
	var triangle_box := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(triangle_pad)
	for index: int in parts.size():
		if not solver._reserve(0): return false
		var part: AABB = parts[index]
		var part_pad := maxf(triangle_pad, (part.position.length() + part.size.length()) * 0.000001)
		if not is_finite(part_pad): return false
		if not part.grow(solver.MARGIN + part_pad).intersects(triangle_box): continue
		if not TriangleBox.separated(a,b,c,part.grow(solver.MARGIN),Callable(solver,"_reserve").bind(0)):
			solver.diagnostic["mesh_oriented_failure"] = {"shape_index": index, "hull": bool(solver.hull_shapes[index]), "box": str(part), "triangle": [[triangle[0].x,triangle[0].y,triangle[0].z], [triangle[1].x,triangle[1].y,triangle[1].z], [triangle[2].x,triangle[2].y,triangle[2].z]]}
			return false
	return solver._reserve(0)

static func outside_parts(solver: RefCounted, hit: Dictionary, start: Transform3D, parts: Array[AABB]) -> bool:
	var body := hit.get("collider") as StaticBody3D
	if body == null or body is AnimatableBody3D: return false
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
	var box := BoxShape3D.new()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = solver.tank.collision_mask
	query.exclude = [solver.tank.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var target := _target_world_bounds(solver, body, int(hit.shape))
	for part: AABB in parts:
		if not solver._reserve(0): return false
		if not target.is_empty():
			var world_part: AABB = (start * part.grow(maxf(box.margin, solver.MARGIN))).grow(maxf(query.margin, 0.0) + solver.MARGIN)
			if _strict_bounds_separation(world_part, target.bounds as AABB):
				var diagnostic: Variant = solver.get("diagnostic")
				if diagnostic is Dictionary: diagnostic["outside_parts_prefilter_skips"] = int(diagnostic.get("outside_parts_prefilter_skips", 0)) + 1
				continue
		if not solver._reserve(): return false
		box.size = part.size
		query.transform = start * Transform3D(Basis.IDENTITY,part.get_center())
		var hits: Array = solver.space.intersect_shape(query,128)
		if hits.size() >= 128: return false
		for found: Dictionary in hits:
			if found.rid == hit.rid and int(found.shape) == int(hit.shape): return false
	return solver._reserve(0)


static func _strict_bounds_separation(a: AABB, b: AABB) -> bool:
	if not a.position.is_finite() or not a.size.is_finite() or not a.end.is_finite() or not b.position.is_finite() or not b.size.is_finite() or not b.end.is_finite(): return false
	# AABB.intersects excludes touching borders; a certificate needs a strict gap.
	return a.end.x < b.position.x or b.end.x < a.position.x or a.end.y < b.position.y or b.end.y < a.position.y or a.end.z < b.position.z or b.end.z < a.position.z


static func _target_world_bounds(solver: RefCounted, body: StaticBody3D, shape_index: int) -> Dictionary:
	# Unknown geometry keeps the original native query. The same bounds routine
	# already supplies the terrain solver's conservative below-part certificate.
	if not solver._reserve(0): return {}
	var terrain: Variant = solver.get("_terrain")
	if terrain == null or not terrain.has_method("_local_bounds"): return {}
	var owner := body.shape_find_owner(shape_index)
	var node := body.shape_owner_get_owner(owner) as CollisionShape3D
	if node == null or node.shape == null: return {}
	var local: Dictionary = terrain._local_bounds(node.shape, solver._reserve)
	if local.is_empty(): return {}
	var bounds: AABB = (node.global_transform * (local.bounds as AABB).grow(maxf(node.shape.margin, solver.MARGIN))).grow(solver.MARGIN)
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.end.is_finite() or bounds.size.x < 0.0 or bounds.size.y < 0.0 or bounds.size.z < 0.0: return {}
	return {"bounds": bounds}
