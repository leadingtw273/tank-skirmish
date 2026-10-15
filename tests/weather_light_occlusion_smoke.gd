## 原生圖形 smoke：兩款真 GLB 開陰影亮度、月光柱影與其他物件遮光。
extends SceneTree

var cams: Array[Camera3D] = []
var result := {}
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _sample_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for x in range(-14, 15):
		for z in range(-14, 15):
			# 排除燈柱／燈臂正下方，避免取到燈具本體像素。
			if absf(x) <= 3 and absf(z) <= 2:
				continue
			pts.append(Vector3(x, 0, z))
	return pts

func _measure(cam: Camera3D, pts: Array[Vector3]) -> PackedFloat32Array:
	var img := root.get_texture().get_image()
	var lum := PackedFloat32Array()
	for p in pts:
		var s := cam.unproject_position(p)
		var px := Vector2i(clampi(int(s.x), 0, img.get_width() - 1), clampi(int(s.y), 0, img.get_height() - 1))
		lum.append(img.get_pixelv(px).get_luminance())
	return lum

func _mean(a: PackedFloat32Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / maxf(1, a.size())

func _effect_shadow_control(lamp: RigidBody3D, floor: MeshInstance3D, camera: Camera3D, out: String, variant: int) -> Dictionary:
	var wall := StaticBody3D.new()
	root.add_child(wall)
	wall.position = Vector3(0,4.2,3)
	var box := BoxMesh.new()
	box.size = Vector3(18,8.4,0.5)
	var wall_visual := MeshInstance3D.new()
	wall_visual.mesh = box
	wall.add_child(wall_visual)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collider.shape = shape
	wall.add_child(collider)
	var atmosphere := Node3D.new()
	atmosphere.set_script(load("res://src/maps/main_battlefield/lamp_atmosphere.gd"))
	lamp.add_child(atmosphere)
	atmosphere.set_process(false)
	var glint := ShaderMaterial.new()
	glint.shader = load("res://src/maps/main_battlefield/wet_road_glint.gdshader")
	var rain_material := ShaderMaterial.new()
	rain_material.shader = load("res://src/maps/main_battlefield/lit_rain.gdshader")
	var rain := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15,0.8)
	quad.material = rain_material
	rain.mesh = quad
	root.add_child(rain)
	rain.position = Vector3(6,1,5)
	var positions := PackedVector3Array([lamp.light.global_position,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	var active := PackedFloat32Array([1,0,0,0,0,0])
	glint.set_shader_parameter("lamp_positions",positions)
	glint.set_shader_parameter("lamp_active",active)
	rain_material.set_shader_parameter("lamp_positions",positions)
	rain_material.set_shader_parameter("lamp_ranges",PackedFloat32Array([22,0,0,0,0,0]))
	var points: Array[Vector3] = []
	for x: float in [5.5,6.0,6.5]:
		for z: float in [4.5,5.0,5.5]:
			points.append(Vector3(x,0,z))
	camera.current = true
	var measurements := {}
	var original_energy: float = lamp.light.light_energy
	for state: String in ["cold-baseline","blocked","unblocked"]:
		lamp.call("set_light_active",true,true)
		lamp.light.light_energy = 0.0 if state == "cold-baseline" else original_energy
		atmosphere.visible = state != "cold-baseline"
		floor.mesh.material.next_pass = null if state == "cold-baseline" else glint
		rain_material.set_shader_parameter("lamp_active",PackedFloat32Array([0,0,0,0,0,0]) if state == "cold-baseline" else active)
		var colors := PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
		if state != "cold-baseline":
			var color: Color = lamp.light.light_color.srgb_to_linear() * original_energy
			colors[0] = Vector3(color.r,color.g,color.b)
		rain_material.set_shader_parameter("lamp_colors",colors)
		if state == "unblocked":
			wall_visual.visible = false
			wall.collision_layer = 0
		await _frames(30)
		var image := root.get_texture().get_image()
		image.save_png(out + "/lamp%d-effects-%s.png" % [variant,state])
		var rain_pixel := Vector2i(camera.unproject_position(rain.global_position))
		measurements[state] = {"floor":_mean(_measure(camera,points)),"rain":image.get_pixelv(rain_pixel).get_luminance()}
		if state == "blocked":
			measurements["hidden_halos"] = atmosphere.halos.all(func(halo: MeshInstance3D): return not halo.visible)
	if measurements.blocked.floor > measurements["cold-baseline"].floor + 0.005 or measurements.blocked.rain > measurements["cold-baseline"].rain + 0.01 or not measurements.hidden_halos:
		failures.append("lamp%d:effects-leak-through-wall" % variant)
	if measurements.unblocked.floor <= measurements["cold-baseline"].floor + 0.02 or measurements.unblocked.rain <= measurements["cold-baseline"].rain + 0.01:
		failures.append("lamp%d:unblocked-effects-control" % variant)
	floor.mesh.material.next_pass = null
	atmosphere.queue_free()
	wall.queue_free()
	rain.queue_free()
	lamp.light.light_energy = original_energy
	await _frames(3)
	return measurements

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("weather_light_occlusion_smoke 必須用原生圖形 renderer 執行")
		quit(2)
		return
	var tag := "author-native-smoke"
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	mat.roughness = 1.0
	plane.material = mat
	floor.mesh = plane
	root.add_child(floor)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 32
	root.add_child(top)
	top.look_at_from_position(Vector3(0, 30, 0.001), Vector3.ZERO, Vector3.UP)
	var oblique := Camera3D.new()
	oblique.fov = 60
	root.add_child(oblique)
	oblique.look_at_from_position(Vector3(14, 16, 14), Vector3(0, 0, 0), Vector3.UP)
	cams = [top, oblique]
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 1.0
	sun.visible = false
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-35, 0, 0)  # 由 +Z 往 -Z 方向斜照，柱影落向 -Z。
	var pts := _sample_points()
	result = {"tag": tag, "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "samples": pts.size(), "lamps": {}}
	for variant in [1, 2]:
		var lamp := (load("res://src/maps/main_battlefield/street_lamp.tscn") as PackedScene).instantiate() as RigidBody3D
		lamp.model_variant = variant
		root.add_child(lamp)
		lamp.freeze = true
		lamp.get_node("LampAtmosphere").queue_free()
		await _frames(4)
		var casts := []
		for v: GeometryInstance3D in lamp.get("visuals"):
			casts.append({"name": str(v.name), "cast_shadow": v.cast_shadow, "layers": v.layers})
		var row := {"visual_cast_shadow": casts, "warm_shadow_caster_mask":lamp.light.shadow_caster_mask, "views": {}}
		for ci in cams.size():
			var cam := cams[ci]
			cam.current = true
			var view := {}
			var lums := {}
			for state in ["off", "noshadow", "shadow"]:
				lamp.call("set_light_active", state != "off", state == "shadow")
				await _frames(10)
				lums[state] = _measure(cam, pts)
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/lamp%d-%s-%s.png" % [out, variant, ["top", "oblique"][ci], state]))
				view[state + "_mean"] = _mean(lums[state])
			var lit_ns: float = view.noshadow_mean - view.off_mean
			var lit_s: float = view.shadow_mean - view.off_mean
			view["retained_ratio"] = lit_s / lit_ns if lit_ns > 0 else -1.0
			var darkened := 0
			for i in pts.size():
				var a: float = lums.noshadow[i] - lums.off[i]
				var b: float = lums.shadow[i] - lums.off[i]
				if a > 0.01 and b < a * 0.5:
					darkened += 1
			view["darkened_samples_gt50pct"] = darkened
			row.views[["top", "oblique"][ci]] = view
		# AC5：燈具是否仍在「其他光源」（方向光）下投影。
		lamp.call("set_light_active", false, false)
		top.current = true
		sun.visible = true
		await _frames(10)
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/lamp%d-top-sun.png" % [out, variant]))
		# 方向光 -35° 俯角，6m 高燈柱影子約落在 z ∈ [-8.5, -0.5]；對照帶在 x=±4。
		var shade := PackedFloat32Array()
		var ref := PackedFloat32Array()
		for zi in range(1, 9):
			var z := -float(zi)
			var off_x := 0.6 if variant == 1 else 0.0
			var s1 := top.unproject_position(Vector3(off_x * 0.0, 0, z))
			var s2 := top.unproject_position(Vector3(4, 0, z))
			shade.append(img.get_pixelv(Vector2i(s1)).get_luminance())
			ref.append(img.get_pixelv(Vector2i(s2)).get_luminance())
		row["sun_pole_shadow_strip_mean"] = _mean(shade)
		row["sun_reference_strip_mean"] = _mean(ref)
		sun.visible = false
		# layer 1 控制物仍須遮擋暖光，避免「100%」來自關閉所有陰影。
		var blocker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2, 3, 2)
		blocker.mesh = box
		root.add_child(blocker)
		blocker.position = Vector3(5, 1.5, 0)
		var control_points: Array[Vector3] = []
		for x in range(7, 11):
			for z in range(-1, 2):
				control_points.append(Vector3(x, 0, z))
		var control := {}
		for state: String in ["noshadow", "shadow"]:
			lamp.call("set_light_active", true, state == "shadow")
			await _frames(10)
			control[state + "_mean"] = _mean(_measure(top, control_points))
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/lamp%d-other-caster-%s.png" % [out, variant, state]))
		row["other_caster_control"] = control
		blocker.queue_free()
		await _frames(3)
		row["effect_shadow_control"] = await _effect_shadow_control(lamp,floor,oblique,out,variant)
		result.lamps["lamp_%d" % variant] = row
		lamp.queue_free()
		await _frames(3)
	for name: String in result.lamps:
		var row: Dictionary = result.lamps[name]
		for view: String in row.views:
			var retained: float = row.views[view].retained_ratio
			if retained < 0.995:
				failures.append(name + ":" + view + ":self-shadow")
		if row.sun_pole_shadow_strip_mean >= row.sun_reference_strip_mean * 0.95:
			failures.append(name + ":sun-pole-shadow")
		if row.other_caster_control.shadow_mean >= row.other_caster_control.noshadow_mean * 0.25:
			failures.append(name + ":other-caster")
	result["failures"] = failures
	var f := FileAccess.open(out + "/metrics.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	print("WEATHER_LIGHT_OCCLUSION failures=", failures.size(), " ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
