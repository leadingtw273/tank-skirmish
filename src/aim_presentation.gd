extends Node

const AIM_MAX_DISTANCE := 180.0
const AIM_COLLISION_MASK := 129
const AIM_LINE_RADIUS := 0.04
const AIM_LINE_MIN_LENGTH := 0.05
const AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE := 3.0
const AIM_LINE_ALPHA := 0.7
const AIM_ALIGNED_ANGLE_RADIANS := 0.004363323
const AIM_VERTICAL_BASIS_THRESHOLD := 0.999
var controlled_tank: CharacterBody3D
var projectile_container: Node3D
var actual_aim_line: MeshInstance3D
var mouse_aim_line: MeshInstance3D


func configure(tank: CharacterBody3D, container: Node3D) -> void:
	controlled_tank = tank
	projectile_container = container
	actual_aim_line = _create_aim_line("ActualAimLine", Color.WHITE)
	mouse_aim_line = _create_aim_line("MouseAimLine", Color.RED)


func _ready() -> void:
	process_priority = 10


func _process(_delta: float) -> void:
	if controlled_tank != null and actual_aim_line != null:
		_update_aim_lines(controlled_tank.get_aim_target())


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
	projectile_container.add_child(line)
	return line


func _aim_line_end(origin: Vector3, direction: Vector3) -> Vector3:
	var normalized_direction := direction.normalized()
	if normalized_direction.is_zero_approx():
		return origin
	var fallback_end := origin + normalized_direction * AIM_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(origin, fallback_end, AIM_COLLISION_MASK, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	return controlled_tank.get_world_3d().direct_space_state.intersect_ray(query).get("position", fallback_end) as Vector3


func _set_aim_line_segment(line: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var segment := end - start
	var length := segment.length()
	if length < AIM_LINE_MIN_LENGTH:
		line.visible = false
		return
	var direction := segment / length
	var reference_axis := Vector3.UP if absf(direction.dot(Vector3.UP)) < AIM_VERTICAL_BASIS_THRESHOLD else Vector3.FORWARD
	var x_axis := reference_axis.cross(direction).normalized()
	var z_axis := x_axis.cross(direction).normalized()
	line.global_transform = Transform3D(Basis(x_axis, direction * length, z_axis), start + segment * 0.5)
	line.visible = true


func _set_aim_line_path(line: MeshInstance3D, origin: Vector3, end: Vector3, hidden_distance := AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE) -> void:
	var path := end - origin
	var length := path.length()
	if length <= hidden_distance:
		line.visible = false
		return
	_set_aim_line_segment(line, origin + path / length * hidden_distance, end)


func _tank_aim_line_clearance_distance(origin: Vector3) -> float:
	var collision := controlled_tank.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var box := collision.shape as BoxShape3D if collision != null else null
	if box == null:
		return origin.distance_to(controlled_tank.get_muzzle_position()) + AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE
	var half_size := box.size * 0.5
	var farthest := 0.0
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				farthest = maxf(farthest, origin.distance_to(collision.global_transform * Vector3(half_size.x * x_sign, half_size.y * y_sign, half_size.z * z_sign)))
	return farthest + AIM_LINE_NEAR_TANK_HIDDEN_DISTANCE


func _update_aim_lines(world_target: Vector3) -> void:
	var muzzle_position: Vector3 = controlled_tank.get_muzzle_position()
	var actual_direction: Vector3 = controlled_tank.get_muzzle_direction()
	_set_aim_line_path(actual_aim_line, muzzle_position, _aim_line_end(muzzle_position, actual_direction))
	var target_offset: Vector3 = world_target - muzzle_position
	if target_offset.length_squared() <= 0.001 or actual_direction.angle_to(target_offset.normalized()) <= AIM_ALIGNED_ANGLE_RADIANS:
		mouse_aim_line.visible = false
		return
	var origin: Vector3 = controlled_tank.turret_pivot.global_position
	var offset: Vector3 = world_target - origin
	if offset.length_squared() <= 0.001:
		mouse_aim_line.visible = false
		return
	var direction: Vector3 = offset.normalized()
	_set_aim_line_path(mouse_aim_line, origin, _aim_line_end(origin, direction), _tank_aim_line_clearance_distance(origin))
