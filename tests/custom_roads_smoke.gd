extends SceneTree

const CATALOG := "res://src/world/roads/custom_catalog.json"
const EXPECTED_HASHES := {
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road1.glb": "3931ec0bfed31802f77447ed9c34e75393a18494078daac3c2fe8ec079f4245f",
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road11_Y_Splitter_45.glb": "c316183c861e265351448545f651a2dabbbd61307b923c534694c54cc296373b",
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_L.glb": "75247172e1fb1abf14c86ff77f85a36b24a2780531a0a11b7dc6579b366d449b",
	"res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road12_Diagonal_Splitter_R.glb": "78f6b2fe9060b1276bf2df97dfa571fba0f046350a90c527ee5df98b7eaf39f2"
}
var failures: Array[String] = []

func _init() -> void:
	for path: String in EXPECTED_HASHES:
		_expect(sha256(path) == EXPECTED_HASHES[path], "source hash changed: " + path)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	_expect(catalog.models.size() == 4, "expected Curve2, Road11, Road12 L and Road12 R")
	var models: Dictionary = {}
	for model: Dictionary in catalog.models:
		models[model.id] = model
		var scene := load(String(model.path)) as PackedScene
		_expect(scene != null, "custom scene fails to load: " + String(model.path))
		var instance := scene.instantiate() as Node3D
		_expect(not instance.get_children().is_empty(), "custom scene has no visual mesh")
		_expect(not has_collision(instance), "custom model must leave collision generation to the root builder")
		_expect(positive_mesh_bases(instance), "wrapper has negative-scale mesh basis")
		instance.free()
	var curve: Dictionary = models["Road1_Curve2_Custom45"]
	var exit: Dictionary = curve.snap_points[1]
	_expect(Vector3(exit.position[0], exit.position[1], exit.position[2]).distance_to(Vector3(7.02943725, 0, 10.97056275)) < 0.0001, "Curve2 exit is not the R24 analytic endpoint")
	_expect(Vector3(exit.outward[0], exit.outward[1], exit.outward[2]).dot(Vector3(0.7071068, 0, 0.7071068)) > 0.99999, "Curve2 exit is not 45 degrees")
	for id: String in ["Road12_Diagonal_Splitter_L_Custom", "Road12_Diagonal_Splitter_R_Custom"]:
		var points: Array = models[id].snap_points
		_expect(points.size() == 5, id + " must retain outer and inner ports")
		for point: Dictionary in points:
			_expect(is_zero_approx(float(point.position[1])), id + " snap must remain on the y=0 installation plane")
		var scene := load(String(models[id].path)) as PackedScene
		var instance := scene.instantiate() as Node3D
		_expect(minimum_mesh_y(instance) < -0.014, id + " visual mesh must retain the intentional y=-0.015 lowering")
		if id == "Road12_Diagonal_Splitter_R_Custom":
			_expect(horizontal_top_winding_is_up(instance), "Road12 R horizontal top faces must retain upward winding and normals")
		instance.free()
	_expect(is_equal_approx(float(models["Road11_Y_Splitter_45_Custom"].snap_points[0].position[2]), 3.0), "Road11 compact stem snap must be z=3")
	finish()

func sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()

func has_collision(node: Node) -> bool:
	if node is CollisionShape3D:
		return true
	for child in node.get_children():
		if has_collision(child):
			return true
	return false

func positive_mesh_bases(node: Node) -> bool:
	if node is MeshInstance3D and node.transform.basis.determinant() <= 0.0:
		return false
	for child in node.get_children():
		if not positive_mesh_bases(child):
			return false
	return true

func minimum_mesh_y(node: Node) -> float:
	var minimum := INF
	if node is MeshInstance3D and node.mesh != null:
		var mesh_minimum: Vector3 = node.transform * node.mesh.get_aabb().position
		minimum = mesh_minimum.y
	for child in node.get_children():
		minimum = minf(minimum, minimum_mesh_y(child))
	return minimum

func horizontal_top_winding_is_up(node: Node) -> bool:
	var stats := PackedInt32Array([0, 0, 0]) # up-facing, down-facing, normal mismatch
	var valid := inspect_top_winding(node, stats)
	print("Road12R_TOP_WINDING up=%d down=%d mismatch=%d" % [stats[0], stats[1], stats[2]])
	return valid and stats[0] > 0 and stats[2] == 0

func inspect_top_winding(node: Node, stats: PackedInt32Array) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				vertices = arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				normals = arrays[Mesh.ARRAY_NORMAL]
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for index in vertices.size():
					indices.append(index)
			for index in range(0, indices.size(), 3):
				var a := vertices[indices[index]]
				var b := vertices[indices[index + 1]]
				var c := vertices[indices[index + 2]]
				var face := (c - a).cross(b - a).normalized()
				if absf(face.y) > 0.9:
					if face.y > 0.0:
						stats[0] += 1
					else:
						stats[1] += 1
					if normals.size() <= indices[index + 2]:
						return false
					var average_normal := (normals[indices[index]] + normals[indices[index + 1]] + normals[indices[index + 2]]).normalized()
					if face.y > 0.0 and (average_normal.dot(Vector3.UP) < 0.9 or face.dot(average_normal) < 0.9):
						stats[2] += 1
	for child in node.get_children():
		if not inspect_top_winding(child, stats):
			return false
	return true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func finish() -> void:
	if failures.is_empty():
		print("custom_roads_smoke: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
