## 相機遮蔽的呈現；不改建築碰撞、坦克視野或射擊規則。
extends Node

const Fade := preload("res://src/visibility/building_fade.gd")
const NearestDepth := preload("res://src/visibility/player_fade_depth.gd")
const Vision := preload("res://src/actors/tank/perception/tank_vision.gd")
const Outline := preload("res://src/visibility/enemy_outline.gd")
const PLAYER_FADE_OUTER_METERS := 2.0

@export var player_runtime: Node
## 玩家與敵方共用核心半徑；只有玩家建築淡出向外延伸固定 2m。
@export_range(1.0, 30.0, 0.5) var window_radius_meters := 5.0
@export_range(0.01, 1.0, 0.01) var fade_seconds := 0.18
@export_flags_3d_physics var occlusion_collision_mask := 129

var _nearest_depth: Node
var controlled_tank: Node3D
var camera: Camera3D
var _fades: Dictionary = {}
var _amounts: Dictionary = {}
var _vision: Node
var _outlines: Dictionary = {}
var _building_candidates: Array[Dictionary] = []
var _building_candidates_dirty := true


func _ready() -> void:
	process_priority = 10
	if not is_instance_valid(player_runtime):
		push_error("TankOcclusion requires PlayerRuntime.")
		set_process(false)
		return
	_nearest_depth = NearestDepth.new()
	add_child(_nearest_depth)
	_vision = Vision.new()
	add_child(_vision)
	get_tree().tree_changed.connect(_invalidate_building_candidates)
	player_runtime.connect("controlled_tank_changed", _bind_tank)
	_bind_tank(player_runtime.get("controlled_tank") as Node3D)


func _bind_tank(tank: Node3D) -> void:
	_restore_buildings()
	_clear_enemy_outlines()
	controlled_tank = tank
	_vision.set("observer", tank)
	var rig := player_runtime.get("camera_controller") as Node
	camera = rig.get("camera") as Camera3D if is_instance_valid(rig) else null


func _exit_tree() -> void:
	_restore_buildings()
	_clear_enemy_outlines()
	if get_tree().tree_changed.is_connected(_invalidate_building_candidates):
		get_tree().tree_changed.disconnect(_invalidate_building_candidates)
	_building_candidates.clear()


func _process(_delta: float) -> void:
	if not _alive(controlled_tank) or not is_instance_valid(camera):
		_restore_buildings()
		_clear_enemy_outlines()
		return
	var window := player_fade_window_for(controlled_tank)
	var obscuring: Array[Node3D] = []
	var foreground_depth := _player_foreground_depth()
	if not window.is_empty():
		obscuring = _window_buildings(window, foreground_depth)
	for building in obscuring:
		if not _fades.has(building):
			_fades[building] = Fade.new(building)
			_amounts[building] = 1.0
	for building in _fades.keys():
		var effect = _fades[building]
		if not effect.is_valid():
			effect.restore()
			_fades.erase(building)
			_amounts.erase(building)
			continue
		if not obscuring.has(building) or window.is_empty():
			effect.restore()
			_fades.erase(building)
			_amounts.erase(building)
		else:
			effect.update_window(window.center, window.radius_pixels, window.viewport_size, 1.0, foreground_depth, window.core_radius_pixels)
	_nearest_depth.sync(camera, window, _fades.values(), foreground_depth)
	for effect in _fades.values():
		effect.set_nearest_depth(_nearest_depth.texture())
	_update_enemy_outlines()


func _invalidate_building_candidates() -> void:
	_building_candidates_dirty = true


func _index_building_meshes(node: Node, indexed: Dictionary) -> void:
	if node is MeshInstance3D:
		var building := _building_for(node)
		if building != null:
			if not indexed.has(building):
				indexed[building] = []
			indexed[building].append(weakref(node))
	for child in node.get_children():
		_index_building_meshes(child, indexed)


