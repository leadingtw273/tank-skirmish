extends RefCounted

# Bake height into mesh/collision geometry; keep node scale suitable for physics.
const HEIGHT_FACTOR := 0.25
const PLACEMENT_LIFT := 0.03 * HEIGHT_FACTOR
const HEIGHT_META := &"road_height_factor"
const ROAD_MODELS := {
	"base": [
		"Road1",
		"Road10_90angle_Corner",
		"Road11_Y_Splitter",
		"Road11_Y_Splitter_45",
		"Road12_Diagonal_Splitter_L",
		"Road12_Diagonal_Splitter_R",
		"Road1_Curve1",
		"Road1_Curve2",
		"Road1_Curve3",
		"Road1_Curve4",
		"Road2_T",
		"Road2_X",
		"Road6_End"
	],
	"bridges": [
		"Bridge1",
		"Bridge1Ramp1",
		"Bridge1Ramp2",
		"Bridge3",
		"Bridge3Start",
		"Bridge4",
		"Bridge6",
		"Road1Ramp1",
		"Road1Ramp2"
	],
	"custom": [
		"Road11_Y_Splitter_45_Custom",
		"Road12_Diagonal_Splitter_L_Custom",
		"Road12_Diagonal_Splitter_R_Custom",
		"Road1_Curve2_Custom45"
	],
	"dirt": [
		"Dirt_Road_1_6m",
		"Dirt_Road_1_Curve_1",
		"Dirt_Road_1_Hill_1"
	],
	"highway": [
		"Gravel_Segment_1",
		"Gravel_Segment_2",
		"Highway_1_Intersection_Segment_1_A",
		"Highway_1_Intersection_Segment_1_B",
		"Highway_1_Intersection_Segment_1_C",
		"Highway_1_Intersection_Segment_2_A",
		"Highway_1_Intersection_Segment_2_B",
		"Highway_1_Intersection_Segment_2_C",
		"Highway_1_Intersection_Segment_2_D",
		"Highway_1_Intersection_Segment_2_E",
		"Highway_1_Intersection_Segment_2_F",
		"Highway_1_Intersection_Segment_2_G",
		"Highway_1_LaneSplitter_1_Fence",
		"Highway_1_LaneSplitter_1_Fenceless",
		"Highway_1_LaneSplitter_1_Median_Fence",
		"Highway_1_LaneSplitter_1_Median_Fenceless",
		"Highway_1_LaneSplitter_Offramp_1_Fence",
		"Highway_1_LaneSplitter_Offramp_1_Fenceless",
		"Highway_1_Segment_Half_Shoulder_1_A_R",
		"Highway_1_Segment_Half_Shoulder_1_B_R",
		"Highway_1_Segment_Median_1",
		"Highway_1_Segment_Median_1_Ascend",
		"Highway_1_Segment_Median_1_Ascend_Fence",
		"Highway_1_Segment_Median_1_Descend",
		"Highway_1_Segment_Median_1_Descend_Fence",
		"Highway_1_Segment_Median_1_Elevation",
		"Highway_1_Segment_Median_1_Elevation_Fence",
		"Highway_1_Segment_Median_1_R",
		"Highway_1_Segment_Middle_Half_L",
		"Highway_1_Segment_Middle_Half_R",
		"Highway_1_Segment_Middle_Half_Zebra_1",
		"Highway_1_Segment_Middle_L",
		"Highway_1_Segment_Middle_L_Blank",
		"Highway_1_Segment_Middle_L_Blank_Full_Line_White_Mid",
		"Highway_1_Segment_Middle_L_Full_Line_White_Side",
		"Highway_1_Segment_Middle_R",
		"Highway_1_Segment_Middle_R_Ascend",
		"Highway_1_Segment_Middle_R_Blank",
		"Highway_1_Segment_Middle_R_Descend",
		"Highway_1_Segment_Middle_R_Elevation",
		"Highway_1_Segment_Middle_R_Full_Line_White",
		"Highway_1_Segment_Shoulder_1_L",
		"Highway_1_Segment_Shoulder_1_R",
		"Highway_1_Segment_Shoulder_1_R_Ascend",
		"Highway_1_Segment_Shoulder_1_R_Ascend_Fence",
		"Highway_1_Segment_Shoulder_1_R_Descend",
		"Highway_1_Segment_Shoulder_1_R_Descend_Fence",
		"Highway_1_Segment_Shoulder_1_R_Elevation",
		"Highway_1_Segment_Shoulder_1_R_Elevation_Fence",
		"Highway_1_Segment_SmallShoulder_1",
		"Highway_1_Segment_SmallShoulder_1_Ascend",
		"Highway_1_Segment_SmallShoulder_1_Ascend_Fence",
		"Highway_1_Segment_SmallShoulder_1_Descend",
		"Highway_1_Segment_SmallShoulder_1_Descend_Fence",
		"Highway_1_Segment_SmallShoulder_1_Elevation",
		"Highway_1_Segment_SmallShoulder_1_Elevation_Fence",
		"Highway_1_TwoLane_Curve_Big_Inner_L",
		"Highway_1_TwoLane_Curve_Big_Inner_L_Fence",
		"Highway_1_TwoLane_Curve_Big_Inner_R",
		"Highway_1_TwoLane_Curve_Big_Inner_R_Fence",
		"Highway_1_TwoLane_Curve_Big_Outer_L",
		"Highway_1_TwoLane_Curve_Big_Outer_L_Fence",
		"Highway_1_TwoLane_Curve_Big_Outer_R",
		"Highway_1_TwoLane_Curve_Big_Outer_R_Fence"
	],
	"ovaltrack": [
		"Track_1_Corner_L",
		"Track_1_Corner_R",
		"Track_1_StraightSegment_1_L",
		"Track_1_StraightSegment_2_L",
		"Track_1_StraightSegment_3_Door_L",
		"Track_1_StraightSegment_Angeled_1_L",
		"Track_1_StraightSegment_Angeled_2_L"
	],
	"parking": [
		"Road1",
		"Road10_90angle_Corner",
		"Road1_Curve1",
		"Road1_Curve2",
		"Road1_Curve3",
		"Road1_Curve4",
		"Road1_Parking1",
		"Road1_Parking1_Open",
		"Road1_Parking2",
		"Road2_T",
		"Road2_T_Parking_Entrance",
		"Road2_T_Parking_Entrance_Open",
		"Road2_X",
		"Road3_Crossing",
		"Road4_Shoulder_Extender",
		"Road4_Shoulder_Narrower",
		"Road5_Shoulder1",
		"Road5_Shoulder2",
		"Road5_Shoulder3",
		"Road6_CornerL",
		"Road6_CornerR",
		"Road6_End",
		"Road7",
		"Road8",
		"Road9",
		"ramp1"
	],
	"racetrack": [
		"Racetrack1_Blue_Default",
		"Racetrack1_Blue_Default_FinishLine1",
		"Racetrack1_Blue_Default_FinishLine2",
		"Racetrack1_Blue_Default_Fork_Curb_Left",
		"Racetrack1_Blue_Default_Fork_Curb_Right",
		"Racetrack1_Blue_Default_Fork_Left",
		"Racetrack1_Blue_Default_Fork_Right",
		"Racetrack1_Blue_Poistions",
		"Racetrack1_Default",
		"Racetrack1_Default_FinishLine1",
		"Racetrack1_Default_FinishLine2",
		"Racetrack1_Default_Fork_Curb_Left",
		"Racetrack1_Default_Fork_Curb_Right",
		"Racetrack1_Default_Fork_Left",
		"Racetrack1_Default_Fork_Right",
		"Racetrack1_Gray_Default",
		"Racetrack1_Jump",
		"Racetrack1_Poistions",
		"Racetrack1_RedGray_Default",
		"Racetrack1_RedGray_PitLane_Boxes",
		"Racetrack1_RedWhiteBlue_CurbLeft",
		"Racetrack1_RedWhiteBlue_CurbRight",
		"Racetrack1_RedWhiteBlue_Curbs",
		"Racetrack1_RedWhiteBlue_Curbs_Curve_45_Long_Left",
		"Racetrack1_RedWhiteBlue_Curbs_Curve_45_Long_Right",
		"Racetrack1_RedWhiteBlue_Curbs_Curve_90_Big_Left",
		"Racetrack1_RedWhiteBlue_Curbs_Curve_90_Big_Right",
		"Racetrack1_RedWhiteBlue_Curbs_Curve_90_Small_Left",
		"Racetrack1_RedWhiteBlue_Curbs_Curve_90_Small_Right",
		"Racetrack1_RedWhiteBlue_RoadAdapter",
		"Racetrack1_RedWhite_CurbLeft",
		"Racetrack1_RedWhite_CurbRight",
		"Racetrack1_RedWhite_Curbs",
		"Racetrack1_RedWhite_Curbs_Curve_45_Long_Left",
		"Racetrack1_RedWhite_Curbs_Curve_45_Long_Right",
		"Racetrack1_RedWhite_Curbs_Curve_90_Big_Left",
		"Racetrack1_RedWhite_Curbs_Curve_90_Big_Right",
		"Racetrack1_RedWhite_Curbs_Curve_90_Small_Left",
		"Racetrack1_RedWhite_Curbs_Curve_90_Small_Right",
		"Racetrack1_RedWhite_Curbs_Overpass",
		"Racetrack1_RedWhite_RoadAdapter",
		"Racetrack1_YellowBlue_CurbLeft",
		"Racetrack1_YellowBlue_CurbRight",
		"Racetrack1_YellowBlue_Curbs_Curve_45_Long_Left",
		"Racetrack1_YellowBlue_Curbs_Curve_45_Long_Right",
		"Racetrack1_YellowBlue_Curbs_Curve_90_Big_Left",
		"Racetrack1_YellowBlue_Curbs_Curve_90_Big_Right",
		"Racetrack1_YellowBlue_Curbs_Curve_90_Small_Left",
		"Racetrack1_YellowBlue_Curbs_Curve_90_Small_Right",
		"Racetrack1_YellowBlue_Default_Fork_Curb_Left",
		"Racetrack1_YellowBlue_RoadAdapter",
		"Racetrack1_Yellowblue_Default_Fork_Curb_Right",
		"Racetrack1_YelowBlue_Curbs"
	]
}

