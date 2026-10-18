## 原出生草保持；其餘草依相機地面範圍分批載入，無每株節點或物理查詢。
extends Node3D

const FIELD_BOUNDS := Rect2(-116.0, -115.0, 25.0, 24.0)
const GRID_STEP := 0.2
const GRID_COLUMNS := 125
const GRID_ROWS := 120
const JITTER := 0.08
const ROAD_CLEARANCE := 1.0
const BUILDING_CLEARANCE := 0.15
const ROOT_HEIGHT := 0.01
const SEED := 117
const CHUNK_SIZE := 16.0
const CELLS := 80
const WORLD_ROOTS := Rect2(-959.0, -959.0, 1918.0, 1918.0)
const INSTANCE_CAP := 750000
const ACTIVE_CAP := 400
const CACHE_CAP := 64
const WORK_USEC := 2000
const CANDIDATE_CAP := 2048
const STREAM_SHADER := preload("res://src/maps/main_battlefield/stream_grass.gdshader")
const GROUND_SHADER := preload("res://src/maps/main_battlefield/spawn_grass_ground.gdshader")

@export var grass_material: ShaderMaterial

var candidate_count := 0
var instance_count := 0
var tile_count := 0
var generation_time_ms := 0
var footprint_count := 0
var _exclusions: Array[Array] = []
var _footprint_buckets: Dictionary = {}
var _chunks: Dictionary = {}
var _desired: Dictionary = {}
var _queue: Array[Vector2i] = []
var _job: Dictionary = {}
var _stream_material: ShaderMaterial
var _quad: QuadMesh
var _camera: Camera3D
var _focus_cell := Vector2i(2147483647, 2147483647)
var _zoom_bucket := -1
var _camera_basis := Basis.IDENTITY
var _viewport_size := Vector2.ZERO
var _focus := Vector2.ZERO
var _build_focus := Vector2.ZERO
var _visible := PackedVector2Array()
var _desired_polygon := PackedVector2Array()
var _mid_polygon := PackedVector2Array()
var _elapsed := 0.0
var _resident_count := 0
var _reserved_count := 0
var _revision := 0
var frame_candidates := 0
var frame_uploads := 0
var work_usec := 0
var upload_usec := 0
var peak_instances := 0
var peak_chunks := 0
var peak_queue := 0
var total_stream_candidates := 0
var last_refresh_usec := 0


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_collect_footprints(get_parent().get_node("Roads"), ROAD_CLEARANCE)
	_collect_footprints(get_parent().get_node("Buildings"), BUILDING_CLEARANCE)
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	var points := PackedVector2Array()
	for z_index: int in GRID_ROWS:
		for x_index: int in GRID_COLUMNS:
			candidate_count += 1
			var point := FIELD_BOUNDS.position + Vector2(
				(float(x_index) + 0.5) * GRID_STEP + random.randf_range(-JITTER, JITTER),
				(float(z_index) + 0.5) * GRID_STEP + random.randf_range(-JITTER, JITTER))
			if not _excluded(point):
				points.append(point)
	instance_count = points.size()
	var center := FIELD_BOUNDS.get_center()
	var origin := Vector3(center.x, 0.0, center.y)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.center_offset = Vector3(0.0, 0.2, 0.0)
	quad.subdivide_width = 2
	quad.subdivide_depth = 2
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = quad
	instances.instance_count = instance_count
	instances.custom_aabb = AABB(Vector3(-13.0, -0.5, -12.5), Vector3(26.0, 1.5, 25.0))
	for index: int in points.size():
		var point := points[index]
		instances.set_instance_transform(index, Transform3D(Basis.IDENTITY,
			Vector3(point.x, ROOT_HEIGHT, point.y) - origin))
	var grass := MultiMeshInstance3D.new()
	grass.name = "SpawnGrass"
	grass.position = origin
	grass.multimesh = instances
	grass.material_override = grass_material
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)
	tile_count = 1
	_resident_count = instance_count
	_quad = quad
	_prepare_stream_material()
	_apply_ground_material()
	generation_time_ms = Time.get_ticks_msec() - started
	print("MAIN_BINBUN_GRASS candidates=%d instances=%d tiles=%d footprints=%d startup_ms=%d" %
		[candidate_count, instance_count, tile_count, footprint_count, generation_time_ms])

