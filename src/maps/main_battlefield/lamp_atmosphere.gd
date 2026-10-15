## 路燈局部效果全部依附燈節點，不保存地圖座標。
extends Node3D

const MIST := preload("res://src/maps/main_battlefield/lamp_mist.gdshader")
const HALO := preload("res://src/maps/main_battlefield/lamp_halo.gdshader")
var source_light: OmniLight3D

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
