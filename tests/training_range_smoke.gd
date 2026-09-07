extends SceneTree

const RANGE_SCENE := "res://src/world/training_ground/training_range.tscn"


func _init() -> void:
	if not await _validate_range():
		quit(1)
		return
	print("Training range smoke validation passed.")
	quit(0)


func _validate_range() -> bool:
	var packed := load(RANGE_SCENE) as PackedScene
	var range := packed.instantiate() as Node3D if packed != null else null
	if range == null:
		return _fail("TrainingRange scene must load.")
	root.add_child(range)
	await physics_frame
	var main_target := range.get_node_or_null("MainTarget") as StaticBody3D
	var clear_target := range.get_node_or_null("ClearTarget") as StaticBody3D
	var spread_toggle_target := range.get_node_or_null("SpreadToggleTarget") as StaticBody3D
	var markers := range.get_node_or_null("Markers") as Node3D
	var target_grid := range.get_node_or_null("MainTarget/TargetGrid") as Node3D
	var range_markings := range.get_node_or_null("RangeMarkings") as Node3D
	if main_target == null or clear_target == null or spread_toggle_target == null or markers == null or target_grid == null or range_markings == null:
		range.queue_free()
		return _fail("TrainingRange must expose stable target, grid, marking, and marker nodes.")
	var main_shape := main_target.get_node_or_null("CollisionShape3D").shape as BoxShape3D
	var clear_shape := clear_target.get_node_or_null("CollisionShape3D").shape as BoxShape3D
	var clear_mesh := clear_target.get_node("ClearVisual").mesh as BoxMesh
	var spread_toggle_shape := spread_toggle_target.get_node_or_null("CollisionShape3D").shape as BoxShape3D
	var spread_toggle_mesh := spread_toggle_target.get_node_or_null("SpreadToggleVisual").mesh as BoxMesh
	var spread_toggle_material := spread_toggle_mesh.material as StandardMaterial3D if spread_toggle_mesh != null else null
	if main_target.collision_layer != 1 or main_target.collision_mask != 0 \
			or clear_target.collision_layer != 1 or clear_target.collision_mask != 0 \
			or spread_toggle_target.collision_layer != 1 or spread_toggle_target.collision_mask != 0 \
			or main_shape == null or not main_shape.size.is_equal_approx(Vector3(10, 10, 0.2)) \
			or clear_shape == null or not clear_shape.size.is_equal_approx(Vector3(4, 4, 0.2)) \
			or spread_toggle_shape == null or not spread_toggle_shape.size.is_equal_approx(Vector3(4, 4, 0.2)) \
			or clear_mesh == null or not clear_mesh.size.is_equal_approx(clear_shape.size) \
			or spread_toggle_mesh == null or not spread_toggle_mesh.size.is_equal_approx(spread_toggle_shape.size) \
			or spread_toggle_material == null or not spread_toggle_material.albedo_color.is_equal_approx(Color(0.2, 0.8, 1.0, 1.0)):
		range.queue_free()
		return _fail("Range targets must retain their layer, mask, matching 4m switch geometry, and blue material.")
	var edge_gap := absf(spread_toggle_target.position.x - clear_target.position.x) - (clear_shape.size.x + spread_toggle_shape.size.x) * 0.5
	if not is_equal_approx(edge_gap, 4.0) \
			or clear_target.position.x >= 0.0 or spread_toggle_target.position.x >= 0.0 \
			or not is_equal_approx(spread_toggle_target.position.y, clear_target.position.y) \
			or not is_equal_approx(spread_toggle_target.position.z, clear_target.position.z) \
			or clear_target.get_node("ClearLabel").font_size != 320 \
			or spread_toggle_target.get_node("SpreadToggleLabel").font_size != 320:
		range.queue_free()
		return _fail("Switch targets must sit on the left, side by side with a 4m edge gap and five-times larger labels.")
	if target_grid.get_child_count() != 22 or range_markings.get_child_count() != 8:
		range.queue_free()
		return _fail("Target grid and 25/50/75/100m markings must be editor-visible authored geometry.")
	for grid_line: Node in target_grid.get_children():
		var grid_mesh := grid_line as MeshInstance3D
		if grid_mesh == null or grid_mesh.position.z <= 0.1:
			range.queue_free()
			return _fail("Target grid must remain outside the main target front surface at local +Z.")
	for distance in [25, 50, 75, 100]:
		if range_markings.get_node_or_null("DistanceLine%dm" % distance) == null \
				or range_markings.get_node_or_null("DistanceLabel%dm" % distance) == null:
			range.queue_free()
			return _fail("Each required distance marking needs a line and metre label.")
	range.set("target_height_m", 12.0)
	if not main_shape.size.is_equal_approx(Vector3(10, 12, 0.2)) or target_grid.get_child_count() != 24:
		range.queue_free()
		return _fail("Exported target dimensions must rebuild the preview geometry and collision.")
	range.set("target_height_m", 10.0)
	var hit := _ray_hit(main_target.global_position + Vector3(0, 0, 4), main_target.global_position - Vector3(0, 0, 2))
	if hit.is_empty() or hit.collider != main_target:
		range.queue_free()
		return _fail("A physical ray toward the front of the main target must hit it.")
	var shot := ShotEvent.new(Transform3D.IDENTITY, Vector3.FORWARD, main_target.get_rid())
	var impact := ImpactEvent.new(shot, main_target, hit.position, hit.normal)
	range.call("consume_impact", impact)
	range.call("consume_impact", impact)
	var first_marker := markers.get_child(0) as MeshInstance3D
	var marker_faces_surface := first_marker != null and absf(first_marker.global_transform.basis.y.dot(hit.normal)) > 0.99
	if int(range.call("get_marker_count")) != 2 or _has_collision(markers) or not marker_faces_surface:
		range.queue_free()
		return _fail("Main-target impacts must accumulate collision-free markers facing the hit surface.")
	var blue_hit := _ray_hit(spread_toggle_target.global_position + Vector3(0, 0, 4), spread_toggle_target.global_position - Vector3(0, 0, 2))
	if blue_hit.is_empty() or blue_hit.collider != spread_toggle_target:
		range.queue_free()
		return _fail("A physical ray toward the front of the blue toggle target must hit it.")
	var toggle_events: Array[bool] = []
	range.spread_preview_toggle_requested.connect(func() -> void: toggle_events.append(true))
	var blue_impact := ImpactEvent.new(shot, spread_toggle_target, blue_hit.position, blue_hit.normal)
	range.call("consume_impact", blue_impact)
	if toggle_events.size() != 1 or int(range.call("get_marker_count")) != 2:
		range.queue_free()
		return _fail("Each blue-target impact must emit one toggle request without changing markers.")
	var clear_impact := ImpactEvent.new(shot, clear_target, clear_target.global_position, Vector3.FORWARD)
	range.call("consume_impact", clear_impact)
	if int(range.call("get_marker_count")) != 0 or toggle_events.size() != 1:
		range.queue_free()
		return _fail("Clear target must remove markers without requesting a spread toggle.")
	range.call("consume_impact", blue_impact)
	if toggle_events.size() != 2 or int(range.call("get_marker_count")) != 0:
		range.queue_free()
		return _fail("Each subsequent blue-target impact must emit exactly one toggle request and preserve markers.")
	range.call("consume_impact", impact)
	var reusable: bool = int(range.call("get_marker_count")) == 1 and is_instance_valid(main_target) and is_instance_valid(clear_target) and is_instance_valid(spread_toggle_target)
	range.queue_free()
	return reusable or _fail("Targets must remain usable after clearing markers.")


func _ray_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return root.get_world_3d().direct_space_state.intersect_ray(query)


func _has_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return true
	for child: Node in node.get_children():
		if _has_collision(child):
			return true
	return false


func _fail(message: String) -> bool:
	push_error(message)
	return false
