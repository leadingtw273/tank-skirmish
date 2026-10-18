## 主圖有界雨體積；碰撞沿用 MainWeather 的高度場，落點在 GPU 直接轉成漣漪。
extends GPUParticles3D

const RAIN_MOTION := preload("res://src/maps/main_battlefield/rain_motion.gdshader")
const RAIN_DRAW := preload("res://src/maps/main_battlefield/lit_rain.gdshader")
const IMPACT_MOTION := preload("res://src/maps/main_battlefield/rain_impact_motion.gdshader")
const IMPACT_DRAW := preload("res://src/maps/main_battlefield/rain_impact.gdshader")


func _ready() -> void:
	amount = 7000
	lifetime = 2.2
	preprocess = 2.2
	local_coords = false
	# 碰撞後不能再沿速度外插繪製到屋頂內；60Hz 步長保留移動平順度。
	fixed_fps = 60
	interpolate = false
	visibility_aabb = AABB(Vector3(-100,-40,-100), Vector3(200,60,200))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion := ShaderMaterial.new()
	motion.shader = RAIN_MOTION
	process_material = motion
	var material := ShaderMaterial.new()
	material.shader = RAIN_DRAW
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.028,0.38)
	mesh.material = material
	draw_pass_1 = mesh
	var impacts := GPUParticles3D.new()
	impacts.name = "RainSurfaceImpacts"
	impacts.amount = 1800
	impacts.lifetime = 0.42
	impacts.emitting = false
	impacts.local_coords = false
	impacts.visibility_aabb = visibility_aabb
	impacts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var impact_motion := ShaderMaterial.new()
	impact_motion.shader = IMPACT_MOTION
	impacts.process_material = impact_motion
	var impact_material := ShaderMaterial.new()
	impact_material.shader = IMPACT_DRAW
	var impact_mesh := PlaneMesh.new()
	impact_mesh.size = Vector2(0.62,0.62)
	impact_mesh.material = impact_material
	impacts.draw_pass_1 = impact_mesh
	add_child(impacts)
	sub_emitter = NodePath("RainSurfaceImpacts")
