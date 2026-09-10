extends SceneTree

const TANKS := [
	"res://src/actors/tank/variants/tank1/tank1.tscn",
	"res://src/actors/tank/variants/tank2/tank2.tscn",
	"res://src/actors/tank/variants/tank3/tank3.tscn",
	"res://src/actors/tank/variants/tank4/tank4.tscn",
]
const PARTS := [
	[&"hull", &"left_track", &"right_track", &"gun"],
	[&"hull", &"left_track", &"right_track", &"gun", &"turret"],
	[&"hull", &"left_track", &"right_track", &"gun", &"turret"],
	[&"hull", &"left_track", &"right_track", &"gun", &"fixed_upper_hull"],
]
const DIRS := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const MASK := 129
var v1 := 0
var v2 := 0


func _init() -> void: call_deferred("_run")


func _run() -> void:
	for tank_index: int in TANKS.size():
		for range_name: StringName in [&"near", &"far"]:
			for part: StringName in PARTS[tank_index]:
				if not await _v1_case(tank_index, part, range_name): return
	if not await _v2_all_blocked(): return
	if not await _v2_all_out(): return
	if not await _v2_boundary(): return
	for kind: StringName in [&"building", &"tank", &"wreck"]:
		if not await _v2_external(kind): return
	if not await _v2_self(): return
	print("PASS partial visibility V1=", v1, " V2=", v2)
	quit(0)


func _v1_case(tank_index: int, part: StringName, range_name: StringName) -> bool:
	var chosen: Dictionary = {}
	for direction: Vector3 in DIRS:
		var fixture := await _fixture(TANKS[tank_index], TANKS[tank_index], range_name, direction)
		var pick := _best_ray(fixture, part)
		if not pick.is_empty():
			chosen = {"fixture": fixture, "pick": pick}
			break
		await _dispose(fixture)
	if chosen.is_empty():
		return _fail("V1 Tank%d/%s/%s: cardinal search found no sample whose true first shape is that part" % [tank_index + 1, part, range_name])
	var f: Dictionary = chosen.fixture
	var pick: Dictionary = chosen.pick
	var observer: CharacterBody3D = f.observer
	var target: CharacterBody3D = f.target
	var vision: Node = f.vision
	var origin: Vector3 = f.origin
	var selected: Vector3 = pick.point
	var all: PackedVector3Array = target.call("part_world_surface_points") as PackedVector3Array
	var blocked := PackedVector3Array([vision.call("target_world_position", target) as Vector3])
	for i: int in all.size():
		if _sample_part(target, i) != part: blocked.append(all[i])
	var blockers: Array[StaticBody3D] = []
	for point: Vector3 in blocked:
		var blocker := _ray_blocker(origin, point, selected)
		if blocker == null: return _fail("V1 Tank%d/%s/%s: required blocked ray overlaps selected ray" % [tank_index + 1, part, range_name])
		(f.root as Node3D).add_child(blocker)
		blockers.append(blocker)
	await physics_frame; await physics_frame
	var selected_hit := _hit(observer, origin, selected)
	if selected_hit.get("collider") != target or _hit_part(target, selected_hit) != part:
		return _fail("V1 Tank%d/%s/%s: blocker screen changed selected true first part" % [tank_index + 1, part, range_name])
	for point: Vector3 in blocked:
		if not blockers.has(_hit(observer, origin, point).get("collider") as StaticBody3D):
			return _fail("V1 Tank%d/%s/%s: center/other-part ray did not first hit finite blocker" % [tank_index + 1, part, range_name])
	var center_after: Vector3 = vision.call("target_world_position", target) as Vector3
	if not blockers.has(_hit(observer, origin, center_after).get("collider") as StaticBody3D):
		print("V1 DEBUG center_before=", blocked[0], " center_after=", center_after)
		return _fail("V1 stable center moved outside its blocker")
	var visible: PackedVector3Array = vision.call("visible_target_points", target) as PackedVector3Array
	if visible.is_empty() or not _contains(visible, selected) or not bool(vision.call("can_see", target)):
		return _fail("V1 Tank%d/%s/%s: exposed part did not discover target" % [tank_index + 1, part, range_name])
	for point: Vector3 in visible:
		var index := _index(all, point)
		if index < 0 or _sample_part(target, index) != part:
			print("V1 DEBUG visible=", point, " index=", index, " mapped_part=", _sample_part(target, index) if index >= 0 else &"none", " selected=", selected)
			return _fail("V1 Tank%d/%s/%s: visible candidate belongs to another part/center" % [tank_index + 1, part, range_name])
	v1 += 1
	print("V1 PASS Tank", tank_index + 1, "/", part, "/", range_name, " visible=", visible.size(), " clearance=", pick.clearance)
	await _dispose(f)
	return true