func _apply_ground_material() -> void:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("noise_texture", grass_material.get_shader_parameter("noise_texture"))
	material.set_shader_parameter("color_gradient", grass_material.get_shader_parameter("color_gradient"))
	var visual := get_parent().get_node("Ground/Visual") as MeshInstance3D
	visual.material_override = material

func _collect_footprints(container: Node, clearance: float) -> void:
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
		for polygon: PackedVector2Array in Geometry2D.offset_polygon(hull, clearance, Geometry2D.JOIN_MITER):
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point: Vector2 in polygon:
				bounds = bounds.expand(point)
			var index := _exclusions.size()
			_exclusions.append([bounds, polygon])
			footprint_count += 1
			var first := _cell(bounds.position)
			var last := _cell(bounds.end)
			for z: int in range(first.y, last.y + 1):
				for x: int in range(first.x, last.x + 1):
					var key := Vector2i(x, z)
					if not _footprint_buckets.has(key):
						_footprint_buckets[key] = []
					_footprint_buckets[key].append(index)

func _excluded(point: Vector2) -> bool:
	for index: int in _footprint_buckets.get(_cell(point), []):
		var footprint: Array = _exclusions[index]
		var bounds: Rect2 = footprint[0]
		if bounds.has_point(point) and Geometry2D.is_point_in_polygon(point, footprint[1]):
			return true
	return false

func _prepare_stream_material() -> void:
	_stream_material = ShaderMaterial.new()
	_stream_material.shader = STREAM_SHADER
	for parameter: Dictionary in grass_material.shader.get_shader_uniform_list():
		var name: StringName = parameter["name"]
		_stream_material.set_shader_parameter(name, grass_material.get_shader_parameter(name))

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE))

func _ray_ground(camera: Camera3D, screen: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.00001:
		return Vector2(origin.x, origin.z)
	var point := origin + direction * (-origin.y / direction.y)
	return Vector2(point.x, point.z)

func _ground_polygon(camera: Camera3D) -> PackedVector2Array:
	var size := get_viewport().get_visible_rect().size
	var points := PackedVector2Array()
	for screen: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		points.append(_ray_ground(camera, screen))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[-1]):
		hull.resize(hull.size() - 1)
	return hull

func _offset(polygon: PackedVector2Array, distance: float) -> PackedVector2Array:
	var polygons := Geometry2D.offset_polygon(polygon, distance, Geometry2D.JOIN_MITER)
	return polygons[0] if not polygons.is_empty() else polygon

func _bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	return bounds

func _tile_intersects(key: Vector2i, polygon: PackedVector2Array) -> bool:
	var origin := Vector2(key) * CHUNK_SIZE
	var square := PackedVector2Array([origin, origin + Vector2(CHUNK_SIZE, 0),
		origin + Vector2(CHUNK_SIZE, CHUNK_SIZE), origin + Vector2(0, CHUNK_SIZE)])
	return not Geometry2D.intersect_polygons(square, polygon).is_empty()

