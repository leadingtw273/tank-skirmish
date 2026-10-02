extends SceneTree
## LEA-177: generate Godot-owned wrappers from imported, official Quaternius GLBs.
## Source Blend files stay immutable in assets/QuaterniusBuildings; this script only
## writes derived scenes/resources below src/world/buildings/quaternius and samples.

const MESH_ROOT := "res://src/world/buildings/quaternius/meshes"
const WRAPPER_ROOT := "res://src/world/buildings/quaternius/items"
const COLLISION_ROOT := "res://src/world/buildings/quaternius/collisions"
const SAMPLE_ROOT := "res://src/samples/buildings"
const PALETTES := ["blue", "casino", "dark", "darkblue", "darkpurple", "green", "grey", "light", "light2", "red", "signs", "yellow"]
const COUNTS := {"finished": 26, "base": 18, "parts": 32, "materials": 26}
const TEXTURED := ["finished", "base", "parts"]
const TANK_SCENES := [
	"res://src/actors/tank/variants/tank1/tank1.tscn",
	"res://src/actors/tank/variants/tank2/tank2.tscn",
	"res://src/actors/tank/variants/tank3/tank3.tscn",
	"res://src/actors/tank/variants/tank4/tank4.tscn",
]

var failures: Array[String] = []
var entries: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--only-tanks" in OS.get_cmdline_user_args():
		build_tank_demo()
		for failure: String in failures:
			push_error(failure)
		print("LEA177_BUILDINGS_TANKS_RESULT failures=%d" % failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	if "--only-demos" in OS.get_cmdline_user_args():
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/world/buildings/quaternius/catalog.json"))
		for entry: Dictionary in catalog.modules:
			entries.append(entry)
	else:
		for group: String in TEXTURED:
			for palette: String in PALETTES:
				build_group(group, palette)
		build_group("materials", "default")
		write_json("res://src/world/buildings/quaternius/catalog.json", {"modules": entries})
	build_demo("finished", filter_entries("finished"))
	build_demo("base", filter_entries("base"))
	build_demo("parts", filter_entries("parts"))
	build_demo("materials", filter_entries("materials"))
	build_demo("full_pack", full_pack_entries())
	build_color_focus_demo()
	build_tank_demo()
	for failure: String in failures:
		push_error(failure)
	print("LEA177_BUILDINGS_RESULT modules=%d failures=%d" % [entries.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func build_group(group: String, palette: String) -> void:
	var mesh_dir := MESH_ROOT.path_join(group if group == "materials" else group.path_join(palette))
	var source_paths := recursive_glbs(mesh_dir)
	if source_paths.size() != int(COUNTS[group]):
		failures.append("%s/%s expected %d imported GLBs, got %d" % [group, palette, COUNTS[group], source_paths.size()])
		return
	for source_path: String in source_paths:
		var wrapper_path := WRAPPER_ROOT.path_join(group).path_join(palette).path_join(source_path.get_file().get_basename() + ".tscn")
		if build_wrapper(source_path, wrapper_path):
			entries.append({"group": group, "palette": palette, "id": source_path.get_file().get_basename(), "path": wrapper_path})

func recursive_glbs(path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not name.begins_with("."):
			var child := path.path_join(name)
			if dir.current_is_dir():
				result.append_array(recursive_glbs(child))
			elif name.get_extension().to_lower() == "glb":
				result.append(child)
		name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result

func build_wrapper(source_path: String, output_path: String) -> bool:
	var packed := load(source_path) as PackedScene
	if packed == null:
		failures.append("Cannot load imported GLB: " + source_path)
		return false
	var source := packed.instantiate() as Node3D
	if source == null:
		failures.append("Cannot instantiate GLB: " + source_path)
		return false
	var meshes: Array[Dictionary] = []
	collect_meshes(source, Transform3D.IDENTITY, meshes)
	if meshes.is_empty():
		failures.append("GLB has no mesh: " + source_path)
		source.free()
		return false
	var body := StaticBody3D.new()
	body.name = source_path.get_file().get_basename().validate_node_name()
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_meta("quaternius_source", source_path)
	for index: int in meshes.size():
		var item: Dictionary = meshes[index]
		var visual := MeshInstance3D.new()
		visual.name = "Model_%d" % index
		visual.mesh = item.mesh
		visual.transform = item.transform
		body.add_child(visual)
		visual.owner = body
		var shape: Shape3D = (item.mesh as Mesh).create_trimesh_shape()
		if shape == null:
			failures.append("Trimesh creation failed: " + source_path)
			body.free(); source.free(); return false
		var shape_path := COLLISION_ROOT.path_join(output_path.trim_prefix(WRAPPER_ROOT).get_base_dir().trim_prefix("/")).path_join("%s_%d.res" % [source_path.get_file().get_basename(), index])
		mkdir(shape_path.get_base_dir())
		if ResourceSaver.save(shape, shape_path) != OK:
			failures.append("Collision save failed: " + shape_path)
			body.free(); source.free(); return false
		var collision := CollisionShape3D.new()
		collision.name = "Collision_%d" % index
		collision.shape = load(shape_path) as Shape3D
		collision.transform = item.transform
		body.add_child(collision)
		collision.owner = body
	var ok := save_scene(body, output_path)
	body.free(); source.free()
	return ok

func collect_meshes(node: Node3D, parent: Transform3D, output: Array[Dictionary]) -> void:
	var transform := parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		output.append({"mesh": node.mesh, "transform": transform})
	for child: Node in node.get_children():
		if child is Node3D:
			collect_meshes(child, transform, output)

func filter_entries(group: String) -> Array[Dictionary]:
	return entries.filter(func(entry: Dictionary) -> bool: return String(entry.group) == group)

func full_pack_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if String(entry.group) == "materials" or String(entry.palette) == "light":
			result.append(entry)
	return result

func build_demo(name_: String, modules: Array[Dictionary]) -> void:
	if modules.is_empty():
		failures.append("Empty demo: " + name_); return
	var root := Node3D.new(); root.name = name_.validate_node_name() + "_demo"
	var models := Node3D.new(); models.name = "Models"; root.add_child(models); models.owner = root
	var columns := maxi(4, ceili(sqrt(modules.size())))
	for index: int in modules.size():
		var module := load(String(modules[index].path)) as PackedScene
		if module == null:
			failures.append("Cannot load wrapper: " + String(modules[index].path)); continue
		var instance := module.instantiate() as StaticBody3D
		instance.name = (String(modules[index].id) + "_" + String(modules[index].palette)).validate_node_name()
		instance.position = Vector3((index % columns) * 18.0, 0, (index / columns) * 18.0)
		models.add_child(instance); instance.owner = root
	add_preview(root, Vector2(columns * 18.0, ceili(float(modules.size()) / columns) * 18.0))
	save_scene(root, SAMPLE_ROOT.path_join(name_ + "_demo.tscn")); root.free()

func build_color_focus_demo() -> void:
	var root := Node3D.new(); root.name = "2Story_Wide_Colors_Demo"
	var models := Node3D.new(); models.name = "Models"; root.add_child(models); models.owner = root
	var paths := [WRAPPER_ROOT.path_join("materials/default/2Story_Wide_Mat.tscn")]
	for palette: String in PALETTES:
		paths.append(WRAPPER_ROOT.path_join("finished").path_join(palette).path_join("2Story_Wide.tscn"))
	for index: int in paths.size():
		var packed := load(String(paths[index])) as PackedScene
		if packed == null: failures.append("Missing color focus module: " + String(paths[index])); continue
		var instance := packed.instantiate() as StaticBody3D
		instance.name = ("Material_Default" if index == 0 else PALETTES[index - 1]).validate_node_name()
		instance.position = Vector3((index % 4) * 20.0, 0, (index / 4) * 18.0)
		models.add_child(instance); instance.owner = root
	add_preview(root, Vector2(80, 72)); save_scene(root, SAMPLE_ROOT.path_join("2story_wide_colors_demo.tscn")); root.free()

func build_tank_demo() -> void:
	# PackedScene.pack() serializes instantiated tank internals and can lose the
	# original scene reference. Write a minimal external-reference scene instead.
	for path: String in TANK_SCENES:
		if not ResourceLoader.exists(path, "PackedScene"):
			failures.append("Missing tank scene: " + path)
	if not failures.is_empty(): return
	var text := "[gd_scene load_steps=5 format=3]\n\n"
	for index: int in TANK_SCENES.size():
		text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%d_tank\"]\n" % [TANK_SCENES[index], index + 1]
	text += "\n[node name=\"TankVariantsDemo\" type=\"Node3D\"]\n\n[node name=\"Tanks\" type=\"Node3D\" parent=\".\"]\nprocess_mode = 4\n"
	for index: int in TANK_SCENES.size():
		text += "\n[node name=\"Tank%d\" parent=\"Tanks\" instance=ExtResource(\"%d_tank\")]\nposition = Vector3(%d, 0, %d)\n" % [index + 1, index + 1, (index % 2) * 18, (index / 2) * 18]
	var output := "res://src/samples/tanks/tank_variants_demo.tscn"
	mkdir(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		failures.append("Tank demo write failed: " + output)
	else:
		file.store_string(text)

func add_preview(root: Node3D, span: Vector2) -> void:
	var camera := Camera3D.new(); camera.name = "PreviewCamera"; camera.position = Vector3(span.x * 0.5, maxf(span.x, span.y), span.y * 1.2); camera.basis = Basis.looking_at(Vector3(span.x * 0.5, 0, span.y * 0.5) - camera.position, Vector3.UP); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = maxf(span.x, span.y) * 1.15; camera.current = true; root.add_child(camera); camera.owner = root
	var light := DirectionalLight3D.new(); light.name = "Sun"; light.rotation_degrees = Vector3(-55, -25, 0); root.add_child(light); light.owner = root
	var environment := WorldEnvironment.new(); environment.name = "PreviewEnvironment"
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	root.add_child(environment); environment.owner = root

func save_scene(node: Node, path: String) -> bool:
	mkdir(path.get_base_dir()); var scene := PackedScene.new()
	if scene.pack(node) != OK or ResourceSaver.save(scene, path) != OK:
		failures.append("Scene save failed: " + path); return false
	return true

func mkdir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func write_json(path: String, data: Dictionary) -> void:
	mkdir(path.get_base_dir()); var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(data, "\t") + "\n")
