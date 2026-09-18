extends SceneTree
## Reconstruct a connected, centrally symmetric street graph from the reference.
const OUT := "res://src/world/roads/generated/fit"
const MAIN := "res://src/maps/main_battlefield/main_battlefield.tscn"
const MODULES := "res://src/world/roads/items/"
const SOURCE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road1.glb"
const ROAD1_A := "res://assets/AtomicRealmModularRoads/base/PLUS/Road1_A.png"
var nodes: Dictionary = {}
var edges: Array[Array] = []
var ports: Dictionary = {}
var templates: Array[Dictionary] = []
var failures: Array[String] = []
var connection_evidence: Array[Dictionary] = []
var fit_cache: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	make_graph()
	make_templates()
	var world := load(MAIN).instantiate() as Node3D
	var roads := world.get_node("Roads") as Node3D
	var destination := MAIN
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 2 and arguments[0] == "--output":
		destination = arguments[1]
	if roads.get_child_count() != 0:
		if destination == MAIN or FileAccess.file_exists(destination):
			push_error("Refusing to overwrite populated Roads; use --output with a new candidate path")
			world.free()
			quit(1)
			return
		for child: Node in roads.get_children():
			child.free()
	world.get_node("Ground").position = Vector3(0, -0.1, 0)
	var junctions := Node3D.new()
	junctions.name = "Junctions"
	roads.add_child(junctions)
	junctions.owner = world
	var connections := Node3D.new()
	connections.name = "Connections"
	roads.add_child(connections)
	connections.owner = world
	for id: String in nodes:
		place_junction(id, junctions, world)
	if failures.is_empty():
		for edge: Array in edges:
			place_connection(edge, connections, world)
	if not failures.is_empty():
		for message: String in failures:
			push_error(message)
		world.free()
		quit(1)
		return
	var scene := PackedScene.new()
	scene.pack(world)
	ResourceSaver.save(scene, destination)
	var evidence := {"reconstruction": "reference-derived approximation, not recovered original transforms", "nodes": {}, "edges": edges, "connections": connection_evidence, "road_width_m": 12.0, "side_passage_clearance_m": 15.92, "original_clearance_m": 7.96}
	for id: String in nodes:
		evidence.nodes[id] = [nodes[id].x, nodes[id].z]
	var evidence_path := "res://docs/maps/main-road-layout.json" if destination == MAIN else destination.get_basename() + "-layout.json"
	var file := FileAccess.open(evidence_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t") + "\n")
	print("MAIN_ROADS_BUILT junctions=%d connections=%d segments=%d clearance=15.92" % [nodes.size(), edges.size(), connections.get_child_count()])
	world.free()
	quit(0)

func make_graph() -> void:
	# Metres. Original screenshot supplies topology, dimensions are reconstructed.
	# Parallel centre spacing 27.92 = 12m road + 2 * original 7.96m clear space.
	var upper := {
		"UL0": Vector3(-132, 0, -72), "UL1": Vector3(-132, 0, -114),
		"UL2": Vector3(-114, 0, -132), "UL3": Vector3(-96, 0, -132),
		"UL4": Vector3(-84, 0, -120), "G0": Vector3(-84, 0, -96),
		"G1": Vector3(-48, 0, -96), "G2": Vector3(0, 0, -96),
		"G3": Vector3(36, 0, -96), "G4": Vector3(84, 0, -96),
		"R0": Vector3(84, 0, -48), "R1": Vector3(111.92, 0, -48),
		"R2": Vector3(111.92, 0, 0), "RI": Vector3(84, 0, -24), "RM": Vector3(84, 0, 0),
		"D0": Vector3(60, 0, -72), "D1": Vector3(84, 0, -72),
		"H0": Vector3(-84, 0, -72), "H1": Vector3(-48, 0, -72), "H2": Vector3(0, 0, -72),
		"L0": Vector3(-132, 0, -54), "L1": Vector3(-111.92, 0, -33.92),
		"L2": Vector3(-111.92, 0, 0), "LI": Vector3(-84, 0, -24), "LM": Vector3(-84, 0, 0),
		"N": Vector3(0, 0, -48), "NW": Vector3(-24, 0, -24), "NE": Vector3(24, 0, -24),
		"W": Vector3(-48, 0, 0), "E": Vector3(48, 0, 0)
	}
	var upper_edges: Array[Array] = [
		["UL0", "UL1"], ["UL1", "UL2"], ["UL2", "UL3"], ["UL3", "UL4"], ["UL4", "G0"],
		["G0", "G1"], ["G1", "G2"], ["G2", "G3"], ["G3", "G4"], ["G4", "D1"],
		["G3", "D0"], ["D0", "D1"], ["D1", "R0"], ["R0", "R1"], ["R1", "R2"],
		["R0", "RI"], ["RI", "RM"], ["UL0", "H0"], ["H0", "H1"], ["H1", "H2"],
		["G0", "H0"], ["G1", "H1"], ["G2", "H2"], ["H2", "N"],
		["UL0", "L0"], ["L0", "L1"], ["L1", "L2"], ["H0", "LI"], ["LI", "LM"],
		["LI", "NW"], ["RI", "NE"], ["N", "NW"], ["N", "NE"], ["NW", "W"], ["NE", "E"],
		["W", "LM"], ["E", "RM"]
	]
	for id: String in upper:
		nodes[id] = upper[id]
	var mirrors: Dictionary = {}
	for id: String in upper:
		var opposite: Vector3 = -upper[id]
		var existing := ""
		for candidate: String in nodes:
			if nodes[candidate].distance_to(opposite) < 0.001:
				existing = candidate
				break
		if existing.is_empty():
			existing = "Mirror_" + id
			nodes[existing] = opposite
		mirrors[id] = existing
	for edge: Array in upper_edges:
		add_edge(edge[0], edge[1])
		add_edge(mirrors[edge[0]], mirrors[edge[1]])

func add_edge(a: String, b: String) -> void:
	for old: Array in edges:
		if old.has(a) and old.has(b):
			return
	edges.append([a, b])

func make_templates() -> void:
	templates = [
		template("Road1", "base/Road1", Vector3.ZERO, [Vector3(0, 0, -6), Vector3(0, 0, 6)], [Vector3.FORWARD, Vector3.BACK]),
		template("Cross", "base/Road2_X", Vector3.ZERO, [Vector3(0, 0, -6), Vector3(0, 0, 6), Vector3(-6, 0, 0), Vector3(6, 0, 0)], [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]),
		template("T", "base/Road2_T", Vector3.ZERO, [Vector3(0, 0, -6), Vector3(-6, 0, 0), Vector3(6, 0, 0)], [Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]),
		template("Corner90", "base/Road10_90angle_Corner", Vector3.ZERO, [Vector3(0, 0, -6), Vector3(6, 0, 0)], [Vector3.FORWARD, Vector3.RIGHT]),
		template("Curve45", "base/Road1_Curve1", Vector3(0, 0, 0.48528), [Vector3(0, 0, -6), Vector3(5.75736, 0, 6.24264)], [Vector3.FORWARD, Vector3(1, 0, 1).normalized()]),
		custom_template("Y", "Road11_Y_Splitter_45_Custom", ["SouthOuter", "LeftOuter", "RightOuter"]),
		custom_template("SplitL", "Road12_Diagonal_Splitter_L_Custom", ["SouthOuter", "NorthOuter", "DiagonalOuter"]),
		custom_template("SplitR", "Road12_Diagonal_Splitter_R_Custom", ["SouthOuter", "NorthOuter", "DiagonalOuter"])
	]

func custom_template(id: String, model_id: String, names: Array) -> Dictionary:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/world/roads/custom_catalog.json"))
	for model: Dictionary in catalog.models:
		if String(model.id) != model_id:
			continue
		var points: Array = []
		var directions: Array = []
		for name_: String in names:
			for port: Dictionary in model.snap_points:
				if String(port.name) == name_:
					points.append(Vector3(port.position[0], port.position[1], port.position[2]))
					directions.append(Vector3(port.outward[0], port.outward[1], port.outward[2]))
		var pivot := Vector3(0, 0, 9)
		if id != "Y":
			# Intersection of the actual diagonal centreline and the vertical stem.
			pivot = Vector3(0, 0, points[2].z - points[2].x * directions[2].z / directions[2].x)
		return template(id, "custom/" + model_id, pivot, points, directions)
	assert(false, "Missing custom model " + model_id)
	return {}

func template(id: String, path: String, pivot: Vector3, points: Array, directions: Array) -> Dictionary:
	var scene_path := MODULES + path + "/Default.tscn"
	for variant: String in ["Road1_B__Road1_A", "Road2_X_B__Road2_X_A"]:
		var alternative := MODULES + path + "/" + variant + ".tscn"
		if FileAccess.file_exists(alternative):
			scene_path = alternative
			break
	return {"id": id, "path": scene_path, "pivot": pivot, "points": points, "directions": directions}

func place_junction(id: String, holder: Node3D, world: Node3D) -> void:
	var neighbors: Array[String] = []
	for edge: Array in edges:
		if edge[0] == id:
			neighbors.append(edge[1])
		elif edge[1] == id:
			neighbors.append(edge[0])
	for candidate: Dictionary in templates:
		if candidate.directions.size() != neighbors.size():
			continue
		for step: int in 8:
			var rotation_ := Basis(Vector3.UP, float(step) * PI / 4.0)
			var matched: Dictionary = {}
			for neighbor: String in neighbors:
				var direction: Vector3 = (nodes[neighbor] - nodes[id]).normalized()
				for index: int in candidate.directions.size():
					if direction.dot(rotation_ * candidate.directions[index]) > 0.99999:
						matched[neighbor] = nodes[id] + rotation_ * (candidate.points[index] - candidate.pivot)
			if matched.size() == neighbors.size():
				var module := load(String(candidate.path)).instantiate() as Node3D
				module.name = id + "__" + String(candidate.id)
				module.transform = Transform3D(rotation_, nodes[id] - rotation_ * candidate.pivot + Vector3(0, 0.03, 0))
				holder.add_child(module)
				module.owner = world
				ports[id] = matched
				return
	failures.append("No compatible junction %s degree=%d at %s" % [id, neighbors.size(), str(nodes[id])])

func place_connection(edge: Array, holder: Node3D, world: Node3D) -> void:
	var a: Vector3 = ports[edge[0]][edge[1]]
	var b: Vector3 = ports[edge[1]][edge[0]]
	var direction: Vector3 = (nodes[edge[1]] - nodes[edge[0]]).normalized()
	var length: float = (b - a).dot(direction)
	if length < -0.001 or (b - a - direction * length).length() > 0.001:
		failures.append("Overlapping or off-axis stubs " + str(edge) + " gap=" + str(length))
		return
	var remaining := length
	var walked := 0.0
	var index := 0
	while remaining > 0.001:
		var segment := minf(12, remaining)
		var path := MODULES + "base/Road1/Road1_B__Road1_A.tscn" if absf(segment - 12) < 0.001 else make_fit(segment)
		var road := load(path).instantiate() as Node3D
		road.name = "%s_to_%s_%02d" % [edge[0], edge[1], index]
		road.basis = Basis.looking_at(-direction, Vector3.UP)
		road.position = a + direction * (walked + segment / 2) + Vector3(0, 0.03, 0)
		holder.add_child(road)
		road.owner = world
		remaining -= segment
		walked += segment
		index += 1
	connection_evidence.append({"from": edge[0], "to": edge[1], "length_m": length, "end_error_m": absf(walked - length), "segments": index})

func make_fit(length: float) -> String:
	var key := "%0.5f" % length
	if fit_cache.has(key):
		return fit_cache[key]
	var root_ := StaticBody3D.new()
	root_.name = "Road1_Fit"
	root_.set_meta("road_module", true)
	root_.set_meta("fit_length_m", length)
	var source := load(SOURCE).instantiate() as Node3D
	var mesh_node := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := ArrayMesh.new()
	for surface: int in mesh_node.mesh.get_surface_count():
		var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i: int in positions.size():
				indices.append(i)
		var out_positions := PackedVector3Array()
		var out_normals := PackedVector3Array()
		var out_uvs := PackedVector2Array()
		for triangle: int in range(0, indices.size(), 3):
			var polygon: Array[Dictionary] = []
			for j: int in 3:
				var idx: int = indices[triangle + j]
				polygon.append({"p": positions[idx], "n": normals[idx], "uv": uvs[idx]})
			polygon = clip_end(polygon, -6 + length)
			for fan: int in range(1, polygon.size() - 1):
				for vertex: Dictionary in [polygon[0], polygon[fan], polygon[fan + 1]]:
					out_positions.append(vertex.p + Vector3(0, 0, 6 - length / 2))
					out_normals.append(vertex.n)
					out_uvs.append(vertex.uv)
		if out_positions.is_empty():
			continue
		var output: Array = []
		output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = out_positions
		output[Mesh.ARRAY_NORMAL] = out_normals
		output[Mesh.ARRAY_TEX_UV] = out_uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output)
		var material := mesh_node.get_active_material(surface).duplicate() as StandardMaterial3D
		material.albedo_texture = load(ROAD1_A)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	root_.add_child(visual)
	visual.owner = root_
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = mesh.create_trimesh_shape()
	root_.add_child(collision)
	collision.owner = root_
	var snap := Node3D.new()
	snap.name = "SnapPoints"
	root_.add_child(snap)
	snap.owner = root_
	for sign_: int in [-1, 1]:
		var marker := Marker3D.new()
		marker.name = "North" if sign_ < 0 else "South"
		marker.position.z = sign_ * length / 2
		marker.basis = Basis.looking_at(Vector3(0, 0, sign_), Vector3.UP)
		snap.add_child(marker)
		marker.owner = root_
	var scene := PackedScene.new()
	scene.pack(root_)
	var path := OUT + "/road1_%s.tscn" % key.replace(".", "_")
	ResourceSaver.save(scene, path)
	fit_cache[key] = path
	root_.free()
	source.free()
	return path

func clip_end(polygon: Array[Dictionary], end: float) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var previous: Dictionary = polygon[-1]
	for current: Dictionary in polygon:
		var pin: bool = previous.p.z <= end + 0.00001
		var cin: bool = current.p.z <= end + 0.00001
		if pin != cin:
			var t: float = (end - previous.p.z) / (current.p.z - previous.p.z)
			output.append({"p": previous.p.lerp(current.p, t), "n": previous.n.lerp(current.n, t).normalized(), "uv": previous.uv.lerp(current.uv, t)})
		if cin:
			output.append(current)
		previous = current
	return output