func _process(delta: float) -> void:
	_elapsed += delta
	frame_candidates = 0
	frame_uploads = 0
	work_usec = 0
	upload_usec = 0
	last_refresh_usec = 0
	var current := get_viewport().get_camera_3d()
	if current == null:
		return
	var size := get_viewport().get_visible_rect().size
	_focus = _ray_ground(current, size * 0.5)
	var cell := _cell(_focus)
	var bucket := ceili(current.size / 4.0)
	if current != _camera or cell != _focus_cell or bucket != _zoom_bucket 			or current.global_basis != _camera_basis or size != _viewport_size:
		_camera = current
		_focus_cell = cell
		_zoom_bucket = bucket
		_camera_basis = current.global_basis
		_viewport_size = size
		_refresh_desired()
	_stream_material.set_shader_parameter("stream_focus", _focus)
	_stream_material.set_shader_parameter("stream_time", _elapsed)
	var polygon := _ground_polygon(current)
	for edge: int in 4:
		_stream_material.set_shader_parameter("view_edge_%d" % edge,
			Vector4(polygon[edge].x, polygon[edge].y, polygon[(edge + 1) % 4].x, polygon[(edge + 1) % 4].y))
	_step_generation()
	peak_instances = maxi(peak_instances, _resident_count + _reserved_count)
	peak_chunks = maxi(peak_chunks, _chunks.size())
	peak_queue = maxi(peak_queue, _queue.size())

func _refresh_desired() -> void:
	var started := Time.get_ticks_usec()
	_revision += 1
	# Snap storage coverage to the cell centre: current focus stays within 11.32m.
	_build_focus = (Vector2(_focus_cell) + Vector2(0.5, 0.5)) * CHUNK_SIZE
	_visible = _ground_polygon(_camera)
	var scale := (float(_zoom_bucket) * 4.0) / _camera.size
	for index: int in _visible.size():
		_visible[index] = _build_focus + (_visible[index] - _focus) * scale
	_desired_polygon = _offset(_visible, 32.0)
	_mid_polygon = _offset(_visible, 24.0)
	var bounds := _bounds(_desired_polygon).intersection(WORLD_ROOTS)
	var keys: Array[Vector2i] = []
	var first := _cell(bounds.position)
	var last := _cell(bounds.end)
	for z: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var key := Vector2i(x, z)
			if _tile_intersects(key, _desired_polygon):
				keys.append(key)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _priority(a) < _priority(b))
	if keys.size() > ACTIVE_CAP:
		keys.resize(ACTIVE_CAP)
	_desired.clear()
	_queue.clear()
	_cancel_job()
	for key: Vector2i in keys:
		var rect := Rect2(Vector2(key) * CHUNK_SIZE, Vector2.ONE * CHUNK_SIZE)
		var closest := _build_focus.clamp(rect.position, rect.end)
		var dense := closest.distance_to(_build_focus) <= 80.0
		var mid := _tile_intersects(key, _mid_polygon)
		_desired[key] = {"dense": dense, "mid": mid}
		if _chunks.has(key):
			var record: Dictionary = _chunks[key]
			record["node"].visible = true
			record["used"] = _revision
			# Extra coverage is fixed per tile. Upgrade only missing tiers.
			if (dense and (not record["dense"] or (not record["dense_full"] and record["focus"] != _build_focus))) \
					or (mid and (not record["mid"] or (not record["mid_full"] and record["polygon"] != _mid_polygon))):
				_queue.append(key)
		else:
			_queue.append(key)
	for key: Vector2i in _chunks:
		if not _desired.has(key):
			_chunks[key]["node"].visible = false
	_trim_cache(CACHE_CAP)
	last_refresh_usec = Time.get_ticks_usec() - started

func _priority(key: Vector2i) -> float:
	var centre := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK_SIZE
	return centre.distance_squared_to(_build_focus) + (0.0 if Geometry2D.is_point_in_polygon(centre, _visible) else 1000000.0)

func _trim_cache(limit: int) -> void:
	var cached: Array[Vector2i] = []
	for key: Vector2i in _chunks:
		if not _desired.has(key):
			cached.append(key)
	cached.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if int(_chunks[a]["used"]) != int(_chunks[b]["used"]):
			return int(_chunks[a]["used"]) < int(_chunks[b]["used"])
		return ((Vector2(a) + Vector2(0.5, 0.5)) * CHUNK_SIZE).distance_squared_to(_focus) \
			> ((Vector2(b) + Vector2(0.5, 0.5)) * CHUNK_SIZE).distance_squared_to(_focus))
	while cached.size() > limit:
		_evict(cached.pop_front())

