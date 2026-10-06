extends Node
## 玩家淡出專用原近表面資料；獨立 World3D 不寫主場 depth。

const DepthShader := preload("res://src/visibility/player_fade_depth.gdshader")
var _viewport: SubViewport
var _camera: Camera3D
var _material: ShaderMaterial
var _disabled_material: ShaderMaterial
var _proxies: Dictionary = {}


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PlayerFadeNearestSurface"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	# Linear RGBA16F avoids display transfer functions on packed data.
	_viewport.use_hdr_2d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_camera.current = true
	_material = ShaderMaterial.new()
	_material.shader = DepthShader
	_disabled_material = ShaderMaterial.new()
	_disabled_material.shader = DepthShader
	_disabled_material.set_shader_parameter(&"surface_enabled", false)


func sync(main_camera: Camera3D, window: Dictionary, effects: Array, foreground_depth: float) -> void:
	var required: Dictionary = {}
	for effect in effects:
		for source in effect.depth_sources():
			required[source.mesh] = source.surfaces
	for source in _proxies.keys():
		if not is_instance_valid(source) or not required.has(source):
			_proxies[source].free()
			_proxies.erase(source)
	if required.is_empty():
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var main_viewport := main_camera.get_viewport()
	var render_size := Vector2(main_viewport.get_texture().get_size()) * main_viewport.scaling_3d_scale
	_viewport.size = Vector2i(maxi(roundi(render_size.x), 1), maxi(roundi(render_size.y), 1))
	for property in [&"projection", &"size", &"fov", &"near", &"far", &"keep_aspect", &"frustum_offset", &"h_offset", &"v_offset", &"cull_mask"]:
		_camera.set(property, main_camera.get(property))
	_camera.global_transform = main_camera.global_transform
	_material.set_shader_parameter(&"window_center_pixels", window.center)
	_material.set_shader_parameter(&"window_radius_pixels", window.radius_pixels)
	_material.set_shader_parameter(&"viewport_size", window.viewport_size)
	_material.set_shader_parameter(&"foreground_enabled", is_finite(foreground_depth))
	_material.set_shader_parameter(&"foreground_depth", foreground_depth if is_finite(foreground_depth) else 0.0)
	for source: MeshInstance3D in required:
		if not _proxies.has(source):
			var proxy := MeshInstance3D.new()
			proxy.mesh = source.mesh
			proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_viewport.add_child(proxy)
			for surface in source.mesh.get_surface_count():
				proxy.set_surface_override_material(surface, _material if surface in required[source] else _disabled_material)
			_proxies[source] = proxy
		var proxy: MeshInstance3D = _proxies[source]
		proxy.global_transform = source.global_transform
		proxy.layers = source.layers
		proxy.visible = source.is_visible_in_tree()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func texture() -> ViewportTexture:
	return _viewport.get_texture()


func clear() -> void:
	for proxy in _proxies.values():
		proxy.free()
	_proxies.clear()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
