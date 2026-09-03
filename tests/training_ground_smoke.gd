extends SceneTree

const TRAINING_GROUND_SCENE := "res://src/world/training_ground/training_ground.tscn"
const TRAINING_GROUND_SHADER := "res://src/world/training_ground/training_ground_grid.gdshader"
const TRAINING_GROUND_PLAYTEST_SCENE := "res://src/world/training_ground/training_ground_playtest.tscn"
const TRAINING_TARGET_SCENE := "res://src/world/training_ground/training_target.tscn"
const EXPECTED_GROUND_COLOR := Color(0.34, 0.36, 0.38, 1)
const EXPECTED_GRID_COLOR := Color.WHITE
const EXPECTED_AMBIENT_COLOR := Color(0.72, 0.74, 0.78, 1)
const EXPECTED_TARGET_COLOR := Color(0.16, 0.18, 0.2, 1)


func _init() -> void:
	if not _validate_training_ground() or not await _validate_playtest_composition():
		quit(1)
		return
	print("Training ground smoke validation passed.")
	quit(0)


func _validate_training_ground() -> bool:
	var training_ground_scene := load(TRAINING_GROUND_SCENE) as PackedScene
	var training_ground := training_ground_scene.instantiate() as Node3D if training_ground_scene != null else null
	if training_ground == null or training_ground.name != "TrainingGround":
		return _fail("Training ground scene must load as a TrainingGround Node3D.")
	if training_ground.get_child_count() != 3:
		training_ground.free()
		return _fail("Training ground must contain only Ground, Targets, and Lighting roots.")
	if training_ground.get_node_or_null("Roads") != null or training_ground.get_node_or_null("Buildings") != null \
			or training_ground.get_node_or_null("GrassField") != null:
		training_ground.free()
		return _fail("Training ground must not include city or vegetation objects.")
	var targets := training_ground.get_node_or_null("Targets") as Node3D
	var training_target := training_ground.get_node_or_null("Targets/TrainingTarget") as Node3D
	var target_tank := training_target.get_node_or_null("SubjectSlot/Tank") as CharacterBody3D \
			if training_target != null else null
	var target_collision := target_tank.get_node_or_null("CollisionShape3D") as CollisionShape3D \
			if target_tank != null else null
	var target_shape := target_collision.shape as BoxShape3D if target_collision != null else null
	var target_model := target_tank.get_node_or_null("VisualRecoilPivot/Tank2") as Node3D \
			if target_tank != null else null
	var health_label := training_target.get_node_or_null("HealthLabel3D") as Label3D if training_target != null else null
	if targets == null or targets.get_child_count() != 1 or training_target == null \
			or training_target.scene_file_path != TRAINING_TARGET_SCENE \
			or not training_target.position.is_equal_approx(Vector3(-40, 0, -6)) \
			or target_tank == null or target_tank.collision_layer != 1 \
			or target_model == null or not target_model.scale.is_equal_approx(Vector3.ONE) \
			or target_shape == null or target_shape.size.x <= 0.0 or target_shape.size.y <= 0.0 or target_shape.size.z <= 0.0 \
			or not is_equal_approx(target_collision.position.y, target_shape.size.y * 0.5) \
			or health_label == null or health_label.font_size <= 0 or health_label.position.y <= target_shape.size.y * 0.5:
		training_ground.free()
		return _fail("Training ground must contain one scale=1 stationary target with grounded collision and a readable health label.")

	var ground := training_ground.get_node_or_null("Ground") as StaticBody3D
	var visual := training_ground.get_node_or_null("Ground/Visual") as MeshInstance3D
	var collision := training_ground.get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D
	var ground_mesh := visual.mesh as BoxMesh if visual != null else null
	var ground_shape := collision.shape as BoxShape3D if collision != null else null
	var grid_material := visual.material_override as ShaderMaterial if visual != null else null
	if ground == null or visual == null or collision == null or ground_mesh == null or ground_shape == null \
			or ground.collision_layer != 128 or ground.collision_mask != 0 \
			or not ground_mesh.size.is_equal_approx(Vector3(960, 0.2, 960)) \
			or not ground_shape.size.is_equal_approx(Vector3(960, 0.2, 960)):
		training_ground.free()
		return _fail("Training ground must provide a 960m collision layer 128 ground plane.")
	if grid_material == null or grid_material.shader == null \
			or grid_material.shader.resource_path != TRAINING_GROUND_SHADER \
			or not (grid_material.get_shader_parameter("ground_color") as Color).is_equal_approx(EXPECTED_GROUND_COLOR) \
			or not (grid_material.get_shader_parameter("grid_color") as Color).is_equal_approx(EXPECTED_GRID_COLOR) \
			or not is_equal_approx(float(grid_material.get_shader_parameter("grid_spacing")), 8.0) \
			or not is_equal_approx(float(grid_material.get_shader_parameter("grid_width")), 0.00078125):
		training_ground.free()
		return _fail("Training ground grid material must expose the approved eight-metre colors and width.")

	var shader_file := FileAccess.open(TRAINING_GROUND_SHADER, FileAccess.READ)
	var shader_source := shader_file.get_as_text() if shader_file != null else ""
	if not shader_source.contains("MODEL_MATRIX") or not shader_source.contains("fract(grid_coordinates)"):
		training_ground.free()
		return _fail("Training ground grid must use world coordinates instead of duplicated line meshes.")

	var lighting := training_ground.get_node_or_null("Lighting") as Node3D
	var sun := training_ground.get_node_or_null("Lighting/Sun") as DirectionalLight3D
	var world_environment := training_ground.get_node_or_null("Lighting/WorldEnvironment") as WorldEnvironment
	var environment := world_environment.environment if world_environment != null else null
	var valid_lighting := lighting != null and sun != null and sun.shadow_enabled and environment != null \
		and environment.background_mode == Environment.BG_SKY and environment.sky != null \
		and environment.ambient_light_color.is_equal_approx(EXPECTED_AMBIENT_COLOR)
	training_ground.free()
	if not valid_lighting:
		return _fail("Training ground must provide shadowed noon lighting, a blue sky, and neutral ambient light.")
	return true


