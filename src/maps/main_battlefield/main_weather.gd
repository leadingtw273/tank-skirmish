## 主圖固定近夜晚中雨；只有相機地面附近的一個雨粒子發射器。
extends Node3D

const LAMP := preload("res://src/maps/main_battlefield/street_lamp.tscn")
const RAIN_MATERIAL := preload("res://src/maps/main_battlefield/lit_rain.gdshader")
const WET_GLINT := preload("res://src/maps/main_battlefield/wet_road_glint.gdshader")
const LAYOUT := preload("res://src/maps/main_battlefield/lamp_layout.gd")
# 街燈8盞＋玩家Spot2盞；超額只保留燈頭，不降級成無陰影光源。
const MAX_ACTIVE_LIGHTS := 8
var lamps: Array[RigidBody3D] = []
var rain: GPUParticles3D
var heightfield: GPUParticlesCollisionHeightField3D
var ground_focus := Vector3.ZERO
var _light_interval := 0.0
var visible_candidates := 0
var budget_dropped := 0
var active_lamps: Array[RigidBody3D] = []
var road_glints: ShaderMaterial
var rain_material: ShaderMaterial
var player_headlights: Array[SpotLight3D] = []
var _player_runtime: Node
var _player_health: HealthComponent

func _ready() -> void:
	for index: int in LAYOUT.LAMPS.size():
		var pose: Array = LAYOUT.LAMPS[index]
		var lamp := LAMP.instantiate() as RigidBody3D
		lamp.name = "StreetLamp%d" % (index + 1)
		lamp.position = pose[0]
		lamp.set_meta("spawn_height", pose[0].y)
		lamp.set_meta("layout_id", pose[2])
		lamp.model_variant = 1
		lamp.rotation.y = pose[1]
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
	_update_lights()
	_sync_road_glints()
	call_deferred("_bind_player_headlights")

func _bind_player_headlights() -> void:
	_player_runtime = get_parent().get_parent().get_node_or_null("PlayerRuntime")
	if _player_runtime == null:
		return
	_player_runtime.connect("controlled_tank_changed", _set_player_headlights_target)
	_set_player_headlights_target(_player_runtime.get("controlled_tank") as Node3D)

func _set_player_headlights_target(tank: Node3D) -> void:
	_clear_player_headlights()
	if tank == null:
		return
	var health := tank.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.current_health <= 0.0:
		return
	_player_health = health
	_player_health.depleted.connect(_clear_player_headlights)
	# 錨點由各車型提供；車燈跟隨車身，不跟砲塔或後座視覺轉動。
	for anchor: Node3D in tank.get_node("Headlights").get_children():
		var light := SpotLight3D.new()
		light.name = "RainHeadlight"
		light.rotation.x = deg_to_rad(-16.0)
		light.light_color = Color(1.0, 0.85, 0.65)
		light.light_energy = 2.4
		light.spot_range = 20.0
		light.spot_angle = 42.0
		light.spot_angle_attenuation = 0.6
		light.spot_attenuation = 1.25
		light.shadow_enabled = true
		anchor.add_child(light)
		player_headlights.append(light)

func _clear_player_headlights() -> void:
	if is_instance_valid(_player_health) and _player_health.depleted.is_connected(_clear_player_headlights):
		_player_health.depleted.disconnect(_clear_player_headlights)
	_player_health = null
	for light: SpotLight3D in player_headlights:
		if is_instance_valid(light):
			light.visible = false
			light.queue_free()
	player_headlights.clear()

func _exit_tree() -> void:
	if is_instance_valid(_player_runtime) and _player_runtime.is_connected("controlled_tank_changed", _set_player_headlights_target):
		_player_runtime.disconnect("controlled_tank_changed", _set_player_headlights_target)
	_clear_player_headlights()

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
	_light_interval -= delta
	if _light_interval <= 0:
		_light_interval = 0.2
		_update_lights()
	_sync_road_glints()

func _in_light_view(camera: Camera3D, lamp: RigidBody3D) -> bool:
	var center: Vector3 = lamp.light.global_position
	if camera.is_position_behind(center):
		return false
	# 正式正交相機：光照球的投影邊界可涵蓋柱在畫面外、光照仍入畫的情形。
	var radius: float = lamp.light.omni_range
	var point := camera.unproject_position(center)
	var extent := Vector2(
		point.distance_to(camera.unproject_position(center + camera.global_basis.x * radius)),
		point.distance_to(camera.unproject_position(center + camera.global_basis.y * radius)))
	return Rect2(point - extent, extent * 2).intersects(get_viewport().get_visible_rect())

func _update_lights() -> void:
	var camera := get_viewport().get_camera_3d()
	var candidates: Array[RigidBody3D] = []
	for lamp: RigidBody3D in lamps:
		if is_instance_valid(lamp) and not lamp.toppled and camera != null and _in_light_view(camera, lamp):
			candidates.append(lamp)
	candidates.sort_custom(func(a: RigidBody3D, b: RigidBody3D):
		return a.global_position.distance_squared_to(ground_focus) < b.global_position.distance_squared_to(ground_focus))
	visible_candidates = candidates.size()
	budget_dropped = maxi(0, visible_candidates - MAX_ACTIVE_LIGHTS)
	active_lamps.clear()
	for index: int in mini(MAX_ACTIVE_LIGHTS, candidates.size()):
		active_lamps.append(candidates[index])
	for lamp: RigidBody3D in lamps:
		if is_instance_valid(lamp):
			lamp.set_light_active(lamp in active_lamps, true)

func _sync_road_glints() -> void:
	var positions := PackedVector3Array()
	var active := PackedFloat32Array()
	for index: int in MAX_ACTIVE_LIGHTS:
		var lamp: RigidBody3D = active_lamps[index] if index < active_lamps.size() else null
		var valid: bool = is_instance_valid(lamp) and lamp.light.visible
		positions.append(lamp.light.global_position if valid else Vector3.ZERO)
		active.append(1.0 if valid else 0.0)
	road_glints.set_shader_parameter("lamp_positions", positions)
	road_glints.set_shader_parameter("lamp_active", active)

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