func _best_ray(f: Dictionary, part: StringName) -> Dictionary:
	if f.is_empty(): return {}
	var target: CharacterBody3D = f.target
	var observer: CharacterBody3D = f.observer
	var origin: Vector3 = f.origin
	var points: PackedVector3Array = target.call("part_world_surface_points") as PackedVector3Array
	var initially_visible: PackedVector3Array = f.vision.call("visible_target_points", target) as PackedVector3Array
	var rivals := PackedVector3Array([f.vision.call("target_world_position", target) as Vector3])
	for i: int in points.size():
		if _sample_part(target, i) != part: rivals.append(points[i])
	var best: Dictionary = {}
	for i: int in points.size():
		if _sample_part(target, i) != part: continue
		if not _contains(initially_visible, points[i]): continue
		var hit := _hit(observer, origin, points[i])
		if hit.get("collider") != target or _hit_part(target, hit) != part: continue
		var clearance := INF
		for other: Vector3 in rivals:
			clearance = minf(clearance, (points[i] - origin).angle_to(other - origin))
		if clearance > 0.000001 and (best.is_empty() or clearance > float(best.clearance)):
			best = {"point": points[i], "clearance": clearance}
	return best


func _ray_blocker(origin: Vector3, point: Vector3, selected: Vector3) -> StaticBody3D:
	var distance := minf(3.0, origin.distance_to(point) * 0.35)
	var position := origin + (point - origin).normalized() * distance
	var selected_direction := (selected - origin).normalized()
	var nearest := origin + selected_direction * (position - origin).dot(selected_direction)
	var separation := position.distance_to(nearest)
	if separation <= 0.00001: return null
	return _sphere(position, minf(0.09, separation * 0.35), "PartScreen")


func _v2_all_blocked() -> bool:
	var f := await _fixture(TANKS[1], TANKS[0], &"near", Vector3.FORWARD)
	var points: PackedVector3Array = f.target.call("part_world_surface_points") as PackedVector3Array
	points.insert(0, f.vision.call("target_world_position", f.target) as Vector3)
	var blockers: Array[StaticBody3D] = []
	for point: Vector3 in points:
		var b := _sphere((f.origin as Vector3).lerp(point, 0.25), 0.1, "AllScreen")
		(f.root as Node3D).add_child(b); blockers.append(b)
	await physics_frame; await physics_frame
	for point: Vector3 in points:
		if not blockers.has(_hit(f.observer, f.origin, point).get("collider") as StaticBody3D):
			return _fail("V2 all blocked precondition failed")
	if not (f.vision.call("visible_target_points", f.target) as PackedVector3Array).is_empty(): return _fail("V2 all blocked remained visible")
	return await _v2_pass("all_points_blocked", f)


func _v2_all_out() -> bool:
	var f := await _fixture(TANKS[1], TANKS[0], &"near", Vector3.FORWARD)
	f.observer.set("vision_near_radius", 1.0); f.observer.set("vision_far_radius", 1.0)
	if not (f.vision.call("visible_target_points", f.target) as PackedVector3Array).is_empty(): return _fail("V2 all range-out remained visible")
	return await _v2_pass("all_points_out_of_range", f)