func _evict(key: Vector2i) -> void:
	_resident_count -= int(_chunks[key]["count"])
	_chunks[key]["node"].queue_free()
	_chunks.erase(key)

func _cancel_job() -> void:
	_reserved_count = 0
	_job.clear()

func _hash_cell(x: int, z: int, salt: int = 0) -> int:
	var mixed := (x * 73856093) ^ (z * 19349663) ^ (SEED * 83492791) ^ salt
	mixed = ((mixed ^ (mixed >> 13)) * 1274126177) & 0x7fffffff
	return mixed ^ (mixed >> 16)

func _step_generation() -> void:
	var started := Time.get_ticks_usec()
	var deadline := started + WORK_USEC
	while frame_candidates < CANDIDATE_CAP and Time.get_ticks_usec() < deadline:
		if _job.is_empty():
			if _queue.is_empty():
				break
			var key: Vector2i = _queue.pop_front()
			if not _desired.has(key):
				continue
			var spec: Dictionary = _desired[key]
			var old: Dictionary = _chunks.get(key, {})
			_job = {"key": key, "cursor": 0, "points": PackedVector2Array(),
				"layers": PackedByteArray(), "ids": PackedByteArray(), "ages": PackedFloat32Array(), "cells": PackedInt32Array(),
				"dense": bool(spec["dense"]) or bool(old.get("dense", false)),
				"mid": bool(spec["mid"]) or bool(old.get("mid", false)),
				"born": _elapsed, "old": old, "focus": _build_focus, "polygon": _mid_polygon}
			_job["stride"] = 1 if _job["dense"] else (2 if _job["mid"] else 4)
			_job["columns"] = CELLS / int(_job["stride"])
		var cursor: int = _job["cursor"]
		var key: Vector2i = _job["key"]
		var columns: int = _job["columns"]
		var stride: int = _job["stride"]
		var x := key.x * CELLS + (cursor % columns) * stride
		var z := key.y * CELLS + floori(float(cursor) / float(columns)) * stride
		_job["cursor"] = cursor + 1
		frame_candidates += 1
		total_stream_candidates += 1
		var layer := 0 if x % 4 == 0 and z % 4 == 0 else (1 if x % 2 == 0 and z % 2 == 0 else 2)
		var available: bool = layer == 0 or (layer == 1 and _job["mid"]) or (layer == 2 and _job["dense"])
		if available:
			var point := Vector2((float(x) + 0.5) * GRID_STEP, (float(z) + 0.5) * GRID_STEP)
			point += Vector2(float(_hash_cell(x, z, 17) % 65536) / 65535.0 * 2.0 - 1.0,
				float(_hash_cell(x, z, 29) % 65536) / 65535.0 * 2.0 - 1.0) * JITTER
			var old: Dictionary = _job["old"]
			var full_cell := (z - key.y * CELLS) * CELLS + x - key.x * CELLS
			var old_epoch := float(old["epochs"][full_cell]) if not old.is_empty() else -1.0
			var in_storage := layer == 0 or (layer == 1 and Geometry2D.is_point_in_polygon(point, _job["polygon"])) \
				or (layer == 2 and point.distance_to(_job["focus"]) <= 80.0)
			if in_storage and WORLD_ROOTS.has_point(point) and not FIELD_BOUNDS.has_point(point) and not _excluded(point):
				if _resident_count + _reserved_count >= INSTANCE_CAP:
					_trim_cache(0)
				if _resident_count + _reserved_count < INSTANCE_CAP:
					_job["points"].append(point)
					_job["layers"].append(layer)
					_job["ids"].append(_hash_cell(x, z) % 4)
					_job["ages"].append(old_epoch)
					_job["cells"].append(full_cell)
					_reserved_count += 1
				else:
					# Finite cap: leave this tile pending until scope/cache releases storage.
					_job["cursor"] = cursor
					break
		if int(_job["cursor"]) == columns * columns:
			work_usec = Time.get_ticks_usec() - started
			_publish_one_chunk()
			return
	work_usec = Time.get_ticks_usec() - started

