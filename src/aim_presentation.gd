## Renders the Tank's current firing direction and pending mouse aim as world-space lines.
## It only presents already-resolved aiming data; it does not read player input or rotate the Tank.
extends Node

@export_category("Aim Raycast")
## Furthest raycast and rendered aim-line endpoint in metres.
@export var max_aim_distance := 180.0
## Physics layers that the aim ray can stop against.
@export_flags_3d_physics var aim_collision_mask := 129

@export_category("Aim Lines")
## Radius of each cylindrical aim line in metres.
@export var aim_line_radius := 0.04
## Segments shorter than this length in metres are hidden to avoid degenerate meshes.
@export var aim_line_min_length := 0.05
## Distance in metres hidden near the firing origin so the line clears the Tank.
@export var aim_line_near_tank_hidden_distance := 3.0
## Opacity from 0 (transparent) to 1 (opaque) for both aim lines.
@export_range(0.0, 1.0, 0.05) var aim_line_alpha := 0.7
## Angular difference in radians below which the mouse line is hidden as aligned with the firing line.
@export var aim_aligned_angle_radians := 0.004363323

const AIM_VERTICAL_BASIS_THRESHOLD := 0.999

var controlled_tank: Node3D
var actual_aim_line: MeshInstance3D
var mouse_aim_line: MeshInstance3D
var world_target := Vector3.ZERO


## Registers the Tank whose muzzle and collision shape this presentation follows.
func set_controlled_tank(tank: Node3D) -> void:
	controlled_tank = tank


## Creates the two reusable line meshes once after the presentation has a scene parent.
func initialize_presentation() -> void:
	if actual_aim_line == null:
		actual_aim_line = _create_aim_line("ActualAimLine", Color.WHITE)
		mouse_aim_line = _create_aim_line("MouseAimLine", Color.RED)


## Updates the mouse-selected world target and redraws both aim lines.
func set_world_target(target: Vector3) -> void:
	world_target = target
	_update_aim_lines()


func _create_aim_line(line_name: String, color: Color) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	line.name = line_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = aim_line_radius
	cylinder.bottom_radius = aim_line_radius
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	line.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material.albedo_color = Color(color.r, color.g, color.b, aim_line_alpha)
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
	if actual_direction.angle_to(firing_target_direction) <= aim_aligned_angle_radians:
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
	var fallback_end := origin + normalized_direction * max_aim_distance
	var query := PhysicsRayQueryParameters3D.create(origin, fallback_end, aim_collision_mask, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	var collision := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	return collision.get("position", fallback_end) as Vector3


func _set_aim_line_segment(line: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var segment := end - start
	var length := segment.length()
	if length < aim_line_min_length:
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


func _set_aim_line_path(line: MeshInstance3D, origin: Vector3, end: Vector3, hidden_distance := -1.0) -> void:
	var path := end - origin
	var length := path.length()
	var requested_hidden_distance := aim_line_near_tank_hidden_distance if hidden_distance < 0.0 else hidden_distance
	var safe_hidden_distance := maxf(requested_hidden_distance, 0.0)
	if length <= safe_hidden_distance:
		line.visible = false
		return
	_set_aim_line_segment(line, origin + path / length * safe_hidden_distance, end)


func _tank_aim_line_clearance_distance(origin: Vector3) -> float:
	var tank_collision := controlled_tank.get("tank_collision") as CollisionShape3D
	var collision_box := tank_collision.shape as BoxShape3D
	if collision_box == null:
		return origin.distance_to(controlled_tank.call("muzzle_global_position") as Vector3) + aim_line_near_tank_hidden_distance
	var half_size := collision_box.size * 0.5
	var farthest_corner_distance := 0.0
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var corner := tank_collision.global_transform * Vector3(half_size.x * x_sign, half_size.y * y_sign, half_size.z * z_sign)
				farthest_corner_distance = maxf(farthest_corner_distance, origin.distance_to(corner))
	return farthest_corner_distance + aim_line_near_tank_hidden_distance