var failures: Array[String] = []
var _height_factor := HEIGHT_FACTOR
var _height_stats := {"topology_valid": true, "mesh_vertices": 0, "collision_vertices": 0, "mesh_surfaces": 0, "lod_levels": 0, "shadow_meshes": 0, "max_shadow_xz_error": 0.0, "max_shadow_y_error": 0.0, "max_collision_xz_error": 0.0, "max_collision_y_error": 0.0, "max_visual_xz_error": 0.0, "max_visual_y_error": 0.0, "max_xz_error": 0.0, "max_y_error": 0.0, "before_y_min": INF, "before_y_max": -INF, "after_y_min": INF, "after_y_max": -INF}

static func is_road_model(pack: String, model_id: String) -> bool:
	return ROAD_MODELS.has(pack) and model_id in ROAD_MODELS[pack]

func mesh_at_height(source: ArrayMesh, transform_: Transform3D, source_factor: float = 1.0) -> ArrayMesh:
	_height_factor = HEIGHT_FACTOR / source_factor
	if is_equal_approx(_height_factor, 1.0):
		return source
	return _clone_mesh(source, transform_, false)

func is_valid() -> bool:
	return failures.is_empty() and bool(_height_stats.topology_valid)

func bake_module(module: Node3D) -> bool:
	var source_factor := float(module.get_meta(HEIGHT_META, 1.0))
	_height_factor = HEIGHT_FACTOR / source_factor
	if is_equal_approx(_height_factor, 1.0):
		return true
	_bake_node(module, Transform3D.IDENTITY, Transform3D.IDENTITY)
	if not is_valid():
		return false
	module.set_meta(HEIGHT_META, HEIGHT_FACTOR)
	return true

