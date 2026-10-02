extends SceneTree

const CATALOG := "res://src/world/buildings/quaternius/catalog.json"
const SAMPLE_ROOT := "res://src/samples/buildings"
const EXPECTED := {"finished": 312, "base": 216, "parts": 384, "materials": 26}
const DEMOS := {"full_pack": 102, "finished": 312, "base": 216, "parts": 384, "materials": 26, "2story_wide_colors": 13}
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not parsed is Dictionary or not parsed.get("modules") is Array:
		failures.append("Missing generated building catalog")
	else:
		var counts := {}
		for entry: Dictionary in parsed.modules:
			var group: String = String(entry.get("group", "")); counts[group] = int(counts.get(group, 0)) + 1
			var packed: PackedScene = load(String(entry.get("path", ""))) as PackedScene
			if packed == null: failures.append("Missing wrapper: " + String(entry.get("path", ""))); continue
			var body: StaticBody3D = packed.instantiate() as StaticBody3D
			if body == null or count_nodes(body, "CollisionShape3D") == 0 or count_nodes(body, "MeshInstance3D") == 0:
				failures.append("Wrapper lacks model or trimesh collision: " + String(entry.get("path", "")))
			elif not every_collision_is_trimesh(body): failures.append("Wrapper lacks ConcavePolygonShape3D: " + String(entry.get("path", "")))
			if body != null: body.free()
		for group: String in EXPECTED:
			if int(counts.get(group, 0)) != int(EXPECTED[group]): failures.append("%s expected %d modules, got %d" % [group, EXPECTED[group], counts.get(group, 0)])
	for demo: String in DEMOS:
		var packed: PackedScene = load(SAMPLE_ROOT.path_join(demo + "_demo.tscn")) as PackedScene
		if packed == null: failures.append("Missing demo: " + demo); continue
		var root: Node3D = packed.instantiate() as Node3D
		var models: Node3D = root.get_node_or_null("Models") as Node3D
		if models == null or models.get_child_count() != int(DEMOS[demo]): failures.append("%s expected %d model references" % [demo, DEMOS[demo]])
		root.free()
	var tanks: PackedScene = load("res://src/samples/tanks/tank_variants_demo.tscn") as PackedScene
	if tanks == null: failures.append("Missing tank variants demo")
	else:
		var root: Node3D = tanks.instantiate() as Node3D; var models: Node3D = root.get_node_or_null("Tanks") as Node3D
		if models == null or models.get_child_count() != 4: failures.append("Tank demo must reference all four tank scenes")
		elif models.process_mode != Node.PROCESS_MODE_DISABLED: failures.append("Only tank demo container may disable processing")
		else:
			for tank: Node in models.get_children():
				if tank.process_mode != Node.PROCESS_MODE_INHERIT: failures.append("Tank roots must inherit processing when copied to a main scene")
		root.free()
	for failure: String in failures: push_error(failure)
	print("BUILDING_SAMPLES_SMOKE failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func count_nodes(node: Node, node_type: String) -> int:
	var total := 1 if node.is_class(node_type) else 0
	for child: Node in node.get_children(): total += count_nodes(child, node_type)
	return total

func every_collision_is_trimesh(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is CollisionShape3D and not child.shape is ConcavePolygonShape3D: return false
		if not every_collision_is_trimesh(child): return false
	return true
