## 預算與資源契約；真正分布、風、碰撞與槽位回收由原生 GPU smoke 驗證。
extends SceneTree

const RAIN := preload("res://src/maps/main_battlefield/rain_volume.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)

func _run() -> void:
	var rain := RAIN.new()
	root.add_child(rain)
	_check("rain-world-space",not rain.local_coords)
	_check("rain-no-post-collision-extrapolation",not rain.interpolate and rain.fixed_fps==60)
	_check("rain-budget",rain.amount==7000 and is_equal_approx(rain.lifetime,2.2) and is_equal_approx(rain.preprocess,2.2))
	_check("production-random-seed",not rain.use_fixed_seed)
	_check("rain-no-shadow",rain.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("rain-mesh",rain.draw_pass_1 is QuadMesh and rain.draw_pass_1.size.is_equal_approx(Vector2(0.028,0.38)))
	_check("rain-motion",rain.process_material is ShaderMaterial and rain.process_material.shader==RAIN.RAIN_MOTION)
	_check("rain-draw",rain.draw_pass_1.material is ShaderMaterial and rain.draw_pass_1.material.shader==RAIN.RAIN_DRAW)
	var impacts := rain.get_node_or_null(rain.sub_emitter) as GPUParticles3D
	_check("impact-sub-emitter",impacts!=null)
	if impacts!=null:
		_check("impact-bounded",impacts.amount==1800 and is_equal_approx(impacts.lifetime,0.42))
		_check("impact-events-only",not impacts.emitting and not impacts.local_coords)
		_check("impact-no-shadow",impacts.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_check("impact-mesh",impacts.draw_pass_1 is PlaneMesh and impacts.draw_pass_1.size.is_equal_approx(Vector2(0.62,0.62)))
		_check("impact-motion",impacts.process_material is ShaderMaterial and impacts.process_material.shader==RAIN.IMPACT_MOTION)
		_check("impact-draw",impacts.draw_pass_1.material is ShaderMaterial and impacts.draw_pass_1.material.shader==RAIN.IMPACT_DRAW)
	print("WEATHER_RAIN_CONTRACT failures=",failures.size()," ",failures)
	rain.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