func _bake_node(node: Node, transform_: Transform3D, parent_transform: Transform3D) -> void:
	if node is MeshInstance3D and node.mesh != null:
		if node.mesh is ArrayMesh:
			node.mesh = _clone_mesh(node.mesh, transform_, false)
		else:
			failures.append("Unsupported road mesh: " + node.mesh.get_class())
	if node is CollisionShape3D and node.shape != null:
		if node.shape is ConcavePolygonShape3D:
			var before := node.shape as ConcavePolygonShape3D
			var after := before.duplicate(false) as ConcavePolygonShape3D
			after.data = _deform_points(before.data, transform_, true)
			_validate_points(before.data, after.data, transform_, false, true)
			node.shape = after
		else:
			failures.append("Unsupported road collision shape: " + node.shape.get_class())
	if node is Marker3D:
		var position_ := transform_.origin
		position_.y *= _height_factor
		node.position = parent_transform.affine_inverse() * position_
	for child in node.get_children():
		if child is Node3D:
			_bake_node(child, transform_ * child.transform, transform_)

func _decode_shadow_vertices(raw: Dictionary) -> PackedVector3Array:
	var bytes: PackedByteArray = raw.get("vertex_data", PackedByteArray())
	var count := int(raw.get("vertex_count", 0))
	var vertices := PackedVector3Array()
	if count == 0 or bytes.size() != count * 8 or int(raw.get("format", 0)) & ((1 << Mesh.ARRAY_MAX) - 1) != (Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_INDEX):
		failures.append("Unsupported packed road shadow vertex format.")
		return vertices
	var bounds: AABB = raw.aabb
	vertices.resize(count)
	for index in count:
		var offset := index * 8
		vertices[index] = bounds.position + Vector3(float(bytes.decode_u16(offset)) / 65535.0 * bounds.size.x, float(bytes.decode_u16(offset+2)) / 65535.0 * bounds.size.y, float(bytes.decode_u16(offset+4)) / 65535.0 * bounds.size.z)
	return vertices


