## 相機遮蔽的呈現；不改建築碰撞、坦克視野或射擊規則。
extends Node

const Fade := preload("res://src/visibility/building_fade.gd")

@export var player_runtime: Node
## 玩家與敵方透視窗口共用同一個世界半徑。
@export_range(1.0, 30.0, 0.5) var window_radius_meters := 8.0
@export_range(0.01, 1.0, 0.01) var fade_seconds := 0.18
@export_flags_3d_physics var occlusion_collision_mask := 129

var controlled_tank: Node3D
var camera: Camera3D
var _fades: Dictionary = {}
var _amounts: Dictionary = {}


func _ready() -> void:
	process_priority = 10
	if not is_instance_valid(player_runtime):
		push_error("TankOcclusion requires PlayerRuntime.")
		set_process(false)
		return
	player_runtime.connect("controlled_tank_changed", _bind_tank)
	_bind_tank(player_runtime.get("controlled_tank") as Node3D)


func _bind_tank(tank: Node3D) -> void:
	_restore_buildings()
	controlled_tank = tank
	var rig := player_runtime.get("camera_controller") as Node
	camera = rig.get("camera") as Camera3D if is_instance_valid(rig) else null


func _exit_tree() -> void:
	_restore_buildings()


func _process(delta: float) -> void:
	if not _alive(controlled_tank) or not is_instance_valid(camera):
		_restore_buildings()
		return
	var window := window_for(controlled_tank)
	var obscuring: Array[Node3D] = []
	if not window.is_empty():
		obscuring = building_occluders(controlled_tank)
	for building in obscuring:
		if not _fades.has(building):
			_fades[building] = Fade.new(building)
			_amounts[building] = 0.0
	for building in _fades.keys():
		var effect = _fades[building]
		if not effect.is_valid():
			_fades.erase(building)
			_amounts.erase(building)
			continue
		var target := 1.0 if obscuring.has(building) else 0.0
		var amount := move_toward(float(_amounts[building]), target, delta / maxf(fade_seconds, 0.01))
		_amounts[building] = amount
		if amount <= 0.0 or window.is_empty():
			effect.restore()
			_fades.erase(building)
			_amounts.erase(building)
		else:
			effect.update_window(window.center, window.radius_pixels, window.viewport_size, amount)


func window_for(target: Node3D) -> Dictionary:
	if not is_instance_valid(target) or not is_instance_valid(camera):
		return {}
	var center := _center(target)
	if camera.is_position_behind(center):
		return {}
	var screen := camera.unproject_position(center)
	var size := camera.get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return {}
	var edge := camera.unproject_position(center + camera.global_basis.x.normalized() * window_radius_meters)
	var radius := screen.distance_to(edge)
	if not Rect2(-Vector2.ONE * radius, size + Vector2.ONE * radius * 2.0).has_point(screen):
		return {}
	return {"center": screen, "radius_pixels": radius, "viewport_size": size, "world_radius": window_radius_meters}


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


func _alive(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	var health := target.get_node_or_null("HealthComponent")
	return health == null or float(health.get("current_health")) > 0.0


func _restore_buildings() -> void:
	for effect in _fades.values():
		effect.restore()
	_fades.clear()
	_amounts.clear()
