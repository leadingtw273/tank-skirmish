## R3-A 唯讀匯出道路模組 transform 與實際碰撞三角形；不建立全圖路燈。
extends SceneTree


func _init() -> void:
	call_deferred("_run")

func _v(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _faces(node: Node) -> Array:
	var rows: Array = []
	for collider: CollisionShape3D in node.find_children("*", "CollisionShape3D", true, false):
		if collider.shape is ConcavePolygonShape3D:
			var points: Array = []
			for point: Vector3 in collider.shape.get_faces():
				points.append(_v(collider.global_transform * point))
			rows.append({"path":str(collider.get_path()), "points":points})
	return rows

func _run() -> void:
	var data := {"roads":[], "buildings":[], "existing_lamps":[], "spawn":[-108,0,-106]}
	var map := load("res://src/maps/main_battlefield/main_battlefield.tscn").instantiate() as Node3D
	var constants: Dictionary = map.get_node("MainWeather").get_script().get_script_constant_map()
	for index: int in constants.POSITIONS.size():
		data.existing_lamps.append({"position":_v(constants.POSITIONS[index]), "yaw":constants.LAMP_YAWS[index]})
	map.get_node("MainWeather").free()
	map.get_node("GrassField").free()
	root.add_child(map)
	for group: String in ["Junctions", "Connections"]:
		for module: Node3D in map.get_node("Roads/" + group).get_children():
			var t := module.global_transform
			data.roads.append({"name":str(module.name), "group":group, "road_id":module.get_meta("road_id", ""), "origin":_v(t.origin), "basis":[_v(t.basis.x),_v(t.basis.y),_v(t.basis.z)], "faces":_faces(module)})
	for building: Node3D in map.get_node("Buildings").get_children():
		data.buildings.append({"name":str(building.name),"faces":_faces(building)})
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	print("ROUND2_GEOMETRY roads=",data.roads.size()," buildings=",data.buildings.size())
	map.free()
	quit()