func _deform_points(points: PackedVector3Array, transform: Transform3D, collision: bool) -> PackedVector3Array:
	var output := points.duplicate()
	var inverse := transform.affine_inverse()
	for index in points.size():
		var before := transform * points[index]
		var after := before
		if _height_factor != 1.0:
			after.y *= _height_factor
			output[index] = inverse * after
	if collision: _height_stats.collision_vertices = int(_height_stats.collision_vertices) + points.size()
	else: _height_stats.mesh_vertices = int(_height_stats.mesh_vertices) + points.size()
	return output


func _validate_points(before_points: PackedVector3Array, after_points: PackedVector3Array, transform: Transform3D, shadow: bool, collision: bool = false) -> void:
	if before_points.size() != after_points.size():
		_height_stats.topology_valid = false
		failures.append("Road vertex count changed after resource readback.")
		return
	for index in before_points.size():
		var before := transform * before_points[index]
		var after := transform * after_points[index]
		var xz_error := maxf(absf(after.x-before.x), absf(after.z-before.z))
		var y_error := absf(after.y-before.y*_height_factor)
		if not is_finite(xz_error) or not is_finite(y_error):
			_height_stats.topology_valid = false
			failures.append("Non-finite road vertex after resource readback.")
			return
		if shadow:
			_height_stats.max_shadow_xz_error = maxf(float(_height_stats.max_shadow_xz_error), xz_error)
			_height_stats.max_shadow_y_error = maxf(float(_height_stats.max_shadow_y_error), y_error)
		elif collision:
			_height_stats.max_collision_xz_error = maxf(float(_height_stats.max_collision_xz_error), xz_error)
			_height_stats.max_collision_y_error = maxf(float(_height_stats.max_collision_y_error), y_error)
		else:
			_height_stats.max_visual_xz_error = maxf(float(_height_stats.max_visual_xz_error), xz_error)
			_height_stats.max_visual_y_error = maxf(float(_height_stats.max_visual_y_error), y_error)
		if not shadow:
			_height_stats.max_xz_error = maxf(float(_height_stats.max_xz_error), xz_error)
			_height_stats.max_y_error = maxf(float(_height_stats.max_y_error), y_error)
		_height_stats.before_y_min = minf(float(_height_stats.before_y_min), before.y)
		_height_stats.before_y_max = maxf(float(_height_stats.before_y_max), before.y)
		_height_stats.after_y_min = minf(float(_height_stats.after_y_min), after.y)
		_height_stats.after_y_max = maxf(float(_height_stats.after_y_max), after.y)


