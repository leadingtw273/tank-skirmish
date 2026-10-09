## 出生庭院一次性 BinbunGrass 散布；無逐幀生成或物理物件。
extends Node3D

const FIELD_BOUNDS := Rect2(-116.0, -115.0, 25.0, 24.0)
const GRID_STEP := 0.2
const GRID_COLUMNS := 125
const GRID_ROWS := 120
const JITTER := 0.08
const CLEARANCE := 1.0
const ROOT_HEIGHT := 0.01
const SEED := 117
const GROUND_SHADER := preload("res://src/maps/main_battlefield/spawn_grass_ground.gdshader")

@export var grass_material: ShaderMaterial

var candidate_count := 0
var instance_count := 0
var tile_count := 0
var generation_time_ms := 0
var footprint_count := 0
var _exclusions: Array[Array] = []

func _ready() -> void:
	var started := Time.get_ticks_msec()
	_collect_footprints(get_parent().get_node("Roads"))
	_collect_footprints(get_parent().get_node("Buildings"))
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
	_add_ground_patch(origin)
	generation_time_ms = Time.get_ticks_msec() - started
	print("MAIN_BINBUN_GRASS candidates=%d instances=%d tiles=%d footprints=%d startup_ms=%d" %
		[candidate_count, instance_count, tile_count, footprint_count, generation_time_ms])

func _add_ground_patch(origin: Vector3) -> void:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("noise_texture", grass_material.get_shader_parameter("noise_texture"))
	material.set_shader_parameter("color_gradient", grass_material.get_shader_parameter("color_gradient"))
	var plane := PlaneMesh.new()
	plane.size = FIELD_BOUNDS.size
	plane.material = material
	var patch := MeshInstance3D.new()
	patch.name = "SpawnGroundPatch"
	patch.position = origin + Vector3(0.0, 0.005, 0.0)
	patch.mesh = plane
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)

func _collect_footprints(container: Node) -> void:
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
			if bounds.intersects(FIELD_BOUNDS):
				_exclusions.append([bounds, polygon])
				footprint_count += 1

func _excluded(point: Vector2) -> bool:
	for footprint: Array in _exclusions:
		var bounds: Rect2 = footprint[0]
		if bounds.has_point(point) and Geometry2D.is_point_in_polygon(point, footprint[1]):
			return true
	return false
