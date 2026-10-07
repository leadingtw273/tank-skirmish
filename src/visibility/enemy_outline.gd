extends Node
## 獨立車體 silhouette；資格、相機建築遮蔽與共同世界半徑由 controller 決定。

const OutlineShader := preload("res://src/visibility/enemy_outline.gdshader")
const GeometryPass := preload("res://src/visibility/enemy_geometry.gd")
const SmokePass := preload("res://src/visibility/enemy_smoke.gd")
const LINE_RADIUS := 2
const MAX_QUERIES := 64
# 同一真部件的所有 surfaces 共用色碼；RGB 僅供紅線視覺，拾取仍只讀 alpha。
const PART_COLORS := {
	&"hull": Color(1.0, 0.0, 0.0),
	&"upper": Color(0.0, 1.0, 0.0),
	&"gun": Color(0.0, 0.0, 1.0),
	&"left_track": Color(1.0, 1.0, 0.0),
	&"right_track": Color(0.0, 1.0, 1.0),
}

var target: Node3D
var active := false
var _main_camera: Camera3D
var _viewport: SubViewport
var _camera: Camera3D
var _overlay: TextureRect
var _material: ShaderMaterial
var _part_materials: Dictionary = {}
var _sources: Array[MeshInstance3D] = []
var _proxies: Array[MeshInstance3D] = []
var _skeleton_sources: Array[Skeleton3D] = []
var _skeleton_proxies: Array[Skeleton3D] = []
var _has_skinned_mesh := false
var _center := Vector2.ZERO
var _radius := 0.0
var _screen_size := Vector2.ONE
var _projected_bounds := Rect2()
var _has_bounds := false
var _image: Image
var _image_frame := -1
var _geometry: Node
var _smoke: Node


func configure(enemy: Node3D, main_camera: Camera3D) -> void:
	set_active(false)
	if is_instance_valid(target):
		if target.tree_exiting.is_connected(_on_target_exiting):
			target.tree_exiting.disconnect(_on_target_exiting)
	target = enemy
	_main_camera = main_camera
	if _viewport == null:
		_create_renderer()
	for proxy in _proxies:
		proxy.free()
	for skeleton in _skeleton_proxies:
		skeleton.free()
	_sources.clear()
	_proxies.clear()
	_skeleton_sources.clear()
	_skeleton_proxies.clear()
	_has_skinned_mesh = false
	_geometry.clear()
	_smoke.configure(target)
	if not is_instance_valid(target):
		return
	target.tree_exiting.connect(_on_target_exiting)
	_collect_meshes(target)
	_geometry.configure(_sources)
	_sync_meshes()
	_update_line_color()


func update_window(main_camera: Camera3D, window: Dictionary) -> void:
	_main_camera = main_camera
	if _viewport == null or not _target_valid() or not is_instance_valid(_main_camera):
		set_active(false)
		return
	_center = window.get("center", Vector2.ZERO)
	_radius = float(window.get("radius_pixels", 0.0))
	_screen_size = window.get("viewport_size", main_camera.get_viewport().get_visible_rect().size)
	var dimensions := Vector2i(maxi(roundi(_screen_size.x), 1), maxi(roundi(_screen_size.y), 1))
	_viewport.size = dimensions
	_overlay.size = _screen_size
	_camera.projection = main_camera.projection
	_camera.size = main_camera.size
	_camera.fov = main_camera.fov
	_camera.near = main_camera.near
	_camera.far = main_camera.far
	_camera.keep_aspect = main_camera.keep_aspect
	_camera.frustum_offset = main_camera.frustum_offset
	_camera.h_offset = main_camera.h_offset
	_camera.v_offset = main_camera.v_offset
	_camera.global_transform = main_camera.global_transform
	_material.set_shader_parameter("viewport_size", _screen_size)
	_material.set_shader_parameter("window_center", _center)
	_material.set_shader_parameter("radius_pixels", _radius)
	_update_line_color()
	_sync_meshes()
	_geometry.sync(main_camera, dimensions, _material)
	_smoke.sync(main_camera, dimensions)


