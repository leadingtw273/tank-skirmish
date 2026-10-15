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
var player_fill: OmniLight3D
var _player_runtime: Node
var _player_health: HealthComponent

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
	call_deferred("_bind_player_fill")

func _bind_player_fill() -> void:
	_player_runtime = get_parent().get_parent().get_node_or_null("PlayerRuntime")
	if _player_runtime == null:
		return
	_player_runtime.connect("controlled_tank_changed", _set_player_fill_target)
	_set_player_fill_target(_player_runtime.get("controlled_tank") as Node3D)

func _set_player_fill_target(tank: Node3D) -> void:
	_clear_player_fill()
	if tank == null:
		return
	var health := tank.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.current_health <= 0.0:
		return
	_player_health = health
	_player_health.depleted.connect(_clear_player_fill)
	# 六盞街燈以外，僅存活的受控車有一盞局部、無陰影補光。
	player_fill = OmniLight3D.new()
	player_fill.name = "RainPlayerFill"
	player_fill.position = Vector3(0, 3.2, 0)
	player_fill.light_color = Color(0.72, 0.82, 1.0)
	player_fill.light_energy = 1.6
	player_fill.omni_range = 5.0
	player_fill.omni_attenuation = 1.5
	player_fill.shadow_enabled = false
	tank.add_child(player_fill)

func _clear_player_fill() -> void:
	if is_instance_valid(_player_health) and _player_health.depleted.is_connected(_clear_player_fill):
		_player_health.depleted.disconnect(_clear_player_fill)
	_player_health = null
	if is_instance_valid(player_fill):
		player_fill.visible = false
		player_fill.queue_free()
	player_fill = null

func _exit_tree() -> void:
	if is_instance_valid(_player_runtime) and _player_runtime.is_connected("controlled_tank_changed", _set_player_fill_target):
		_player_runtime.disconnect("controlled_tank_changed", _set_player_fill_target)
	_clear_player_fill()

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