func _v2_boundary() -> bool:
	var f := await _fixture(TANKS[1], TANKS[0], &"near", Vector3.FORWARD)
	var center: Vector3 = f.vision.call("target_world_position", f.target) as Vector3
	var points: PackedVector3Array = f.target.call("part_world_surface_points") as PackedVector3Array
	var closest := points[0]
	for point: Vector3 in points:
		if _xdist(f.observer.global_position, point) < _xdist(f.observer.global_position, closest): closest = point
	var limit := (_xdist(f.observer.global_position, closest) + _xdist(f.observer.global_position, center)) * 0.5
	if limit >= _xdist(f.observer.global_position, center): return _fail("V2 boundary has no closer actual part point")
	f.observer.set("vision_near_radius", limit); f.observer.set("vision_far_radius", 0.0)
	var visible: PackedVector3Array = f.vision.call("visible_target_points", f.target) as PackedVector3Array
	if _contains(visible, center) or not _contains(visible, closest): return _fail("V2 center-out/part-in did not use per-point range")
	return await _v2_pass("center_out_part_in", f)


func _v2_external(kind: StringName) -> bool:
	var f := await _fixture(TANKS[1], TANKS[0], &"near", Vector3.FORWARD)
	var blocker: CollisionObject3D
	if kind == &"building": blocker = _building()
	else:
		blocker = (load(TANKS[0]) as PackedScene).instantiate() as CharacterBody3D
		if kind == &"wreck": blocker.add_to_group("player_wreck")
	if blocker == null: return _fail("V2 %s real fixture unavailable" % kind)
	blocker.name = "External_%s" % kind
	(f.root as Node3D).add_child(blocker)
	## _ready 之後再停止物理更新，避免遮擋車被接觸回應推離已鎖定的位置。
	blocker.set_physics_process(false)
	if kind == &"building":
		blocker.global_position = (f.observer as Node3D).global_position.lerp((f.target as Node3D).global_position, 0.4)
	else:
		## Align stable centers from the actual elevated ray origin.  The nearer identical
		## tank/wreck then subtends a strictly larger silhouette than the target.
		var desired_center: Vector3 = (f.origin as Vector3).lerp(f.vision.call("target_world_position", f.target) as Vector3, 0.25)
		var blocker_center: Vector3 = blocker.call("stable_world_center") as Vector3
		blocker.global_position += desired_center - blocker_center
	await physics_frame; await physics_frame
	var center: Vector3 = f.vision.call("target_world_position", f.target) as Vector3
	if _hit(f.observer, f.origin, center).get("collider") != blocker: return _fail("V2 %s is not first center blocker" % kind)
	for point: Vector3 in f.target.call("part_world_surface_points") as PackedVector3Array:
		if _hit(f.observer, f.origin, point).get("collider") != blocker: return _fail("V2 %s sample occlusion precondition failed" % kind)
	if not (f.vision.call("visible_target_points", f.target) as PackedVector3Array).is_empty(): return _fail("V2 %s did not occlude every candidate" % kind)
	return await _v2_pass(str(kind), f)


func _v2_self() -> bool:
	var f := await _fixture(TANKS[1], TANKS[0], &"near", Vector3.FORWARD)
	var center: Vector3 = f.vision.call("target_world_position", f.target) as Vector3
	## Add a real shape owned by the observer directly on the sight line.  This makes the
	## counterfactual deterministic even when the authored hull contains the ray origin.
	var self_collision := CollisionShape3D.new()
	var self_shape := SphereShape3D.new(); self_shape.radius = 0.2; self_collision.shape = self_shape
	self_collision.position = (f.observer as Node3D).to_local((f.origin as Vector3).lerp(center, 0.25))
	(f.observer as CharacterBody3D).add_child(self_collision)
	await physics_frame; await physics_frame
	var raw := PhysicsRayQueryParameters3D.create(f.origin, center, MASK)
	if f.observer.get_world_3d().direct_space_state.intersect_ray(raw).get("collider") != f.observer:
		return _fail("V2 self-block precondition: unexcluded ray did not hit observer")
	if not bool(f.vision.call("can_see", f.target)): return _fail("V2 observer blocked itself")
	return await _v2_pass("observer_not_self_blocked", f)