func _window_buildings(window: Dictionary, foreground_depth: float) -> Array[Node3D]:
	if _building_candidates_dirty:
		var indexed: Dictionary = {}
		_index_building_meshes(get_tree().root, indexed)
		_building_candidates.clear()
		for building in indexed:
			_building_candidates.append({"building": weakref(building), "meshes": indexed[building]})
		_building_candidates_dirty = false
	var result: Array[Node3D] = []
	for candidate in _building_candidates:
		var building := candidate.building.get_ref() as Node3D
		if not is_instance_valid(building):
			continue
		for reference in candidate.meshes:
			var instance := reference.get_ref() as MeshInstance3D
			if is_instance_valid(instance) and instance.mesh != null and instance.is_visible_in_tree() \
					and _mesh_intersects_window(instance, window, foreground_depth):
				result.append(building)
				break
	return result


func _mesh_intersects_window(instance: MeshInstance3D, window: Dictionary, foreground_depth: float) -> bool:
	var bounds := instance.get_aabb()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var in_front := false
	for index in 8:
		var point := instance.global_transform * bounds.get_endpoint(index)
		if camera.is_position_behind(point):
			continue
		in_front = in_front or camera.to_local(point).z > foreground_depth
		var projected := camera.unproject_position(point)
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	if not in_front:
		return false
	var nearest := (window.center as Vector2).clamp(minimum, maximum)
	return nearest.distance_squared_to(window.center) < float(window.radius_pixels) * float(window.radius_pixels)


func _player_foreground_depth() -> float:
	# Include the farthest real body/part point, so a wall in front of the rear
	# hull or tracks still fades even when it lies behind the tank's center.
	var depth := camera.to_local(_center(controlled_tank)).z
	if controlled_tank.has_method("part_world_surface_points"):
		var points: PackedVector3Array = controlled_tank.call("part_world_surface_points")
		for point in points:
			if point.is_finite():
				depth = minf(depth, camera.to_local(point).z)
	return depth


func _update_enemy_outlines() -> void:
	var enemies := get_tree().get_nodes_in_group(&"enemy_tank")
	for candidate in enemies:
		var enemy := candidate as Node3D
		if enemy == controlled_tank or not _present(enemy):
			continue
		var window := window_for(enemy)
		var eligible := not window.is_empty() and bool(_vision.call("can_see", enemy))
		if eligible:
			eligible = not building_occluders(enemy).is_empty()
		if eligible and not _outlines.has(enemy):
			var outline := Outline.new()
			add_child(outline)
			outline.configure(enemy, camera)
			_outlines[enemy] = outline
		if _outlines.has(enemy):
			var outline = _outlines[enemy]
			if eligible:
				outline.update_window(camera, window)
			outline.set_active(eligible)
	for enemy in _outlines.keys():
		if not is_instance_valid(enemy) or not enemies.has(enemy) or not _present(enemy):
			_outlines[enemy].set_active(false)
			_outlines[enemy].queue_free()
			_outlines.erase(enemy)


func outlined_enemies() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for enemy in _outlines:
		if is_instance_valid(enemy) and bool(_outlines[enemy].active):
			result.append(enemy)
	return result


## 只優先處理目前啟用的敵車投影；一般 picking 仍保留原首撞行為。
func resolve_enemy_target(screen_position: Vector2, collision_mask: int = 129) -> Dictionary:
	if not _alive(controlled_tank) or not is_instance_valid(camera):
		return {}
	var excluded: Array[RID] = []
	if controlled_tank is CollisionObject3D:
		excluded.append(controlled_tank.get_rid())
	var closest := INF
	var result: Dictionary = {}
	for enemy in outlined_enemies():
		if not _alive(enemy):
			continue
		var hit: Dictionary = _outlines[enemy].pick(screen_position, excluded, collision_mask)
		if hit.is_empty():
			continue
		var depth := -camera.to_local(hit.position).z
		if depth < closest:
			closest = depth
			result = hit
	return result


func _clear_enemy_outlines() -> void:
	for outline in _outlines.values():
		outline.set_active(false)
		outline.queue_free()
	_outlines.clear()


