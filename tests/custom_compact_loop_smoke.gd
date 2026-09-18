extends SceneTree

const DEMO := "res://src/samples/roads/compact_loop_demo.tscn"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := load(DEMO) as PackedScene
	_expect(scene != null, "compact loop demo must load")
	if scene == null:
		finish()
		return
	var root := scene.instantiate() as Node3D
	get_root().add_child(root)
	await process_frame
	verify_loop(root.get_node("SmallRight"), "RightOuter", "south", "east", 1)
	verify_loop(root.get_node("SmallLeft"), "LeftOuter", "east", "south", 1)
	verify_loop(root.get_node("LargeLeft"), "DiagonalOuter", "south", "east", 3)
	verify_loop(root.get_node("LargeRight"), "DiagonalOuter", "east", "south", 3)
	root.get_parent().remove_child(root)
	root.free()
	finish()

func verify_loop(holder: Node, y_exit: String, corner_entry: String, corner_exit: String, roads_per_span: int) -> void:
	var modules: Array[Node] = []
	for child in holder.get_children():
		if child is StaticBody3D:
			modules.append(child)
	_expect(modules.size() == 6 + 4 * roads_per_span, holder.name + " unexpected module count")
	var cursor := 0
	var first_y: Node = modules[cursor]; cursor += 1
	var first_roads := modules.slice(cursor, cursor + roads_per_span); cursor += roads_per_span
	var second_y: Node = modules[cursor]; cursor += 1
	var first_corner: Node = modules[cursor]; cursor += 1
	var second_roads := modules.slice(cursor, cursor + roads_per_span); cursor += roads_per_span
	var third_y: Node = modules[cursor]; cursor += 1
	var third_roads := modules.slice(cursor, cursor + roads_per_span); cursor += roads_per_span
	var fourth_y: Node = modules[cursor]; cursor += 1
	var second_corner: Node = modules[cursor]; cursor += 1
	var fourth_roads := modules.slice(cursor, cursor + roads_per_span)
	connect_chain(first_y, y_exit, first_roads, second_y, "SouthOuter")
	connect_pair(second_y, y_exit, first_corner, corner_entry)
	connect_chain(first_corner, corner_exit, second_roads, third_y, "SouthOuter")
	connect_chain(third_y, y_exit, third_roads, fourth_y, "SouthOuter")
	connect_pair(fourth_y, y_exit, second_corner, corner_entry)
	connect_chain(second_corner, corner_exit, fourth_roads, first_y, "SouthOuter")

func connect_chain(start: Node, start_marker: String, roads: Array, finish: Node, finish_marker: String) -> void:
	var previous := start
	var previous_marker := start_marker
	for road: Node in roads:
		connect_pair(previous, previous_marker, road, "south")
		previous = road
		previous_marker = "north"
	connect_pair(previous, previous_marker, finish, finish_marker)

func connect_pair(first: Node, first_name: String, second: Node, second_name: String) -> void:
	var a := first.get_node("SnapPoints/" + first_name) as Marker3D
	var b := second.get_node("SnapPoints/" + second_name) as Marker3D
	_expect(a != null and b != null, "missing snap marker")
	_expect(a.global_position.distance_to(b.global_position) < 0.001, "snap position gap %s/%s" % [first.name, second.name])
	var outward_a := -a.global_transform.basis.z.normalized()
	var outward_b := -b.global_transform.basis.z.normalized()
	_expect(outward_a.dot(outward_b) < -0.9999, "snap direction mismatch %s/%s" % [first.name, second.name])

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func finish() -> void:
	if failures.is_empty():
		print("custom_compact_loop_smoke: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
