extends SceneTree

const AimPresentation := preload("res://src/player/aim_presentation.gd")


func _init() -> void:
	var presentation := AimPresentation.new()
	root.add_child(presentation)
	presentation.initialize_presentation()

	var cursor_texture := presentation.aim_cursor_texture as Texture2D
	if cursor_texture == null or cursor_texture.get_width() != 64 or cursor_texture.get_height() != 64:
		_fail("Aim cursor must use the 64x64 Kenney crosshair texture.")
		return
	if presentation.aim_cursor_hotspot != Vector2(32.0, 32.0):
		_fail("Aim cursor hotspot must stay at the center of the 64x64 texture.")
		return
	if not is_equal_approx(presentation.aim_cursor_scale, 2.0 / 3.0):
		_fail("Aim cursor must default to two-thirds of the source texture size.")
		return
	var scaled_texture := presentation.scaled_aim_cursor_texture as Texture2D
	if scaled_texture == null or scaled_texture.get_width() != 43 or scaled_texture.get_height() != 43:
		_fail("Aim cursor runtime texture must resize from 64x64 to 43x43.")
		return
	if presentation.actual_aim_line == null or presentation.mouse_aim_line == null:
		_fail("Initializing the aim cursor must preserve both existing aim lines.")
		return
	if not FileAccess.file_exists("res://assets/KenneyCrosshair/LICENSE.txt"):
		_fail("Kenney crosshair CC0 license must remain vendored with the asset.")
		return

	print("Aim cursor smoke validation passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
