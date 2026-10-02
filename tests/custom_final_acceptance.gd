extends SceneTree
## Independent LEA-177 acceptance: inspect generated data and instantiated ports.

const CATALOG := "res://src/world/roads/custom_catalog.json"
const DEMO := "res://src/samples/roads/compact_loop_demo.tscn"
const SOURCE_HASHES := {
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road1.glb": "3931ec0bfed31802f77447ed9c34e75393a18494078daac3c2fe8ec079f4245f",
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road11_Y_Splitter_45.glb": "c316183c861e265351448545f651a2dabbbd61307b923c534694c54cc296373b",
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_L.glb": "75247172e1fb1abf14c86ff77f85a36b24a2780531a0a11b7dc6579b366d449b",
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_R.glb": "78f6b2fe9060b1276bf2df97dfa571fba0f046350a90c527ee5df98b7eaf39f2"
}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for path: String in SOURCE_HASHES:
		_expect(sha256(path) == SOURCE_HASHES[path], "source GLB bytes changed: " + path)
	verify_godot_cw_winding_control()
	var models := catalog_models()
	verify_curve(models)
	verify_compact_models(models)
	await verify_demo()
	finish()

func catalog_models() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	_expect(parsed is Dictionary, "custom catalog is not JSON object")
	var models: Dictionary = {}
	if parsed is Dictionary:
		for model: Dictionary in parsed.get("models", []):
			models[String(model.get("id", ""))] = model
	return models

func verify_curve(models: Dictionary) -> void:
	var curve: Dictionary = models.get("Road1_Curve2_Custom45", {})
	_expect(not curve.is_empty(), "missing Curve2 catalog entry")
	var points: Array = curve.get("snap_points", [])
	_expect(points.size() == 2, "Curve2 must expose exactly two endpoints")
	if points.size() == 2:
		var entry := vector(points[0].position)
		var exit := vector(points[1].position)
		_expect(entry.distance_to(Vector3(0, 0, -6)) < 0.0001, "Curve2 entry differs from native Road1 port")
		_expect(exit.distance_to(Vector3(7.02943725, 0, 10.97056275)) < 0.0001, "Curve2 endpoint is not R24 / 45 degrees")
		_expect(vector(points[1].outward).dot(Vector3(0.70710678, 0, 0.70710678)) > 0.99999, "Curve2 exit outward is not 45 degrees")
	var scene := load(String(curve.get("path", ""))) as PackedScene
	_expect(scene != null, "Curve2 generated scene cannot load")
	if scene == null:
		return
	var instance := scene.instantiate() as Node3D
	_expect(meshes_have_normals_and_uvs(instance), "Curve2 mesh lost interpolated normals or UVs")
	_expect(curve_keeps_native_uv_recipe(), "Curve2 generator no longer preserves native 12m UV/dash cadence")
	instance.free()

func curve_keeps_native_uv_recipe() -> bool:
	var script := FileAccess.get_file_as_string("res://scripts/roads/build_custom_roads.gd")
	return script.contains("CURVE_RADIUS := 24.0") and script.contains("CURVE_ANGLE := PI * 0.25") and script.contains("ARC_STEPS := 32") and script.contains("var modules := ceili(length / 12.0)") and script.contains("uvs.append(vertex.uv)") and script.contains("clip_z(triangle, local_start, true)")

func verify_compact_models(models: Dictionary) -> void:
	var road11: Dictionary = models.get("Road11_Y_Splitter_45_Custom", {})
	_expect(not road11.is_empty(), "missing Road11 custom catalog entry")
	if not road11.is_empty():
		_expect(catalog_marker_position(road11, "SouthOuter").distance_to(Vector3(0, 0, 3)) < 0.0001, "Road11 compact stem must end at z=3")
	for id: String in ["Road12_Diagonal_Splitter_L_Custom", "Road12_Diagonal_Splitter_R_Custom"]:
		var model: Dictionary = models.get(id, {})
		_expect(not model.is_empty(), "missing " + id)
		if model.is_empty():
			continue
		var raw := load(String(model.path)) as PackedScene
		_expect(raw != null, id + " generated scene cannot load")
		if raw == null:
			continue
		var visual := raw.instantiate() as Node3D
		_expect(minimum_mesh_y(visual) < -0.014, id + " visual mesh is not lowered to y=-0.015")
		_expect(positive_mesh_bases(visual), id + " has negative-scale visual basis")
		_expect(horizontal_top_winding_is_up(visual), id + " has downward/black horizontal top face")
		_expect(cap_is_12m(visual, "NorthCap"), id + " NorthCap is not one 12m cross-section")
		_expect(cap_is_12m(visual, "DiagonalCap"), id + " DiagonalCap is not one 12m cross-section")
		visual.free()
		var installed := load("res://src/world/roads/items/custom/" + id + "/Default.tscn") as PackedScene
		_expect(installed != null, id + " install scene cannot load")
		if installed != null:
			var module := installed.instantiate() as Node3D
			_expect(all_snap_points_on_install_plane(module), id + " SnapPoints are not y=0")
			_expect(minimum_collision_y(module) < -0.014, id + " collision is not lowered with visual mesh")
			_expect(positive_mesh_bases(module), id + " install scene has negative-scale mesh basis")
			module.free()

