extends SceneTree
## Rebuilds only the bespoke road modules. Vendor GLBs are read, never modified.

const OUT := "res://src/world/roads/generated/custom"
const CATALOG := "res://src/world/roads/custom_catalog.json"
const ROAD1_SOURCE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road1.glb"
const ROAD11_SOURCE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road11_Y_Splitter_45.glb"
const ROAD12_L_SOURCE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_L.glb"
const ROAD12_R_SOURCE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_R.glb"
const CURVE_RADIUS := 24.0
const CURVE_ANGLE := PI * 0.25
const ARC_STEPS := 32
const Q := 0.7071067811865476

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var curve_path := OUT.path_join("road1_curve2_45.tscn")
	var curve := make_curve_scene()
	if curve == null:
		quit(1)
		return
	if not save_scene(curve, curve_path):
		quit(1)
		return
	var splitter := make_compact_wrapper(ROAD11_SOURCE, "Road11YSplitter45", 0.0, [half_plane(Vector3(0, 0, 1), 3.0, true)], [cap("StemCap", Vector3(0, 0, 1), 3.0, -6.00001, 6.00001, 0.0, 0.475349, Vector3(0, 0, -1))])
	var diagonal_left := make_compact_wrapper(ROAD12_L_SOURCE, "Road12DiagonalSplitterL", -0.015, [half_plane(Vector3(0, 0, 1), 14.4852813742, false), half_plane(Vector3(Q, 0, Q), 14.4852813742, false)], [cap("NorthCap", Vector3(0, 0, 1), 14.4852813742, -6.0, 6.0, -0.015, 0.460351, Vector3(0, 0, 1)), cap("DiagonalCap", Vector3(Q, 0, Q), 14.4852813742, -6.023522, 5.976479, -0.015, 0.460349, Vector3(Q, 0, Q))])
	var diagonal_right := make_compact_wrapper(ROAD12_R_SOURCE, "Road12DiagonalSplitterR", -0.015, [half_plane(Vector3(0, 0, 1), 14.4852813742, false), half_plane(Vector3(-Q, 0, Q), 14.4852813742, false)], [cap("NorthCap", Vector3(0, 0, 1), 14.4852813742, -6.0, 6.0, -0.015, 0.460351, Vector3(0, 0, 1)), cap("DiagonalCap", Vector3(-Q, 0, Q), 14.4852813742, -5.976484, 6.023517, -0.015, 0.460349, Vector3(-Q, 0, Q))])
	if splitter == null or diagonal_left == null or diagonal_right == null:
		push_error("A source Y mesh is required; custom roads were not generated")
		quit(1)
		return
	if not save_scene(splitter, OUT.path_join("road11_y_splitter_45.tscn")) or not save_scene(diagonal_left, OUT.path_join("road12_diagonal_splitter_l.tscn")) or not save_scene(diagonal_right, OUT.path_join("road12_diagonal_splitter_r.tscn")):
		quit(1)
		return
	write_catalog()
	print("CUSTOM_ROADS_RESULT curve_radius=%.1f arc_length=%.6f slices=%d" % [CURVE_RADIUS, CURVE_RADIUS * CURVE_ANGLE, ARC_STEPS])
	quit(0)

func make_curve_scene() -> PackedScene:
	var sources := source_meshes(ROAD1_SOURCE)
	if sources.is_empty():
		push_error("Road1 source mesh is required; custom road was not generated")
		return null
	var root := Node3D.new()
	root.name = "Road1Curve2_45"
	root.set_meta("road_module", true)
	root.set_meta("road_id", "Road1_Curve2_Custom45")
	root.set_meta("centerline_radius_m", CURVE_RADIUS)
	root.set_meta("turn_degrees", 45.0)
	for source in sources:
		add_mesh(root, String(source.name), warp_road1_surface(source), source.material)
	return pack(root)

# Arc parameter s is physical centerline distance.  This keeps every UV repeat
# and paint dash tied to metres rather than stretching it across the bend.
func center_at(s: float) -> Vector3:
	var theta := PI - s / CURVE_RADIUS
	return Vector3(CURVE_RADIUS + CURVE_RADIUS * cos(theta), 0.0, -6.0 + CURVE_RADIUS * sin(theta))

func lateral_at(s: float) -> Vector3:
	var theta := PI - s / CURVE_RADIUS
	return Vector3(-cos(theta), 0.0, -sin(theta))