func _publish_one_chunk() -> void:
	var started := Time.get_ticks_usec()
	var key: Vector2i = _job["key"]
	var points: PackedVector2Array = _job["points"]
	var epochs := PackedFloat32Array()
	epochs.resize(CELLS * CELLS)
	epochs.fill(-1.0)
	var buffer := PackedFloat32Array()
	buffer.resize(points.size() * 16)
	var origin := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK_SIZE
	for index: int in points.size():
		var offset := index * 16
		var point := points[index] - origin
		buffer[offset] = 1.0
		buffer[offset + 3] = point.x
		buffer[offset + 5] = 1.0
		buffer[offset + 7] = ROOT_HEIGHT
		buffer[offset + 10] = 1.0
		buffer[offset + 11] = point.y
		buffer[offset + 12] = float(_job["ids"][index])
		buffer[offset + 13] = float(_job["layers"][index])
		var epoch := float(_job["ages"][index])
		if epoch < 0.0:
			epoch = _elapsed
		buffer[offset + 14] = epoch
		epochs[int(_job["cells"][index])] = epoch
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = _quad
	instances.instance_count = points.size()
	instances.custom_aabb = AABB(Vector3(-8.3, -0.5, -8.3), Vector3(16.6, 1.5, 16.6))
	instances.buffer = buffer
	var grass := MultiMeshInstance3D.new()
	grass.name = "Stream_%d_%d" % [key.x, key.y]
	grass.position = Vector3(origin.x, 0, origin.y)
	grass.material_override = _stream_material
	grass.multimesh = instances
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)
	if _chunks.has(key):
		_evict(key)
	_resident_count += points.size()
	var corners := [Vector2(key) * CHUNK_SIZE, (Vector2(key) + Vector2.ONE) * CHUNK_SIZE,
		Vector2(key) * CHUNK_SIZE + Vector2(CHUNK_SIZE, 0), Vector2(key) * CHUNK_SIZE + Vector2(0, CHUNK_SIZE)]
	var dense_full := true
	var mid_full := true
	for corner: Vector2 in corners:
		dense_full = dense_full and corner.distance_to(_job["focus"]) <= 79.8
		mid_full = mid_full and Geometry2D.is_point_in_polygon(corner, _job["polygon"])
	_chunks[key] = {"node": grass, "count": points.size(), "dense": _job["dense"],
		"focus": _job["focus"], "polygon": _job["polygon"], "dense_full": dense_full, "mid_full": mid_full, "epochs": epochs,
		"mid": _job["mid"], "born": _job["born"], "used": _revision}
	_cancel_job()
	frame_uploads = 1
	upload_usec = Time.get_ticks_usec() - started
	tile_count = 1 + _desired.size()

func get_stream_stats() -> Dictionary:
	var cached := 0
	for key: Vector2i in _chunks:
		if not _desired.has(key):
			cached += 1
	return {"resident_instances": _resident_count, "pending_instances": _reserved_count,
		"active_chunks": _chunks.size() - cached, "cached_chunks": cached,
		"desired_chunks": _desired.size(), "queued_jobs": _queue.size(), "generating": not _job.is_empty(),
		"frame_candidates": frame_candidates, "frame_uploads": frame_uploads,
		"work_usec": work_usec, "upload_usec": upload_usec, "refresh_usec": last_refresh_usec,
		"peak_instances": peak_instances, "peak_chunks": peak_chunks, "peak_queue": peak_queue,
		"total_candidates": total_stream_candidates, "focus": _focus, "revision": _revision}
