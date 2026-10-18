## 作者原生效能診斷；不修改光源／陰影／遊戲畫質，不作產品驗收。
## -- <output-dir> <label> [f5-first|dense-first]
extends SceneTree

const WARMUP := 360
const STEADY := 240
var _viewport_rid: RID
var _device: RenderingDevice
var _output: String
var _rows: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n":0}
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	return {"n":sorted.size(), "median":(sorted[middle-1] + sorted[middle]) * 0.5 if sorted.size() % 2 == 0 else sorted[middle],
		"p95":sorted[ceili(sorted.size() * 0.95) - 1], "min":sorted.front(), "max":sorted.back()}

func _summary(samples: Array[Dictionary]) -> Dictionary:
	var result := {}
	for key: String in ["process_ms", "physics_ms", "navigation_ms", "setup_cpu_ms", "viewport_cpu_ms", "interval_ms", "draw_calls", "render_objects"]:
		var values: Array = []
		for row: Dictionary in samples:
			values.append(row[key])
		result[key] = _stats(values)
	var gpu: Array = []
	var seen := {}
	var zero_gpu := 0
	var repeated_timestamp := 0
	for row: Dictionary in samples:
		if row.viewport_gpu_ms <= 0:
			zero_gpu += 1
			continue
		if row.gpu_timestamp_frame < 0:
			gpu.append(row.viewport_gpu_ms)
		elif not seen.has(row.gpu_timestamp_frame):
			seen[row.gpu_timestamp_frame] = true
			gpu.append(row.viewport_gpu_ms)
		else:
			repeated_timestamp += 1
	result["viewport_gpu_ms"] = _stats(gpu)
	result["zero_gpu_samples"] = zero_gpu
	result["repeated_gpu_timestamp_frames"] = repeated_timestamp
	result["focused_frames"] = samples.filter(func(row: Dictionary): return row.focused).size()
	result["camera_unchanged_frames"] = samples.filter(func(row: Dictionary): return row.camera_unchanged).size()
	result["viewport_1080_frames"] = samples.filter(func(row: Dictionary): return row.viewport_1080).size()
	return result

func _sample(camera: Camera3D, weather: Node, tag: String) -> void:
	var warm: Array[Dictionary] = []
	var steady: Array[Dictionary] = []
	var previous_usec := Time.get_ticks_usec()
	var expected_transform := camera.global_transform
	var expected_size := camera.size
	for frame: int in WARMUP + STEADY:
		if frame < WARMUP and frame % 60 == 0 and not DisplayServer.window_is_focused():
			root.grab_focus()
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var timestamp_frame := -1
		if _device != null and _device.has_method("get_captured_timestamps_frame"):
			timestamp_frame = _device.get_captured_timestamps_frame()
		var sample := {
			"process_frame":Engine.get_process_frames(), "gpu_timestamp_frame":timestamp_frame,
			"process_ms":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"navigation_ms":Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
			"setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),
			"viewport_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid),
			"viewport_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid),
			"interval_ms":float(now - previous_usec) / 1000.0,
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"focused":DisplayServer.window_is_focused(),
			"viewport_1080":root.get_visible_rect().size.is_equal_approx(Vector2(1920,1080)),
			"camera_unchanged":camera.global_transform.is_equal_approx(expected_transform) and is_equal_approx(camera.size, expected_size)}
		previous_usec = now
		if frame < WARMUP:
			warm.append(sample)
		else:
			steady.append(sample)
	var light_rows: Array[Dictionary] = []
	for lamp in weather.lamps:
		if is_instance_valid(lamp):
			light_rows.append({"name":str(lamp.name), "enabled":lamp.light.visible, "shadow":lamp.light.shadow_enabled, "class":lamp.light.get_class()})
	var row := {"view":tag, "transform":str(camera.global_transform), "size":camera.size,
		"warmup":_summary(warm), "steady":_summary(steady), "warmup_samples":warm, "steady_samples":steady,
		"street_lights":light_rows,
		"candidates":weather.get("visible_candidates") if "visible_candidates" in weather else -1,
		"budget_dropped":weather.get("budget_dropped") if "budget_dropped" in weather else 0}
	_rows.append(row)
	print("WEATHER_PROFILE ", tag, " process=", row.steady.process_ms, " gpu=", row.steady.viewport_gpu_ms,
		" viewport_cpu=", row.steady.viewport_cpu_ms, " setup=", row.steady.setup_cpu_ms)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 1 and args[0] == "--validate-api":
		for method: String in ["viewport_set_measure_render_time", "viewport_get_measured_render_time_cpu", "viewport_get_measured_render_time_gpu", "get_frame_setup_time_cpu"]:
			assert(RenderingServer.has_method(method), method)
		print("WEATHER_PROFILE_API PASS ", Engine.get_version_info().string)
		quit(0)
		return
	if DisplayServer.get_name() == "headless" or args.size() < 2:
		push_error("需要原生圖形 renderer，參數為 output-dir label [f5-first|dense-first]")
		quit(2)
		return
	_output = args[0]
	DirAccess.make_dir_recursive_absolute(_output)
	## 避免 Windows 有邊框視窗被工作區壓短，導致 canvas expand 實際變成 2019×1080。
	root.borderless = true
	root.size = Vector2i(1920,1080)
	root.position = Vector2i.ZERO
	var main := load("res://src/main.tscn").instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	# Git archive 不含本機生成地圖；拒絕以缺道路／建築的副本產出效能結論。
	var roads := main.get_node("World/Roads").find_children("*", "MeshInstance3D", true, false).size()
	var buildings := main.get_node("World/Buildings").find_children("*", "MeshInstance3D", true, false).size()
	if roads < 200 or buildings < 170:
		push_error("正式主圖資源不完整：roads=%d buildings=%d" % [roads, buildings])
		quit(2)
		return
	var runtime := main.get_node("PlayerRuntime")
	runtime.call("set_controls_enabled", false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process(false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process_input(false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process_unhandled_input(false)
	runtime.get("player_aim_controller").set_process(false)
	runtime.get("player_aim_controller").set_physics_process(false)
	var camera := root.get_camera_3d()
	var f5_transform := camera.global_transform
	var f5_size := camera.size
	var weather := main.get_node("World/MainWeather")
	_viewport_rid = root.get_viewport_rid()
	_device = RenderingServer.get_rendering_device()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	var views: Array[String] = ["f5", "dense-street"]
	if args.size() > 2 and args[2] == "dense-first":
		views.reverse()
	for tag: String in views:
		root.grab_focus()
		camera.global_transform = f5_transform
		camera.size = f5_size
		if tag == "dense-street":
			camera.global_position = Vector3(-84,0,-48) + f5_transform.basis.z * 135
			camera.size = 100
		await _sample(camera, weather, tag)
	var result := {"label":args[1], "engine":Engine.get_version_info(), "adapter":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(), "viewport":str(root.size), "visible_rect":str(root.get_visible_rect()),
		"vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "refresh_hz":DisplayServer.screen_get_refresh_rate(),
		"grass_enabled":main.get_node("World/GrassField").visible, "measurement_phase":"frame_post_draw; latest CPU/GPU reports; GPU not frame-aligned with CPU",
		"atlas_size":root.positional_shadow_atlas_size, "atlas_16bits":root.positional_shadow_atlas_16_bits,
		"atlas_quadrants":[root.positional_shadow_atlas_quad_0,root.positional_shadow_atlas_quad_1,root.positional_shadow_atlas_quad_2,root.positional_shadow_atlas_quad_3],
		"road_meshes":roads, "building_meshes":buildings,
		"warmup_frames":WARMUP, "steady_frames":STEADY, "views":_rows}
	var file := FileAccess.open(_output + "/profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)
	main.queue_free()
	for frame: int in 3:
		await process_frame
	var valid := _rows.all(func(row: Dictionary): return row.steady.viewport_1080_frames == STEADY)
	quit(0 if valid else 2)
