@tool
extends MeshInstance3D
## 訓練場專用的水平視野輪廓；只讀 Vision，絕不控制 AI 或射擊。

@export var vision: Node
@export var display_enabled := true
@export var tint := Color(1.0, 0.2, 0.2, 0.15)
## 平坦訓練場顯示輪廓的地面高度；水平射線仍從砲塔視線高度發出。
@export var ground_height := 0.04

const RANGE_SHADER := preload("res://src/world/training_ground/vision_range_preview.gdshader")
const ANGULAR_STEP_DEGREES := 0.5
const MAX_RAYS_PER_UPDATE := 2048
const MAX_EDGE_REFINEMENT_DEPTH := 3
const EDGE_OUTSIDE_DEGREES := 0.01
const EDGE_DISTANCE_DELTA := 2.0
const MAX_FRAME_WORK_SAMPLES := 240

var _range_material: ShaderMaterial
var _active_space: PhysicsDirectSpaceState3D
var _active_state: Dictionary = {}
var _active_origin := Vector3.ZERO
var _active_ray_count := 0
var _active_excludes: Array[RID] = []
var _active_collision_mask := 0
var _active_near_range := 0.0
var _active_far_range := 0.0
var _active_fov_degrees := 0.0
var _active_front_angle := 0.0
var _active_half_angle := 0.0
var _active_has_far_field := false

## 公開資料只在完整輪廓、mesh 與 transform 一起交換時更新。
var published_snapshot: Dictionary = {}
var published_outline := PackedVector3Array()
var published_angles := PackedFloat64Array()
var published_distances := PackedFloat64Array()
var completed_updates := 0
var last_update_elapsed_ms := 0.0
var last_update_ray_count := 0
var frame_work_times_ms: Array[float] = []


func _ready() -> void:
	_range_material = ShaderMaterial.new()
	_range_material.shader = RANGE_SHADER
	material_override = _range_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _physics_process(_delta: float) -> void:
	if not display_enabled:
		visible = false
		return
	var started_usec := Time.get_ticks_usec()
	if not _has_valid_inputs():
		_clear_invalid_preview()
		return
	var observer := vision.get("observer") as Node3D
	var state: Dictionary = vision.call("capture_visibility_state") as Dictionary
	if state.is_empty() or not state.has("view_origin"):
		_clear_invalid_preview()
		return
	var world := observer.get_world_3d()
	if world == null or world.direct_space_state == null:
		_clear_invalid_preview()
		return
	var origin: Vector3 = state.get("view_origin", Vector3.ZERO)
	var forward: Vector3 = state.get("forward", Vector3.ZERO)
	forward.y = 0.0
	if origin.is_finite() == false:
		_clear_invalid_preview()
		return
	if not forward.is_zero_approx():
		forward = forward.normalized()
	state["forward"] = forward
	_active_space = world.direct_space_state
	_active_state = state
	_active_origin = origin
	_active_ray_count = 0
	_cache_active_query_values(forward)
	var samples := _base_samples()
	if samples.size() < 3:
		_clear_invalid_preview()
		return
	var refined := _refined_samples(samples)
	if refined.size() < 3:
		_clear_invalid_preview()
		return
	_publish_outline(observer, state, origin, refined, started_usec)
	_active_space = null
	_active_state.clear()
	_active_excludes.clear()


func _has_valid_inputs() -> bool:
	if not is_instance_valid(vision):
		return false
	var observer_value: Variant = vision.get("observer")
	if not is_instance_valid(observer_value):
		return false
	var observer := observer_value as Node3D
	return is_instance_valid(observer) and observer.get_world_3d() != null


func _cache_active_query_values(forward: Vector3) -> void:
	_active_excludes.clear()
	for rid in _active_state.get("exclude", []):
		if rid is RID:
			_active_excludes.append(rid)
	_active_collision_mask = int(_active_state.get("collision_mask", 0))
	_active_near_range = maxf(float(_active_state.get("near_radius", 0.0)), 0.0)
	_active_far_range = maxf(_active_near_range, float(_active_state.get("far_radius", 0.0)))
	_active_fov_degrees = clampf(float(_active_state.get("far_field_of_view_degrees", 0.0)), 0.0, 360.0)
	_active_half_angle = deg_to_rad(_active_fov_degrees * 0.5)
	_active_front_angle = atan2(forward.z, forward.x) if not forward.is_zero_approx() else 0.0
	_active_has_far_field = _active_fov_degrees >= 360.0 or not forward.is_zero_approx()


func _base_samples() -> Array[Dictionary]:
	var angles: Array[float] = []
	var base_count := int(round(360.0 / ANGULAR_STEP_DEGREES))
	for index in base_count:
		angles.append(deg_to_rad(float(index) * ANGULAR_STEP_DEGREES))
	_append_far_field_boundaries(angles)
	var samples: Array[Dictionary] = []
	for angle in _sorted_unique_angles(angles):
		if _active_ray_count >= MAX_RAYS_PER_UPDATE:
			break
		samples.append(_sample_ray(angle))
	return samples