func _fixture(observer_path: String, target_path: String, range_name: StringName, direction: Vector3) -> Dictionary:
	var observer := (load(observer_path) as PackedScene).instantiate() as CharacterBody3D
	var target := (load(target_path) as PackedScene).instantiate() as CharacterBody3D
	var holder := Node3D.new()
	observer.position = Vector3(0, 80, 0)
	target.position = observer.position + direction * (12.0 if range_name == &"near" else 60.0)
	holder.add_child(observer); holder.add_child(target)
	var vision := TankVision.new(); vision.observer = observer; holder.add_child(vision); root.add_child(holder)
	target.set_physics_process(false)
	await physics_frame; await physics_frame
	if range_name == &"far":
		observer.call("aim_turret_at", vision.call("target_world_position", target) as Vector3, 10.0)
		await physics_frame; await physics_frame
	observer.set_physics_process(false)
	var turret := observer.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	return {"root": holder, "observer": observer, "target": target, "vision": vision, "origin": turret.global_position}


func _sample_part(target: CharacterBody3D, wanted: int) -> StringName:
	var geometry := target.get("part_geometry") as Resource
	var cursor := 0
	for part: Resource in geometry.get("parts") as Array:
		var count := (part.get("surface_points") as PackedVector3Array).size()
		if wanted < cursor + count: return StringName(str(part.get("id")))
		cursor += count
	return &""


func _hit_part(target: CharacterBody3D, hit: Dictionary) -> StringName:
	var owner_id := target.shape_find_owner(int(hit.get("shape", -1)))
	if owner_id < 0: return &""
	var owner := target.shape_owner_get_owner(owner_id) as Node
	if owner == null: return &""
	var text := String(owner.name)
	if not text.begins_with("PartCollision_"): return &""
	var pieces := text.trim_prefix("PartCollision_").split("_")
	pieces.remove_at(pieces.size() - 1)
	return StringName("_".join(pieces))


func _hit(observer: CharacterBody3D, from: Vector3, to: Vector3) -> Dictionary:
	return observer.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, MASK, [observer.get_rid()]))


func _sphere(position: Vector3, radius: float, label: String) -> StaticBody3D:
	var body := StaticBody3D.new(); body.name = label
	var collision := CollisionShape3D.new(); var shape := SphereShape3D.new(); shape.radius = radius
	collision.shape = shape; body.add_child(collision); body.position = position
	return body


func _building() -> StaticBody3D:
	var scene := (load("res://src/world/training_ground/training_ground_playtest.tscn") as PackedScene).instantiate() as Node3D
	var source := scene.get_node_or_null("SightBlockers/BuildingRowA/CentralOneStory") as StaticBody3D
	var result := source.duplicate() as StaticBody3D if source != null else null
	scene.free(); return result


func _index(points: PackedVector3Array, expected: Vector3) -> int:
	for i: int in points.size():
		if points[i].is_equal_approx(expected): return i
	return -1


func _contains(points: PackedVector3Array, expected: Vector3) -> bool: return _index(points, expected) >= 0
func _xdist(a: Vector3, b: Vector3) -> float:
	var d := b - a; d.y = 0.0; return d.length()


func _v2_pass(label: String, f: Dictionary) -> bool:
	v2 += 1; print("V2 PASS ", label); await _dispose(f); return true


func _dispose(f: Dictionary) -> void:
	var holder := f.get("root") as Node3D
	if is_instance_valid(holder): holder.queue_free(); await physics_frame; await physics_frame


func _fail(message: String) -> bool:
	push_error(message); print("FAIL: ", message); quit(1); return false
