extends SceneTree
## Fresh acceptance: intentionally derives road joins from instantiated Marker3D geometry,
## rather than trusting docs/maps/main-road-layout.json.

const CATALOG := "res://src/world/roads/modules.json"
const MAIN := "res://src/maps/main_battlefield/main_battlefield.tscn"
const DEMOS := ["base_demo", "bridges_demo", "dirt_demo", "highway_demo", "ovaltrack_demo", "parking_demo", "racetrack_demo", "signs_demo", "custom_demo"]
const EPS := 0.001
var failures: Array[String] = []

func _init() -> void:
	if not OS.get_cmdline_user_args().has("--skip-catalog"):
		check_catalog()
	check_demos_round_trip()
	check_main_world()
	if failures.is_empty():
		print("road_rebuild_acceptance: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func check_catalog() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	expect(catalog.has("modules") and catalog.modules.size() >= 583, "catalog has fewer than 583 modules")
	for entry: Dictionary in catalog.get("modules", []):
		var path := String(entry.get("path", ""))
		var packed := load(path) as PackedScene
		expect(packed != null, "catalog path does not load: " + path)
		if packed == null:
			continue
		var root := packed.instantiate()
		expect(root is StaticBody3D, "road root is not StaticBody3D: " + path)
		var visual := first_mesh(root)
		var collision := first_collision(root)
		expect(visual != null and visual.mesh != null, "missing visual mesh: " + path)
		expect(collision != null and collision.shape is ConcavePolygonShape3D, "missing trimesh collision: " + path)
		if visual != null and collision != null:
			expect(visual.transform.origin.distance_to(collision.transform.origin) < EPS, "visual/collision transforms diverge: " + path)
		root.free()

func check_demos_round_trip() -> void:
	for demo: String in DEMOS:
		var path := "res://src/samples/roads/%s.tscn" % demo
		var packed := load(path) as PackedScene
		expect(packed != null, "demo does not load: " + path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		var temp := "/tmp/road-acceptance-%s.tscn" % demo
		var saved := PackedScene.new()
		expect(saved.pack(instance) == OK and ResourceSaver.save(saved, temp) == OK, "cannot save demo: " + demo)
		var reloaded := load(temp) as PackedScene
		expect(reloaded != null, "cannot reload demo: " + demo)
		if reloaded != null:
			var restored := reloaded.instantiate()
			expect(node_signature(instance) == node_signature(restored), "round-trip loses nodes: " + demo)
			expect(all_owned(restored), "reloaded tree has unowned node: " + demo)
			restored.free()
		instance.free()

func check_main_world() -> void:
	var main_path := candidate_path()
	var packed := load(main_path) as PackedScene
	expect(packed != null, "main battlefield does not load")
	if packed == null:
		return
	var world := packed.instantiate() as Node3D
	get_root().add_child(world)
	var roads := world.get_node_or_null("Roads") as Node3D
	var ground := world.get_node_or_null("Ground/Visual") as MeshInstance3D
	expect(roads != null, "main map has no Roads")
	expect(ground != null and ground.mesh is BoxMesh and is_equal_approx((ground.mesh as BoxMesh).size.x, 1920.0), "floor is not 1920m")
	expect(world.find_child("GapNotes", true, false) == null and world.find_child("Label3D", true, false) == null, "map retains GapNotes/label helpers")
	if roads == null:
		world.queue_free()
		return
	var junctions := roads.get_node_or_null("Junctions") as Node3D
	var connections := roads.get_node_or_null("Connections") as Node3D
	expect(junctions != null and junctions.get_child_count() == 52, "expected 52 junctions")
	expect(connections != null and connections.get_child_count() == 148, "expected 148 connection segments")
	if junctions != null and connections != null:
		var jports := marker_positions(junctions)
		var groups := connection_groups(connections)
		expect(groups.size() == 72, "expected 72 logical connections")
		check_connection_geometry(groups, jports)
		check_connected(groups)
		check_half_turn_symmetry(junctions, connections)
		check_clearance(junctions)
		check_side_cross_links(junctions, groups)
		for pair: Array in [["D1__T", Vector3(84, 0.03, -66)], ["Mirror_D1__T", Vector3(-84, 0.03, 66)]]:
			var bend_join := junctions.get_node_or_null(pair[0]) as Node3D
			expect(bend_join != null, "missing enlarged inner-bend T: " + str(pair[0]))
			if bend_join != null:
				expect(bend_join.position.distance_to(pair[1]) < EPS, "inner bend was not moved inward by 6m: " + str(pair[0]))
		for id: String in ["UL1", "UL4", "Mirror_UL1", "Mirror_UL4"]:
			expect(junctions.has_node(id + "__Corner90"), "U turn requires fixed native 90-degree corners: " + id)
		for id: String in ["UL1_to_UL4", "Mirror_UL1_to_Mirror_UL4"]:
			expect(groups.has(id), "U turn requires one straight crown: " + id)
		for id: String in ["UL2", "UL3", "Mirror_UL2", "Mirror_UL3"]:
			for junction in junctions.get_children():
				expect(not str(junction.name).begins_with(id + "__"), "obsolete diagonal U bend remains: " + id)
	world.queue_free()

func check_side_cross_links(junctions: Node3D, groups: Dictionary) -> void:
	for name_: String in ["L1__Y", "Mirror_L1__Y", "LJoin__T", "Mirror_LJoin__T"]:
		var junction := junctions.get_node_or_null(name_)
		expect(junction != null, "missing green-line three-way junction: " + name_)
		if junction != null:
			expect(marker_positions(junction).size() == 3, "junction must have three actual ports: " + name_)
	for id: String in ["RI", "RM", "Mirror_RI", "LM"]:
		expect(junctions.has_node(id + "__T"), "red-link removal must restore original inner T: " + id)
	for id: String in ["L1_to_LJoin", "Mirror_L1_to_Mirror_LJoin"]:
		expect(groups.has(id), "missing green-line connection at outer bend: " + id)
	for id: String in ["RI_to_RUpper", "RM_to_R2", "Mirror_RI_to_Mirror_RUpper", "LM_to_L2"]:
		expect(not groups.has(id), "red-marked connection must be removed: " + id)

func check_connection_geometry(groups: Dictionary, junction_ports: Array[Vector3]) -> void:
	for id: String in groups:
		var pieces: Array = groups[id]
		pieces.sort_custom(func(a: Node3D, b: Node3D): return a.name.naturalnocasecmp_to(b.name) < 0)
		var endpoints: Array[Vector3] = []
		for piece: Node3D in pieces:
			var points := marker_positions(piece)
			expect(points.size() == 2, "segment lacks two real snap markers: " + piece.name)
			if points.size() == 2:
				endpoints.append_array(points)
		if endpoints.size() < 2:
			continue
		var outer := unmatched_endpoints(endpoints)
		expect(outer.size() == 2, "segments do not form a single chain: " + id)
		if outer.size() == 2:
			expect(nearest_distance(outer[0], junction_ports) < EPS and nearest_distance(outer[1], junction_ports) < EPS, "connection endpoints do not meet junction geometry: " + id)
			var delta := outer[1] - outer[0]
			expect(absf(delta.x) < EPS or absf(delta.z) < EPS or absf(absf(delta.x) - absf(delta.z)) < EPS, "connection is not horizontal, vertical, or 45 degrees: " + id)

func check_connected(groups: Dictionary) -> void:
	var graph: Dictionary = {}
	for id: String in groups:
		var split := id.split("_to_")
		if split.size() != 2:
			continue
		for pair in [[split[0], split[1]], [split[1], split[0]]]:
			if not graph.has(pair[0]): graph[pair[0]] = []
			graph[pair[0]].append(pair[1])
	var seen: Dictionary = {}
	var todo: Array = [String(graph.keys()[0])] if not graph.is_empty() else []
	while not todo.is_empty():
		var current: String = todo.pop_back()
		if seen.has(current): continue
		seen[current] = true
		for next: String in graph.get(current, []): todo.append(next)
	expect(seen.size() == 52, "road graph is not fully connected")

func check_half_turn_symmetry(junctions: Node3D, connections: Node3D) -> void:
	var all: Array = []
	all.append_array(junctions.get_children())
	all.append_array(connections.get_children())
	for node: Node3D in all:
		var expected_points: Array[Vector3] = []
		for point in marker_positions(node): expected_points.append(Vector3(-point.x, point.y, -point.z))
		var matched := false
		for candidate: Node3D in all:
			if point_sets_match(expected_points, marker_positions(candidate)):
				matched = true
				break
		expect(matched, "no 180-degree snap-geometry counterpart for: " + node.name)

func check_clearance(junctions: Node3D) -> void:
	var found_center_spacing := false
	for first: Node3D in junctions.get_children():
		for second: Node3D in junctions.get_children():
			var delta := first.position - second.position
			if (absf(delta.x) < EPS and is_equal_approx(absf(delta.z), 27.92)) or (absf(delta.z) < EPS and is_equal_approx(absf(delta.x), 27.92)):
				found_center_spacing = true
	expect(found_center_spacing, "no 27.92m parallel centerline spacing (12m road + 15.92m clearance)")

func candidate_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate="):
			return argument.trim_prefix("--candidate=")
	return MAIN

func marker_positions(root: Node) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for marker: Marker3D in root.find_children("*", "Marker3D", true, false): result.append(transform_from_root(marker))
	return result

func transform_from_root(node: Node3D) -> Vector3:
	var transform_ := Transform3D.IDENTITY
	var current: Node = node
	while current is Node3D:
		transform_ = (current as Node3D).transform * transform_
		current = current.get_parent()
	return transform_.origin

func point_sets_match(first: Array[Vector3], second: Array[Vector3]) -> bool:
	if first.size() != second.size() or first.is_empty(): return false
	for point in first:
		if nearest_distance(point, second) >= EPS: return false
	return true

func connection_groups(connections: Node3D) -> Dictionary:
	var result := {}
	for child: Node3D in connections.get_children():
		var cut := child.name.rfind("_")
		var id := child.name.left(cut)
		if not result.has(id): result[id] = []
		result[id].append(child)
	return result

func unmatched_endpoints(points: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in points:
		var count := 0
		for other in points:
			if point.distance_to(other) < EPS: count += 1
		if count == 1: result.append(point)
	return result

func nearest_distance(point: Vector3, others: Array[Vector3]) -> float:
	var nearest := INF
	for other in others: nearest = minf(nearest, point.distance_to(other))
	return nearest

func first_mesh(root: Node) -> MeshInstance3D:
	var found := root.find_children("*", "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null

func first_collision(root: Node) -> CollisionShape3D:
	var found := root.find_children("*", "CollisionShape3D", true, false)
	return found[0] as CollisionShape3D if not found.is_empty() else null

func node_signature(root: Node) -> Array[String]:
	var result: Array[String] = []
	for node in [root] + root.find_children("*", "", true, false): result.append(root.get_path_to(node).get_concatenated_names() + ":" + node.get_class())
	result.sort()
	return result

func all_owned(node: Node) -> bool:
	for child in node.get_children():
		if child.owner == null or not all_owned(child): return false
	return true

func basis_error(a: Basis, b: Basis) -> float:
	return maxf((a.x - b.x).length(), maxf((a.y - b.y).length(), (a.z - b.z).length()))

func expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
