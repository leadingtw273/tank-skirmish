extends MultiMeshInstance3D

const INSTANCE_COUNT := 480000
const DISTRIBUTION_SEED := 117
const FIELD_BOUNDS := Rect2(-476.0, -476.0, 952.0, 952.0)
const ROAD_FOOTPRINT_HALF_EXTENT := Vector2(11.0, 11.0)
const BUILDING_CLEARANCE := 0.5
const DISTRICT_DENSE_RADIUS := 96.0
const DENSE_DENSITY := 1.0
const OPEN_FIELD_DENSITY := 0.32
const MAX_PLACEMENT_ATTEMPTS := 4800000
const ROAD_SCENE_NAMES := [
	"street_straight.glb",
	"street_curve.glb",
	"street_3way.glb",
	"street_4way.glb",
]


func _ready() -> void:
	var grass_mesh := QuadMesh.new()
	grass_mesh.size = Vector2(0.9, 1.35)
	grass_mesh.subdivide_width = 2
	grass_mesh.subdivide_depth = 2
	grass_mesh.center_offset = Vector3(0.0, 0.675, 0.0)

	var grass_multimesh := MultiMesh.new()
	grass_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	grass_multimesh.mesh = grass_mesh

	var random := RandomNumberGenerator.new()
	random.seed = DISTRIBUTION_SEED
	var scene_root := get_tree().current_scene as Node
	if scene_root == null:
		scene_root = get_tree().root
	var road_footprints := _collect_road_footprints(scene_root)
	var building_clearances := _collect_building_clearances(scene_root)
	var district_centers := _collect_district_centers(scene_root)

	var transforms: Array[Transform3D] = []
	var attempts := 0
	while transforms.size() < INSTANCE_COUNT and attempts < MAX_PLACEMENT_ATTEMPTS:
		attempts += 1
		var point := Vector2(
			random.randf_range(FIELD_BOUNDS.position.x, FIELD_BOUNDS.end.x),
			random.randf_range(FIELD_BOUNDS.position.y, FIELD_BOUNDS.end.y),
		)
		if not _is_grass_position(point, road_footprints, building_clearances):
			continue
		if random.randf() > _grass_density_at(point, district_centers):
			continue
		var position := Vector3(point.x, 0.01, point.y)
		var transform := Transform3D(Basis(Vector3.UP, random.randf_range(0.0, TAU)), position)
		transform.basis = transform.basis.scaled(Vector3.ONE * random.randf_range(0.75, 1.25))
		transforms.append(transform)

	grass_multimesh.instance_count = transforms.size()
	for index in transforms.size():
		grass_multimesh.set_instance_transform(index, transforms[index])

	multimesh = grass_multimesh


func _collect_road_footprints(scene_root: Node) -> Array[Rect2]:
	var footprints: Array[Rect2] = []
	_collect_road_footprints_recursive(scene_root, footprints)
	return footprints


func _collect_road_footprints_recursive(node: Node, footprints: Array[Rect2]) -> void:
	if node is Node3D and ROAD_SCENE_NAMES.has(node.scene_file_path.get_file()):
		var road := node as Node3D
		var road_transform := _accumulated_transform(road)
		var center := Vector2(road_transform.origin.x, road_transform.origin.z)
		footprints.append(Rect2(center - ROAD_FOOTPRINT_HALF_EXTENT, ROAD_FOOTPRINT_HALF_EXTENT * 2.0))
	for child in node.get_children():
		_collect_road_footprints_recursive(child, footprints)


func _collect_building_clearances(scene_root: Node) -> Array[Rect2]:
	var clearances: Array[Rect2] = []
	_collect_building_clearances_recursive(scene_root, clearances)
	return clearances


func _collect_building_clearances_recursive(node: Node, clearances: Array[Rect2]) -> void:
	if node is CollisionShape3D:
		var collision := node as CollisionShape3D
		var building := collision.get_parent() as StaticBody3D
		if building != null and building.get_node_or_null("Model") != null:
			var box := collision.shape as BoxShape3D
			if box != null:
				clearances.append(_collision_clearance(collision, box))
	for child in node.get_children():
		_collect_building_clearances_recursive(child, clearances)


func _collect_district_centers(scene_root: Node) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	_collect_district_centers_recursive(scene_root, centers)
	return centers


func _collect_district_centers_recursive(node: Node, centers: Array[Vector2]) -> void:
	if node is Node3D:
		var spatial_node := node as Node3D
		if spatial_node.name == "Buildings" or spatial_node.scene_file_path.get_file() == "satellite_district.tscn":
			var district_transform := _accumulated_transform(spatial_node)
			centers.append(Vector2(district_transform.origin.x, district_transform.origin.z))
	for child in node.get_children():
		_collect_district_centers_recursive(child, centers)


func _collision_clearance(collision: CollisionShape3D, box: BoxShape3D) -> Rect2:
	var transform := _accumulated_transform(collision)
	var basis := transform.basis
	var half_size := box.size * 0.5
	var half_extent := Vector2(
		absf(basis.x.x) * half_size.x
			+ absf(basis.y.x) * half_size.y
			+ absf(basis.z.x) * half_size.z,
		absf(basis.x.z) * half_size.x
			+ absf(basis.y.z) * half_size.y
			+ absf(basis.z.z) * half_size.z,
	) + Vector2.ONE * BUILDING_CLEARANCE
	var center := Vector2(transform.origin.x, transform.origin.z)
	return Rect2(center - half_extent, half_extent * 2.0)


func _accumulated_transform(node: Node3D) -> Transform3D:
	var transform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform


func _grass_density_at(point: Vector2, district_centers: Array[Vector2]) -> float:
	for center in district_centers:
		if point.distance_to(center) <= DISTRICT_DENSE_RADIUS:
			return DENSE_DENSITY
	return OPEN_FIELD_DENSITY


func _is_grass_position(point: Vector2, road_footprints: Array[Rect2], building_clearances: Array[Rect2]) -> bool:
	for footprint in road_footprints:
		if footprint.has_point(point):
			return false
	for clearance in building_clearances:
		if clearance.has_point(point):
			return false
	return true
