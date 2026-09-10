## Task 1：四車離線部位 geometry、穩定中心、機械姿態與視覺後座隔離的有限 smoke。
extends SceneTree

const VARIANTS := [
	{"id": "tank1", "scene": "res://src/actors/tank/variants/tank1/tank1.tscn", "parts": ["hull", "left_track", "right_track", "gun"], "center": Vector3(0, 1.519596, 0)},
	{"id": "tank2", "scene": "res://src/actors/tank/variants/tank2/tank2.tscn", "parts": ["hull", "left_track", "right_track", "gun", "turret"], "center": Vector3(0, 1.039605154183, 0)},
	{"id": "tank3", "scene": "res://src/actors/tank/variants/tank3/tank3.tscn", "parts": ["hull", "left_track", "right_track", "gun", "turret"], "center": Vector3(0, 1.673166, 0)},
	{"id": "tank4", "scene": "res://src/actors/tank/variants/tank4/tank4.tscn", "parts": ["hull", "left_track", "right_track", "gun", "fixed_upper_hull"], "center": Vector3(0, 1.34941, 0)},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _validate_shape_budget():
		quit(1)
		return
	for contract in VARIANTS:
		if not await _validate_variant(contract):
			quit(1)
			return
	print("Tank part geometry smoke validation passed.")
	quit(0)


func _validate_shape_budget() -> bool:
	var part := TankPartDefinition.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.FORWARD])
	part.surface_points = PackedVector3Array([Vector3.ZERO])
	for index in 16:
		part.convex_shapes.append(shape)
		part.convex_transforms.append(Transform3D.IDENTITY)
	if not part.is_valid_part():
		return _fail("The approved 16-shape part budget must be accepted.")
	part.convex_shapes.append(shape)
	part.convex_transforms.append(Transform3D.IDENTITY)
	if part.is_valid_part():
		return _fail("A part exceeding the approved 16-shape budget must be rejected.")
	print("Part shape budget: 16 accepted, 17 rejected.")
	return true


func _validate_variant(contract: Dictionary) -> bool:
	var packed := load(String(contract.scene)) as PackedScene
	var tank := packed.instantiate() as CharacterBody3D if packed != null else null
	if tank == null:
		return _fail("%s must load as a CharacterBody3D." % contract.id)
	root.add_child(tank)
	await physics_frame
	await physics_frame
	var geometry := tank.part_geometry as TankPartGeometry
	var root_shapes := _root_collision_shapes(tank)
	var stable_center_before: Vector3 = tank.stable_world_center()
	var valid: bool = geometry != null and geometry.is_valid_geometry() \
		and geometry.parts.size() == (contract.parts as Array).size() \
		and (tank.global_transform.affine_inverse() * stable_center_before).distance_to(contract.center as Vector3) < 0.001 \
		and root_shapes.size() == tank.part_shape_world_transforms().size() \
		and root_shapes.all(func(shape: CollisionShape3D) -> bool: return shape.shape is ConvexPolygonShape3D and shape.get_parent() == tank)
	if valid:
		for expected_id in contract.parts:
			var part := geometry.part_named(StringName(expected_id))
			valid = valid and part != null and part.is_valid_part()
		if tank.part_world_surface_points().is_empty() or tank.part_world_bounds().size.is_zero_approx():
			valid = false
	## 開闊場景操作不依賴舊單一 Box：平移後中心、root owner 與所有凸形仍保持可用。
	var open_field_center_before: Vector3 = tank.stable_world_center()
	var open_field_offset: Vector3 = Vector3(7.0, 0.0, -3.0)
	tank.global_position += open_field_offset
	tank.call("_sync_part_collision_shapes")
	await physics_frame
	var open_field_operational: bool = tank.stable_world_center().is_equal_approx(open_field_center_before + open_field_offset) \
		and _root_collision_shapes(tank).all(func(shape: CollisionShape3D) -> bool: return shape.get_parent() == tank and shape.global_transform.is_finite())
	valid = valid and open_field_operational
	tank.global_transform = Transform3D.IDENTITY
	tank.call("_sync_part_collision_shapes")
	await physics_frame
	var hull_before := _part_shape_transform(tank, "hull")
	var gun_before := _part_shape_transform(tank, "gun")
	tank.aim_turret_at(tank.global_position + Vector3.FORWARD * 100.0, 10.0)
	tank.aim_gun_pitch_at_target(tank.muzzle_global_position() + Vector3(-100.0, 100.0, 0.0), 10.0)
	var hull_after_aim := _part_shape_transform(tank, "hull")
	var gun_after_aim := _part_shape_transform(tank, "gun")
	var candidate_transforms: Array[Transform3D] = tank.candidate_part_shape_world_transforms(tank.global_transform, tank.turret_pivot.rotation.y, -tank.gun_pitch_pivot.rotation.z)
	var candidates_match := _transforms_equal(candidate_transforms, tank.part_shape_world_transforms())
	valid = valid and hull_before.is_equal_approx(hull_after_aim) and not gun_before.is_equal_approx(gun_after_aim) and candidates_match
	var collisions_before_recoil: Array[Transform3D] = tank.part_shape_world_transforms()
	tank.request_fire()
	await physics_frame
	var recoil_isolated := _transforms_equal(collisions_before_recoil, tank.part_shape_world_transforms())
	var center_is_stable: bool = (tank.global_transform.affine_inverse() * tank.stable_world_center()).distance_to(contract.center as Vector3) < 0.001
	valid = valid and recoil_isolated and center_is_stable
	if not valid:
		print("GEOMETRY_DEBUG %s parts=%d root_shapes=%d transforms=%d center_stable=%s center_resource=%s center_local=%s expected=%s open_field_operational=%s hull_static=%s gun_moves=%s candidates_match=%s recoil_isolated=%s yaw=%f pitch=%f" % [contract.id, geometry.parts.size() if geometry != null else -1, root_shapes.size(), tank.part_shape_world_transforms().size(), center_is_stable, geometry.stable_center, tank.global_transform.affine_inverse() * tank.stable_world_center(), contract.center, open_field_operational, hull_before.is_equal_approx(hull_after_aim), not gun_before.is_equal_approx(gun_after_aim), candidates_match, recoil_isolated, tank.turret_pivot.rotation.y, -tank.gun_pitch_pivot.rotation.z])
		if not candidates_match:
			for index in mini(candidate_transforms.size(), tank.part_shape_world_transforms().size()):
				if not candidate_transforms[index].is_equal_approx(tank.part_shape_world_transforms()[index]):
					print("CANDIDATE_MISMATCH %s index=%d candidate=%s current=%s" % [contract.id, index, candidate_transforms[index], tank.part_shape_world_transforms()[index]])
					break
	tank.queue_free()
	await process_frame
	return valid or _fail("%s must expose finite true part geometry on the Tank body, preserve its old center, and isolate collision from visual recoil." % contract.id)


func _root_collision_shapes(tank: CharacterBody3D) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	for child in tank.get_children():
		if child is CollisionShape3D:
			result.append(child as CollisionShape3D)
	return result


func _part_shape_transform(tank: CharacterBody3D, id: StringName) -> Transform3D:
	var geometry := tank.part_geometry as TankPartGeometry
	var index := 0
	for part in geometry.parts:
		for unused in part.convex_shapes:
			if part.id == id:
				return tank.part_shape_world_transforms()[index]
			index += 1
	return Transform3D.IDENTITY


func _transforms_equal(left: Array[Transform3D], right: Array[Transform3D]) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]):
			return false
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
