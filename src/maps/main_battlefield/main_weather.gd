## 主圖固定近夜晚中雨；只有相機地面附近的一個雨粒子發射器。
extends Node3D

const LAMP := preload("res://src/maps/main_battlefield/street_lamp.tscn")
const POSITIONS := [Vector3(-94, 0, -106), Vector3(-140, 0, -132),
	Vector3(-80, 0, -140), Vector3(-140, 0, -72),
	Vector3(-77, 0, -88), Vector3(-94, 0, -114)]
var lamps: Array[RigidBody3D] = []
var rain: GPUParticles3D
var heightfield: GPUParticlesCollisionHeightField3D
var ground_focus := Vector3.ZERO
var _light_interval := 0.0

func _ready() -> void:
	for index: int in POSITIONS.size():
		var lamp := LAMP.instantiate() as RigidBody3D
		lamp.name = "StreetLamp%d" % (index + 1)
		lamp.position = POSITIONS[index]
		lamp.model_variant = 1 + index % 2
		add_child(lamp)
		lamps.append(lamp)
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
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.60, 0.72, 0.85, 0.36)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = material
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

func _process(delta: float) -> void:
	_update_camera()
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
