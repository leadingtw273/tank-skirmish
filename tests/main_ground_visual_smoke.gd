extends SceneTree
const MAP := preload("res://src/maps/main_battlefield/main_battlefield.tscn")
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var world := MAP.instantiate() as Node3D
	root.add_child(world)
	await physics_frame
	await physics_frame
	var visual := world.get_node("Ground/Visual") as MeshInstance3D
	var collision := world.get_node("Ground/CollisionShape3D") as CollisionShape3D
	var visual_bounds: AABB = visual.global_transform * visual.get_aabb()
	var size := (collision.shape as BoxShape3D).size
	var collision_bounds: AABB = collision.global_transform * AABB(-size * 0.5, size)
	var ok := visual_bounds.position.distance_to(collision_bounds.position) < 0.001 and visual_bounds.end.distance_to(collision_bounds.end) < 0.001
	for point in [Vector3.ZERO, Vector3(-108, 0, -106), Vector3(-120, 0, -100)]:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 10.0, point + Vector3.DOWN * 1.0, 128)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		ok = ok and not hit.is_empty() and absf((hit.get("position", Vector3.INF) as Vector3).y) < 0.001
	print("GROUND_VISUAL visual=%s collision=%s aligned=%s" % [visual_bounds, collision_bounds, ok])
	world.queue_free()
	await physics_frame
	quit(0 if ok else 1)
