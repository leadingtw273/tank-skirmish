extends SceneTree

const TerrainClassifier := preload("res://src/actors/rigid_tank/rigid_terrain_classifier.gd")
const Road := preload("res://src/world/roads/items/base/Road1/Road1_B__Road1_A.tscn")

var failures: Array[String] = []
var reserve_calls := 0
var reserve_invocations := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var classifier := TerrainClassifier.new()
	var low_box := _static_box(Vector3(2.0, 1.0, 2.0), Vector3(0.0, 0.0, 0.0))
	_expect(classifier.body_is_traversable(low_box, 0.51, _reserve), "static Box top=.50 must pass max=.51")

	var road := Road.instantiate() as StaticBody3D
	road.position.y = 0.03
	root.add_child(road)
	_expect(classifier.body_is_traversable(road, 0.51, _reserve), "Road1 collider top=.5053 at y=.03 must pass max=.51")

	var high_wall := _static_box(Vector3(0.3, 2.0, 2.0), Vector3(0.0, 1.0, 0.0))
	_expect(not classifier.body_is_traversable(high_wall, 0.51, _reserve), "high static wall must fail")

	var combined := StaticBody3D.new()
	root.add_child(combined)
	_add_box(combined, Vector3(4.0, 0.2, 4.0), Vector3(0.0, -0.1, 0.0))
	_add_box(combined, Vector3(0.3, 2.0, 2.0), Vector3(0.0, 1.0, 0.0))
	_expect(not classifier.body_is_traversable(combined, 0.51, _reserve), "static floor plus high wall must fail as one body")

	var dynamic_low := RigidBody3D.new()
	root.add_child(dynamic_low)
	_add_box(dynamic_low, Vector3(2.0, 0.2, 2.0), Vector3(0.0, -0.1, 0.0))
	_expect(not classifier.body_is_traversable(dynamic_low, 0.51, _reserve), "dynamic RigidBody3D must fail even below cap")
	var unknown_shape := StaticBody3D.new()
	root.add_child(unknown_shape)
	var sphere_collision := CollisionShape3D.new()
	sphere_collision.shape = SphereShape3D.new()
	unknown_shape.add_child(sphere_collision)
	_expect(not classifier.body_is_traversable(unknown_shape, 0.51, _reserve), "unknown SphereShape3D must fail closed")
	_expect(not classifier.body_is_traversable(low_box, 0.51, func(_count: int = 1) -> bool: return false), "exhausted reserve must fail closed")
	_expect(not classifier.body_is_traversable(low_box, -INF, _reserve), "missing maximum_y must fail closed")

	var cache_box := _static_box(Vector3(2.0, 1.0, 2.0), Vector3(4.0, 0.0, 0.0))
	_expect(classifier.body_is_traversable(cache_box, 0.51, _reserve), "cached low box first lookup must pass")
	var after_first := reserve_calls
	var invocations_after_first := reserve_invocations
	_expect(classifier.body_is_traversable(cache_box, 0.51, _reserve), "cached low box second lookup must pass")
	_expect(reserve_calls == after_first, "same-frame geometry cache must avoid a second positive reserve")
	_expect(reserve_invocations > invocations_after_first, "cached lookup must still call reserve(0) for deadline checks")
	await physics_frame
	var next_snapshot := TerrainClassifier.new()
	_expect(next_snapshot.body_is_traversable(cache_box, 0.51, _reserve), "low box in next snapshot must pass")
	_expect(reserve_calls > after_first, "new next-frame helper must reserve geometry again")

	print("RIGID_TERRAIN_CLASSIFIER failures=", failures)
	quit(0 if failures.is_empty() else 1)


func _static_box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	root.add_child(body)
	_add_box(body, size, position)
	return body


func _add_box(body: CollisionObject3D, size: Vector3, position: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = position
	body.add_child(collision)


func _reserve(count: int = 1) -> bool:
	reserve_invocations += 1
	reserve_calls += count
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
