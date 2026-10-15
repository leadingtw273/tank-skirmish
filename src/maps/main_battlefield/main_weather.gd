## 主圖固定近夜晚中雨；只有相機地面附近的一個雨粒子發射器。
extends Node3D

const LAMP := preload("res://src/maps/main_battlefield/street_lamp.tscn")
const RAIN_MATERIAL := preload("res://src/maps/main_battlefield/lit_rain.gdshader")
const WET_GLINT := preload("res://src/maps/main_battlefield/wet_road_glint.gdshader")
const SIDEWALK_HEIGHT := 0.110125
const POSITIONS := [Vector3(-89.5, SIDEWALK_HEIGHT, -108), Vector3(-78.5, SIDEWALK_HEIGHT, -120),
	Vector3(-108, SIDEWALK_HEIGHT, -126.5), Vector3(-126.5, SIDEWALK_HEIGHT, -100),
	Vector3(-108, SIDEWALK_HEIGHT, -77.5), Vector3(-89.5, SIDEWALK_HEIGHT, -77.5)]
const LAMP_YAWS := [0.0, PI, PI * 0.5, PI, -PI * 0.5, -PI * 0.25]
var lamps: Array[RigidBody3D] = []
var rain: GPUParticles3D
var heightfield: GPUParticlesCollisionHeightField3D
var ground_focus := Vector3.ZERO
var _light_interval := 0.0
var road_glints: ShaderMaterial
var rain_material: ShaderMaterial

func _ready() -> void:
	for index: int in POSITIONS.size():
		var lamp := LAMP.instantiate() as RigidBody3D
		lamp.name = "StreetLamp%d" % (index + 1)
		lamp.position = POSITIONS[index]
		lamp.set_meta("spawn_height", POSITIONS[index].y)
		lamp.model_variant = 1
		lamp.rotation.y = LAMP_YAWS[index]
		add_child(lamp)
		lamps.append(lamp)
	road_glints = ShaderMaterial.new()
	road_glints.shader = WET_GLINT
	_wet_roads(get_parent().get_node("Roads"), {})
	rain = GPUParticles3D.new()
	rain.name = "BoundedRain"
	rain.amount = 7000
	rain.lifetime = 2.2
	rain.preprocess = 2.2
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-100, -40, -100), Vector3(200, 60, 200))
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(80, 1, 80)
	process.direction = Vector3(0.07, -1, 0.025)
	process.spread = 2.0
	process.initial_velocity_min = 17.0
	process.initial_velocity_max = 21.0
	process.gravity = Vector3(0, -3, 0)
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	rain.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.8)
	rain_material = ShaderMaterial.new()
	rain_material.shader = RAIN_MATERIAL
	mesh.material = rain_material
	rain.draw_pass_1 = mesh
	add_child(rain)
	heightfield = GPUParticlesCollisionHeightField3D.new()
	heightfield.name = "LocalRainRoofHeightfield"
	heightfield.size = Vector3(180, 80, 180)
	heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	heightfield.follow_camera_enabled = false
	add_child(heightfield)
	_update_camera()
	call_deferred("_bind_player_readability")

func _bind_player_readability() -> void:
	var runtime := get_parent().get_parent().get_node_or_null("PlayerRuntime")
	if runtime == null:
		return
	runtime.connect("controlled_tank_changed", _apply_player_readability)
	_apply_player_readability(runtime.get("controlled_tank") as Node3D)

func _apply_player_readability(tank: Node3D) -> void:
	if tank == null or tank.get_meta("rain_readability_applied", false):
		return
	var visual := tank.get_node_or_null("CombatTank/VisualRecoilPivot")
	if visual == null:
		return
	_fill_player_materials(visual, {})
	tank.set_meta("rain_readability_applied", true)

func _fill_player_materials(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D and not node.is_in_group("effect_mesh"):
		var instance := node as MeshInstance3D
		var override := instance.material_override as StandardMaterial3D
		if override != null:
			instance.material_override = _readable_player_material(override, materials)
		elif instance.mesh != null:
			for surface: int in instance.mesh.get_surface_count():
				var source := instance.get_active_material(surface) as StandardMaterial3D
				if source != null:
					instance.set_surface_override_material(surface, _readable_player_material(source, materials))
	for child: Node in node.get_children():
		_fill_player_materials(child, materials)

func _readable_player_material(source: StandardMaterial3D, materials: Dictionary) -> StandardMaterial3D:
	if source.emission_enabled:
		return source
	if not materials.has(source):
		var fill := source.duplicate() as StandardMaterial3D
		fill.emission_enabled = true
		fill.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
		fill.emission = Color(0.18, 0.23, 0.28)
		materials[source] = fill
	return materials[source] as StandardMaterial3D

func _wet_roads(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if not materials.has(source):
				var wet := source.duplicate() as StandardMaterial3D
				# 保留原金屬比例與貼圖，壓暗濕底，避免把冷色漫反射帶回整條道路。
				wet.albedo_color = source.albedo_color * Color(0.82, 0.82, 0.82, 1)
				wet.roughness = 0.9
				wet.metallic_specular = 0.0
				wet.clearcoat_enabled = false
				wet.next_pass = road_glints
				materials[source] = wet
			mesh_instance.set_surface_override_material(surface, materials[source])
	for child: Node in node.get_children():
		_wet_roads(child, materials)

func _process(delta: float) -> void:
	_update_camera()
	_sync_road_glints()
	_light_interval -= delta
	if _light_interval > 0:
		return
	_light_interval = 0.2
	var standing: Array[RigidBody3D] = []
	for lamp in lamps:
		if is_instance_valid(lamp) and not lamp.toppled:
			standing.append(lamp)
	standing.sort_custom(func(a: RigidBody3D, b: RigidBody3D):
		return a.global_position.distance_squared_to(ground_focus) < b.global_position.distance_squared_to(ground_focus))
	for index: int in standing.size():
		var lamp := standing[index]
		lamp.set_light_active(lamp.global_position.distance_to(ground_focus) < 110.0, index < 2)

func _sync_road_glints() -> void:
	var positions := PackedVector3Array()
	var active := PackedFloat32Array()
	var colors := PackedVector3Array()
	var ranges := PackedFloat32Array()
	for lamp in lamps:
		var valid := is_instance_valid(lamp)
		positions.append(lamp.light.global_position if valid else Vector3.ZERO)
		active.append(1.0 if valid and lamp.light.visible else 0.0)
		var color: Color = lamp.light.light_color.srgb_to_linear() if valid else Color.BLACK
		colors.append(Vector3(color.r, color.g, color.b) * lamp.light.light_energy if valid else Vector3.ZERO)
		ranges.append(lamp.light.omni_range if valid else 1.0)
	road_glints.set_shader_parameter("lamp_positions", positions)
	road_glints.set_shader_parameter("lamp_active", active)
	rain_material.set_shader_parameter("lamp_positions", positions)
	rain_material.set_shader_parameter("lamp_active", active)
	rain_material.set_shader_parameter("lamp_colors", colors)
	rain_material.set_shader_parameter("lamp_ranges", ranges)

func _update_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		rain.emitting = false
		return
	rain.emitting = true
	var screen := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.001:
		return
	ground_focus = origin + direction * (-origin.y / direction.y)
	# 高度場與發射盒共用有限範圍，只在跨越 8m 格時重繪屋頂／地面。
	var snapped := Vector3(snappedf(ground_focus.x, 8), 0, snappedf(ground_focus.z, 8))
	rain.global_position = snapped + Vector3.UP * 32.0
	heightfield.global_position = snapped + Vector3.UP * 20.0