func _clone_mesh(source: ArrayMesh, transform: Transform3D, shadow: bool) -> ArrayMesh:
	if shadow and _height_factor == 1.0:
		var control_clone := source.duplicate(true) as ArrayMesh
		for surface in source.get_surface_count():
			var before_raw := RenderingServer.mesh_get_surface(source.get_rid(), surface)
			var after_raw := RenderingServer.mesh_get_surface(control_clone.get_rid(), surface)
			var before_points: PackedVector3Array = _decode_shadow_vertices(before_raw)
			var after_points: PackedVector3Array = _decode_shadow_vertices(after_raw)
			_validate_points(before_points, after_points, transform, true)
		return control_clone
	if source.get_blend_shape_count() != 0:
		failures.append("Road mesh blend shapes cannot be preserved: " + source.resource_path)
		return source.duplicate(true) as ArrayMesh
	var clone := ArrayMesh.new()
	clone.resource_name = source.resource_name
	clone.custom_aabb = source.custom_aabb
	var basis := transform.basis
	var vertical := Basis(Vector3.RIGHT, Vector3.UP * _height_factor, Vector3.BACK)
	var deformation := basis.inverse() * vertical * basis
	var normal_matrix := deformation.inverse().transposed()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface).duplicate(true)
		var raw := RenderingServer.mesh_get_surface(source.get_rid(), surface)
		var original_vertices: PackedVector3Array = _decode_shadow_vertices(raw) if arrays[Mesh.ARRAY_VERTEX] == null else arrays[Mesh.ARRAY_VERTEX]
		if original_vertices.is_empty():
			_height_stats.topology_valid = false
			return clone
		arrays[Mesh.ARRAY_VERTEX] = _deform_points(original_vertices, transform, false)
		if _height_factor != 1.0 and arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for index in normals.size(): normals[index] = (normal_matrix * normals[index]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		if _height_factor != 1.0 and arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			var normals_for_tangent: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for index in tangents.size() / 4:
				var tangent := (deformation * Vector3(tangents[index*4], tangents[index*4+1], tangents[index*4+2])).normalized()
				if index < normals_for_tangent.size(): tangent = (tangent - normals_for_tangent[index] * tangent.dot(normals_for_tangent[index])).normalized()
				tangents[index*4] = tangent.x
				tangents[index*4+1] = tangent.y
				tangents[index*4+2] = tangent.z
			arrays[Mesh.ARRAY_TANGENT] = tangents
		var main_indices: PackedInt32Array = PackedInt32Array() if arrays[Mesh.ARRAY_INDEX] == null else arrays[Mesh.ARRAY_INDEX]
		var main_bytes: PackedByteArray = raw.get("index_data", PackedByteArray())
		var main_count := int(raw.get("index_count", 0))
		var width := 0
		if main_count > 0 and main_bytes.size() % main_count == 0:
			width = main_bytes.size() / main_count
		if main_count == 0 and main_bytes.is_empty():
			width = 0
		elif width != 2 and width != 4:
			failures.append("Unsupported road index width at surface %d: %d" % [surface, width])
			_height_stats.topology_valid = false
			return clone
		if width != 0 and _decode_indices(main_bytes, width) != main_indices:
			failures.append("Road main index decode differs from public mesh arrays.")
			_height_stats.topology_valid = false
		var lods := {}
		for lod in raw.get("lods", []):
			if width == 0:
				failures.append("Unindexed road surface unexpectedly has LOD indices.")
				_height_stats.topology_valid = false
				return clone
			var lod_bytes: PackedByteArray = lod.index_data
			if lod_bytes.size() % width != 0:
				failures.append("Road LOD index bytes are misaligned.")
				_height_stats.topology_valid = false
				return clone
			lods[float(lod.edge_length)] = _decode_indices(lod_bytes, width)
			_height_stats.lod_levels = int(_height_stats.lod_levels) + 1
		# Keep decoded coordinates exact: rebuilding compressed AABBs can move XZ.
		var flags := source.surface_get_format(surface) & ~((1 << Mesh.ARRAY_MAX) - 1) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		clone.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], lods, flags)
		var created := clone.get_surface_count() - 1
		clone.surface_set_material(created, source.surface_get_material(surface))
		clone.surface_set_name(created, source.surface_get_name(surface))
		var rebuilt := RenderingServer.mesh_get_surface(clone.get_rid(), created)
		var rebuilt_arrays := clone.surface_get_arrays(created)
		var rebuilt_vertices: PackedVector3Array = _decode_shadow_vertices(rebuilt) if rebuilt_arrays[Mesh.ARRAY_VERTEX] == null else rebuilt_arrays[Mesh.ARRAY_VERTEX]
		_validate_points(original_vertices, rebuilt_vertices, transform, shadow)
		var rebuilt_indices: PackedInt32Array = PackedInt32Array() if rebuilt_arrays[Mesh.ARRAY_INDEX] == null else rebuilt_arrays[Mesh.ARRAY_INDEX]
		if rebuilt_indices != main_indices or int(rebuilt.get("primitive", -1)) != int(raw.get("primitive", -2)):
			_height_stats.topology_valid = false
		var rebuilt_lods: Array = rebuilt.get("lods", [])
		var original_lods: Array = raw.get("lods", [])
		if rebuilt_lods.size() != original_lods.size(): _height_stats.topology_valid = false
		else:
			for level in original_lods.size():
				var before_lod: Dictionary = original_lods[level]
				var after_lod: Dictionary = rebuilt_lods[level]
				var after_bytes: PackedByteArray = after_lod.index_data
				if not is_equal_approx(float(before_lod.edge_length), float(after_lod.edge_length)) or _decode_indices(before_lod.index_data, width) != _decode_indices(after_bytes, width):
					_height_stats.topology_valid = false
		_height_stats.mesh_surfaces = int(_height_stats.mesh_surfaces) + 1
	if source.shadow_mesh != null:
		_height_stats.shadow_meshes = int(_height_stats.shadow_meshes) + 1
		if source.shadow_mesh is ArrayMesh: clone.shadow_mesh = _clone_mesh(source.shadow_mesh as ArrayMesh, transform, true)
		else: failures.append("Unsupported road shadow mesh: " + source.shadow_mesh.get_class())
	return clone


func _decode_indices(bytes: PackedByteArray, width: int) -> PackedInt32Array:
	var values := PackedInt32Array()
	values.resize(bytes.size() / width)
	for index in values.size():
		values[index] = bytes.decode_u16(index*width) if width == 2 else bytes.decode_u32(index*width)
	return values