func _validate_playtest_composition() -> bool:
	var playtest_scene := load(TRAINING_GROUND_PLAYTEST_SCENE) as PackedScene
	var playtest := playtest_scene.instantiate() as Node3D if playtest_scene != null else null
	if playtest == null:
		return _fail("Training ground playtest scene must load.")
	root.add_child(playtest)
	await process_frame
	var gameplay_runtime := playtest.get_node_or_null("Main") as Node3D
	var world := gameplay_runtime.get_node_or_null("World") as Node3D if gameplay_runtime != null else null
	var expected_runtime_nodes := [&"CameraRig", &"Tank", &"PlayerRuntime", &"CombatRuntime", &"SurfaceEffects", &"World"]
	var has_existing_runtime := gameplay_runtime != null and gameplay_runtime.get_child_count() == expected_runtime_nodes.size()
	if has_existing_runtime:
		for node_name in expected_runtime_nodes:
			if gameplay_runtime.get_node_or_null(NodePath(node_name)) == null:
				has_existing_runtime = false
				break
	var training_target := world.get_node_or_null("Targets/TrainingTarget") as Node3D if world != null else null
	var target_tank := training_target.get_node_or_null("SubjectSlot/Tank") as CharacterBody3D \
			if training_target != null else null
	var valid := has_existing_runtime and world != null \
		and world.scene_file_path == TRAINING_GROUND_SCENE \
		and world.get_node_or_null("Ground") != null \
		and world.get_node_or_null("Roads") == null \
		and training_target != null and target_tank != null \
		and target_tank.collision_layer == 1 \
		and target_tank.get_node_or_null("CollisionShape3D") != null \
		and _all_target_meshes_are_gray(training_target)
	playtest.queue_free()
	if not valid:
		return _fail("Training ground playtest must reuse main gameplay and replace only World.")
	return true


func _all_target_meshes_are_gray(root_node: Node) -> bool:
	var mesh_count := 0
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.is_in_group("effect_mesh"):
			if mesh_instance.material_override is StandardMaterial3D \
					and (mesh_instance.material_override as StandardMaterial3D).albedo_color.is_equal_approx(EXPECTED_TARGET_COLOR):
				return false
			continue
		var material := mesh_instance.material_override as StandardMaterial3D
		if material == null or not material.albedo_color.is_equal_approx(EXPECTED_TARGET_COLOR):
			return false
		mesh_count += 1
	return mesh_count > 0


func _fail(message: String) -> bool:
	push_error(message)
	return false
