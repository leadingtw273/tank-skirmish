## 相機遮蔽的呈現；不改建築碰撞、坦克視野或射擊規則。
extends Node

const Fade := preload("res://src/visibility/building_fade.gd")
const Vision := preload("res://src/actors/tank/perception/tank_vision.gd")
const Outline := preload("res://src/visibility/enemy_outline.gd")

@export var player_runtime: Node
## 玩家與敵方透視窗口共用同一個世界半徑。
@export_range(1.0, 30.0, 0.5) var window_radius_meters := 8.0
@export_range(0.01, 1.0, 0.01) var fade_seconds := 0.18
@export_flags_3d_physics var occlusion_collision_mask := 129

var controlled_tank: Node3D
var camera: Camera3D
var _fades: Dictionary = {}
var _amounts: Dictionary = {}
var _vision: Node
var _outlines: Dictionary = {}


func _ready() -> void:
	process_priority = 10
	if not is_instance_valid(player_runtime):
		push_error("TankOcclusion requires PlayerRuntime.")
		set_process(false)
		return
	_vision = Vision.new()
	add_child(_vision)
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


func _process(delta: float) -> void:
	if not _alive(controlled_tank) or not is_instance_valid(camera):
		_restore_buildings()
		_clear_enemy_outlines()
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
	_update_enemy_outlines()


func _update_enemy_outlines() -> void:
	var enemies := get_tree().get_nodes_in_group(&"enemy_tank")
	for candidate in enemies:
		var enemy := candidate as Node3D
		if enemy == controlled_tank or not _alive(enemy):
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
		if not is_instance_valid(enemy) or not enemies.has(enemy) or not _alive(enemy):
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
