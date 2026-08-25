extends SceneTree

const SATELLITE_DISTRICT_SCENE := "res://src/satellite_district.tscn"
const ARTERIAL_CORRIDOR_SCENE := "res://src/arterial_corridor.tscn"
const GRID_SIZE := 20.0
const ROAD_SCALE := Vector3(10, 1, 10)
const ALLOWED_ROAD_SCENES := [
	"street_straight.glb",
	"street_curve.glb",
	"street_3way.glb",
	"street_4way.glb",
]


func _init() -> void:
	if not _validate_satellite_district() or not _validate_arterial_corridor():
		quit(1)
		return
	print("960m map component smoke validation passed.")
	quit(0)


func _validate_satellite_district() -> bool:
	var district := _instantiate(SATELLITE_DISTRICT_SCENE)
	if district == null:
		return false
	if district.name != "SatelliteDistrict":
		push_error("Satellite district root must be named SatelliteDistrict")
		return false

	var roads := _road_children(district)
	if roads.size() != 45:
		push_error("Satellite district must contain exactly 45 road modules, found %d" % roads.size())
		return false
	var scene_counts := {"street_straight.glb": 0, "street_curve.glb": 0, "street_3way.glb": 0, "street_4way.glb": 0}
	for road in roads:
		if not _validate_road_transform(road):
			return false
		var scene_name := road.scene_file_path.get_file()
		if not ALLOWED_ROAD_SCENES.has(scene_name):
			push_error("Satellite district uses an unapproved road asset: %s" % scene_name)
			return false
		scene_counts[scene_name] += 1
	if scene_counts != {"street_straight.glb": 36, "street_curve.glb": 4, "street_3way.glb": 4, "street_4way.glb": 1}:
		push_error("Satellite district road-model mix does not match the approved reusable layout")
		return false

	if not _has_road(district, "CentralEntrance", Vector3(0, 0, 80), "street_3way.glb", -PI / 2.0):
		return false
	for coordinate in [-80.0, -60.0, -40.0, 0.0, 40.0, 60.0, 80.0]:
		if not _has_road_at(district, Vector3(coordinate, 0, -80)) or not _has_road_at(district, Vector3(coordinate, 0, 80)):
			push_error("Satellite district outer ring must remain continuous on the 20m grid")
			return false
		if not _has_road_at(district, Vector3(-80, 0, coordinate)) or not _has_road_at(district, Vector3(80, 0, coordinate)):
			push_error("Satellite district outer ring must remain continuous on the 20m grid")
			return false
	for coordinate in [-80.0, -60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0, 80.0]:
		if not _has_road_at(district, Vector3(coordinate, 0, 0)) or not _has_road_at(district, Vector3(0, 0, coordinate)):
			push_error("Satellite district must contain continuous horizontal and vertical main roads")
			return false
	district.free()
	return true


func _validate_arterial_corridor() -> bool:
	var corridor := _instantiate(ARTERIAL_CORRIDOR_SCENE)
	if corridor == null:
		return false
	if corridor.name != "ArterialCorridor":
		push_error("Arterial corridor root must be named ArterialCorridor")
		return false
	var roads := _road_children(corridor)
	if roads.size() != 9:
		push_error("Arterial corridor must contain nine reusable straight-road modules")
		return false
	for index in range(roads.size()):
		var road := roads[index]
		if road.scene_file_path.get_file() != "street_straight.glb" or not _validate_road_transform(road):
			push_error("Arterial corridor may only contain aligned Street_Straight modules")
			return false
		if not road.position.is_equal_approx(Vector3(index * GRID_SIZE, 0, 0)):
			push_error("Arterial corridor must be continuous at 20m intervals")
			return false
	if not _has_road(corridor, "CentralEndpoint", Vector3.ZERO, "street_straight.glb", 0.0) \
			or not _has_road(corridor, "SatelliteEndpoint", Vector3(160, 0, 0), "street_straight.glb", 0.0):
		return false
	corridor.free()
	return true


func _instantiate(path: String) -> Node3D:
	var packed_scene := load(path) as PackedScene
	if packed_scene == null:
		push_error("Unable to load component scene: %s" % path)
		return null
	var instance := packed_scene.instantiate() as Node3D
	if instance == null:
		push_error("Unable to instantiate component scene: %s" % path)
	return instance


func _road_children(parent: Node3D) -> Array[Node3D]:
	var roads: Array[Node3D] = []
	for child in parent.get_children():
		if child is Node3D:
			roads.append(child as Node3D)
	return roads


func _validate_road_transform(road: Node3D) -> bool:
	if not is_zero_approx(road.position.y) \
			or not is_zero_approx(fmod(road.position.x, GRID_SIZE)) \
			or not is_zero_approx(fmod(road.position.z, GRID_SIZE)):
		push_error("Road %s is not positioned on the 20m grid" % road.name)
		return false
	if not road.scale.is_equal_approx(ROAD_SCALE):
		push_error("Road %s must retain the approved 20m model scale" % road.name)
		return false
	var rotation_quarters := road.rotation.y / (PI / 2.0)
	if not is_equal_approx(rotation_quarters, roundf(rotation_quarters)):
		push_error("Road %s rotation must be a 90-degree increment" % road.name)
		return false
	return true


func _has_road(parent: Node3D, node_name: String, position: Vector3, scene_name: String, rotation_y: float) -> bool:
	var road := parent.get_node_or_null(node_name) as Node3D
	if road == null or not road.position.is_equal_approx(position) \
			or road.scene_file_path.get_file() != scene_name \
			or not is_equal_approx(road.rotation.y, rotation_y):
		push_error("Required road %s is missing or has an unexpected transform" % node_name)
		return false
	return true


func _has_road_at(parent: Node3D, position: Vector3) -> bool:
	for road in _road_children(parent):
		if road.position.is_equal_approx(position):
			return true
	return false
