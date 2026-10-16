## 作者原生 F5 診斷。每個 process 僅四次真左鍵；不以 TIME_PROCESS 作逐幀時間。
## -- <output-dir> <label> [normal|all-fx-off|fx-lights-off|smoke-off|flash-off|projectile-off]
## *-off 僅供根因消去實驗，不是可採用的產品修正。
extends SceneTree

class DiagnosticMouseFilter extends Node:
	var discarded_buttons := 0
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton and not event.has_meta(&"first_shot_profile"):
			discarded_buttons += 1
			get_viewport().set_input_as_handled()

var scene: Node3D
var player: Node3D
var started: int
var previous: int
var samples: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var requests: Array[Dictionary] = []
var events: Array[Dictionary] = []
var counters: Dictionary = {}
var mode := "normal"
var requested := 0
var viewport_rid: RID

func _init() -> void:
	call_deferred("_run")

func _pipelines() -> Dictionary:
	var values := {}
	for key: String in counters:
		values[key] = RenderingServer.get_rendering_info(counters[key])
	return values

func _fired(_event: Variant) -> void:
	shots.append({"shot":shots.size() + 1, "t_ms":float(Time.get_ticks_usec() - started) / 1000.0,
		"frame":Engine.get_process_frames(), "pipeline":_pipelines()})

func _added(node: Node) -> void:
	var label := str(node.name)
	var path := str(node.get_path())
	var firing_light := path.contains("/MuzzleFlash/") or path.contains("/Projectiles/Projectile") or path.contains("/ImpactVFX/")
	if mode == "fx-lights-off" and node is Light3D and firing_light:
		node.visible = false
	if node is Node3D and ((mode == "all-fx-off" and (label.begins_with("MuzzleSmokeVFX") or label.begins_with("MuzzleFlash") or label.begins_with("Projectile") or label.begins_with("ImpactVFX")))
		or (mode == "smoke-off" and label.begins_with("MuzzleSmokeVFX"))
		or (mode == "flash-off" and label.begins_with("MuzzleFlash"))
		or (mode == "projectile-off" and label.begins_with("Projectile"))):
		node.visible = false
	if node is Light3D or label.begins_with("Projectile") or label.begins_with("Muzzle") or label.begins_with("Impact"):
		var row := {"t_ms":float(Time.get_ticks_usec() - started) / 1000.0, "frame":Engine.get_process_frames(),
			"kind":"node_added", "path":str(node.get_path()), "class":node.get_class()}
		if node is Light3D:
			row["shadow"] = node.shadow_enabled
			row["visible"] = node.visible
		events.append(row)

func _fire() -> void:
	root.grab_focus()
	requested += 1
	var begin := Time.get_ticks_usec()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.get_visible_rect().size * 0.5
	click.set_meta(&"first_shot_profile", true)
	Input.parse_input_event(click)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
	requests.append({"request":requested, "t_ms":float(begin - started) / 1000.0,
		"input_dispatch_ms":float(Time.get_ticks_usec() - begin) / 1000.0, "frame":Engine.get_process_frames()})

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 2)
	assert(DisplayServer.get_name() == "Windows" and RenderingServer.get_current_rendering_method() == "forward_plus")
	assert(str(ProjectSettings.get_setting("application/config/custom_user_dir_name")).begins_with("TankRainRound3"))
	if args.size() > 2:
		mode = args[2]
	assert(mode in ["normal", "all-fx-off", "fx-lights-off", "smoke-off", "flash-off", "projectile-off"])
	root.grab_focus()
	for key in ClassDB.class_get_integer_constant_list("RenderingServer"):
		if str(key).begins_with("RENDERING_INFO_PIPELINE_COMPILATIONS_"):
			counters[key] = ClassDB.class_get_integer_constant("RenderingServer", key)
	scene = load("res://src/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var road_meshes := scene.get_node("World/Roads").find_children("*", "MeshInstance3D", true, false).size()
	var building_meshes := scene.get_node("World/Buildings").find_children("*", "MeshInstance3D", true, false).size()
	if road_meshes < 200 or building_meshes < 170:
		push_error("FIRST_SHOT_MAP_CLOSURE road=%d building=%d" % [road_meshes,building_meshes])
		quit(4)
		return
	root.grab_focus()
	var runtime := scene.get_node("PlayerRuntime")
	# 僅診斷副本隔離外部滑鼠按鍵；受控左鍵仍走原始 PlayerController／ShotEvent。
	var mouse_filter := DiagnosticMouseFilter.new()
	root.add_child(mouse_filter)
	scene.get_node("PlayerSpawnGroup/CameraRig").set_process_unhandled_input(false)
	player = runtime.get("controlled_tank")
	# 保留正式玩家左鍵／ShotEvent、物理、相機跟隨與後座；僅固定鍵盤移動／滑鼠瞄準輸入。
	runtime.get_node("PlayerController").set_physics_process(false)
	runtime.get("player_aim_controller").call("set_controls_enabled", false)
	player.connect("shot_event_fired", _fired)
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	started = Time.get_ticks_usec()
	previous = started
	node_added.connect(_added)
	while true:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := float(now - started) / 1000.0
		samples.append({"t_ms":elapsed, "interval_ms":float(now - previous) / 1000.0,
			"frame":Engine.get_process_frames(), "focused":DisplayServer.window_is_focused(), "camera_size":root.get_camera_3d().size,
			"setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),
			"viewport_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
			"viewport_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid), "pipeline":_pipelines()})
		previous = now
		if requested < 4 and elapsed >= 7000.0 + requested * 4000.0:
			_fire()
		if elapsed >= 23000.0:
			break
	node_added.disconnect(_added)
	var camera := root.get_camera_3d()
	var result := {"author_diagnostic_only":true, "label":args[1], "mode":mode, "entry":"res://src/main.tscn",
		"engine":Engine.get_version_info(), "adapter":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(), "viewport":str(root.get_visible_rect()),
		"vsync":DisplayServer.window_get_vsync_mode(), "refresh_hz":DisplayServer.screen_get_refresh_rate(), "max_fps":Engine.max_fps,
		"user_data_dir":OS.get_user_data_dir(), "grass":scene.get_node("World/GrassField").visible,
		"road_meshes":road_meshes, "building_meshes":building_meshes,
		"camera_transform":str(camera.global_transform), "camera_size":camera.size,
		"atlas_size":root.positional_shadow_atlas_size, "atlas_16bits":root.positional_shadow_atlas_16_bits,
		"atlas_quadrants":[root.positional_shadow_atlas_quad_0,root.positional_shadow_atlas_quad_1,root.positional_shadow_atlas_quad_2,root.positional_shadow_atlas_quad_3],
		"external_mouse_buttons_discarded":mouse_filter.discarded_buttons,
		"requests":requests, "shots":shots, "events":events, "frames":samples}
	DirAccess.make_dir_recursive_absolute(args[0])
	var file := FileAccess.open(args[0] + "/first-shot.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("FIRST_SHOT_PROFILE ", args[1], " requested=", requested, " actual=", shots.size(), " mode=", mode)
	var valid := shots.size() == 4 and requests.size() == 4 and samples.all(func(row: Dictionary): return is_equal_approx(row.camera_size, 100.0))
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	scene.queue_free()
	for frame: int in 3:
		await process_frame
	quit(0 if valid else 2)