func verify_demo() -> void:
	var packed := load(DEMO) as PackedScene
	_expect(packed != null, "compact loop demo cannot load")
	if packed == null:
		return
	var root := packed.instantiate() as Node3D
	get_root().add_child(root)
	await process_frame
	for spec: Dictionary in [
		{"holder": "SmallRight", "exit": "RightOuter", "entry": "south", "corner_exit": "east", "roads": 1},
		{"holder": "SmallLeft", "exit": "LeftOuter", "entry": "east", "corner_exit": "south", "roads": 1},
		{"holder": "LargeLeft", "exit": "DiagonalOuter", "entry": "south", "corner_exit": "east", "roads": 3},
		{"holder": "LargeRight", "exit": "DiagonalOuter", "entry": "east", "corner_exit": "south", "roads": 3}
	]:
		var holder := root.get_node_or_null(String(spec.holder))
		_expect(holder != null, "missing loop " + String(spec.holder))
		if holder != null:
			verify_loop(holder, String(spec.exit), String(spec.entry), String(spec.corner_exit), int(spec.roads))
	root.get_parent().remove_child(root)
	root.free()

func verify_loop(holder: Node, y_exit: String, corner_entry: String, corner_exit: String, roads_per_span: int) -> void:
	var modules: Array[Node] = []
	for child in holder.get_children():
		if child is StaticBody3D:
			modules.append(child)
			_expect(String(child.get_meta("road_id", "")) in ["Road1", "Road10_90angle_Corner", "Road11_Y_Splitter_45_Custom", "Road12_Diagonal_Splitter_L_Custom", "Road12_Diagonal_Splitter_R_Custom"], holder.name + " contains non-approved module")
	_expect(modules.size() == 6 + 4 * roads_per_span, holder.name + " does not contain the finite expected module count")
	if modules.size() != 6 + 4 * roads_per_span:
		return
	var cursor := 0
	var y1 := modules[cursor]; cursor += 1
	var roads1 := modules.slice(cursor, cursor + roads_per_span); cursor += roads_per_span
	var y2 := modules[cursor]; cursor += 1
	var corner1 := modules[cursor]; cursor += 1
	var roads2 := modules.slice(cursor, cursor + roads_per_span); cursor += roads_per_span
	var y3 := modules[cursor]; cursor += 1
	var roads3 := modules.slice(cursor, cursor + roads_per_span); cursor += roads_per_span
	var y4 := modules[cursor]; cursor += 1
	var corner2 := modules[cursor]; cursor += 1
	var roads4 := modules.slice(cursor, cursor + roads_per_span)
	connect_chain(y1, y_exit, roads1, y2, "SouthOuter")
	connect_pair(y2, y_exit, corner1, corner_entry)
	connect_chain(corner1, corner_exit, roads2, y3, "SouthOuter")
	connect_chain(y3, y_exit, roads3, y4, "SouthOuter")
	connect_pair(y4, y_exit, corner2, corner_entry)
	connect_chain(corner2, corner_exit, roads4, y1, "SouthOuter")

func connect_chain(first: Node, first_marker: String, roads: Array, last: Node, last_marker: String) -> void:
	var previous := first
	var marker := first_marker
	for road: Node in roads:
		_expect(String(road.get_meta("road_id", "")) == "Road1", "loop straight is not native 12m Road1")
		connect_pair(previous, marker, road, "south")
		previous = road
		marker = "north"
	connect_pair(previous, marker, last, last_marker)

