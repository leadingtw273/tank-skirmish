extends MultiMeshInstance3D

const INSTANCE_COUNT := 144000
const DISTRIBUTION_SEED := 117
const FIELD_BOUNDS := Rect2(-116.0, -116.0, 232.0, 232.0)
const ROAD_X := [-90.0, -30.0, 30.0, 90.0]
const ROAD_Z := [-82.0, -22.0, 38.0, 98.0]
const ROAD_HALF_WIDTH := 11.0
const BUILDING_CLEARANCE := 0.5
const MAX_PLACEMENT_ATTEMPTS := 1440000


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
	var building_clearances := _collect_building_clearances()

	var transforms: Array[Transform3D] = []
	var attempts := 0
	while transforms.size() < INSTANCE_COUNT and attempts < MAX_PLACEMENT_ATTEMPTS:
		attempts += 1
		var point := Vector2(
			random.randf_range(FIELD_BOUNDS.position.x, FIELD_BOUNDS.end.x),
			random.randf_range(FIELD_BOUNDS.position.y, FIELD_BOUNDS.end.y),
		)
		if not _is_grass_position(point, building_clearances):
			continue
		var position := Vector3(point.x, 0.01, point.y)
		var transform := Transform3D(Basis(Vector3.UP, random.randf_range(0.0, TAU)), position)
		transform.basis = transform.basis.scaled(Vector3.ONE * random.randf_range(0.75, 1.25))
		transforms.append(transform)

	grass_multimesh.instance_count = transforms.size()
	for index in transforms.size():
		grass_multimesh.set_instance_transform(index, transforms[index])

	multimesh = grass_multimesh


func _collect_building_clearances() -> Array[Rect2]:
	var clearances: Array[Rect2] = []
	for building in get_node("../Buildings").get_children():
		var collision := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision == null:
			continue
		var box := collision.shape as BoxShape3D
		if box == null:
			continue

		var basis := collision.global_transform.basis
		var half_size := box.size * 0.5
		var half_extent := Vector2(
			absf(basis.x.x) * half_size.x
				+ absf(basis.y.x) * half_size.y
				+ absf(basis.z.x) * half_size.z,
			absf(basis.x.z) * half_size.x
				+ absf(basis.y.z) * half_size.y
				+ absf(basis.z.z) * half_size.z,
		) + Vector2.ONE * BUILDING_CLEARANCE
		var center := Vector2(collision.global_position.x, collision.global_position.z)
		clearances.append(Rect2(center - half_extent, half_extent * 2.0))
	return clearances


func _is_grass_position(point: Vector2, building_clearances: Array[Rect2]) -> bool:
	for road_x in ROAD_X:
		if absf(point.x - road_x) <= ROAD_HALF_WIDTH:
			return false
	for road_z in ROAD_Z:
		if absf(point.y - road_z) <= ROAD_HALF_WIDTH:
			return false
	for building in building_clearances:
		if building.has_point(point):
			return false
	return true