func half_plane(normal: Vector3, offset: float, keep_greater: bool) -> Dictionary:
	return {"normal": normal.normalized(), "offset": offset, "keep_greater": keep_greater}

func cap(name_: String, normal: Vector3, offset: float, transverse_min: float, transverse_max: float, height_min: float, height_max: float, outward: Vector3) -> Dictionary:
	return {"name": name_, "normal": normal.normalized(), "offset": offset, "transverse_min": transverse_min, "transverse_max": transverse_max, "height_min": height_min, "height_max": height_max, "outward": outward.normalized()}

func make_compact_wrapper(source_path: String, id: String, y_offset: float, constraints: Array, caps: Array) -> PackedScene:
	var sources := source_meshes(source_path)
	if sources.is_empty():
		return null
	var root := Node3D.new()
	root.name = id
	root.set_meta("road_module", true)
	root.set_meta("road_id", id)
	root.set_meta("compact", true)
	if id == "Road11YSplitter45":
		root.set_meta("compact_endpoints", {"south": [0.0, 0.0, 3.0], "left": [-4.59158, 0.0, 13.59158], "right": [4.59158, 0.0, 13.59158]})
	else:
		var side := 1.0 if id.ends_with("L") else -1.0
		root.set_meta("compact_endpoints", {"south": [0.0, 0.0, -6.0], "north": [0.0, 0.0, 14.485281], "diagonal": [10.259273 * side, 0.0, 10.226008]})
	for source in sources:
		add_mesh(root, String(source.name), clip_source_surface(source, constraints, y_offset), source.material)
	for definition: Dictionary in caps:
		add_mesh(root, String(definition.name), rect_cap_mesh(definition), sources[0].material)
	return pack(root)

func rect_cap_mesh(definition: Dictionary) -> ArrayMesh:
	var normal: Vector3 = definition.normal
	var tangent := Vector3(-normal.z, 0.0, normal.x).normalized()
	var center := normal * float(definition.offset)
	var left_bottom := center + tangent * float(definition.transverse_min) + Vector3.UP * float(definition.height_min)
	var right_bottom := center + tangent * float(definition.transverse_max) + Vector3.UP * float(definition.height_min)
	var left_top := center + tangent * float(definition.transverse_min) + Vector3.UP * float(definition.height_max)
	var right_top := center + tangent * float(definition.transverse_max) + Vector3.UP * float(definition.height_max)
	var vertices := PackedVector3Array([left_bottom, left_top, right_bottom, right_top])
	var outward: Vector3 = definition.outward
	var normals := PackedVector3Array([outward, outward, outward, outward])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func source_meshes(source_path: String) -> Array[Dictionary]:
	var packed := load(source_path) as PackedScene
	if packed == null:
		return []
	var root := packed.instantiate()
	var result: Array[Dictionary] = []
	collect_source_meshes(root, Transform3D.IDENTITY, result)
	root.free()
	return result

func collect_source_meshes(node: Node, parent: Transform3D, output: Array[Dictionary]) -> void:
	var transform_ := parent
	if node is Node3D:
		transform_ = parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				output.append({"name": "Road1Surface_%d" % surface, "arrays": arrays, "material": node.get_active_material(surface), "transform": transform_})
	for child in node.get_children():
		collect_source_meshes(child, transform_, output)