func connect_pair(first: Node, first_name: String, second: Node, second_name: String) -> void:
	var a := first.get_node_or_null("SnapPoints/" + first_name) as Marker3D
	var b := second.get_node_or_null("SnapPoints/" + second_name) as Marker3D
	_expect(a != null and b != null, "missing marker in continuous loop")
	if a == null or b == null:
		return
	_expect(a.global_position.distance_to(b.global_position) < 0.001, "marker position gap: %s/%s" % [first.name, second.name])
	_expect((-a.global_transform.basis.z).normalized().dot((-b.global_transform.basis.z).normalized()) < -0.9999, "marker direction mismatch: %s/%s" % [first.name, second.name])

func catalog_marker_position(model: Dictionary, name_: String) -> Vector3:
	for marker: Dictionary in model.get("snap_points", []):
		if String(marker.get("name", "")) == name_:
			return vector(marker.position)
	return Vector3.INF

func meshes_have_normals_and_uvs(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty() or (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() != (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() or (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() != (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				return false
	for child in node.get_children():
		if not meshes_have_normals_and_uvs(child): return false
	return true

func cap_is_12m(root: Node, name_: String) -> bool:
	var cap := root.get_node_or_null(name_) as MeshInstance3D
	if cap == null or cap.mesh == null or cap.mesh.get_surface_count() != 1: return false
	var vertices: PackedVector3Array = cap.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() != 4: return false
	var widest := 0.0
	for a in vertices:
		for b in vertices:
			widest = maxf(widest, a.distance_to(b))
	return widest > 12.0 and widest < 12.2

func all_snap_points_on_install_plane(root: Node) -> bool:
	var snaps := root.get_node_or_null("SnapPoints")
	if snaps == null: return false
	for child in snaps.get_children():
		if child is Marker3D and absf(child.position.y) > 0.0001: return false
	return true

func minimum_mesh_y(node: Node) -> float:
	var minimum := INF
	if node is MeshInstance3D and node.mesh != null:
		minimum = (node.transform * node.mesh.get_aabb().position).y
	for child in node.get_children(): minimum = minf(minimum, minimum_mesh_y(child))
	return minimum

func minimum_collision_y(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> float:
	var minimum := INF
	var transform_ := parent_transform
	if node is Node3D: transform_ = parent_transform * node.transform
	if node is CollisionShape3D and node.shape != null:
		minimum = (transform_ * node.shape.get_debug_mesh().get_aabb().position).y
	for child in node.get_children(): minimum = minf(minimum, minimum_collision_y(child, transform_))
	return minimum

func positive_mesh_bases(node: Node) -> bool:
	if node is MeshInstance3D and node.transform.basis.determinant() <= 0.0: return false
	for child in node.get_children():
		if not positive_mesh_bases(child): return false
	return true

func horizontal_top_winding_is_up(node: Node, minimum_height: float = 0.3) -> bool:
	var top_triangles := PackedInt32Array([0])
	return inspect_top_winding(node, top_triangles, minimum_height) and top_triangles[0] > 0

func inspect_top_winding(node: Node, top_triangles: PackedInt32Array, minimum_height: float) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for index in vertices.size():
					indices.append(index)
			for index in range(0, indices.size(), 3):
				var a := vertices[indices[index]]; var b := vertices[indices[index + 1]]; var c := vertices[indices[index + 2]]
				# Godot's front-facing convention is clockwise, not OpenGL's CCW.
				var face := (c - a).cross(b - a).normalized()
				if face.y > 0.9 and a.y > minimum_height and b.y > minimum_height and c.y > minimum_height:
					top_triangles[0] += 1
					if normals.size() <= indices[index + 2]: return false
					var average_normal := (normals[indices[index]] + normals[indices[index + 1]] + normals[indices[index + 2]]).normalized()
					if average_normal.dot(Vector3.UP) < 0.9 or face.dot(average_normal) < 0.9: return false
	for child in node.get_children():
		if not inspect_top_winding(child, top_triangles, minimum_height): return false
	return true

func verify_godot_cw_winding_control() -> void:
	var control := MeshInstance3D.new()
	control.mesh = PlaneMesh.new()
	_expect(horizontal_top_winding_is_up(control, -0.001), "acceptance control: Godot PlaneMesh top must be clockwise/up")
	control.free()

func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func sha256(path: String) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(FileAccess.get_file_as_bytes(path)); return context.finish().hex_encode()

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func finish() -> void:
	if failures.is_empty(): print("custom_final_acceptance: PASS"); quit(0); return
	for failure in failures: push_error(failure)
	quit(1)
