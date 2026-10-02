extends SceneTree

const RoadHeight := preload("res://scripts/roads/road_height_baker.gd")
## Rebuild paid-source references locally; never edits vendor files.
const SOURCE := "res://assets/AtomicRealmModularRoads/catalog.json"
const OUT := "res://src/world/roads"
var entries: Array[Dictionary] = []
var failures: Array[String] = []
var texture_derivatives: Dictionary = {}
var base_snap_points: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var only_custom := "--only-custom" in OS.get_cmdline_user_args()
	if only_custom:
		if not FileAccess.file_exists(OUT + "/modules.json"):
			push_error("Run a full sample build before --only-custom")
			quit(1)
			return
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/modules.json"))
		for entry: Dictionary in previous.modules:
			if String(entry.pack) != "custom":
				entries.append(entry)
	if FileAccess.file_exists(OUT + "/base_snap_points.json"):
		base_snap_points = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/base_snap_points.json")).models
	if FileAccess.file_exists(OUT + "/texture_derivatives.json"):
		texture_derivatives = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/texture_derivatives.json"))
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not source is Dictionary:
		push_error("Missing source catalog")
		quit(1)
		return
	for pack: Dictionary in source.packs:
		if only_custom:
			continue
		var group: Array[Dictionary] = []
		for model: Dictionary in pack.models:
			group.append_array(build_model(String(pack.id), model, pack.textures))
		if FileAccess.file_exists(OUT + "/converted_catalog.json"):
			var converted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/converted_catalog.json"))
			for model: Dictionary in converted.models:
				if String(model.pack) == String(pack.id):
					group.append_array(build_model(String(pack.id), model, pack.textures))
		entries.append_array(group)
		build_demo(String(pack.id), group)
	if FileAccess.file_exists(OUT + "/custom_catalog.json"):
		var custom: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/custom_catalog.json"))
		var group: Array[Dictionary] = []
		for model: Dictionary in custom.models:
			var original_id := String(model.id).trim_suffix("_Custom")
			if original_id == "Road1_Curve2_Custom45":
				original_id = "Road1"
			for original: Dictionary in source.packs[0].models:
				if String(original.id) == original_id:
					model.materials = original.materials
			group.append_array(build_model("custom", model, source.packs[0].textures))
		entries.append_array(group)
		build_demo("custom", group)
	write_json(OUT + "/modules.json", {"modules": entries})
	for failure: String in failures:
		push_error(failure)
	print("ROAD_SAMPLES_RESULT modules=%d failures=%d" % [entries.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func build_model(pack: String, model: Dictionary, textures: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var scene := load(String(model.path)) as PackedScene
	if scene == null:
		failures.append("Cannot load " + String(model.path))
		return result
	var source := scene.instantiate() as Node3D
	var meshes: Array[Dictionary] = []
	collect_meshes(source, Transform3D.IDENTITY, meshes)
	if meshes.is_empty():
		failures.append("Empty model " + String(model.path))
		source.free()
		return result
	var road_model := RoadHeight.is_road_model(pack, String(model.id))
	if road_model:
		var baker := RoadHeight.new()
		var source_factor := float(source.get_meta(RoadHeight.HEIGHT_META, 1.0))
		for item: Dictionary in meshes:
			item.mesh = baker.mesh_at_height(item.mesh as ArrayMesh, item.transform, source_factor)
		if not baker.is_valid():
			failures.append_array(baker.failures)
			failures.append("Height bake failed for " + String(model.id))
			source.free()
			return result
	var options: Array[Dictionary] = [{"name": "Default", "image": "", "texture": ""}]
	var seen: Dictionary = {}
	for mat: Dictionary in model.materials:
		var image_name := String(mat.get("image_name", "")).get_file().get_basename()
		if image_name.is_empty():
			continue
		for texture: Dictionary in textures:
			var name_ := String(texture.name).get_basename()
			if compatible_palette(image_name, name_) and name_ != image_name:
				var key := image_name + "__" + name_
				if not seen.has(key):
					seen[key] = true
					options.append({"name": key, "image": image_name, "texture": texture.path})
	var bounds: AABB = meshes[0].transform * meshes[0].mesh.get_aabb()
	for item: Dictionary in meshes:
		bounds = bounds.merge(item.transform * item.mesh.get_aabb())
	var collision_paths: Array[String] = []
	for index: int in meshes.size():
		var shape: Shape3D = meshes[index].mesh.create_trimesh_shape()
		var path := OUT + "/generated/collisions/%s/%s_%d.res" % [pack, model.id, index]
		mkdir(path.get_base_dir())
		if shape == null or ResourceSaver.save(shape, path) != OK:
			failures.append("Collision save " + path)
		collision_paths.append(path)
	for option: Dictionary in options:
		var replacement: Texture2D = null
		if not String(option.texture).is_empty():
			var texture_path: String = texture_derivatives.get(String(option.texture), String(option.texture))
			replacement = load(texture_path) as Texture2D
			if replacement == null:
				failures.append("Cannot load variant texture " + texture_path)
				continue
		var module := StaticBody3D.new()
		module.name = String(model.id).validate_node_name()
		module.collision_layer = 1
		module.collision_mask = 1
		module.set_meta("road_module", true)
		module.set_meta("road_id", model.id)
		module.set_meta("variant", option.name)
		module.set_meta("source_pack", pack)
		if road_model:
			module.set_meta(RoadHeight.HEIGHT_META, RoadHeight.HEIGHT_FACTOR)
		for index: int in meshes.size():
			var item: Dictionary = meshes[index]
			var visual := MeshInstance3D.new()
			visual.name = "Mesh_%d" % index
			visual.mesh = item.mesh
			visual.transform = item.transform
			module.add_child(visual)
			visual.owner = module
			for surface: int in visual.mesh.get_surface_count():
				var material: Material = item.materials[surface]
				if material is StandardMaterial3D and not String(option.texture).is_empty():
					var tex: Texture2D = material.albedo_texture
					var tex_name := "" if tex == null else tex.resource_name.get_basename()
					var material_name := material.resource_name
					var matched := tex_name == String(option.image)
					for declared: Dictionary in model.materials:
						if String(declared.get("image_name", "")).get_basename() == String(option.image) and String(declared.name) == material_name:
							matched = true
					if matched:
						material = material.duplicate()
						material.albedo_texture = replacement
				visual.set_surface_override_material(surface, material)
			var collision := CollisionShape3D.new()
			collision.name = "Collision_%d" % index
			collision.shape = load(collision_paths[index])
			collision.transform = item.transform
			module.add_child(collision)
			collision.owner = module
		add_snap_points(module, model, bounds)
		var path := OUT + "/items/%s/%s/%s.tscn" % [pack, model.id, option.name]
		if save_scene(module, path):
			result.append({"id": model.id, "pack": pack, "variant": option.name, "path": path,
				"bounds": [bounds.position.x, bounds.position.y, bounds.position.z, bounds.size.x, bounds.size.y, bounds.size.z],
				"meshes": meshes.size(), "road_height_factor": RoadHeight.HEIGHT_FACTOR if road_model else 1.0})
		module.free()
	source.free()
	return result

func compatible_palette(image_name: String, candidate: String) -> bool:
	# Only known UV families. Arbitrary textures are never applied across models.
	for family: String in ["Road1_", "Road2_X_", "Road6_"]:
		if image_name.begins_with(family):
			return candidate.begins_with(family)
	if candidate.begins_with(image_name + "_"):
		return true
	return image_name.begins_with("Texture_") and candidate.trim_suffix("b").trim_suffix("c") == image_name

func collect_meshes(node: Node3D, parent_transform: Transform3D, output: Array[Dictionary]) -> void:
	var transform_: Transform3D = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var materials: Array[Material] = []
		for surface: int in node.mesh.get_surface_count():
			materials.append(node.get_active_material(surface))
		if transform_.basis.determinant() < 0.0:
			output.append({"mesh": bake_mirrored_mesh(node.mesh, transform_), "transform": Transform3D.IDENTITY, "materials": materials})
		else:
			output.append({"mesh": node.mesh, "transform": transform_, "materials": materials})
	for child: Node in node.get_children():
		if child is Node3D:
			collect_meshes(child, transform_, output)

func bake_mirrored_mesh(source: Mesh, transform_: Transform3D) -> ArrayMesh:
	# Vendor mirrored transforms must reverse winding when flattened for export.
	var result := ArrayMesh.new()
	var normal_basis := transform_.basis.inverse().transposed()
	for surface: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in vertices.size():
			vertices[i] = transform_ * vertices[i]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i: int in normals.size():
				normals[i] = (normal_basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i: int in range(0, tangents.size(), 4):
				var tangent := (transform_.basis * Vector3(tangents[i], tangents[i + 1], tangents[i + 2])).normalized()
				tangents[i] = tangent.x
				tangents[i + 1] = tangent.y
				tangents[i + 2] = tangent.z
				tangents[i + 3] = -tangents[i + 3]
			arrays[Mesh.ARRAY_TANGENT] = tangents
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		if indices.is_empty():
			for i: int in vertices.size():
				indices.append(i)
		for i: int in range(0, indices.size(), 3):
			var swap := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = swap
		arrays[Mesh.ARRAY_INDEX] = indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	return result

func add_snap_points(module: Node3D, model: Dictionary, bounds: AABB) -> void:
	var holder := Node3D.new()
	holder.name = "SnapPoints"
	module.add_child(holder)
	holder.owner = module
	var id := String(model.id)
	var points: Array = model.get("snap_points", base_snap_points.get(id, []))
	if points.is_empty():
		var center := bounds.get_center()
		if id == "Road1" or id.contains("Crossing"):
			points = [point("North", Vector3(center.x, 0, bounds.position.z), Vector3.FORWARD), point("South", Vector3(center.x, 0, bounds.end.z), Vector3.BACK)]
		elif id == "Road2_X" or id == "Road2_T":
			points = [point("North", Vector3(0, 0, -6), Vector3.FORWARD), point("East", Vector3(6, 0, 0), Vector3.RIGHT), point("West", Vector3(-6, 0, 0), Vector3.LEFT)]
			if id == "Road2_X":
				points.append(point("South", Vector3(0, 0, 6), Vector3.BACK))
	for data: Dictionary in points:
		var marker := Marker3D.new()
		marker.name = String(data.name)
		marker.position = Vector3(data.position[0], data.position[1], data.position[2])
		if module.has_meta(RoadHeight.HEIGHT_META):
			marker.position.y *= RoadHeight.HEIGHT_FACTOR
		var outward := Vector3(data.outward[0], data.outward[1], data.outward[2])
		marker.basis = Basis.looking_at(outward, Vector3.UP)
		holder.add_child(marker)
		marker.owner = module

func point(name_: String, position_: Vector3, outward: Vector3) -> Dictionary:
	return {"name": name_, "position": [position_.x, position_.y, position_.z], "outward": [outward.x, outward.y, outward.z]}

func build_demo(pack: String, modules: Array[Dictionary]) -> void:
	if modules.is_empty():
		return
	var scene := Node3D.new()
	scene.name = (pack + "_demo").validate_node_name()
	var models := Node3D.new()
	models.name = "Models"
	scene.add_child(models)
	models.owner = scene
	var labels := Node3D.new()
	labels.name = "Labels"
	scene.add_child(labels)
	labels.owner = scene
	var columns: int = maxi(4, ceili(sqrt(modules.size())))
	var rows: int = ceili(float(modules.size()) / columns)
	var widths: Array[float] = []
	var depths: Array[float] = []
	widths.resize(columns)
	depths.resize(rows)
	widths.fill(22.0)
	depths.fill(24.0)
	for i: int in modules.size():
		widths[i % columns] = maxf(widths[i % columns], modules[i].bounds[3] + 10)
		depths[i / columns] = maxf(depths[i / columns], modules[i].bounds[5] + 14)
	var span := Vector2(0, 0)
	for width: float in widths:
		span.x += width
	for depth: float in depths:
		span.y += depth
	var z := -span.y / 2
	for row: int in rows:
		var x := -span.x / 2
		for column: int in columns:
			var index: int = row * columns + column
			if index >= modules.size():
				break
			var entry: Dictionary = modules[index]
			var module := load(String(entry.path)).instantiate() as Node3D
			module.name = (String(entry.id) + "__" + String(entry.variant)).validate_node_name()
			module.position = Vector3(x + widths[column] / 2 - entry.bounds[0] - entry.bounds[3] / 2, 0, z + depths[row] / 2 - entry.bounds[2] - entry.bounds[5] / 2)
			models.add_child(module)
			module.owner = scene
			var label_ := Label3D.new()
			label_.name = "Label_%d" % index
			label_.text = String(entry.id) + "\n" + String(entry.variant)
			label_.font_size = 32
			label_.pixel_size = 0.04
			label_.position = Vector3(x + widths[column] / 2, 0.2, z + depths[row] - 3)
			label_.rotation_degrees.x = -90
			labels.add_child(label_)
			label_.owner = scene
			x += widths[column]
		z += depths[row]
	add_preview(scene, span)
	save_scene(scene, "res://src/samples/roads/%s_demo.tscn" % pack)
	scene.free()

func add_preview(scene: Node3D, span: Vector2) -> void:
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var extent := maxf(span.x, span.y)
	camera.position = Vector3(0, extent, extent * 0.45)
	camera.basis = Basis.looking_at(-camera.position, Vector3.UP)
	camera.size = extent * 1.1
	camera.current = true
	scene.add_child(camera)
	camera.owner = scene
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.1
	scene.add_child(light)
	light.owner = scene
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.11, 0.13, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	environment.owner = scene
	var floor_ := MeshInstance3D.new()
	floor_.name = "PreviewFloor"
	var plane := PlaneMesh.new()
	plane.size = span + Vector2(12, 12)
	floor_.mesh = plane
	floor_.position.y = -0.08
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.29, 0.31, 0.34)
	floor_.material_override = material
	scene.add_child(floor_)
	floor_.owner = scene

func save_scene(node: Node, path: String) -> bool:
	mkdir(path.get_base_dir())
	var scene := PackedScene.new()
	if scene.pack(node) != OK or ResourceSaver.save(scene, path) != OK:
		failures.append("Scene save " + path)
		return false
	return true

func mkdir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func write_json(path: String, data: Dictionary) -> void:
	mkdir(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t") + "\n")
