extends RefCounted

static func supported_fixture(tank: CharacterBody3D) -> bool:
	var support: Dictionary = tank.ground_support_at(tank.global_transform)
	var supported := bool(support.get("supported", false)) and absf(float(support.get("height_delta", INF))) < 0.001
	print("HULL_SUPPORT_FIXTURE %s supported=%s height_delta=%.6f position=%s" % [tank.scene_file_path, supported, float(support.get("height_delta", INF)), tank.global_position])
	return supported


static func fixture_ground_for(tank: CharacterBody3D, size: float) -> StaticBody3D:
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	var top_y := INF
	for point in snapshot.ground_points:
		top_y = minf(top_y, (tank.global_transform * (point as Vector3)).y)
	var ground := StaticBody3D.new()
	ground.name = "HullSupportFixtureGround"
	ground.collision_layer = 128
	ground.collision_mask = 0
	ground.position = Vector3(tank.global_position.x, top_y - 0.1, tank.global_position.z)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.2, size)
	collision.shape = box
	ground.add_child(collision)
	return ground


static func restore_geometry_body(body: RigidBody3D, state: Dictionary) -> void:
	body.linear_velocity = state.linear_velocity
	body.angular_velocity = state.angular_velocity
	body.freeze = state.freeze


static func freeze_geometry_body(body: RigidBody3D) -> Dictionary:
	var state := {"freeze": body.freeze, "linear_velocity": body.linear_velocity, "angular_velocity": body.angular_velocity}
	body.freeze = true
	return state
