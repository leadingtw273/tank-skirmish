## 主地圖一次性 BinbunGrass 散布；不建立每株節點或物理物件。
extends Node3D

const FIELD_HALF_SIZE := 960.0
const GRID_STEP := 3.0
const GRID_COLUMNS := 640
const TILE_SIZE := 128.0
const TILE_COLUMNS := 15
const CLEARANCE := 1.0
const ROOT_HEIGHT := 0.01
const SEED := 117

@export var grass_material: ShaderMaterial

var candidate_count := 0
var instance_count := 0
var tile_count := 0
var generation_time_ms := 0
var footprint_count := 0

func _ready() -> void:
	var started := Time.get_ticks_msec()
	var exclusions: Array[Array] = []
	var buckets: Array[Array] = []
	for index: int in TILE_COLUMNS * TILE_COLUMNS:
		exclusions.append([])
		buckets.append([])
	_collect_footprints(get_parent().get_node("Roads"), exclusions)
	_collect_footprints(get_parent().get_node("Buildings"), exclusions)
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	for z_index: int in GRID_COLUMNS:
		for x_index: int in GRID_COLUMNS:
			candidate_count += 1
			var jitter_x := 0.5 if x_index == 0 or x_index == GRID_COLUMNS - 1 else 1.4
			var jitter_z := 0.5 if z_index == 0 or z_index == GRID_COLUMNS - 1 else 1.4
			var point := Vector2(
				-FIELD_HALF_SIZE + (float(x_index) + 0.5) * GRID_STEP + random.randf_range(-jitter_x, jitter_x),
				-FIELD_HALF_SIZE + (float(z_index) + 0.5) * GRID_STEP + random.randf_range(-jitter_z, jitter_z)
			)
			var tile_x := int(floor((point.x + FIELD_HALF_SIZE) / TILE_SIZE))
			var tile_z := int(floor((point.y + FIELD_HALF_SIZE) / TILE_SIZE))
			var tile_index := tile_z * TILE_COLUMNS + tile_x
			if not _excluded(point, exclusions[tile_index]):
				buckets[tile_index].append(point)
				instance_count += 1
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.9)
	quad.center_offset = Vector3(0.0, 0.45, 0.0)
	for index: int in buckets.size():
		if buckets[index].is_empty():
			continue
		var origin := Vector3(
			-FIELD_HALF_SIZE + float(index % TILE_COLUMNS) * TILE_SIZE,
			0.0,
			-FIELD_HALF_SIZE + float(index / TILE_COLUMNS) * TILE_SIZE
		)
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = quad
		instances.instance_count = buckets[index].size()
		## 含最大 billboard 伸展；透明草形裁切不改此保守範圍。
		instances.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(130.0, 2.0, 130.0))
		for point_index: int in buckets[index].size():
			var point: Vector2 = buckets[index][point_index]
			instances.set_instance_transform(point_index, Transform3D(Basis.IDENTITY,
				Vector3(point.x, ROOT_HEIGHT, point.y) - origin))
		var tile := MultiMeshInstance3D.new()
		tile.name = "GrassTile_%02d_%02d" % [index % TILE_COLUMNS, index / TILE_COLUMNS]
		tile.position = origin
		tile.multimesh = instances
		tile.material_override = grass_material
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tile)
		tile_count += 1
	generation_time_ms = Time.get_ticks_msec() - started
	print("MAIN_BINBUN_GRASS candidates=%d instances=%d tiles=%d footprints=%d startup_ms=%d" %
		[candidate_count, instance_count, tile_count, footprint_count, generation_time_ms])

func _collect_footprints(container: Node, exclusions: Array[Array]) -> void:
	for child: Node in container.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null or not instance.visible:
			continue
		var local_bounds := instance.mesh.get_aabb()
		var points := PackedVector2Array()
		for corner: int in 8:
			var local_point := local_bounds.position + local_bounds.size * Vector3(
				float(corner & 1), float((corner >> 1) & 1), float((corner >> 2) & 1))
			var world_point := instance.global_transform * local_point
			points.append(Vector2(world_point.x, world_point.z))
		var hull := Geometry2D.convex_hull(points)
		if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
			hull.resize(hull.size() - 1)
		if hull.size() < 3:
			continue
		for polygon: PackedVector2Array in Geometry2D.offset_polygon(hull, CLEARANCE, Geometry2D.JOIN_MITER):
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point: Vector2 in polygon:
				bounds = bounds.expand(point)
			var minimum := Vector2i(
				clampi(int(floor((bounds.position.x + FIELD_HALF_SIZE) / TILE_SIZE)), 0, TILE_COLUMNS - 1),
				clampi(int(floor((bounds.position.y + FIELD_HALF_SIZE) / TILE_SIZE)), 0, TILE_COLUMNS - 1))
			var maximum := Vector2i(
				clampi(int(floor((bounds.end.x + FIELD_HALF_SIZE) / TILE_SIZE)), 0, TILE_COLUMNS - 1),
				clampi(int(floor((bounds.end.y + FIELD_HALF_SIZE) / TILE_SIZE)), 0, TILE_COLUMNS - 1))
			var footprint := {"bounds": bounds, "polygon": polygon}
			for tile_z: int in range(minimum.y, maximum.y + 1):
				for tile_x: int in range(minimum.x, maximum.x + 1):
					exclusions[tile_z * TILE_COLUMNS + tile_x].append(footprint)
			footprint_count += 1

func _excluded(point: Vector2, footprints: Array) -> bool:
	for footprint: Dictionary in footprints:
		var bounds: Rect2 = footprint["bounds"]
		if bounds.has_point(point) and Geometry2D.is_point_in_polygon(point, footprint["polygon"]):
			return true
	return false
