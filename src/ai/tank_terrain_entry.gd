## 高路緣需要穩定入射方向與起步距離；只提出需求，所有命令仍經正式 predictor。
extends RefCounted

var phase: StringName = &""
var entry := Vector3.ZERO
var heading := Vector3.ZERO
var staging := Vector3.ZERO
var exit_distance := 4.0
var last_entry := Vector3.INF

func reset() -> void:
	phase = &""
	last_entry = Vector3.INF

func guide(tank: Node3D, path: PackedVector3Array, index: int, position: Vector3, speed: float) -> Dictionary:
	if not tank is RigidBody3D: return {}
	if phase == &"": _find_entry(tank, path, index, position)
	if phase == &"": return {}
	var forward := _flat(-tank.global_basis.x).normalized()
	var angle := atan2(forward.cross(heading).y, forward.dot(heading))
	if phase == &"approach" and position.distance_to(staging) <= 0.8 and speed <= 0.15:
		phase = &"align"
	if phase == &"align" and absf(angle) <= deg_to_rad(3.0) and absf((tank as RigidBody3D).angular_velocity.y) <= 0.03:
		phase = &"cross"
	if phase == &"cross" and (position-entry).dot(heading) >= exit_distance - 0.7 and speed <= 0.15:
		last_entry = entry
		phase = &""
		return {}
	if phase == &"approach": return {"target": staging, "stop": 0.5, "phase": phase}
	return {"target": entry + heading * exit_distance, "stop": 0.0, "phase": phase}

func _find_entry(tank: Node3D, path: PackedVector3Array, index: int, position: Vector3) -> void:
	if path.size() < 2: return
	var space := tank.get_world_3d().direct_space_state
	for i in range(maxi(index, 1), path.size()):
		if _flat(path[i]-position).length() > 40.0: return
		# 小路肩沿用正常駕駛；只處理超出既有 0.21m 案例的明顯高差。
		var crest := _rise_end(path, i)
		if crest < 0: continue
		var direction := _flat(path[crest]-path[i-1]).normalized()
		if direction.is_zero_approx(): continue
		var from := path[i-1] + Vector3.UP * 0.05
		var to := Vector3(path[crest].x, from.y, path[crest].z) + direction * 1.0
		var hit := _ray(space, tank, from, to)
		if hit.is_empty() or not hit.collider is StaticBody3D: continue
		var inward := -_flat(hit.normal as Vector3).normalized()
		if inward.is_zero_approx() or inward.dot(direction) < 0.5: continue
		var candidate := position + inward * _flat((hit.position as Vector3)-position).dot(inward)
		if last_entry.is_finite() and candidate.distance_to(last_entry) < 6.0: continue
		# 保持目前橫向位置，但必須實際確認同一個路緣面延伸至此。
		var check_from := candidate - inward
		check_from.y = from.y
		var check := _ray(space, tank, check_from, check_from + inward * 2.0)
		if check.is_empty() or check.collider != hit.collider or (-_flat(check.normal as Vector3).normalized()).dot(inward) < 0.95: continue
		candidate = _flat(check.position as Vector3)
		var snapshot: Dictionary = tank.predictive_driving_snapshot()
		var span := 0.0
		for point: Vector3 in snapshot.get("ground_points", []): span = maxf(span, absf(point.x))
		span = maxf(span, 3.0)
		var acceleration := maxf(float(tank.combat_tank.engine_horsepower)/maxf(float(tank.get("tank_mass_tonnes")),0.001)*0.08,0.1)
		var top_speed := float(tank.get("movement_speed"))
		var runup := span + top_speed * top_speed / (2.0 * acceleration) + 1.0
		var start := candidate - inward * runup
		if (start-position).dot(inward) < 1.0: continue
		var map := tank.get_world_3d().navigation_map
		var nearest := NavigationServer3D.map_get_closest_point(map, start)
		if _flat(nearest-start).length() > 0.5: continue
		var approach := NavigationServer3D.map_get_path(map, position, start, true, 1)
		if approach.size() < 2 or _flat(approach[-1]-start).length() > 0.5: continue
		var length := 0.0
		for j in range(1, approach.size()): length += _flat(approach[j]-approach[j-1]).length()
		if length > position.distance_to(start) * 1.1 + 0.5: continue
		entry = candidate
		heading = inward
		staging = start
		exit_distance = span + 1.0
		# Cross the full raised band before turning: the entry face is not its far edge.
		# The existing native path supplies the first descent after this rise; commands
		# still pass through the complete predictor, including braking at this target.
		var crest_height := path[crest].y
		for j in range(crest + 1, path.size()):
			var depth := _flat(path[j]-candidate).dot(inward)
			if depth < 0.0 or depth > span * 2.0: break
			crest_height = maxf(crest_height,path[j].y)
			if crest_height-path[j].y >= 0.2:
				exit_distance += depth
				break
		phase = &"align"
		return

static func _ray(space: PhysicsDirectSpaceState3D, tank: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, tank.collision_mask, [tank.get_rid()])
	return space.intersect_ray(query)

static func _flat(v: Vector3) -> Vector3: return Vector3(v.x, 0.0, v.z)


# Navmesh voxelization may split one curb into multiple short rising edges.
# The horizontal ray still has to prove that this is an actual raised face.
static func _rise_end(path: PackedVector3Array, index: int) -> int:
	if index < 1 or index >= path.size() or path[index].y <= path[index-1].y: return -1
	if path[index].y-path[index-1].y > 0.3: return index
	var length := 0.0
	for end in range(index, path.size()):
		length += _flat(path[end]-path[end-1]).length()
		if length > 3.0 or path[end].y < path[end-1].y - 0.01: break
		if path[end].y-path[index-1].y > 0.3: return end
	return -1
