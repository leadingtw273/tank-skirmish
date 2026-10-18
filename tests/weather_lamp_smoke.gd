## 本輪有限矩陣：全圖燈實際 shape、原 Tank2 接觸、推動及 5+2 秒生命週期。
extends SceneTree

var failures: Array[String] = []
var trace: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _expect(label: String, passed: bool, detail: Variant) -> void:
	print("WEATHER_LAMP ", label, " PASS " if passed else " FAIL ", detail)
	if not passed:
		failures.append(label)

func _frames(count: int) -> void:
	for unused: int in count:
		await physics_frame

func _run() -> void:
	var main := load("res://src/main.tscn").instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	var weather := main.get_node("World/MainWeather")
	var tank := main.get_node("PlayerSpawnGroup/Tank") as ContactTank
	main.get_node("PlayerRuntime/PlayerController").set_physics_process(false)
	main.get_node("PlayerRuntime/PlayerController").set_process(false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process(false)
	await _frames(180)
	var lamps: Array = weather.lamps
	var excluded: Array[RID] = [main.get_node("World/Ground").get_rid()]
	for lamp: RigidBody3D in lamps:
		excluded.append(lamp.get_rid())
	var placements: Array[Dictionary] = []
	for lamp: RigidBody3D in lamps:
		var overlaps: Array[String] = []
		for child: Node in lamp.get_children():
			if not child is CollisionShape3D:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = child.global_transform
			query.collision_mask = 129
			query.exclude = excluded
			for hit: Dictionary in lamp.get_world_3d().direct_space_state.intersect_shape(query):
				overlaps.append(str(hit.collider.get_path()))
		var row := {"name": lamp.name, "position": str(lamp.global_position),
			"tilt": rad_to_deg(acos(clampf(lamp.global_basis.y.dot(Vector3.UP), -1, 1))),
			"toppled": lamp.toppled, "overlaps": overlaps}
		placements.append(row)
		var spawn_height: float = lamp.get_meta("spawn_height")
		_expect("standing-" + str(lamp.name), not lamp.toppled and row.tilt < 1 and absf(lamp.position.y - spawn_height) < 0.05 and overlaps.is_empty(), row)
		var model_casts: bool = lamp.visuals.size() == 1 + lamp.heads.size() and lamp.visuals[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var heads_do_not_cast: bool = lamp.heads.all(func(head: MeshInstance3D): return head.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_expect("pole-shadow-casters-" + str(lamp.name), model_casts and heads_do_not_cast, lamp.visuals.size())
	_expect("bounds", weather.rain.amount <= 7000 and lamps.size() == 117 and weather.heightfield.size == Vector3(180, 80, 180), {"particles":weather.rain.amount,"lamps":lamps.size()})
	var lamp: RigidBody3D = lamps.filter(func(item: RigidBody3D): return item.get_meta("layout_id") == "G0__T:corner:0")[0]
	var other: RigidBody3D = lamps.filter(func(item: RigidBody3D): return item.get_meta("layout_id") == "UL1__Corner90:corner:0")[0]
	# 沿新 G0 路口燈 所在街邊朝 +Z 行駛，車心向車道偏 1m；只控制原公開輸入及初始姿勢。
	tank.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), lamp.global_position + Vector3(-1, 1, -8))
	tank.linear_velocity = Vector3.ZERO
	tank.angular_velocity = Vector3.ZERO
	await _frames(120)
	tank.set_movement_input(1.0)
	for unused: int in 420:
		await physics_frame
		if lamp.toppled:
			break
	_expect("actual-Tank2-contact", lamp.toppled and lamp.contact_count > 0, {"tank":str(tank.global_position),"lamp":str(lamp.global_position),"contacts":lamp.contact_count})
	if not lamp.toppled:
		main.queue_free()
		await _frames(2)
		quit(1)
		return
	var first_position := lamp.global_position
	var first_time: float = lamp.toppled_seconds
	var peak_tilt := 0.0
	var peak_push := 0.0
	var repeat_push := 0.0
	var repeat_position := Vector3.INF
	var screenshots := [0.0, 0.5, 1.5, 2.5, 4.5, 5.5, 6.8]
	var off_now: bool = not lamp.light.visible
	for head: MeshInstance3D in lamp.heads:
		off_now = off_now and not (head.mesh.material as StandardMaterial3D).emission_enabled
	_expect("immediate-off", off_now and first_time < 0.1, first_time)
	var light_ref: WeakRef = weakref(lamp.light)
	var shape_ref: WeakRef = weakref(lamp.get_children().filter(func(x: Node): return x is CollisionShape3D)[0])
	var root_ref: WeakRef = weakref(lamp)
	var alive_45 := false
	var fade_mid := false
	var repeat_no_reset := true
	var previous_seconds := first_time
	for frame: int in 450:
		await physics_frame
		if not is_instance_valid(lamp):
			break
		var seconds: float = lamp.toppled_seconds
		var tilt := rad_to_deg(acos(clampf(lamp.global_basis.y.dot(Vector3.UP), -1, 1)))
		peak_tilt = maxf(peak_tilt, tilt)
		peak_push = maxf(peak_push, Vector2(lamp.position.x - first_position.x, lamp.position.z - first_position.z).length())
		if repeat_position == Vector3.INF and lamp.contact_count > 1 and tilt > 45:
			repeat_position = lamp.position
		if repeat_position != Vector3.INF:
			repeat_push = maxf(repeat_push, Vector2(lamp.position.x - repeat_position.x, lamp.position.z - repeat_position.z).length())
		repeat_no_reset = repeat_no_reset and seconds >= previous_seconds and not lamp.light.visible
		previous_seconds = seconds
		if seconds >= 4.45 and seconds <= 4.65:
			alive_45 = lamp.visuals[0].transparency == 0.0 and shape_ref.get_ref() != null
		if seconds >= 5.9 and seconds < 6.1:
			fade_mid = lamp.visuals[0].transparency > 0.4 and lamp.visuals[0].transparency < 0.6
		if frame % 15 == 0:
			trace.append({"seconds":seconds,"position":str(lamp.global_position),"tilt_deg":tilt,"push_m":peak_push,"light":lamp.light.visible,"transparency":lamp.visuals[0].transparency,"contacts":lamp.contact_count})
		if DisplayServer.get_name() != "headless" and not screenshots.is_empty() and seconds >= screenshots[0]:
			var mark: float = screenshots.pop_front()
			await RenderingServer.frame_post_draw
			var png := ProjectSettings.globalize_path("res://../weather-lamp-%.1f.png" % mark)
			_expect("PNG-%.1f" % mark, root.get_texture().get_image().save_png(png) == OK, png)
		if seconds > 2.5:
			tank.set_movement_input(0.0)
	_expect("tilt-and-push", peak_tilt > 45 and peak_push >= 0.3, {"tilt":peak_tilt,"push":peak_push})
	_expect("fallen-recontact-push", repeat_push >= 0.3, repeat_push)
	_expect("wait-and-fade", alive_45 and fade_mid, {"alive45":alive_45,"fade6":fade_mid})
	_expect("repeat-keeps-clock", repeat_no_reset, previous_seconds)
	_expect("all-free-at7", root_ref.get_ref() == null and light_ref.get_ref() == null and shape_ref.get_ref() == null, previous_seconds)
	# 讓原距離／陰影管理在 root 已釋放後續跑，不能留下已釋放 reference 錯誤。
	await _frames(15)
	_expect("other-stays-lit", not other.toppled and other.light.visible, other.light.visible)
	var lights := 0
	var shadows := 0
	for standing in lamps:
		if is_instance_valid(standing):
			lights += int(standing.light.visible)
			shadows += int(standing.light.visible and standing.light.shadow_enabled)
	_expect("light-limits", lights == weather.visible_candidates and shadows == lights, {"lights":lights,"shadows":shadows})
	var old_focus: Vector3 = weather.ground_focus
	root.get_camera_3d().global_position += Vector3(32, 0, 16)
	for unused: int in 3:
		await process_frame
	_expect("rain-follows-camera", weather.rain.emitting and weather.ground_focus.distance_to(old_focus) > 30 and weather.rain.global_position.distance_to(weather.heightfield.global_position) == 12, weather.ground_focus)
	var output := {"placements":placements,"trace":trace,"peak_tilt":peak_tilt,"push_m":peak_push,"fallen_recontact_push_m":repeat_push,"lights":lights,"shadows":shadows,"failures":failures,"engine":Engine.get_version_info()}
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../weather-lamp-trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	file.close()
	main.queue_free()
	await _frames(2)
	print("WEATHER_LAMP failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
