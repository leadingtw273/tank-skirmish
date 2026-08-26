extends Node

const AIM_MAX_DISTANCE := 180.0
const AIM_COLLISION_MASK := 129
const AIM_LINE_RADIUS := 0.04
const AIM_LINE_MIN_LENGTH := 0.05
const AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE := 3.0
const AIM_LINE_ALPHA := 0.7
const AIM_ALIGNED_ANGLE_RADIANS := 0.004363323
const AIM_VERTICAL_BASIS_THRESHOLD := 0.999

var controlled_tank: Node3D
var actual_aim_line: MeshInstance3D
var mouse_aim_line: MeshInstance3D
var world_target := Vector3.ZERO


func set_controlled_tank(tank: Node3D) -> void:
	controlled_tank = tank


func initialize_presentation() -> void:
	if actual_aim_line == null:
		actual_aim_line = _create_aim_line("ActualAimLine", Color.WHITE)
		mouse_aim_line = _create_aim_line("MouseAimLine", Color.RED)


func set_world_target(target: Vector3) -> void:
	world_target = target
	_update_aim_lines()


func _create_aim_line(line_name: String, color: Color) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	line.name = line_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = AIM_LINE_RADIUS
	cylinder.bottom_radius = AIM_LINE_RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	line.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material.albedo_color = Color(color.r, color.g, color.b, AIM_LINE_ALPHA)
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	add_child(line)
	return line


func _update_aim_lines() -> void:
	if actual_aim_line == null or mouse_aim_line == null or controlled_tank == null:
		return
	var muzzle_position := controlled_tank.call("muzzle_global_position") as Vector3
	var actual_direction := controlled_tank.call("muzzle_global_direction") as Vector3
	_set_aim_line_path(actual_aim_line, muzzle_position, _aim_line_end(muzzle_position, actual_direction))

	var firing_target_offset := world_target - muzzle_position
	if firing_target_offset.length_squared() <= 0.001:
		mouse_aim_line.visible = false
		return
	var firing_target_direction := firing_target_offset.normalized()
	if actual_direction.angle_to(firing_target_direction) <= AIM_ALIGNED_ANGLE_RADIANS:
		mouse_aim_line.visible = false
		return

	var turret_pivot := controlled_tank.get("turret_pivot") as Node3D
	var mouse_line_origin := turret_pivot.global_position
	var mouse_line_offset := world_target - mouse_line_origin
	if mouse_line_offset.length_squared() <= 0.001:
		mouse_aim_line.visible = false
		return
	var mouse_line_direction := mouse_line_offset.normalized()
	_set_aim_line_path(
		mouse_aim_line,
		mouse_line_origin,
		_aim_line_end(mouse_line_origin, mouse_line_direction),
		_tank_aim_line_clearance_distance(mouse_line_origin),
	)


func _aim_line_end(origin: Vector3, direction: Vector3) -> Vector3:
	var normalized_direction := direction.normalized()
	if normalized_direction.is_zero_approx():
		return origin
	var fallback_end := origin + normalized_direction * AIM_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(origin, fallback_end, AIM_COLLISION_MASK, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	var collision := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	return collision.get("position", fallback_end) as Vector3


func _set_aim_line_segment(line: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var segment := end - start
	var length := segment.length()
	if length < AIM_LINE_MIN_LENGTH:
		line.visible = false
		return
	var direction := segment / length
	var reference_axis := Vector3.UP
	if absf(direction.dot(Vector3.UP)) >= AIM_VERTICAL_BASIS_THRESHOLD:
		reference_axis = Vector3.FORWARD
	var x_axis := reference_axis.cross(direction).normalized()
	var z_axis := x_axis.cross(direction).normalized()
	line.global_transform = Transform3D(Basis(x_axis, direction * length, z_axis), start + segment * 0.5)
	line.visible = true


func _set_aim_line_path(line: MeshInstance3D, origin: Vector3, end: Vector3, hidden_distance := AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE) -> void:
	var path := end - origin
	var length := path.length()
	var safe_hidden_distance := maxf(hidden_distance, 0.0)
	if length <= safe_hidden_distance:
		line.visible = false
		return
	_set_aim_line_segment(line, origin + path / length * safe_hidden_distance, end)


func _tank_aim_line_clearance_distance(origin: Vector3) -> float:
	var tank_collision := controlled_tank.get("tank_collision") as CollisionShape3D
	var collision_box := tank_collision.shape as BoxShape3D
	if collision_box == null:
		return origin.distance_to(controlled_tank.call("muzzle_global_position") as Vector3) + AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE
	var half_size := collision_box.size * 0.5
	var farthest_corner_distance := 0.0
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var corner := tank_collision.global_transform * Vector3(half_size.x * x_sign, half_size.y * y_sign, half_size.z * z_sign)
				farthest_corner_distance = maxf(farthest_corner_distance, origin.distance_to(corner))
	return farthest_corner_distance + AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE
