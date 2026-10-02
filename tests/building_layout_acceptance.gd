extends SceneTree

const CATALOG := "res://src/world/buildings/quaternius/catalog.json"
const DEMOS := {"full_pack": 102, "finished": 312, "base": 216, "parts": 384, "materials": 26}
const COLORS := ["blue", "casino", "dark", "darkblue", "darkpurple", "green", "grey", "light", "light2", "red", "signs", "yellow"]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_wrappers()
	check_demos()
	check_color_focus()
	check_tank_demo()
	for failure: String in failures:
		push_error(failure)
	print("BUILDING_LAYOUT_ACCEPTANCE failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check_wrappers() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not parsed is Dictionary or not parsed.get("modules") is Array:
		failures.append("catalog missing modules"); return
	var paths := {}
	for entry: Dictionary in parsed.modules:
		paths[String(entry.get("path", ""))] = true
	if paths.size() != 938:
		failures.append("expected 938 unique wrappers, got %d" % paths.size())
	for path: String in paths:
		var scene := load(path) as PackedScene
		var body := scene.instantiate() as StaticBody3D if scene != null else null
		if body == null:
			failures.append("wrapper is not StaticBody3D: " + path); continue
		for index: int in count_direct_meshes(body):
			var visual := body.get_node_or_null("Model_%d" % index) as MeshInstance3D
			var collision := body.get_node_or_null("Collision_%d" % index) as CollisionShape3D
			if visual == null or collision == null or not collision.shape is ConcavePolygonShape3D:
				failures.append("missing visual/trimesh pair: %s #%d" % [path, index])
			elif not visual.transform.is_equal_approx(collision.transform):
				failures.append("visual/collision transform differs: %s #%d" % [path, index])
		body.free()

func count_direct_meshes(body: StaticBody3D) -> int:
	var count := 0
	while body.get_node_or_null("Model_%d" % count) != null:
		count += 1
	return count

func check_demos() -> void:
	for name: String in DEMOS:
		var scene := load("res://src/samples/buildings/%s_demo.tscn" % name) as PackedScene
		var root := scene.instantiate() as Node3D if scene != null else null
		var models := root.get_node_or_null("Models") as Node3D if root != null else null
		if models == null or models.get_child_count() != int(DEMOS[name]):
			failures.append("demo count wrong: " + name)
		elif has_duplicate_xz(models):
			failures.append("demo has duplicate model XZ origin: " + name)
		elif not camera_targets_models(root, models):
			failures.append("preview camera does not target Models bounds: " + name)
		if root != null: root.free()

func has_duplicate_xz(models: Node3D) -> bool:
	var seen := {}
	for child: Node in models.get_children():
		var model := child as Node3D
		if model == null: return true
		var key := "%0.3f,%0.3f" % [model.position.x, model.position.z]
		if seen.has(key): return true
		seen[key] = true
	return false

func camera_targets_models(root: Node3D, models: Node3D) -> bool:
	var camera := root.get_node_or_null("PreviewCamera") as Camera3D
	if camera == null: return false
	var direction := -camera.transform.basis.z
	if direction.y >= -0.001: return false
	var ground_hit := camera.position + direction * (-camera.position.y / direction.y)
	var min_x := INF; var max_x := -INF; var min_z := INF; var max_z := -INF
	for child: Node in models.get_children():
		var model := child as Node3D
		if model == null: return false
		min_x = minf(min_x, model.position.x); max_x = maxf(max_x, model.position.x)
		min_z = minf(min_z, model.position.z); max_z = maxf(max_z, model.position.z)
	return ground_hit.x >= min_x and ground_hit.x <= max_x and ground_hit.z >= min_z and ground_hit.z <= max_z

func check_color_focus() -> void:
	var scene := load("res://src/samples/buildings/2story_wide_colors_demo.tscn") as PackedScene
	var root := scene.instantiate() as Node3D if scene != null else null
	var models := root.get_node_or_null("Models") as Node3D if root != null else null
	if models == null or models.get_child_count() != 13:
		failures.append("color focus must contain default plus 12 palettes")
	elif has_duplicate_xz(models):
		failures.append("color focus has duplicate model XZ origin")
	elif not camera_targets_models(root, models):
		failures.append("color focus preview camera does not target Models bounds")
	else:
		var signatures := {}
		var texture_ids := {}
		var material_default := models.get_node_or_null("Material_Default") as StaticBody3D
		if material_default == null or not has_nonwhite_albedo(material_default):
			failures.append("Material_Default is a white fallback rather than visible source material")
		for color: String in COLORS:
			var body := models.get_node_or_null(color) as StaticBody3D
			if body == null:
				failures.append("missing color focus entry: " + color); continue
			signatures[mesh_signature(body)] = true
			var texture_id := albedo_signature(body)
			if texture_id.is_empty(): failures.append("missing albedo texture: " + color)
			texture_ids[texture_id] = true
		if signatures.size() != 1: failures.append("12 palette scenes do not share one mesh shape")
		if texture_ids.size() != 12: failures.append("12 palette scenes do not have 12 distinct albedo images")
	if root != null: root.free()

func mesh_signature(body: Node) -> String:
	var values: Array[String] = []
	for child: Node in body.get_children():
		var visual := child as MeshInstance3D
		if visual != null and visual.mesh != null:
			values.append("%d:%s" % [visual.mesh.get_surface_count(), str(visual.mesh.get_aabb().size)])
	values.sort()
	return ",".join(values)

func albedo_signature(body: Node) -> String:
	for child: Node in body.get_children():
		var visual := child as MeshInstance3D
		if visual == null: continue
		for surface: int in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				var image := material.albedo_texture.get_image()
				if image != null:
					var samples: Array[String] = []
					for x: int in range(8):
						for y: int in range(8):
							samples.append(str(image.get_pixel(x * (image.get_width() - 1) / 7, y * (image.get_height() - 1) / 7)))
					return ",".join(samples)
	return ""

func has_nonwhite_albedo(body: Node) -> bool:
	for child: Node in body.get_children():
		var visual := child as MeshInstance3D
		if visual == null: continue
		for surface: int in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material == null: continue
			if not material.albedo_color.is_equal_approx(Color.WHITE): return true
			if material.albedo_texture == null: continue
			var image := material.albedo_texture.get_image()
			if image == null: continue
			for x: int in range(8):
				for y: int in range(8):
					if not image.get_pixel(x * (image.get_width() - 1) / 7, y * (image.get_height() - 1) / 7).is_equal_approx(Color.WHITE): return true
	return false

func check_tank_demo() -> void:
	var scene := load("res://src/samples/tanks/tank_variants_demo.tscn") as PackedScene
	var root := scene.instantiate() as Node3D if scene != null else null
	var tanks := root.get_node_or_null("Tanks") as Node3D if root != null else null
	if tanks == null or tanks.get_child_count() != 4:
		failures.append("tank demo must have four scenes")
	elif tanks.process_mode != Node.PROCESS_MODE_DISABLED:
		failures.append("only Tanks container may disable processing")
	else:
		for child: Node in tanks.get_children():
			if child.process_mode != Node.PROCESS_MODE_INHERIT:
				failures.append("tank root does not inherit processing: " + child.name)
	if root != null: root.free()
