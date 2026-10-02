extends SceneTree
## Read-only geometric probe for proposed compact-road cap planes.

const ROAD11 := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road11_Y_Splitter_45.glb"
const ROAD12_L := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_L.glb"
const ROAD12_R := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_R.glb"
const CUSTOM11 := "res://src/world/roads/generated/custom/road11_y_splitter_45.tscn"
const CUSTOM12_L := "res://src/world/roads/generated/custom/road12_diagonal_splitter_l.tscn"
const CUSTOM12_R := "res://src/world/roads/generated/custom/road12_diagonal_splitter_r.tscn"
const Q := 0.7071067811865476
const TOLERANCE := 0.0001
const REPORT := "res://artifacts-local/roads/compact-cap-probe.json"

func _init() -> void:
	var report := {
		"road12_l": probe(ROAD12_L, [plane("south", Vector3.ZERO, Vector3(0, 0, 1), -6.0), plane("north", Vector3.ZERO, Vector3(0, 0, 1), 14.4852813742), plane("diagonal", Vector3.ZERO, Vector3(Q, 0, Q), 14.4852813742)]),
		"road12_r": probe(ROAD12_R, [plane("south", Vector3.ZERO, Vector3(0, 0, 1), -6.0), plane("north", Vector3.ZERO, Vector3(0, 0, 1), 14.4852813742), plane("diagonal", Vector3.ZERO, Vector3(-Q, 0, Q), 14.4852813742)]),
		"road11": probe(ROAD11, [plane("stem", Vector3(0, 0, 9), Vector3(0, 0, 1), -6.0), plane("right", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.0), plane("left", Vector3(0, 0, 9), Vector3(-Q, 0, Q), 6.0)]),
		"road11_right_sweep": probe(ROAD11, [plane("s_6_10", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.10), plane("s_6_20", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.20), plane("s_6_30", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.30), plane("s_6_40", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.40), plane("s_6_45", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.45), plane("s_6_49", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.49), plane("s_outer", Vector3(0, 0, 9), Vector3(Q, 0, Q), 6.493)]),
		"compact_road11": probe(CUSTOM11, [plane("stem", Vector3.ZERO, Vector3(0, 0, 1), 3.0)]),
		"compact_road12_l": probe(CUSTOM12_L, [plane("north", Vector3.ZERO, Vector3(0, 0, 1), 14.4852813742), plane("diagonal", Vector3.ZERO, Vector3(Q, 0, Q), 14.4852813742)]),
		"compact_road12_r": probe(CUSTOM12_R, [plane("north", Vector3.ZERO, Vector3(0, 0, 1), 14.4852813742), plane("diagonal", Vector3.ZERO, Vector3(-Q, 0, Q), 14.4852813742)])
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT.get_base_dir()))
	var file := FileAccess.open(REPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("COMPACT_CAP_PROBE_RESULT " + JSON.stringify(report))
	quit()

func plane(name_: String, origin: Vector3, normal: Vector3, offset: float) -> Dictionary:
	return {"name": name_, "origin": origin, "normal": normal.normalized(), "offset": offset}

func probe(path: String, planes: Array) -> Dictionary:
	var triangles := load_triangles(path)
	var results: Array = []
	for definition: Dictionary in planes:
		results.append(probe_plane(triangles, definition))
	return {"source": path, "triangles": triangles.size(), "planes": results}

func load_triangles(path: String) -> Array:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Cannot load " + path)
		return []
	var root := packed.instantiate()
	var triangles: Array = []
	collect_triangles(root, Transform3D.IDENTITY, triangles)
	root.free()
	return triangles

func collect_triangles(node: Node, parent: Transform3D, output: Array) -> void:
	var transform := parent
	if node is Node3D:
		transform = parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices = PackedInt32Array()
				for index: int in vertices.size():
					indices.append(index)
			for index: int in range(0, indices.size(), 3):
				output.append([transform * vertices[indices[index]], transform * vertices[indices[index + 1]], transform * vertices[indices[index + 2]]])
	for child: Node in node.get_children():
		collect_triangles(child, transform, output)

func probe_plane(triangles: Array, definition: Dictionary) -> Dictionary:
	var segments: Array = []
	for triangle: Array in triangles:
		var points := triangle_plane_points(triangle, definition.origin, definition.normal, float(definition.offset))
		if points.size() == 2 and points[0].distance_to(points[1]) > TOLERANCE:
			segments.append(points)
	var components := components_from_segments(segments)
	var tangent: Vector3 = Vector3(-definition.normal.z, 0.0, definition.normal.x).normalized()
	var summaries: Array = []
	for component: Array in components:
		var range := projection_range(component, definition.origin, tangent)
		var heights := projection_range(component, Vector3.ZERO, Vector3.UP)
		summaries.append({"points": component.size(), "width": range.y - range.x, "transverse_min": range.x, "transverse_max": range.y, "height_min": heights.x, "height_max": heights.y})
	summaries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.width > b.width)
	return {"name": definition.name, "segments": segments.size(), "components": summaries}

func triangle_plane_points(triangle: Array, origin: Vector3, normal: Vector3, offset: float) -> Array:
	var points: Array = []
	for edge: int in 3:
		var first: Vector3 = triangle[edge]
		var second: Vector3 = triangle[(edge + 1) % 3]
		var first_distance: float = normal.dot(first - origin) - offset
		var second_distance: float = normal.dot(second - origin) - offset
		if absf(first_distance) <= TOLERANCE:
			append_unique(points, first)
		if first_distance * second_distance < -TOLERANCE * TOLERANCE:
			var fraction: float = first_distance / (first_distance - second_distance)
			append_unique(points, first.lerp(second, fraction))
	return points

func append_unique(points: Array, candidate: Vector3) -> void:
	for point: Vector3 in points:
		if point.distance_to(candidate) <= TOLERANCE:
			return
	points.append(candidate)

func components_from_segments(segments: Array) -> Array:
	var points: Array = []
	var adjacency: Array = []
	for segment: Array in segments:
		var first := point_index(points, segment[0])
		var second := point_index(points, segment[1])
		while adjacency.size() < points.size():
			adjacency.append([])
		if not adjacency[first].has(second):
			adjacency[first].append(second)
			adjacency[second].append(first)
	var visited: Dictionary = {}
	var result: Array = []
	for start: int in points.size():
		if visited.has(start):
			continue
		var pending: Array[int] = [start]
		var component: Array = []
		visited[start] = true
		while not pending.is_empty():
			var current: int = pending.pop_back()
			component.append(points[current])
			for next: int in adjacency[current]:
				if not visited.has(next):
					visited[next] = true
					pending.append(next)
		result.append(component)
	return result

func point_index(points: Array, candidate: Vector3) -> int:
	for index: int in points.size():
		if points[index].distance_to(candidate) <= TOLERANCE:
			return index
	points.append(candidate)
	return points.size() - 1

func projection_range(points: Array, origin: Vector3, axis: Vector3) -> Vector2:
	var minimum := INF
	var maximum := -INF
	for point: Vector3 in points:
		var projection: float = axis.dot(point - origin)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	return Vector2(minimum, maximum)
