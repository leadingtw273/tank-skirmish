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
const DETAIL_TILE_SIZE := 32.0
const DETAIL_GRID_STEP := 0.5
const DETAIL_COLUMNS := 64
const DETAIL_RADIUS := 4
const DETAIL_BATCH_SIZE := 1024
const DETAIL_JITTER := 0.2

@export var grass_material: ShaderMaterial

var candidate_count := 0
var instance_count := 0
var tile_count := 0
var generation_time_ms := 0
var footprint_count := 0
var detail_tiles: Dictionary = {}
var detail_queue: Array[Vector2i] = []
var detail_desired_count := 0
var detail_candidate_count := 0
var detail_instance_count := 0
var detail_last_batch_candidates := 0
var detail_last_batch_us := 0
var detail_max_batch_us := 0
var _exclusions: Array[Array] = []
var _detail_center := Vector2i(100000, 100000)
var _detail_active := false
var _detail_key := Vector2i.ZERO
var _detail_cursor := 0
var _detail_count := 0
var _detail_buffer := PackedFloat32Array()
var _detail_random := RandomNumberGenerator.new()
var _detail_quad: QuadMesh

func _ready() -> void:
	var started := Time.get_ticks_msec()
	var exclusions: Array[Array] = []
	var buckets: Array[Array] = []
	for index: int in TILE_COLUMNS * TILE_COLUMNS:
		exclusions.append([])
		buckets.append([])
	_collect_footprints(get_parent().get_node("Roads"), exclusions)
	_collect_footprints(get_parent().get_node("Buildings"), exclusions)
	_exclusions = exclusions
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
		instances.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(131.0, 3.0, 131.0))
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
	_detail_quad = QuadMesh.new()
	_detail_quad.size = Vector2(0.8, 1.0)
	_detail_quad.center_offset = Vector3(0.0, 0.5, 0.0)

func _process(_delta: float) -> void:
	detail_last_batch_candidates = 0
	detail_last_batch_us = 0
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_basis.z
	if forward.y >= -0.0001:
		return
	var focus := camera.global_position + forward * (-camera.global_position.y / forward.y)
	var center := Vector2i(floori(focus.x / DETAIL_TILE_SIZE), floori(focus.z / DETAIL_TILE_SIZE))
	if center != _detail_center:
		_update_detail_center(center)
	if not _detail_active and detail_queue.is_empty():
		return
	var started := Time.get_ticks_usec()
	if not _detail_active:
		_detail_key = detail_queue.pop_front()
		_detail_cursor = 0
		_detail_count = 0
		_detail_buffer.resize(DETAIL_COLUMNS * DETAIL_COLUMNS * 12)
		_detail_random.seed = SEED + (_detail_key.x + 30) * 1009 + (_detail_key.y + 30) * 9176
		_detail_active = true
	var origin := Vector2(_detail_key) * DETAIL_TILE_SIZE
	for batch_index: int in DETAIL_BATCH_SIZE:
		if _detail_cursor >= DETAIL_COLUMNS * DETAIL_COLUMNS:
			break
		var point := origin + Vector2(
			(float(_detail_cursor % DETAIL_COLUMNS) + 0.5) * DETAIL_GRID_STEP + _detail_random.randf_range(-DETAIL_JITTER, DETAIL_JITTER),
			(float(_detail_cursor / DETAIL_COLUMNS) + 0.5) * DETAIL_GRID_STEP + _detail_random.randf_range(-DETAIL_JITTER, DETAIL_JITTER))
		_detail_cursor += 1
		detail_last_batch_candidates += 1
		detail_candidate_count += 1
		if absf(point.x) > FIELD_HALF_SIZE - CLEARANCE or absf(point.y) > FIELD_HALF_SIZE - CLEARANCE:
			continue
		var tile_x := floori((point.x + FIELD_HALF_SIZE) / TILE_SIZE)
		var tile_z := floori((point.y + FIELD_HALF_SIZE) / TILE_SIZE)
		if _excluded(point, _exclusions[tile_z * TILE_COLUMNS + tile_x]):
			continue
		var offset := _detail_count * 12
		_detail_buffer[offset] = 1.0
		_detail_buffer[offset + 1] = 0.0
		_detail_buffer[offset + 2] = 0.0
		_detail_buffer[offset + 3] = point.x - origin.x
		_detail_buffer[offset + 4] = 0.0
		_detail_buffer[offset + 5] = 1.0
		_detail_buffer[offset + 6] = 0.0
		_detail_buffer[offset + 7] = ROOT_HEIGHT
		_detail_buffer[offset + 8] = 0.0
		_detail_buffer[offset + 9] = 0.0
		_detail_buffer[offset + 10] = 1.0
		_detail_buffer[offset + 11] = point.y - origin.y
		_detail_count += 1
	if _detail_cursor == DETAIL_COLUMNS * DETAIL_COLUMNS:
		_commit_detail_tile(origin)
	detail_last_batch_us = Time.get_ticks_usec() - started
	detail_max_batch_us = maxi(detail_max_batch_us, detail_last_batch_us)

func _update_detail_center(center: Vector2i) -> void:
	_detail_center = center
	var wanted: Dictionary = {}
	for z: int in range(center.y - DETAIL_RADIUS, center.y + DETAIL_RADIUS + 1):
		for x: int in range(center.x - DETAIL_RADIUS, center.x + DETAIL_RADIUS + 1):
			if x >= -30 and x < 30 and z >= -30 and z < 30:
				wanted[Vector2i(x, z)] = true
	for key: Vector2i in detail_tiles.keys():
		if not wanted.has(key):
			var tile := detail_tiles[key] as MultiMeshInstance3D
			detail_instance_count -= tile.multimesh.instance_count
			remove_child(tile)
			tile.queue_free()
			detail_tiles.erase(key)
	if _detail_active and not wanted.has(_detail_key):
		_detail_active = false
		_detail_buffer.clear()
	detail_queue.clear()
	for key: Vector2i in wanted.keys():
		if not detail_tiles.has(key) and (not _detail_active or key != _detail_key):
			detail_queue.append(key)
	detail_queue.sort_custom(_nearer_detail_tile)
	detail_desired_count = wanted.size()

func _nearer_detail_tile(a: Vector2i, b: Vector2i) -> bool:
	return (a - _detail_center).length_squared() < (b - _detail_center).length_squared()

func _commit_detail_tile(origin: Vector2) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = _detail_quad
	instances.instance_count = _detail_count
	_detail_buffer.resize(_detail_count * 12)
	instances.buffer = _detail_buffer
	## 含 billboard 葉片與原 wind_velocity 的最大 .335m 位移。
	instances.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(35.0, 3.0, 35.0))
	var tile := MultiMeshInstance3D.new()
	tile.name = "GrassDetail_%d_%d" % [_detail_key.x, _detail_key.y]
	tile.position = Vector3(origin.x, 0.0, origin.y)
	tile.multimesh = instances
	tile.material_override = grass_material
	tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tile)
	detail_tiles[_detail_key] = tile
	detail_instance_count += _detail_count
	_detail_active = false
	_detail_buffer.clear()

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
