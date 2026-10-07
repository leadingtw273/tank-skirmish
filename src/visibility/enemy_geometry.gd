extends Node
## 本敵幾何資料；與原 picking mask 分開，只借用來源 mesh/skin。

const DataShader := preload("res://src/visibility/enemy_geometry.gdshader")
var _viewport: SubViewport
var _camera: Camera3D
var _material: ShaderMaterial
var _sources: Array[MeshInstance3D] = []
var _proxies: Array[MeshInstance3D] = []
var _skeletons: Dictionary = {}
var depth_min := 0.0
var depth_span := 1.0


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "EnemyGeometryData"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	# 同 player_fade_depth 的線性 RGBA16F 資料路徑。
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
	_camera.current = true
	_viewport.add_child(_camera)
	_material = ShaderMaterial.new()
	_material.shader = DataShader


func configure(sources: Array[MeshInstance3D]) -> void:
	clear()
	_sources.assign(sources)
	for source in _sources:
		var proxy := MeshInstance3D.new()
		proxy.mesh = source.mesh
		proxy.material_override = _material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_viewport.add_child(proxy)
		if source.skin != null:
			var skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D
			if skeleton != null:
				proxy.skin = source.skin
				proxy.skeleton = proxy.get_path_to(_skeleton_proxy(skeleton))
		_proxies.append(proxy)


func sync(camera: Camera3D, dimensions: Vector2i, composite: ShaderMaterial) -> void:
	_viewport.size = dimensions
	for key in [&"projection", &"size", &"fov", &"near", &"far", &"keep_aspect", &"frustum_offset", &"h_offset", &"v_offset"]:
		_camera.set(key, camera.get(key))
	_camera.global_transform = camera.global_transform
	for source: Skeleton3D in _skeletons:
		if not is_instance_valid(source) or not source.is_inside_tree():
			continue
		var proxy: Skeleton3D = _skeletons[source]
		proxy.global_transform = source.global_transform
		proxy.motion_scale = source.motion_scale
		for bone in source.get_bone_count():
			proxy.set_bone_pose_position(bone, source.get_bone_pose_position(bone))
			proxy.set_bone_pose_rotation(bone, source.get_bone_pose_rotation(bone))
			proxy.set_bone_pose_scale(bone, source.get_bone_pose_scale(bone))
	var closest := INF
	var farthest := -INF
	var view := camera.global_transform.affine_inverse()
	for index in _sources.size():
		var source := _sources[index]
		var proxy := _proxies[index]
		proxy.visible = is_instance_valid(source) and source.is_inside_tree() and source.is_visible_in_tree()
		if not proxy.visible:
			continue
		proxy.mesh = source.mesh
		proxy.global_transform = source.global_transform
		var transform := view * source.global_transform
		var box := source.get_aabb()
		for corner in 8:
			var depth := -(transform * box.get_endpoint(corner)).z
			closest = minf(closest, depth)
			farthest = maxf(farthest, depth)
	if is_finite(closest):
		# 真來源幾何 bounds 隨姿態／相機更新，留出履帶 pose 的有限 margin。
		depth_min = closest - 0.5
		depth_span = maxf(farthest - closest + 1.0, 1.0)
	_material.set_shader_parameter(&"depth_min", depth_min)
	_material.set_shader_parameter(&"depth_span", depth_span)
	composite.set_shader_parameter(&"geometry_data", texture())
	composite.set_shader_parameter(&"depth_min", depth_min)
	composite.set_shader_parameter(&"depth_span", depth_span)
	composite.set_shader_parameter(&"inverse_projection", camera.get_camera_projection().inverse())
	composite.set_shader_parameter(&"orthogonal", camera.projection == Camera3D.PROJECTION_ORTHOGONAL)


func _skeleton_proxy(source: Skeleton3D) -> Skeleton3D:
	if _skeletons.has(source):
		return _skeletons[source]
	var proxy := Skeleton3D.new()
	_viewport.add_child(proxy)
	for bone in source.get_bone_count():
		proxy.add_bone(source.get_bone_name(bone))
	for bone in source.get_bone_count():
		proxy.set_bone_parent(bone, source.get_bone_parent(bone))
		proxy.set_bone_rest(bone, source.get_bone_rest(bone))
		proxy.set_bone_enabled(bone, source.is_bone_enabled(bone))
	_skeletons[source] = proxy
	return proxy


func texture() -> ViewportTexture:
	return _viewport.get_texture()


func set_active(enabled: bool) -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED


func clear() -> void:
	for proxy in _proxies:
		proxy.free()
	for proxy: Skeleton3D in _skeletons.values():
		proxy.free()
	_sources.clear()
	_proxies.clear()
	_skeletons.clear()
