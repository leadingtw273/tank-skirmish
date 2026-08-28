extends SceneTree

const SATELLITE_DISTRICT_SCENE := "res://src/world/satellite_district.tscn"
const ARTERIAL_CORRIDOR_SCENE := "res://src/world/arterial_corridor.tscn"
const GRASS_FIELD_SCRIPT := "res://src/world/grass_field.gd"
const GRID_SIZE := 20.0
const ROAD_SCALE := Vector3(10, 1, 10)
const ROAD_FOOTPRINT_HALF_EXTENT := Vector2(10.0, 10.0)
const MIN_ROAD_SETBACK := 1.0
const ALLOWED_ROAD_SCENES := [
	"street_straight.glb",
	"street_curve.glb",
	"street_3way.glb",
	"street_4way.glb",
]


func _init() -> void:
	if not _validate_satellite_district() or not _validate_arterial_corridor() or not _validate_grass_field():
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
	root.add_child(district)

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
	if not _validate_satellite_buildings(district, roads):
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
		if child is Node3D and ALLOWED_ROAD_SCENES.has(child.scene_file_path.get_file()):
			roads.append(child as Node3D)
	return roads


func _validate_satellite_buildings(district: Node3D, roads: Array[Node3D]) -> bool:
	var buildings_root := district.get_node_or_null("Buildings") as Node3D
	if buildings_root == null:
		push_error("Satellite district must contain a Buildings node")
		return false
	var buildings: Array[StaticBody3D] = []
	for child in buildings_root.get_children():
		if child is StaticBody3D:
			buildings.append(child as StaticBody3D)
	if buildings.size() != 24:
		push_error("Satellite district must contain exactly 24 buildings, found %d" % buildings.size())
		return false

	var building_rects: Array[Rect2] = []
	for building in buildings:
		if building.get_node_or_null("Model") == null:
			push_error("Building %s must keep its existing model instance" % building.name)
			return false
		var collision := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var box := collision.shape as BoxShape3D if collision != null else null
		if collision == null or box == null:
			push_error("Building %s must keep a BoxShape3D collision" % building.name)
			return false
		if not _validate_building_rotation(building):
			return false
		var building_rect := _collision_rect(collision, box)
		for existing_rect in building_rects:
			if building_rect.intersects(existing_rect):
				push_error("Satellite district buildings must not overlap")
				return false
		building_rects.append(building_rect)
		if not _validate_building_road_clearance(building, building_rect, roads):
			return false
	return true


func _validate_building_rotation(building: StaticBody3D) -> bool:
	var expected_rotation := 0.0
	if building.name.begins_with("South"):
		expected_rotation = PI
	elif building.name.begins_with("West"):
		expected_rotation = PI / 2.0
	elif building.name.begins_with("East"):
		expected_rotation = -PI / 2.0
	if not is_equal_approx(building.rotation.y, expected_rotation):
		push_error("Building %s must face its adjacent road with a cardinal rotation" % building.name)
		return false
	return true


func _collision_rect(collision: CollisionShape3D, box: BoxShape3D) -> Rect2:
	var transform := _accumulated_transform(collision)
	var basis := transform.basis
	var half_size := box.size * 0.5
	var half_extent := Vector2(
		absf(basis.x.x) * half_size.x + absf(basis.y.x) * half_size.y + absf(basis.z.x) * half_size.z,
		absf(basis.x.z) * half_size.x + absf(basis.y.z) * half_size.y + absf(basis.z.z) * half_size.z,
	)
	var center := Vector2(transform.origin.x, transform.origin.z)
	return Rect2(center - half_extent, half_extent * 2.0)


func _accumulated_transform(node: Node3D) -> Transform3D:
	var transform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform


func _validate_building_road_clearance(building: StaticBody3D, building_rect: Rect2, roads: Array[Node3D]) -> bool:
	var nearest_road_distance := INF
	for road in roads:
		var road_center := Vector2(road.position.x, road.position.z)
		var road_rect := Rect2(road_center - ROAD_FOOTPRINT_HALF_EXTENT, ROAD_FOOTPRINT_HALF_EXTENT * 2.0)
		if building_rect.intersects(road_rect.grow(MIN_ROAD_SETBACK)):
			push_error("Building %s must not overlap its adjacent road or block its entrance" % building.name)
			return false
		nearest_road_distance = minf(nearest_road_distance, _rect_distance(building_rect, road_rect))
	if nearest_road_distance > 4.0:
		push_error("Building %s must remain adjacent to a road" % building.name)
		return false
	return true


func _rect_distance(first: Rect2, second: Rect2) -> float:
	var horizontal_gap := maxf(maxf(first.position.x - second.end.x, second.position.x - first.end.x), 0.0)
	var vertical_gap := maxf(maxf(first.position.y - second.end.y, second.position.y - first.end.y), 0.0)
	return Vector2(horizontal_gap, vertical_gap).length()


func _validate_grass_field() -> bool:
	var grass_field = load(GRASS_FIELD_SCRIPT).new()
	if grass_field.INSTANCE_COUNT != 480000 \
			or grass_field.DISTRIBUTION_SEED != 117 \
			or not grass_field.FIELD_BOUNDS.is_equal_approx(Rect2(-476.0, -476.0, 952.0, 952.0)):
		push_error("Grass field must retain its seed and cover the 952m inset of the 960m map")
		return false
	if grass_field.DENSE_DENSITY <= grass_field.OPEN_FIELD_DENSITY:
		push_error("Grass density must be higher around districts than in open terrain")
		return false

	var host := Node3D.new()
	root.add_child(host)
	var central_buildings := Node3D.new()
	central_buildings.name = "Buildings"
	host.add_child(central_buildings)
	var central_building := StaticBody3D.new()
	central_building.position = Vector3(-300, 0, -300)
	central_buildings.add_child(central_building)
	var central_model := Node3D.new()
	central_model.name = "Model"
	central_building.add_child(central_model)
	var central_collision := CollisionShape3D.new()
	var central_box := BoxShape3D.new()
	central_box.size = Vector3(8, 6, 8)
	central_collision.shape = central_box
	central_building.add_child(central_collision)

	var satellite := _instantiate(SATELLITE_DISTRICT_SCENE)
	if satellite == null:
		grass_field.free()
		host.free()
		return false
	satellite.position = Vector3(160, 0, 0)
	host.add_child(satellite)

	var road_footprints: Array[Rect2] = grass_field._collect_road_footprints(host)
	var building_clearances: Array[Rect2] = grass_field._collect_building_clearances(host)
	var district_centers: Array[Vector2] = grass_field._collect_district_centers(host)
	var valid: bool = road_footprints.size() == 45 \
		and building_clearances.size() == 25 \
		and not grass_field._is_grass_position(Vector2(160, -80), road_footprints, building_clearances) \
		and not grass_field._is_grass_position(Vector2(-300, -300), road_footprints, building_clearances) \
		and is_equal_approx(grass_field._grass_density_at(Vector2(160, 0), district_centers), grass_field.DENSE_DENSITY) \
		and is_equal_approx(grass_field._grass_density_at(Vector2(400, 400), district_centers), grass_field.OPEN_FIELD_DENSITY)
	grass_field.free()
	host.free()
	if not valid:
		push_error("Grass field must recursively avoid central and satellite roads and buildings")
		return false
	return true


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
