## 原生 GPU 回歸：真粒子分布／陣風／屋頂碰撞／落地槽位回收，不以節點存在冒充發射。
extends SceneTree

const RAIN := preload("res://src/maps/main_battlefield/rain_volume.gd")
const COLUMNS := 60
const TILE := Vector2i(28,4)
const IMPACT_ROW := 125
var _failures: Array[String] = []
var _output: String
var _births := {}
var _columns := {}
var _samples: Array[Dictionary] = []
var _images: Array[Image] = []
var _seed_min := 31
var _seed_max := 0
var _roof_drops := 0
var _roof_hits := 0
var _floor_hits := 0

func _init() -> void:
	call_deferred("_run")

func _check(label: String, valid: bool) -> void:
	if not valid and not _failures.has(label):
		_failures.append(label)

func _unpack(image: Image, slot: int, stripe: int, row_offset: int) -> int:
	var color := image.get_pixel((slot % COLUMNS)*TILE.x+stripe*4+2,
		image.get_height()-1-((slot/COLUMNS+row_offset)*TILE.y+2))
	return roundi(color.r*255.0) | (roundi(color.g*255.0)<<8) | (roundi(color.b*255.0)<<16)

func _draw_probe(impact: bool) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never;
uniform bool impact = false;
uniform int row_offset = 0;
varying flat vec4 data;
varying flat vec4 custom;
varying flat vec3 world;
void vertex() {
 data=COLOR; custom=INSTANCE_CUSTOM; world=MODEL_MATRIX[3].xyz;
 vec2 pixel=vec2(mod(COLOR.r,60.0)*28.0,(floor(COLOR.r/60.0)+float(row_offset))*4.0)+UV*vec2(28.0,4.0);
 POSITION=vec4(pixel.x/1920.0*2.0-1.0,1.0-pixel.y/1080.0*2.0,0.0,1.0);
 if (length(MODEL_MATRIX[0].xyz)<0.001) POSITION=vec4(2.0,2.0,0.0,1.0);
}
vec3 pack_value(float value) {
 uint bits=uint(round(value));
 vec3 bytes=vec3(float(bits&255u),float((bits>>8u)&255u),float((bits>>16u)&255u))/255.0;
 return mix(bytes/12.92,pow((bytes+0.055)/1.055,vec3(2.4)),greaterThan(bytes,vec3(0.04045)));
}
void fragment() {
 int stripe=int(floor(UV.x*7.0));
 float value=(impact ? world.x : data.z)+512.0; value*=64.0;
 if (stripe==1) value=((impact ? world.z : data.w)+512.0)*64.0;
 if (stripe==2) {
  uvec2 speed=uvec2(clamp(round((custom.zw+vec2(16.0))*128.0),vec2(0.0),vec2(4095.0)));
  value=impact ? max(0.0,custom.y)*4096.0 : float(speed.x|(speed.y<<12u));
 }
 if (stripe==3) value=float((uint(data.y)&524287u)*32u+uint(clamp(custom.x,0.0,0.9999)*31.0));
 if (stripe==4) value=(world.x+512.0)*64.0;
 if (stripe==5) value=(world.y+64.0)*128.0;
 if (stripe==6) value=(world.z+512.0)*64.0;
 ALBEDO=pack_value(value);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("impact",impact)
	material.set_shader_parameter("row_offset",IMPACT_ROW if impact else 0)
	return material

func _instrument(rain: GPUParticles3D) -> void:
	var source: String = rain.process_material.shader.code
	assert(source.contains("COLOR = vec4(1.0);"),"雨的診斷接點已變更，不能默默測錯 shader")
	var shader := Shader.new()
	shader.code = source.replace("COLOR = vec4(1.0);","COLOR = vec4(float(INDEX),float(NUMBER),TRANSFORM[3].x,TRANSFORM[3].z);")
	var process := ShaderMaterial.new()
	process.shader = shader
	rain.process_material = process
	rain.draw_pass_1 = rain.draw_pass_1.duplicate()
	rain.draw_pass_1.material = _draw_probe(false)
	rain.layers = 1<<17
	var impacts: GPUParticles3D = rain.get_node("RainSurfaceImpacts")
	var impact_shader := Shader.new()
	impact_shader.code = impacts.process_material.shader.code.replace("void process() {","void process() { COLOR.r=float(INDEX);")
	var impact_process := ShaderMaterial.new()
	impact_process.shader = impact_shader
	impacts.process_material = impact_process
	impacts.draw_pass_1 = impacts.draw_pass_1.duplicate()
	impacts.draw_pass_1.material = _draw_probe(true)
	impacts.layers = 1<<17
	rain.use_fixed_seed = true
	rain.seed = 21204
	rain.restart()

func _read(image: Image, elapsed: float, rain: GPUParticles3D) -> Dictionary:
	var active := 0
	var speed := Vector2.ZERO
	for slot: int in rain.amount:
		var x := _unpack(image,slot,0,0)
		if x==0: continue
		var z := _unpack(image,slot,1,0)
		var marker := _unpack(image,slot,3,0)
		var key := Vector4i(slot,marker>>5,x,z)
		if not _births.has(key):
			_births[key] = true
			var column := Vector2i(x,z)
			_columns[column] = int(_columns.get(column,0))+1
		_seed_min = mini(_seed_min,marker&31)
		_seed_max = maxi(_seed_max,marker&31)
		var velocity := _unpack(image,slot,2,0)
		speed += Vector2(float(velocity&4095)/128.0-16.0,float(velocity>>12)/128.0-16.0)
		active += 1
		var point := Vector3(float(_unpack(image,slot,4,0))/64.0-512.0,
			float(_unpack(image,slot,5,0))/128.0-64.0,float(_unpack(image,slot,6,0))/64.0-512.0)
		if absf(point.x)<9.0 and absf(point.z)<9.0:
			_roof_drops += 1
			_check("rain-below-roof",point.y>=4.8)
	var impacts: GPUParticles3D = rain.get_node("RainSurfaceImpacts")
	var live := 0
	var expired := 0
	var max_age := 0.0
	for slot: int in impacts.amount:
		if _unpack(image,slot,0,IMPACT_ROW)==0: continue
		var age := float(_unpack(image,slot,2,IMPACT_ROW))/4096.0
		max_age = maxf(max_age,age)
		expired += int(age>1.05)
		live += int(age<1.0)
		var point := Vector3(float(_unpack(image,slot,4,IMPACT_ROW))/64.0-512.0,
			float(_unpack(image,slot,5,IMPACT_ROW))/128.0-64.0,float(_unpack(image,slot,6,IMPACT_ROW))/64.0-512.0)
		if absf(point.x)<9.0 and absf(point.z)<9.0:
			_roof_hits += 1
			_check("impact-not-on-roof",absf(point.y-5.018)<0.2)
		elif absf(point.x)>11.0 or absf(point.z)>11.0:
			_floor_hits += 1
			_check("impact-not-on-floor",absf(point.y-0.018)<0.2)
	return {"seconds":elapsed,"rain_active":active,"mean_wind":speed/float(maxi(active,1)),
		"young_impacts":live,"expired_active_impacts":expired,"max_impact_age":max_age,"foreground":DisplayServer.window_is_focused()}

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("weather_rain_gpu_smoke 需要原生圖形 renderer")
		quit(2)
		return
	_output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_output)
	root.borderless = true
	root.size = Vector2i(1920,1080)
	root.position = Vector2i.ZERO
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	scene.add_child(environment)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 100
	camera.look_at_from_position(Vector3(80,73,81),Vector3.ZERO)
	camera.cull_mask = 1<<17
	camera.current = true
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor.mesh = plane
	scene.add_child(floor)
	var roof := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(20,2,20)
	roof.mesh = box
	scene.add_child(roof)
	roof.position.y = 4.0
	var rain := RAIN.new()
	scene.add_child(rain)
	rain.position.y = 32.0
	_instrument(rain)
	var field := GPUParticlesCollisionHeightField3D.new()
	field.size = Vector3(180,80,180)
	field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	field.follow_camera_enabled = false
	field.heightfield_mask = 1
	scene.add_child(field)
	field.position.y = 20.0
	for frame: int in 360: await process_frame
	root.grab_focus()
	var started := Time.get_ticks_usec()
	var next_sample := started
	while true:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := float(now-started)/1000000.0
		if now>=next_sample:
			var image := root.get_texture().get_image()
			_images.append(image)
			_samples.append(_read(image,elapsed,rain))
			next_sample = now+200000
		if elapsed>=9.1: break
	var minimum_wind := Vector2(INF,INF)
	var maximum_wind := Vector2(-INF,-INF)
	for sample: Dictionary in _samples:
		minimum_wind = minimum_wind.min(sample.mean_wind)
		maximum_wind = maximum_wind.max(sample.mean_wind)
		_check("impact-expired-remains-active",sample.expired_active_impacts==0)
		_check("impacts-not-continuous",sample.young_impacts>=10)
	var unique_fraction := float(_columns.size())/float(maxi(_births.size(),1))
	var reuse := 0
	for count: int in _columns.values(): reuse = maxi(reuse,count)
	_check("spawn-columns-concentrated",unique_fraction>0.90 and reuse<10)
	_check("wind-not-time-varying",(maximum_wind-minimum_wind).length()>0.5)
	_check("drop-variation-missing",_seed_max-_seed_min>=24)
	_check("roof-controls-not-observed",_roof_drops>=20 and _roof_hits>=5 and _floor_hits>=20)
	rain.emitting = false
	var stop_started := Time.get_ticks_usec()
	while Time.get_ticks_usec()-stop_started<3400000: await process_frame
	await RenderingServer.frame_post_draw
	var stopped_image := root.get_texture().get_image()
	var stopped := _read(stopped_image,12.5,rain)
	_check("impact-not-recycled-after-stop",stopped.young_impacts==0 and stopped.expired_active_impacts==0)
	for index: int in _images.size(): _images[index].save_png(_output+"/state-%04d.png"%index)
	stopped_image.save_png(_output+"/stopped.png")
	var result := {"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"samples":_samples,"birth_states":_births.size(),
		"unique_columns":_columns.size(),"unique_fraction":unique_fraction,"max_column_reuse":reuse,
		"wind_range":maximum_wind-minimum_wind,"seed_range":[_seed_min,_seed_max],
		"roof_drop_samples":_roof_drops,"roof_impact_samples":_roof_hits,"floor_impact_samples":_floor_hits,
		"after_stop":stopped,"diagnostic_fixed_seed":21204,"failures":_failures}
	var file := FileAccess.open(_output+"/metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("WEATHER_RAIN_GPU failures=",_failures.size()," ",_failures," unique=",unique_fraction," reuse=",reuse)
	scene.queue_free()
	for frame: int in 3: await process_frame
	quit(0 if _failures.is_empty() else 1)
