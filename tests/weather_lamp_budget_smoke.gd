## 作者覆蓋／全亮回歸：畫內含12m緩衝全亮投影，畫外暖點，跨街廓重算。
extends SceneTree
var failures: Array[String] = []
func _init() -> void:call_deferred("_run")
func _expect(label: String, passed: bool) -> void:
	print("LAMP_COVERAGE ",label," PASS" if passed else " FAIL")
	if not passed: failures.append(label)
func _run() -> void:
	var atlas_before := root.positional_shadow_atlas_size
	var precision_before := root.positional_shadow_atlas_16_bits
	var main := load("res://src/main.tscn").instantiate() as Node3D
	root.add_child(main);current_scene = main
	main.get_node("PlayerRuntime").call("set_controls_enabled",false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process(false)
	for frame: int in 120:await physics_frame
	var weather := main.get_node("World/MainWeather")
	var camera := root.get_camera_3d()
	var minimum := INF
	for i: int in weather.lamps.size():
		for j: int in range(i+1,weather.lamps.size()):
			minimum=minf(minimum,weather.lamps[i].global_position.distance_to(weather.lamps[j].global_position))
	_expect("117-generated-min12m", weather.lamps.size()==117 and minimum>=12)
	_expect("256-shadow-slots-512px-32bit",root.positional_shadow_atlas_size==8192 and not root.positional_shadow_atlas_16_bits and root.positional_shadow_atlas_quad_0==Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64 and root.positional_shadow_atlas_quad_1==Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64 and root.positional_shadow_atlas_quad_2==Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64 and root.positional_shadow_atlas_quad_3==Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64)
	var offset: Vector3=camera.global_position-weather.ground_focus
	for center: Vector3 in [Vector3(-108,0,-106),Vector3(-84,0,-48),Vector3(0,0,0),Vector3(84,0,48),Vector3(108,0,106)]:
		camera.global_position=center+offset
		# 相機跳轉也必須在下一次process直接重算，不能等0.2秒。
		await process_frame
		await process_frame
		var center_pixel:=camera.unproject_position(center)
		var padding:=Vector2(center_pixel.distance_to(camera.unproject_position(center+camera.global_basis.x*12)),center_pixel.distance_to(camera.unproject_position(center+camera.global_basis.y*12)))
		var area:=Rect2(-padding,root.get_visible_rect().size+padding*2)
		var lit:=0;var in_view:=0;var remote:=0
		for lamp in weather.lamps:
			var required:=not camera.is_position_behind(lamp.light.global_position) and area.has_point(camera.unproject_position(lamp.light.global_position))
			in_view+=int(required)
			lit+=int(lamp.light.visible)
			_expect("view-active-"+str(lamp.name),lamp.light.visible==required)
			_expect("real-down-spot-shadow-"+str(lamp.name),lamp.light is SpotLight3D and (-lamp.light.global_basis.z).dot(Vector3.DOWN)>.999 and (not required or lamp.light.shadow_enabled) and lamp.light.spot_range==22 and lamp.light.spot_angle==75)
			if not required:
				remote+=1
				_expect("remote-warm-point-"+str(lamp.name),lamp.heads.all(func(head: MeshInstance3D):return (head.mesh.material as StandardMaterial3D).emission_enabled and (head.mesh.material as StandardMaterial3D).emission_energy_multiplier>=6 and is_equal_approx((head.mesh as SphereMesh).radius,.22)))
				_expect("inactive-fx-no-rays-"+str(lamp.name),not lamp.atmosphere.visible and not lamp.atmosphere.is_physics_processing())
		_expect("every-view-light-enabled-shadowed",lit==in_view and lit==weather.visible_candidates and weather.budget_dropped==0 and remote>0)
		print("LAMP_COVERAGE_VIEW ",center," required=",in_view," lit=",lit," dropped=",weather.budget_dropped)
	main.queue_free()
	for frame: int in 3:await physics_frame
	_expect("unload-restores-viewport-atlas",root.positional_shadow_atlas_size==atlas_before and root.positional_shadow_atlas_16_bits==precision_before)
	print("LAMP_COVERAGE minimum=",minimum," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