func window_for(target: Node3D) -> Dictionary:
	return _window_for(target, window_radius_meters)


## 玩家候選、兩個材質 pass 與 nearest-depth 共用此外窗口。
func player_fade_window_for(target: Node3D) -> Dictionary:
	var window := _window_for(target, window_radius_meters + PLAYER_FADE_OUTER_METERS)
	if not window.is_empty():
		var core_edge := camera.unproject_position(_center(target) + camera.global_basis.x.normalized() * window_radius_meters)
		window["core_radius_pixels"] = (window.center as Vector2).distance_to(core_edge)
		window["core_world_radius"] = window_radius_meters
	return window


func _window_for(target: Node3D, radius_meters: float) -> Dictionary:
	if not is_instance_valid(target) or not is_instance_valid(camera):
		return {}
	var center := _center(target)
	if camera.is_position_behind(center):
		return {}
	var screen := camera.unproject_position(center)
	var size := camera.get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return {}
	var edge := camera.unproject_position(center + camera.global_basis.x.normalized() * radius_meters)
	var radius := screen.distance_to(edge)
	if not Rect2(-Vector2.ONE * radius, size + Vector2.ONE * radius * 2.0).has_point(screen):
		return {}
	return {"center": screen, "radius_pixels": radius, "viewport_size": size, "world_radius": radius_meters}


## 正交相機的射線起點各不相同，不能從 Camera3D 的位置向車體射線。
func building_occluders(target: Node3D) -> Array[Node3D]:
	var buildings: Array[Node3D] = []
	if not is_instance_valid(target) or not is_instance_valid(camera) or not target.is_inside_tree():
		return buildings
	var points := PackedVector3Array([_center(target)])
	if target.has_method("part_world_surface_points"):
		var surface_points: PackedVector3Array = target.call("part_world_surface_points")
		var stride := maxi(1, ceili(float(surface_points.size()) / 24.0))
		for index in range(0, surface_points.size(), stride):
			points.append(surface_points[index])
	var space := target.get_world_3d().direct_space_state
	for point in points:
		if camera.is_position_behind(point):
			continue
		var screen := camera.unproject_position(point)
		if not camera.get_viewport().get_visible_rect().has_point(screen):
			continue
		var excluded: Array[RID] = []
		if target is CollisionObject3D:
			excluded.append(target.get_rid())
		var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(screen), point, occlusion_collision_mask, excluded)
		query.hit_from_inside = true
		## 同一畫面射線可經過多棟建築；保留各棟獨立的顯示狀態。
		for _step in range(64):
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			var building := _building_for(hit.get("collider") as Node)
			if building != null and not buildings.has(building):
				buildings.append(building)
			var rid: RID = hit.get("rid", RID())
			if not rid.is_valid() or excluded.has(rid):
				break
			excluded.append(rid)
			query.exclude = excluded
	return buildings


func faded_buildings() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for building in _fades:
		if is_instance_valid(building) and float(_amounts.get(building, 0.0)) > 0.0:
			result.append(building)
	return result


func _building_for(collider: Node) -> Node3D:
	var current := collider
	while is_instance_valid(current):
		if current is Node3D and (current.has_meta("quaternius_source") or current.is_in_group("occlusion_building")):
			return current as Node3D
		var parent := current.get_parent()
		if parent != null and parent.name == &"Buildings":
			return current as Node3D
		current = parent
	return null


func _center(target: Node3D) -> Vector3:
	return target.call("stable_world_center") as Vector3 if target.has_method("stable_world_center") else target.global_position


func _present(target: Node3D) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion()


func _alive(target: Node3D) -> bool:
	if not _present(target):
		return false
	var health := target.get_node_or_null("HealthComponent")
	return health == null or float(health.get("current_health")) > 0.0


func _restore_buildings() -> void:
	for effect in _fades.values():
		effect.restore()
	_fades.clear()
	_amounts.clear()
	if is_instance_valid(_nearest_depth):
		_nearest_depth.clear()
