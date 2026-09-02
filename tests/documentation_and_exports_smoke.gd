extends SceneTree

const SCRIPT_REQUIREMENTS := {
	"res://src/player/aim_presentation.gd": ["func set_controlled_tank", "func initialize_presentation", "func set_world_target"],
	"res://src/camera/camera_controller.gd": ["func set_follow_target", "func play_shot_recoil", "func calculate_look_ahead_offset"],
	"res://src/combat/combat_runtime.gd": ["func register_shot_source", "func unregister_shot_source"],
	"res://src/combat/impact_event.gd": ["var shot_event", "var collider", "var position", "var normal"],
	"res://src/combat/projectile.gd": ["signal hit_detected", "signal impact_detected", "func initialize"],
	"res://src/combat/shot_event.gd": ["var muzzle_transform", "var direction", "var shooter_rid"],
	"res://src/actors/tank/tank_controller.gd": ["signal shot_fired", "signal shot_event_fired", "func get_actual_linear_speed", "func get_actual_angular_speed", "func set_movement_input", "func set_turn_input", "func aim_turret_at", "func aim_gun_pitch_at_target", "func muzzle_global_position", "func muzzle_global_direction", "func request_fire"],
	"res://src/actors/tank/track_contact_effects/track_contact_effects.gd": ["signal track_contact"],
	"res://src/vfx/surface_effects/surface_effects.gd": ["func consume_track_contact", "func get_emitter"],
}

const DEFAULT_REQUIREMENTS := {
	"res://src/player/aim_presentation.gd": ["@export var max_aim_distance := 180.0", "@export_flags_3d_physics var aim_collision_mask := 129", "@export var aim_cursor_texture: Texture2D = preload(\"res://assets/KenneyCrosshair/PNG/Light/crosshair-014.png\")", "@export var aim_cursor_hotspot := Vector2(32.0, 32.0)", "@export_range(0.1, 2.0, 0.05) var aim_cursor_scale := 2.0 / 3.0", "@export var aim_line_radius := 0.04", "@export var aim_line_min_length := 0.05", "@export var aim_line_near_tank_hidden_distance := 3.0", "@export_range(0.0, 1.0, 0.05) var aim_line_alpha := 0.7", "@export var aim_aligned_angle_radians := 0.004363323"],
	"res://src/camera/camera_controller.gd": ["@export_range(0.0, 1.0, 0.01) var look_ahead_dead_zone := 0.18", "@export var look_ahead_smoothing_speed := 8.0", "@export var zoom_step := 5.0", "@export var min_zoom_size := 25.0", "@export var max_zoom_size := 100.0", "@export_range(0.0, 5.0, 0.01) var fire_shake_kick_distance := 0.25", "@export_range(0.01, 2.0, 0.01) var fire_shake_duration_seconds := 0.2"],
	"res://src/combat/combat_runtime.gd": ["@export_range(0.1, 10.0, 0.05) var impact_vfx_scale := 1.0", "@export var impact_vfx_lifetime_seconds := 1.3", "@export var impact_vfx_surface_offset := 0.05"],
	"res://src/combat/projectile.gd": ["@export var speed := 120.0", "@export var max_distance := 180.0", "@export_flags_3d_physics var collision_mask := 129"],
	"res://src/actors/tank/tank_controller.gd": ["@export var movement_speed := 15.0", "@export var reverse_movement_speed := 5.0", "@export var turn_speed := 0.8", "@export_range(0.0, 1.0, 0.05) var turning_movement_speed_ratio := 0.5", "@export_range(0.0, 1.0, 0.05) var firing_movement_speed_loss_ratio := 0.25", "@export var tank_mass_tonnes := 60.0", "@export var engine_horsepower := 1500.0", "@export var brake_force_kilonewtons := 240.0", "@export var turn_response := 0.4", "@export var tread_animation_blend_seconds := 0.12", "@export_range(0.01, 100.0, 0.01) var tread_animation_reference_speed := 15.0", "@export_range(0.0, 4.0, 0.01) var tread_animation_speed_multiplier := 1.0", "@export var turret_turn_speed := 1.777778", "@export var gun_pitch_speed := 1.2", "@export_range(0.0, 45.0, 0.5) var gun_max_elevation_degrees := 20.0", "@export_range(0.0, 45.0, 0.5) var gun_max_depression_degrees := 8.0", "@export var visual_recoil_distance := 0.36", "@export var visual_recoil_kick_seconds := 0.04", "@export var visual_recoil_return_seconds := 0.18", "@export var max_camera_look_ahead_distance := 30.0", "@export var muzzle_flash_lifetime_seconds := 0.25", "@export var muzzle_flash_scale := 4.0"],
	"res://src/actors/tank/track_contact_effects/track_contact_effects.gd": ["@export var source_id: StringName = &\"player_tank\"", "@export_flags_3d_physics var ground_collision_mask := 128", "@export_range(0.0, 3.0, 0.01) var ray_start_height := 0.5", "@export_range(0.05, 10.0, 0.01) var ray_length := 1.5", "@export_range(0.01, 100.0, 0.01) var linear_speed_for_full_intensity := 15.0", "@export_range(0.01, 10.0, 0.01) var angular_speed_for_full_intensity := 0.8"],
	"res://src/vfx/surface_effects/surface_effects.gd": ["@export_range(0.1, 4.0, 0.05) var tread_dust_scale := 0.85", "@export_range(0.1, 1.0, 0.01) var tread_dust_initial_size_ratio := 0.65", "@export_range(0.1, 5.0, 0.05) var tread_dust_lifetime_seconds := 1.2", "@export_range(2, 128, 1) var tread_dust_emission_amount := 28", "@export_range(0.01, 5.0, 0.01) var tread_dust_activation_speed := 0.15", "@export_range(0.0, 1.0, 0.01) var surface_normal_offset := 0.05"],
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