func _append_far_field_boundaries(angles: Array[float]) -> void:
	if _active_fov_degrees >= 360.0 or not _active_has_far_field:
		return
	var outside := deg_to_rad(EDGE_OUTSIDE_DEGREES)
	for boundary in [_active_front_angle - _active_half_angle, _active_front_angle + _active_half_angle]:
		angles.append(wrapf(boundary, 0.0, TAU))
		angles.append(wrapf(boundary - outside, 0.0, TAU))
		angles.append(wrapf(boundary + outside, 0.0, TAU))


func _sorted_unique_angles(angles: Array[float]) -> Array[float]:
	var normalized_angles: Array[float] = []
	for angle in angles:
		normalized_angles.append(wrapf(angle, 0.0, TAU))
	normalized_angles.sort()
	var unique: Array[float] = []
	for normalized in normalized_angles:
		if unique.is_empty() or absf(normalized - unique.back()) > 0.000001:
			unique.append(normalized)
	return unique


func _sample_ray(angle: float) -> Dictionary:
	var range := _range_for_angle(angle)
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	var endpoint := _active_origin + direction * range
	var hit_state := false
	if range > 0.0 and _active_space != null:
		var query := PhysicsRayQueryParameters3D.create(_active_origin, endpoint,
			_active_collision_mask, _active_excludes)
		var hit := _active_space.intersect_ray(query)
		_active_ray_count += 1
		if not hit.is_empty():
			hit_state = true
			endpoint = hit.get("position", endpoint) as Vector3
	var horizontal := endpoint - _active_origin
	horizontal.y = 0.0
	return {"angle": angle, "distance": horizontal.length(), "hit": hit_state, "endpoint": endpoint}


func _range_for_angle(angle: float) -> float:
	return _active_far_range if _angle_is_in_far_field(angle) else _active_near_range


func _angle_is_in_far_field(angle: float) -> bool:
	if _active_fov_degrees >= 360.0:
		return true
	if not _active_has_far_field:
		return false
	var difference := absf(wrapf(angle - _active_front_angle + PI, 0.0, TAU) - PI)
	return difference <= _active_half_angle + 0.000001


func _refined_samples(base_samples: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in base_samples.size():
		var left := base_samples[index]
		var right := base_samples[(index + 1) % base_samples.size()].duplicate(true)
		if index == base_samples.size() - 1:
			right["angle"] = float(right["angle"]) + TAU
		_append_refined_interval(result, left, right, 0)
	return result


func _append_refined_interval(result: Array[Dictionary], left: Dictionary, right: Dictionary, depth: int) -> void:
	if depth >= MAX_EDGE_REFINEMENT_DEPTH or not _needs_refinement(left, right) \
			or _active_ray_count >= MAX_RAYS_PER_UPDATE:
		result.append(left)
		return
	var midpoint_angle := (float(left["angle"]) + float(right["angle"])) * 0.5
	var midpoint := _sample_ray(wrapf(midpoint_angle, 0.0, TAU))
	midpoint["angle"] = midpoint_angle
	_append_refined_interval(result, left, midpoint, depth + 1)
	_append_refined_interval(result, midpoint, right, depth + 1)


func _needs_refinement(left: Dictionary, right: Dictionary) -> bool:
	return bool(left["hit"]) != bool(right["hit"]) \
		or absf(float(left["distance"]) - float(right["distance"])) > EDGE_DISTANCE_DELTA


func _publish_outline(observer: Node3D, state: Dictionary, origin: Vector3,
		samples: Array[Dictionary], started_usec: int) -> void:
	var outline := PackedVector3Array()
	var angles := PackedFloat64Array()
	var distances := PackedFloat64Array()
	var vertices := PackedVector3Array([Vector3.ZERO])
	var indices := PackedInt32Array()
	for sample in samples:
		var endpoint: Vector3 = sample["endpoint"]
		var ground_endpoint := Vector3(endpoint.x, ground_height, endpoint.z)
		outline.append(ground_endpoint)
		angles.append(wrapf(float(sample["angle"]), 0.0, TAU))
		distances.append(float(sample["distance"]))
		vertices.append(Vector3(endpoint.x - origin.x, 0.0, endpoint.z - origin.z))
	for index in samples.size():
		indices.append(0)
		indices.append(index + 1)
		indices.append((index + 1) % samples.size() + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var new_mesh := ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_range_material.set_shader_parameter("tint", tint)
	## mesh、轉換與公開快照在同一個完整 physics 更新交換。
	mesh = new_mesh
	global_transform = Transform3D(Basis.IDENTITY, Vector3(origin.x, ground_height, origin.z))
	published_snapshot = {
		"observer_instance_id": observer.get_instance_id(),
		"observer_state": state.duplicate(true),
		"origin": Vector3(origin.x, ground_height, origin.z),
	}
	published_outline = outline
	published_angles = angles
	published_distances = distances
	completed_updates += 1
	last_update_elapsed_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
	last_update_ray_count = _active_ray_count
	_append_frame_work_time(last_update_elapsed_ms)
	visible = not outline.is_empty()


func _append_frame_work_time(milliseconds: float) -> void:
	frame_work_times_ms.append(milliseconds)
	if frame_work_times_ms.size() > MAX_FRAME_WORK_SAMPLES:
		frame_work_times_ms.pop_front()


func _clear_invalid_preview() -> void:
	visible = false
	mesh = null
	published_snapshot.clear()
	published_outline = PackedVector3Array()
	published_angles = PackedFloat64Array()
	published_distances = PackedFloat64Array()
	last_update_ray_count = 0
