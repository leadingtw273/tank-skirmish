@tool
extends MeshInstance3D
## 訓練場專用理論視野示意；只讀取視野設定，不參與偵測或建築遮擋判定。

@export var vision: Node
## 關閉時僅隱藏示意，不影響敵方 AI。
@export var display_enabled := true
## A 是不透明度；預設 0.15。
@export var tint := Color(1.0, 0.2, 0.2, 0.15)
## 平坦訓練場地面的世界高度，略微抬高避免與地面閃爍。
@export var ground_height := 0.04

const RANGE_SHADER := preload("res://src/world/training_ground/vision_range_preview.gdshader")
var _range_material: ShaderMaterial


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 2.0
	mesh = plane
	_range_material = ShaderMaterial.new()
	_range_material.shader = RANGE_SHADER
	material_override = _range_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_process(0.0)


func _process(_delta: float) -> void:
	visible = display_enabled and is_instance_valid(vision)
	if not visible or _range_material == null:
		return
	var observer := vision.get("observer") as Node3D
	if not is_instance_valid(observer):
		visible = false
		return
	var near_radius := float(vision.get("near_radius"))
	var far_radius := float(vision.get("far_radius"))
	var radius := maxf(near_radius, far_radius)
	var forward_3d: Vector3 = vision.call("get_horizontal_forward")
	var forward := Vector2(forward_3d.x, forward_3d.z)
	visible = radius > 0.0 and not forward.is_zero_approx()
	if not visible:
		return
	## 使用世界座標，父節點的旋轉與縮放不會扭曲公尺範圍。
	global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(radius, 1.0, radius)),
		Vector3(observer.global_position.x, ground_height, observer.global_position.z))
	_range_material.set_shader_parameter("radius", radius)
	_range_material.set_shader_parameter("near_radius", near_radius)
	_range_material.set_shader_parameter("far_radius", far_radius)
	_range_material.set_shader_parameter("forward_direction", forward.normalized())
	_range_material.set_shader_parameter("half_angle_cos", cos(deg_to_rad(
		float(vision.get("far_field_of_view_degrees")) * 0.5)))
	_range_material.set_shader_parameter("tint", tint)
