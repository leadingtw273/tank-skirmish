extends SceneTree
## 真 Forward+ attachment 與 GPU sampler roundtrip；headless 不冒充圖形證據。
const Depth := preload("res://src/visibility/player_fade_depth.gd")
const Fade := preload("res://src/visibility/building_fade.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PLAYER_FADE_DEPTH requires graphical Forward+; no GPU claim")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 50.0
	camera.far = 400.0
	world.add_child(camera)
	camera.current = true
	var building := Node3D.new()
	world.add_child(building)
	var source := StandardMaterial3D.new()
	source.cull_mode = BaseMaterial3D.CULL_DISABLED
	var depths := [13.123456, 13.1267]
	for i in 2:
		var visual := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(40.0, 40.0) if i == 1 else Vector2(20.0, 40.0)
		mesh.material = source
		visual.mesh = mesh
		building.add_child(visual)
		visual.position = Vector3(0.0 if i == 1 else -10.0, 0.0, -depths[i])
	var effect := Fade.new(building)
	var helper := Depth.new()
	world.add_child(helper)
	var window := {"center": Vector2(640, 360), "radius_pixels": 200.0, "viewport_size": Vector2(1280, 720)}
	helper.sync(camera, window, [effect], -15.0)
	var consumer := SubViewport.new()
	consumer.size = Vector2i(1280, 720)
	consumer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(consumer)
	var rectangle := ColorRect.new()
	rectangle.size = Vector2(1280, 720)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D data_texture : filter_nearest, repeat_disable;
void fragment() {
 vec4 value = texture(data_texture, UV);
 vec3 bytes = floor(value.rgb * 255.0 + 0.5);
 float depth = dot(bytes, vec3(65536.0, 256.0, 1.0)) / 4096.0;
 float expected = UV.x < 0.5 ? 13.123456 : 13.1267;
 COLOR = value.a < 0.5 ? vec4(0.0,0.0,1.0,1.0) : (abs(depth - expected) <= 0.0005 ? vec4(0.0,1.0,0.0,1.0) : vec4(1.0,0.0,0.0,1.0));
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"data_texture", helper.texture())
	rectangle.material = material
	consumer.add_child(rectangle)
	for _frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := helper.texture().get_image()
	var decoded := consumer.get_texture().get_image()
	var max_error := 0.0
	for x in range(442, 839):
		var value := image.get_pixel(x, 360)
		var expected: float = depths[0 if x < 640 else 1]
		var bytes := Vector3(roundf(value.r * 255.0), roundf(value.g * 255.0), roundf(value.b * 255.0))
		var depth := bytes.dot(Vector3(65536, 256, 1)) / 4096.0
		max_error = maxf(max_error, absf(depth - expected))
		expect(value.a > 0.99 and absf(depth - expected) <= 0.0005, "raw nearest depth x=" + str(x))
		expect(decoded.get_pixel(x, 360).g > 0.99, "GPU decode / nearest sample x=" + str(x))
	expect(image.get_pixel(400, 360).a == 0.0 and decoded.get_pixel(400, 360).b > 0.99, "clear outside window cannot select background")
	helper.sync(camera, window, [effect], -12.0)
	for _frame in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	expect(helper.texture().get_image().get_pixel(550, 360).a == 0.0, "foreground gate rejects both deeper original surfaces")
	helper.clear()
	expect(helper.get("_proxies").is_empty(), "cleanup removes all proxies")
	effect.restore()
	print("PLAYER_FADE_DEPTH format=", image.get_format(), " max_error_m=", max_error, " GPU_pixels=397 failures=", failures.size())
	world.queue_free()
	consumer.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
