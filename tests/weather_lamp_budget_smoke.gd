## 作者全圖預算回歸：所有亮燈投影，超額及畫外只保留燈頭，跨街廓重算。
extends SceneTree
var failures: Array[String] = []
func _init() -> void:
	call_deferred("_run")
func _expect(label: String, passed: bool) -> void:
	print("LAMP_BUDGET ",label," PASS" if passed else " FAIL")
	if not passed: failures.append(label)
func _run() -> void:
	var main := load("res://src/main.tscn").instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	main.get_node("PlayerRuntime").call("set_controls_enabled",false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process(false)
	for frame: int in 120: await physics_frame
	var weather := main.get_node("World/MainWeather")
	var camera := root.get_camera_3d()
	var minimum := INF
	for i: int in weather.lamps.size():
		for j: int in range(i+1,weather.lamps.size()):
			minimum = minf(minimum,weather.lamps[i].global_position.distance_to(weather.lamps[j].global_position))
	_expect("69-generated-all-at-least12m", weather.lamps.size() == 69 and minimum >= 12)
	var offset: Vector3 = camera.global_position - weather.ground_focus
	var overflow_views := 0
	for center: Vector3 in [Vector3(-108,0,-106),Vector3(-84,0,-48),Vector3(0,0,0),Vector3(84,0,48),Vector3(108,0,106)]:
		camera.global_position = center + offset
		weather.call("_update_camera")
		weather.call("_update_lights")
		weather.call("_sync_road_glints")
		await physics_frame
		var lit := 0
		var remote := 0
		for lamp in weather.lamps:
			lit += int(lamp.light.visible)
			_expect("all-enabled-cast-"+str(lamp.name), not lamp.light.visible or lamp.light.shadow_enabled)
			var in_view: bool = weather.call("_in_light_view",camera,lamp)
			_expect("offscreen-no-light-"+str(lamp.name),in_view or not lamp.light.visible)
			if not lamp.light.visible:
				remote += 1
				_expect("remote-head-stays-emissive-"+str(lamp.name),lamp.heads.all(func(head: MeshInstance3D): return (head.mesh.material as StandardMaterial3D).emission_enabled))
				_expect("inactive-fx-no-rays-"+str(lamp.name),not lamp.atmosphere.visible and not lamp.atmosphere.is_physics_processing())
		_expect("bounded-with-shadows",lit == mini(8,weather.visible_candidates) and remote > 0 and weather.budget_dropped == maxi(0,weather.visible_candidates-8))
		overflow_views += int(weather.budget_dropped > 0)
		print("LAMP_BUDGET_VIEW ",center," candidates=",weather.visible_candidates," lit=",lit," dropped=",weather.budget_dropped)
	print("LAMP_BUDGET minimum=",minimum," overflow_views=",overflow_views,"/5 failures=",failures.size())
	main.queue_free()
	for frame: int in 2: await physics_frame
	quit(0 if failures.is_empty() else 1)
