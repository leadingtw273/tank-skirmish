extends SceneTree

const SCRIPT_REQUIREMENTS := {
	"res://src/aim_presentation.gd": ["func set_controlled_tank", "func initialize_presentation", "func set_world_target"],
	"res://src/camera_controller.gd": ["func set_follow_target", "func calculate_look_ahead_offset"],
	"res://src/combat_runtime.gd": ["func register_shot_source", "func unregister_shot_source"],
	"res://src/impact_event.gd": ["var shot_event", "var collider", "var position", "var normal"],
	"res://src/projectile.gd": ["signal hit_detected", "signal impact_detected", "func initialize"],
	"res://src/shot_event.gd": ["var muzzle_transform", "var direction", "var shooter_rid"],
	"res://src/tank_controller.gd": ["signal shot_fired", "signal shot_event_fired", "func set_movement_input", "func set_turn_input", "func aim_turret_at", "func aim_gun_pitch_at_target", "func muzzle_global_position", "func muzzle_global_direction", "func request_fire"],
}

const DEFAULT_REQUIREMENTS := {
	"res://src/aim_presentation.gd": ["@export var max_aim_distance := 180.0", "@export_flags_3d_physics var aim_collision_mask := 129", "@export var aim_line_radius := 0.04", "@export var aim_line_min_length := 0.05", "@export var aim_line_near_tank_hidden_distance := 3.0", "@export_range(0.0, 1.0, 0.05) var aim_line_alpha := 0.7", "@export var aim_aligned_angle_radians := 0.004363323"],
	"res://src/camera_controller.gd": ["@export_range(0.0, 1.0, 0.01) var look_ahead_dead_zone := 0.18", "@export var look_ahead_smoothing_speed := 8.0", "@export var zoom_step := 5.0", "@export var min_zoom_size := 25.0", "@export var max_zoom_size := 100.0"],
	"res://src/combat_runtime.gd": ["@export var impact_vfx_lifetime_seconds := 0.9", "@export var impact_vfx_surface_offset := 0.05"],
	"res://src/projectile.gd": ["@export var speed := 120.0", "@export var max_distance := 180.0", "@export_flags_3d_physics var collision_mask := 129"],
	"res://src/tank_controller.gd": ["@export var movement_speed := 15.0", "@export var turn_speed := 0.8", "@export var tread_animation_blend_seconds := 0.12", "@export var turret_turn_speed := 1.777778", "@export var gun_pitch_speed := 1.2", "@export_range(0.0, 45.0, 0.5) var gun_max_elevation_degrees := 20.0", "@export_range(0.0, 45.0, 0.5) var gun_max_depression_degrees := 8.0", "@export var visual_recoil_distance := 0.36", "@export var visual_recoil_kick_seconds := 0.04", "@export var visual_recoil_return_seconds := 0.18", "@export var max_camera_look_ahead_distance := 30.0", "@export var muzzle_flash_lifetime_seconds := 0.25", "@export var muzzle_flash_scale := 4.0"],
}


func _init() -> void:
	if not _validate_documentation() or not _validate_defaults():
		quit(1)
		return
	print("Documentation and export contract smoke validation passed.")
	quit(0)


func _validate_documentation() -> bool:
	for path: String in SCRIPT_REQUIREMENTS:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _fail("Documentation contract could not open %s." % path)
		var lines := file.get_as_text().split("\n")
		if not _has_script_documentation(lines):
			return _fail("%s must begin with a script-level responsibility and non-responsibility comment." % path)
		for declaration: String in SCRIPT_REQUIREMENTS[path]:
			if not _has_documented_declaration(lines, declaration):
				return _fail("%s must document public declaration %s." % [path, declaration])
		for index in range(lines.size()):
			if _is_exported_property_attribute(lines[index]) and not _has_preceding_doc_comment(lines, index):
				return _fail("%s export at line %d requires an Inspector tooltip comment." % [path, index + 1])
	return true


func _has_script_documentation(lines: PackedStringArray) -> bool:
	for index in range(mini(lines.size(), 6)):
		if lines[index].strip_edges().begins_with("##"):
			return true
	return false


func _has_documented_declaration(lines: PackedStringArray, declaration: String) -> bool:
	for index in range(lines.size()):
		if lines[index].strip_edges().begins_with(declaration):
			return _has_preceding_doc_comment(lines, index)
	return false


func _is_exported_property_attribute(line: String) -> bool:
	var attribute := line.strip_edges()
	return attribute.begins_with("@export ") or attribute.begins_with("@export_range") \
		or attribute.begins_with("@export_flags")


func _has_preceding_doc_comment(lines: PackedStringArray, declaration_index: int) -> bool:
	var comment_index := declaration_index - 1
	while comment_index >= 0 and lines[comment_index].strip_edges().is_empty():
		comment_index -= 1
	return comment_index >= 0 and lines[comment_index].strip_edges().begins_with("##")


func _validate_defaults() -> bool:
	for path: String in DEFAULT_REQUIREMENTS:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _fail("Export contract could not open %s." % path)
		var source := file.get_as_text()
		for declaration: String in DEFAULT_REQUIREMENTS[path]:
			if not source.contains(declaration):
				return _fail("%s export default drifted: %s." % [path, declaration])
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