func set_active(enabled: bool) -> void:
	active = enabled and _target_valid() and _viewport != null
	if _overlay != null:
		_overlay.visible = active
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		_image = null
	if _geometry != null:
		_geometry.set_active(active)
		_smoke.set_active(active)


func mask_image() -> Image:
	if not active or not _target_valid() or _viewport == null or DisplayServer.get_name() == "headless":
		return null
	var frame := Engine.get_process_frames()
	if _image_frame != frame:
		_image_frame = frame
		_image = _viewport.get_texture().get_image()
	return _image if _image != null and not _image.is_empty() else null


func pick(screen_position: Vector2, excluded: Array[RID] = [], collision_mask: int = 129) -> Dictionary:
	if not active or not _target_alive() or not is_instance_valid(_main_camera):
		return {}
	if _radius <= 0.0 or screen_position.distance_to(_center) >= _radius:
		return {}
	# 現役履帶超出靜態 mesh AABB；這些車只用共同 circle 粗篩。
	if not _has_skinned_mesh and (not _has_bounds or not _projected_bounds.grow(LINE_RADIUS + 1.0).has_point(screen_position)):
		return {}
	var mask := mask_image()
	if mask == null:
		return {}
	var pixel := Vector2i(screen_position.floor())
	var samples: Array[Vector2] = []
	for y in range(-LINE_RADIUS, LINE_RADIUS + 1):
		for x in range(-LINE_RADIUS, LINE_RADIUS + 1):
			if x * x + y * y > LINE_RADIUS * LINE_RADIUS:
				continue
			var candidate := pixel + Vector2i(x, y)
			if candidate.x < 0 or candidate.y < 0 or candidate.x >= mask.get_width() or candidate.y >= mask.get_height():
				continue
			if mask.get_pixelv(candidate).a > 0.1:
				samples.append(Vector2(candidate) + Vector2(0.5, 0.5))
	if samples.is_empty():
		return {}
	samples.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(screen_position) < b.distance_squared_to(screen_position))
	var ignored: Array[RID] = excluded.duplicate()
	var remaining := MAX_QUERIES
	var space := target.get_world_3d().direct_space_state
	for sample in samples:
		var origin := _main_camera.project_ray_origin(sample)
		var end := origin + _main_camera.project_ray_normal(sample) * _main_camera.far
		while remaining > 0:
			remaining -= 1
			var query := PhysicsRayQueryParameters3D.create(origin, end, collision_mask, ignored)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			if hit.get("collider") == target:
				return {"target": target, "position": hit.position}
			var rid: RID = hit.get("rid", RID())
			if not rid.is_valid() or ignored.has(rid):
				break
			ignored.append(rid)
		if remaining == 0:
			break
	# 真模型表面點 fallback；不能把建築交點或 AABB 中心當敵車命中。
	if target.has_method("part_world_surface_points"):
		var points: PackedVector3Array = target.call("part_world_surface_points")
		var nearest := Vector3.ZERO
		var best := INF
		for point in points:
			if _main_camera.is_position_behind(point):
				continue
			var distance := _main_camera.unproject_position(point).distance_squared_to(samples[0])
			if distance < best:
				best = distance
				nearest = point
		if best < INF:
			return {"target": target, "position": nearest}
	return {}


func _create_renderer() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "EnemyMask"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_camera.current = true
	for part in PART_COLORS:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = PART_COLORS[part]
		_part_materials[part] = material
	var layer := CanvasLayer.new()
	layer.name = "EnemyOutlineLayer"
	layer.layer = 1
	add_child(layer)
	_overlay = TextureRect.new()
	_overlay.name = "EnemyOutline"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.texture = _viewport.get_texture()
	_overlay.visible = false
	_material = ShaderMaterial.new()
	_material.shader = OutlineShader
	_geometry = GeometryPass.new()
	add_child(_geometry)
	_smoke = SmokePass.new()
	add_child(_smoke)
	_material.set_shader_parameter(&"smoke_alpha", _smoke.texture())
	_overlay.material = _material
	layer.add_child(_overlay)


