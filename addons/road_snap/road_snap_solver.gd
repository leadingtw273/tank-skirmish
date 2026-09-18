@tool
extends RefCounted

## Stateless matching rules. Keeping this separate lets the geometry be tested
## without an EditorPlugin or a 3D viewport.

static func collect_module_endpoints(module: Node) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	if not (module is StaticBody3D) or not module.get_meta("road_module", false):
		return points
	var snap_points := module.get_node_or_null("SnapPoints") as Node3D
	if snap_points == null:
		return points
	_collect_markers(module, snap_points, points)
	return points


static func _collect_markers(module: Node, parent: Node, points: Array[Dictionary]) -> void:
	for child in parent.get_children():
		if child is Marker3D:
			var marker := child as Marker3D
			var outward := -marker.global_transform.basis.z
			if outward.length_squared() > 0.0:
				points.append({"owner": module, "position": marker.global_position, "outward": outward.normalized()})
		_collect_markers(module, child, points)


static func find_nearest_compatible(source_points: Array[Dictionary], target_points: Array[Dictionary], selected_modules: Array, radius_meters: float, angle_tolerance_degrees: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance_squared := radius_meters * radius_meters
	var opposing_dot_limit := -cos(deg_to_rad(angle_tolerance_degrees))
	for source in source_points:
		for target in target_points:
			if target.get("owner") == source.get("owner") or selected_modules.has(target.get("owner")):
				continue
			var source_outward := source.get("outward", Vector3.ZERO) as Vector3
			var target_outward := target.get("outward", Vector3.ZERO) as Vector3
			if source_outward.dot(target_outward) > opposing_dot_limit:
				continue
			var offset := (target.get("position", Vector3.ZERO) as Vector3) - (source.get("position", Vector3.ZERO) as Vector3)
			var distance_squared := offset.length_squared()
			if distance_squared <= best_distance_squared:
				best_distance_squared = distance_squared
				best = {"source": source, "target": target, "translation": offset}
	return best


static func translate_positions(positions: Array[Vector3], translation: Vector3) -> Array[Vector3]:
	var translated: Array[Vector3] = []
	for position in positions:
		translated.append(position + translation)
	return translated
