extends SceneTree

const SATELLITE_DISTRICT := "res://src/satellite_district.tscn"
const ARTERIAL_CORRIDOR := "res://src/arterial_corridor.tscn"
const GRID_SIZE := 20.0
const ROAD_SCALE := Vector3(10, 1, 10)
const DISTRICT_ROAD_COUNT := 45
const CORRIDOR_ROAD_COUNT := 10
const ALLOWED_ROAD_MODELS := [
	"street_straight.glb",
	"street_curve.glb",
	"street_3way.glb",
	"street_4way.glb",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _validate_satellite_district():
		_finish(1)
		return
	if not _validate_arterial_corridor():
		_finish(1)
		return
	print("Map 960 component smoke passed.")
	_finish(0)


func _finish(status: int) -> void:
	for child in root.get_children():
		child.queue_free()
	call_deferred("_quit_after_cleanup", status)


func _quit_after_cleanup(status: int) -> void:
	await process_frame
	quit(status)


func _validate_satellite_district() -> bool:
	var district := _instantiate(SATELLITE_DISTRICT)
	if district == null:
		return false
	if district.name != "SatelliteDistrict":
		push_error("Satellite district root must remain named SatelliteDistrict")
		return false
	if district.get_child_count() != DISTRICT_ROAD_COUNT:
		push_error("Satellite district must contain %d road nodes, found %d" % [DISTRICT_ROAD_COUNT, district.get_child_count()])
		return false
	if not _validate_road_children(district):
		return false
	if not _validate_district_ring(district):
		return false
	if not _validate_district_cross_and_entrance(district):
		return false
	return true


func _validate_arterial_corridor() -> bool:
	var corridor := _instantiate(ARTERIAL_CORRIDOR)
	if corridor == null:
		return false
	if corridor.name != "ArterialCorridor":
		push_error("Arterial corridor root must remain named ArterialCorridor")
		return false
	if corridor.get_child_count() != CORRIDOR_ROAD_COUNT:
		push_error("Arterial corridor must contain %d road nodes, found %d" % [CORRIDOR_ROAD_COUNT, corridor.get_child_count()])
		return false
	if not _validate_road_children(corridor):
		return false
	for child in corridor.get_children():
		var road := child as Node3D
		if road == null or road.scene_file_path.get_file() != "street_straight.glb":
			push_error("Arterial corridor may only use Street_Straight")
			return false
	if not _has_road_at(corridor, Vector3(0, 0, 0), "street_straight.glb") or not _has_road_at(corridor, Vector3(0, 0, 180), "street_straight.glb"):
		push_error("Arterial corridor endpoints must remain at z=0 and z=180")
		return false
	for z in range(0, 200, 20):
		if not _has_road_at(corridor, Vector3(0, 0, z), "street_straight.glb"):
			push_error("Arterial corridor has a gap at z=%d" % z)
			return false
	return true


func _instantiate(scene_path: String) -> Node3D:
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Unable to load scene: %s" % scene_path)
		return null
	var instance := packed_scene.instantiate() as Node3D
	if instance == null:
		push_error("Unable to instantiate scene: %s" % scene_path)
		return null
	root.add_child(instance)
	return instance


func _validate_road_children(root: Node3D) -> bool:
	for child in root.get_children():
		var road := child as Node3D
		if road == null:
			push_error("%s may only contain road Node3D children" % root.name)
			return false
		if not ALLOWED_ROAD_MODELS.has(road.scene_file_path.get_file()):
			push_error("%s uses an unapproved road model: %s" % [road.name, road.scene_file_path])
			return false
		if not road.scale.is_equal_approx(ROAD_SCALE):
			push_error("%s must use the existing road scale" % road.name)
			return false
		if not is_zero_approx(road.position.y) or not _is_grid_aligned(road.position.x) or not _is_grid_aligned(road.position.z):
			push_error("%s is not aligned to the 20m road grid" % road.name)
			return false
		if not _is_orthogonal_rotation(road.rotation.y):
			push_error("%s must use an orthogonal road rotation" % road.name)
			return false
	return true


func _validate_district_ring(district: Node3D) -> bool:
	for coordinate in [-80, -60, -40, -20, 0, 20, 40, 60, 80]:
		if not _has_any_road_at(district, Vector3(coordinate, 0, -80)) or not _has_any_road_at(district, Vector3(coordinate, 0, 80)):
			push_error("Satellite district outer north or south ring is discontinuous")
			return false
		if not _has_any_road_at(district, Vector3(-80, 0, coordinate)) or not _has_any_road_at(district, Vector3(80, 0, coordinate)):
			push_error("Satellite district outer west or east ring is discontinuous")
			return false
	return true


func _validate_district_cross_and_entrance(district: Node3D) -> bool:
	if not _has_road_at(district, Vector3(0, 0, -80), "street_4way.glb"):
		push_error("Satellite district must keep a central-facing entrance at the north ring")
		return false
	if not _has_road_at(district, Vector3(0, 0, 0), "street_4way.glb"):
		push_error("Satellite district must keep its central four-way crossing")
		return false
	for coordinate in [-80, -60, -40, -20, 0, 20, 40, 60, 80]:
		if not _has_any_road_at(district, Vector3(coordinate, 0, 0)) or not _has_any_road_at(district, Vector3(0, 0, coordinate)):
			push_error("Satellite district cross road is discontinuous")
			return false
	return true


func _has_any_road_at(root: Node3D, expected_position: Vector3) -> bool:
	for child in root.get_children():
		var road := child as Node3D
		if road != null and road.position.is_equal_approx(expected_position):
			return true
	return false


func _has_road_at(root: Node3D, expected_position: Vector3, expected_model: String) -> bool:
	for child in root.get_children():
		var road := child as Node3D
		if road != null and road.position.is_equal_approx(expected_position) and road.scene_file_path.get_file() == expected_model:
			return true
	return false


func _is_grid_aligned(value: float) -> bool:
	return is_equal_approx(fposmod(value, GRID_SIZE), 0.0)


func _is_orthogonal_rotation(value: float) -> bool:
	for allowed_rotation in [0.0, PI / 2.0, -PI / 2.0, PI, -PI]:
		if is_equal_approx(value, allowed_rotation):
			return true
	return false
