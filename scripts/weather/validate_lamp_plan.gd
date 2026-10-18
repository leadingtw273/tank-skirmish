## R3-A 作者幾何查核：重用一盞原型的實際碰撞形狀，不鋪設全圖實例。
extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var map := load("res://src/maps/main_battlefield/main_battlefield.tscn").instantiate() as Node3D
	map.get_node("MainWeather").free()
	map.get_node("GrassField").free()
	root.add_child(map)
	current_scene = map
	var prototype := load("res://src/maps/main_battlefield/street_lamp.tscn").instantiate() as RigidBody3D
	prototype.position = Vector3(-800, 100, -800)
	map.add_child(prototype)
	prototype.freeze = true
	for frame: int in 3:
		await physics_frame
	var excluded: Array[RID] = [prototype.get_rid(), map.get_node("Ground").get_rid()]
	var rows: Array[Dictionary] = []
	var failures := 0
	for lamp: Dictionary in plan.lamps:
		var p: Array = lamp.position
		var position := Vector3(p[0], p[1], p[2])
		var pose := Transform3D(Basis(Vector3.UP, lamp.yaw), position)
		var errors: Array[String] = []
		for shape: Node in prototype.get_children():
			if not shape is CollisionShape3D:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape.shape
			query.transform = pose * shape.transform
			query.collision_mask = 129
			query.exclude = excluded
			for hit: Dictionary in map.get_world_3d().direct_space_state.intersect_shape(query):
				errors.append("overlap:" + str(hit.collider.get_path()))
		var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP, position - Vector3.UP, 129, excluded)
		var support := map.get_world_3d().direct_space_state.intersect_ray(ray)
		if support.is_empty() or not support.collider.get_meta("road_module", false):
			errors.append("未站在道路模組人行道")
		elif absf(support.position.y - position.y) > 0.001 or support.normal.y < 0.9:
			errors.append("高度或支撐斜率錯誤")
		rows.append({"id":lamp.id,"position":str(position),"errors":errors,"support_y":support.position.y if not support.is_empty() else null})
		failures += int(not errors.is_empty())
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"failures":failures,"engine":Engine.get_version_info()},"\t"))
	file.close()
	print("LAMP_PLAN_GEOMETRY lamps=", rows.size(), " failures=", failures)
	map.queue_free()
	for frame: int in 2:
		await physics_frame
	quit(0 if failures == 0 else 1)
