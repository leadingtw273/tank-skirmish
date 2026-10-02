extends SceneTree
## Read-only mesh inspector for validating the authored road-port data.

const MODELS := [
	"Road1", "Road1_Curve1", "Road1_Curve2", "Road1_Curve3", "Road1_Curve4",
	"Road2_T", "Road2_X", "Road6_End", "Road10_90angle_Corner",
	"Road11_Y_Splitter", "Road11_Y_Splitter_45", "Road12_Diagonal_Splitter_R",
	"Road12_Diagonal_Splitter_L",
]
const BASE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/"
const CROSSING := "res://assets/AtomicRealmModularRoads/parking/PLUS/gltf/Road3_Crossing.glb"

func _initialize() -> void:
	for model: String in MODELS:
		inspect(model, BASE + model + ".glb")
	inspect("Road3_Crossing", CROSSING)
	quit()

func inspect(model: String, path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Cannot load " + path)
		return
	var root := scene.instantiate()
	var vertices: Array[Vector3] = []
	collect_vertices(root, Transform3D.IDENTITY, vertices)
	var points := PackedVector3Array(vertices)
	var aabb := AABB()
	for point: Vector3 in points:
		aabb = aabb.expand(point)
	print("PORT_INSPECT %s aabb=%s vertices=%d" % [model, aabb, points.size()])
	for point: Vector3 in edge_centres(points, aabb):
		print("PORT_EDGE %s %s" % [model, point])
	root.queue_free()

func collect_vertices(node: Node, parent_transform: Transform3D, output: Array[Vector3]) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh:
			for surface: int in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					output.append(transform * vertex)
	for child: Node in node.get_children():
		collect_vertices(child, transform, output)

func edge_centres(points: PackedVector3Array, aabb: AABB) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var limits := [aabb.position.x, aabb.end.x, aabb.position.z, aabb.end.z]
	for limit: float in limits:
		var sum := Vector3.ZERO
		var count := 0
		for point: Vector3 in points:
			var coordinate := point.x if limit == limits[0] or limit == limits[1] else point.z
			if is_equal_approx(coordinate, limit):
				sum += point
				count += 1
		if count > 0:
			result.append(sum / count)
	return result
