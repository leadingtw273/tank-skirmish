## 主圖固定近夜晚中雨；雨體積與落地反應皆限於相機地面附近。
extends Node3D

const LAMP := preload("res://src/maps/main_battlefield/street_lamp.tscn")
const RAIN_MATERIAL := preload("res://src/maps/main_battlefield/lit_rain.gdshader")
const WET_GLINT := preload("res://src/maps/main_battlefield/wet_road_glint.gdshader")
const LAYOUT := preload("res://src/maps/main_battlefield/lamp_layout.gd")
const RAIN_VOLUME := preload("res://src/maps/main_battlefield/rain_volume.gd")
# 畫面含12m緩衝內全亮、全投影；256只供倒影uniform容量，不是關燈上限。
const VIEW_BUFFER_METERS := 12.0
const GLINT_CAPACITY := 256
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
var _shadow_viewport: Viewport
var _previous_atlas: Dictionary = {}
var _last_view := Transform3D()
var _last_view_size := -1.0
var _player_health: HealthComponent

func _ready() -> void:
	_configure_shadow_atlas()
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
	rain = RAIN_VOLUME.new()
	rain.name = "BoundedRain"
	add_child(rain)
	rain_material = rain.draw_pass_1.material as ShaderMaterial
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
	if is_instance_valid(_shadow_viewport):
		for property: String in _previous_atlas:
			_shadow_viewport.set(property, _previous_atlas[property])
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

func _configure_shadow_atlas() -> void:
	_shadow_viewport = get_viewport()
	for property: String in ["positional_shadow_atlas_size", "positional_shadow_atlas_16_bits", "positional_shadow_atlas_quad_0", "positional_shadow_atlas_quad_1", "positional_shadow_atlas_quad_2", "positional_shadow_atlas_quad_3"]:
		_previous_atlas[property] = _shadow_viewport.get(property)
	# 4象限×64個Spot，共256個512px槽；避免畫面內燈開著卻拿不到陰影槽。
	_shadow_viewport.positional_shadow_atlas_size = 8192
	_shadow_viewport.positional_shadow_atlas_16_bits = false
	for quadrant: int in 4:
		_shadow_viewport.set_positional_shadow_atlas_quadrant_subdiv(quadrant, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64)

func _process(delta: float) -> void:
	_update_camera()
	_light_interval -= delta
	var camera := get_viewport().get_camera_3d()
	var moved := camera != null and (not camera.global_transform.is_equal_approx(_last_view) or not is_equal_approx(camera.size, _last_view_size))
	if _light_interval <= 0 or moved:
		_light_interval = 0.2
		_update_lights()
	_sync_road_glints()

func _in_light_view(camera: Camera3D, lamp: RigidBody3D) -> bool:
	var center: Vector3 = lamp.light.global_position
	if camera.is_position_behind(center):
		return false
	var point := camera.unproject_position(center)
	var extent := Vector2(
		point.distance_to(camera.unproject_position(center + camera.global_basis.x * VIEW_BUFFER_METERS)),
		point.distance_to(camera.unproject_position(center + camera.global_basis.y * VIEW_BUFFER_METERS)))
	return Rect2(point - extent, extent * 2).intersects(get_viewport().get_visible_rect())

func _update_lights() -> void:
	var camera := get_viewport().get_camera_3d()
	active_lamps.clear()
	for lamp: RigidBody3D in lamps:
		if not is_instance_valid(lamp):
			continue
		var active: bool = not lamp.toppled and camera != null and _in_light_view(camera, lamp)
		lamp.set_light_active(active, true)
		if active:
			active_lamps.append(lamp)
	visible_candidates = active_lamps.size()
	budget_dropped = 0
	if camera != null:
		_last_view = camera.global_transform
		_last_view_size = camera.size

func _sync_road_glints() -> void:
	var positions := PackedVector3Array()
	for lamp: RigidBody3D in active_lamps:
		if is_instance_valid(lamp) and lamp.light.visible:
			positions.append(lamp.light.global_position)
	var count := positions.size()
	assert(count <= GLINT_CAPACITY, "活躍來源超出倒影容量；不可截斷或關燈")
	positions.resize(GLINT_CAPACITY)
	road_glints.set_shader_parameter("lamp_positions", positions)
	road_glints.set_shader_parameter("lamp_count", count)

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