# The source's z=-6..6 interval is one native Road1 module.  Each source
# triangle is clipped into 32 z slabs before warping, so y, shoulders, paint,
# normals and UV interpolation all originate in the vendor cross-section.
func warp_road1_surface(source: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var source_vertices: PackedVector3Array = source.arrays[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = source.arrays[Mesh.ARRAY_NORMAL]
	var source_uvs: PackedVector2Array = source.arrays[Mesh.ARRAY_TEX_UV]
	var source_indices: PackedInt32Array = source.arrays[Mesh.ARRAY_INDEX]
	var transform: Transform3D = source.transform
	var indices := source_indices
	if indices.is_empty():
		indices = PackedInt32Array()
		for index in source_vertices.size():
			indices.append(index)
	var length := CURVE_RADIUS * CURVE_ANGLE
	var modules := ceili(length / 12.0)
	for module in range(modules):
		var module_start := float(module) * 12.0
		var module_end := minf(module_start + 12.0, length)
		for slice in range(ARC_STEPS):
			var local_start := -6.0 + 12.0 * float(slice) / float(ARC_STEPS)
			var local_end := -6.0 + 12.0 * float(slice + 1) / float(ARC_STEPS)
			if module_start + local_start + 6.0 >= module_end:
				break
			for index in range(0, indices.size(), 3):
				var triangle := [source_vertex(source_vertices, source_normals, source_uvs, indices[index], transform), source_vertex(source_vertices, source_normals, source_uvs, indices[index + 1], transform), source_vertex(source_vertices, source_normals, source_uvs, indices[index + 2], transform)]
				var clipped := clip_z(triangle, local_start, true)
				clipped = clip_z(clipped, minf(local_end, module_end - module_start - 6.0), false)
				append_polygon(clipped, module_start, vertices, normals, uvs)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# A source scene can carry importer transforms, including a mirrored basis.
# Bake both vertex positions and inverse-transpose normals into a fresh mesh so
# L/R are independent, positively wound scenes with no runtime negative scale.
func bake_source_surface(source: Dictionary, y_offset: float) -> ArrayMesh:
	var arrays: Array = source.arrays.duplicate(true)
	var transform: Transform3D = source.transform
	var normal_basis := transform.basis.inverse().transposed()
	var original_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var baked_vertices := PackedVector3Array()
	for vertex in original_vertices:
		baked_vertices.append(transform * vertex + Vector3.UP * y_offset)
	arrays[Mesh.ARRAY_VERTEX] = baked_vertices
	if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		var original_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var baked_normals := PackedVector3Array()
		for normal in original_normals:
			baked_normals.append((normal_basis * normal).normalized())
		arrays[Mesh.ARRAY_NORMAL] = baked_normals
	if transform.basis.determinant() < 0.0 and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var corrected_indices := PackedInt32Array()
		for index in range(0, original_indices.size(), 3):
			corrected_indices.append_array(PackedInt32Array([original_indices[index], original_indices[index + 2], original_indices[index + 1]]))
		arrays[Mesh.ARRAY_INDEX] = corrected_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func clip_source_surface(source: Dictionary, constraints: Array, y_offset: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var source_vertices: PackedVector3Array = source.arrays[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = source.arrays[Mesh.ARRAY_NORMAL]
	var source_uvs: PackedVector2Array = source.arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = source.arrays[Mesh.ARRAY_INDEX].duplicate()
	var transform: Transform3D = source.transform
	if indices.is_empty():
		for index: int in source_vertices.size():
			indices.append(index)
	for index: int in range(0, indices.size(), 3):
		var polygon: Array = [source_vertex(source_vertices, source_normals, source_uvs, indices[index], transform), source_vertex(source_vertices, source_normals, source_uvs, indices[index + 1], transform), source_vertex(source_vertices, source_normals, source_uvs, indices[index + 2], transform)]
		for constraint: Dictionary in constraints:
			polygon = clip_plane(polygon, constraint.normal, float(constraint.offset), bool(constraint.keep_greater))
			if polygon.is_empty():
				break
		for point_index: int in range(1, polygon.size() - 1):
			var triangle: Array = [polygon[0], polygon[point_index], polygon[point_index + 1]]
			if transform.basis.determinant() < 0.0:
				triangle = [polygon[0], polygon[point_index + 1], polygon[point_index]]
			# Preserve the source normals. Godot front faces use clockwise winding;
			# a CCW cross-product must not be used to flip shared polygon vertices.
			for vertex: Dictionary in triangle:
				vertices.append(vertex.position + Vector3.UP * y_offset)
				normals.append(vertex.normal.normalized())
				uvs.append(vertex.uv)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func source_vertex(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, index: int, transform: Transform3D) -> Dictionary:
	var normal := Vector3.UP if index >= normals.size() else normals[index]
	var uv := Vector2.ZERO if index >= uvs.size() else uvs[index]
	var normal_basis := transform.basis.inverse().transposed()
	return {"position": transform * vertices[index], "normal": normal_basis * normal, "uv": uv}

func clip_z(polygon: Array, boundary: float, keep_greater: bool) -> Array:
	return clip_plane(polygon, Vector3(0, 0, 1), boundary, keep_greater)

func clip_plane(polygon: Array, normal: Vector3, boundary: float, keep_greater: bool) -> Array:
	if polygon.is_empty():
		return []
	var result: Array = []
	var previous: Dictionary = polygon[-1]
	var previous_distance: float = normal.dot(previous.position) - boundary
	var previous_inside: bool = previous_distance >= 0.0 if keep_greater else previous_distance <= 0.0
	for current: Dictionary in polygon:
		var current_distance: float = normal.dot(current.position) - boundary
		var current_inside: bool = current_distance >= 0.0 if keep_greater else current_distance <= 0.0
		if current_inside != previous_inside:
			var fraction: float = previous_distance / (previous_distance - current_distance)
			result.append(interpolate_vertex(previous, current, fraction))
		if current_inside:
			result.append(current)
		previous = current
		previous_distance = current_distance
		previous_inside = current_inside
	return result

func interpolate_vertex(first: Dictionary, second: Dictionary, fraction: float) -> Dictionary:
	return {"position": first.position.lerp(second.position, fraction), "normal": first.normal.lerp(second.normal, fraction).normalized(), "uv": first.uv.lerp(second.uv, fraction)}

func append_polygon(polygon: Array, module_start: float, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array) -> void:
	for index in range(1, polygon.size() - 1):
		for vertex: Dictionary in [polygon[0], polygon[index], polygon[index + 1]]:
			var s: float = module_start + vertex.position.z + 6.0
			vertices.append(center_at(s) + lateral_at(s) * vertex.position.x + Vector3.UP * vertex.position.y)
			var theta: float = PI - s / CURVE_RADIUS
			var tangent := Vector3(sin(theta), 0.0, -cos(theta))
			normals.append((lateral_at(s) * vertex.normal.x + Vector3.UP * vertex.normal.y + tangent * vertex.normal.z).normalized())
			uvs.append(vertex.uv)

func add_mesh(root: Node3D, name_: String, mesh: ArrayMesh, material: Material = null) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name_
	instance.mesh = mesh
	instance.material_override = material
	root.add_child(instance)
	instance.owner = root


func pack(root: Node3D) -> PackedScene:
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene

func save_scene(scene: PackedScene, path: String) -> bool:
	if ResourceSaver.save(scene, path) != OK:
		push_error("Could not save " + path)
		return false
	return true

func write_catalog() -> void:
	var endpoint := Vector3(CURVE_RADIUS * (1.0 - cos(CURVE_ANGLE)), 0.0, -6.0 + CURVE_RADIUS * sin(CURVE_ANGLE))
	var catalog := {
		"models": [{
			"id": "Road1_Curve2_Custom45",
			"path": OUT.path_join("road1_curve2_45.tscn"),
			"materials": [],
			"snap_points": [
				point("Entry", Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -1.0)),
				point("Exit45", endpoint, Vector3(sin(CURVE_ANGLE), 0.0, cos(CURVE_ANGLE)))
			]
		}, {
			"id": "Road11_Y_Splitter_45_Custom",
			"path": OUT.path_join("road11_y_splitter_45.tscn"),
			"materials": [],
			"snap_points": [
				point("SouthOuter", Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, -1.0)),
				point("LeftOuter", Vector3(-4.59158, 0.0, 13.59158), Vector3(-0.7071068, 0.0, 0.7071068)),
				point("RightOuter", Vector3(4.59158, 0.0, 13.59158), Vector3(0.7071068, 0.0, 0.7071068))
			]
		}, diagonal_catalog("Road12_Diagonal_Splitter_L_Custom", "road12_diagonal_splitter_l.tscn", 1.0), diagonal_catalog("Road12_Diagonal_Splitter_R_Custom", "road12_diagonal_splitter_r.tscn", -1.0)]
	}
	var file := FileAccess.open(CATALOG, FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog, "\t") + "\n")

func diagonal_catalog(id: String, file_name: String, side: float) -> Dictionary:
	return {"id": id, "path": OUT.path_join(file_name), "materials": [], "snap_points": [
		point("SouthOuter", Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -1.0)),
		point("NorthOuter", Vector3(0.0, 0.0, 14.485281), Vector3(0.0, 0.0, 1.0)),
		point("DiagonalOuter", Vector3(10.259273 * side, 0.0, 10.226008), Vector3(0.7071068 * side, 0.0, 0.7071068)),
		point("DiagonalInner", Vector3(8.137953 * side, 0.0, 8.104688), Vector3(0.7071068 * side, 0.0, 0.7071068)),
		point("NorthInner", Vector3(0.0, 0.0, 11.485281), Vector3(0.0, 0.0, 1.0))
	]}

func point(name_: String, position_: Vector3, outward: Vector3) -> Dictionary:
	return {"name": name_, "position": [position_.x, position_.y, position_.z], "outward": [outward.x, outward.y, outward.z]}
