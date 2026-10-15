## 路燈局部效果全部依附燈節點，不保存地圖座標。
extends Node3D

const MIST := preload("res://src/maps/main_battlefield/lamp_mist.gdshader")
const HALO := preload("res://src/maps/main_battlefield/lamp_halo.gdshader")
var source_light: OmniLight3D
var halos: Array[MeshInstance3D] = []
var _occlusion_interval := 0.0

func _ready() -> void:
	source_light = get_parent().get_node("WarmLight") as OmniLight3D
	for head: MeshInstance3D in get_parent().heads:
		var halo := MeshInstance3D.new()
		halo.name = "HeadHalo"
		halo.position = head.position + Vector3(0, -0.08, 0)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var quad := QuadMesh.new()
		quad.size = Vector2(2.4, 2.4)
		var material := ShaderMaterial.new()
		material.shader = HALO
		quad.material = material
		halo.mesh = quad
		add_child(halo)
		halos.append(halo)
	for index: int in 3:
		var layer := MeshInstance3D.new()
		layer.name = "GroundMist%d" % index
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var quad := QuadMesh.new()
		quad.size = Vector2(22 - index * 3, 22 - index * 3)
		var material := ShaderMaterial.new()
		material.shader = MIST
		material.set_shader_parameter("noise_offset", float(index) * 7.3)
		quad.material = material
		layer.mesh = quad
		layer.position = Vector3(0, 0.35 + index * 0.5, 0)
		layer.rotation.x = -PI * 0.5
		add_child(layer)

func _process(_delta: float) -> void:
	visible = source_light.visible

func _physics_process(delta: float) -> void:
	_occlusion_interval -= delta
	if _occlusion_interval > 0.0:
		return
	_occlusion_interval = 0.1
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for halo: MeshInstance3D in halos:
		# 正交相機每個燈頭有自己的平行視線，不能從相機中心直接射向燈頭。
		var screen := camera.unproject_position(halo.global_position)
		var origin := camera.project_ray_origin(screen)
		var query := PhysicsRayQueryParameters3D.create(origin, halo.global_position, 129, [get_parent().get_rid()])
		halo.visible = not camera.is_position_behind(halo.global_position) and get_world_3d().direct_space_state.intersect_ray(query).is_empty()