func _collect_meshes(node: Node) -> void:
	# 原 VFX 面片保留自己的世界呈現，不納入車體 mask 或幾何細節。
	if node is MeshInstance3D and node.mesh != null and not node.is_in_group(&"effect_mesh"):
		var proxy := MeshInstance3D.new()
		proxy.mesh = node.mesh
		proxy.material_override = _part_materials[_mesh_part(node.name)]
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_viewport.add_child(proxy)
		# 僅同步現役 catalog 車身／履帶已有骨架；不複製動畫腳本或碰撞。
		if node.skin != null:
			_has_skinned_mesh = true
			var skeleton := node.get_node_or_null(node.skeleton) as Skeleton3D
			if skeleton != null:
				var skeleton_proxy := _skeleton_proxy(skeleton)
				proxy.skin = node.skin
				proxy.skeleton = proxy.get_path_to(skeleton_proxy)
		_sources.append(node)
		_proxies.append(proxy)
	for child in node.get_children():
		_collect_meshes(child)


func _mesh_part(mesh_name: StringName) -> StringName:
	# 現役四車的匯入名稱。tank4 固定上車體仍名為 Tank_Turret，
	# tank1 無獨立砲塔；不能僅按 visual ancestry 虛構或合併部件。
	match mesh_name:
		&"TrackMesh_L": return &"left_track"
		&"TrackMesh_R": return &"right_track"
		&"Tank_Gun": return &"gun"
		&"Tank_Turret": return &"upper"
		_: return &"hull"


func _sync_meshes() -> void:
	for index in _skeleton_sources.size():
		var source := _skeleton_sources[index]
		var proxy := _skeleton_proxies[index]
		if not is_instance_valid(source) or not source.is_inside_tree():
			continue
		proxy.global_transform = source.global_transform
		proxy.motion_scale = source.motion_scale
		for bone in source.get_bone_count():
			proxy.set_bone_pose_position(bone, source.get_bone_pose_position(bone))
			proxy.set_bone_pose_rotation(bone, source.get_bone_pose_rotation(bone))
			proxy.set_bone_pose_scale(bone, source.get_bone_pose_scale(bone))
	_has_bounds = false
	for index in _sources.size():
		var source := _sources[index]
		var proxy := _proxies[index]
		proxy.visible = is_instance_valid(source) and source.is_inside_tree() and source.is_visible_in_tree()
		if not proxy.visible:
			continue
		proxy.mesh = source.mesh
		proxy.global_transform = source.global_transform
		if not is_instance_valid(_main_camera):
			continue
		var box := source.get_aabb()
		_extend_bounds(box, source.global_transform)


func _extend_bounds(box: AABB, transform: Transform3D) -> void:
	for corner in range(8):
		var world_point := transform * box.get_endpoint(corner)
		if _main_camera.is_position_behind(world_point):
			continue
		var projected := _main_camera.unproject_position(world_point)
		if not _has_bounds:
			_projected_bounds = Rect2(projected, Vector2.ZERO)
			_has_bounds = true
		else:
			_projected_bounds = _projected_bounds.expand(projected)


func _skeleton_proxy(source: Skeleton3D) -> Skeleton3D:
	var index := _skeleton_sources.find(source)
	if index >= 0:
		return _skeleton_proxies[index]
	var proxy := Skeleton3D.new()
	_viewport.add_child(proxy)
	for bone in source.get_bone_count():
		proxy.add_bone(source.get_bone_name(bone))
	for bone in source.get_bone_count():
		proxy.set_bone_parent(bone, source.get_bone_parent(bone))
		proxy.set_bone_rest(bone, source.get_bone_rest(bone))
		proxy.set_bone_enabled(bone, source.is_bone_enabled(bone))
	_skeleton_sources.append(source)
	_skeleton_proxies.append(proxy)
	return proxy


func _target_valid() -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion()


func _target_alive() -> bool:
	if not _target_valid():
		return false
	var health := target.get_node_or_null("HealthComponent")
	return health == null or float(health.get("current_health")) > 0.0


func _update_line_color() -> void:
	_material.set_shader_parameter(&"line_color", Vector3(1.0, 0.025, 0.045) if _target_alive() else Vector3(0.72, 0.72, 0.72))


func _on_target_exiting() -> void:
	set_active(false)


func _process(_delta: float) -> void:
	if active and not _target_valid():
		set_active(false)
	elif active:
		_update_line_color()
