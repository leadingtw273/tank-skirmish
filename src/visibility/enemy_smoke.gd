extends Node
## 僅借原 Smoke 的 VisualInstance base；自有 instance、不建立或重啟 emitter。

var _viewport: SubViewport
var _camera: Camera3D
var _target: Node3D
var _instances: Dictionary = {}
var _active := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "EnemyRealSmokeAlpha"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	_camera = Camera3D.new()
	_camera.current = true
	_viewport.add_child(_camera)
	RenderingServer.frame_pre_draw.connect(_sync_instances)


func configure(target: Node3D) -> void:
	clear()
	_target = target


func sync(camera: Camera3D, dimensions: Vector2i) -> void:
	_viewport.size = dimensions
	for key in [&"projection", &"size", &"fov", &"near", &"far", &"keep_aspect", &"frustum_offset", &"h_offset", &"v_offset"]:
		_camera.set(key, camera.get(key))
	_camera.global_transform = camera.global_transform
	_sync_instances()


func _sync_instances() -> void:
	var required: Dictionary = {}
	if _active and is_instance_valid(_target) and _target.is_inside_tree():
		# retired stage 尚可見的殘粒同樣在本車 damage anchor 子樹，不看 emitting。
		for source: GPUParticles3D in _target.find_children("Smoke", "GPUParticles3D", true, false):
			if source.is_visible_in_tree() and String(source.get_path()).contains("DamageVFXAnchor/"):
				required[source] = true
	for source in _instances.keys():
		if not is_instance_valid(source) or not required.has(source):
			RenderingServer.free_rid(_instances[source])
			_instances.erase(source)
	for source: GPUParticles3D in required:
		if not _instances.has(source):
			var instance := RenderingServer.instance_create()
			RenderingServer.instance_set_base(instance, source.get_base())
			RenderingServer.instance_set_scenario(instance, _viewport.find_world_3d().scenario)
			RenderingServer.instance_geometry_set_cast_shadows_setting(instance, RenderingServer.SHADOW_CASTING_SETTING_OFF)
			_instances[source] = instance
		var instance: RID = _instances[source]
		RenderingServer.instance_set_transform(instance, source.global_transform)
		RenderingServer.instance_set_visible(instance, source.is_visible_in_tree())
		if source.material_override != null:
			RenderingServer.instance_geometry_set_material_override(instance, source.material_override.get_rid())


func texture() -> ViewportTexture:
	return _viewport.get_texture()


func set_active(enabled: bool) -> void:
	_active = enabled
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	_sync_instances()


func clear() -> void:
	for instance: RID in _instances.values():
		RenderingServer.free_rid(instance)
	_instances.clear()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_instances):
		RenderingServer.frame_pre_draw.disconnect(_sync_instances)
	clear()
