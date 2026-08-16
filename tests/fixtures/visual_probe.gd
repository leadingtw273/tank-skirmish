extends Node2D

const REQUIRED_WIDTH := 1920
const REQUIRED_HEIGHT := 1080
const PROBE_SCENE := "res://tests/fixtures/visual_probe.tscn"

var draw_probe_pattern := true


func _ready() -> void:
	var output_path := ""
	var target_scene := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--target-scene="):
			target_scene = argument.trim_prefix("--target-scene=")

	if output_path.is_empty():
		_fail("Visual probe requires --out=<absolute png path>.")
		return
	if target_scene.is_empty():
		_fail("Visual probe requires --target-scene=<res:// scene path>.")
		return
	if target_scene != PROBE_SCENE:
		draw_probe_pattern = false
		var packed_scene := ResourceLoader.load(target_scene, "PackedScene") as PackedScene
		if packed_scene == null:
			_fail("Visual probe could not load target scene: %s" % target_scene)
			return
		add_child(packed_scene.instantiate())

	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	if image == null:
		_fail("Visual probe could not read the viewport image.")
		return
	if image.get_width() != REQUIRED_WIDTH or image.get_height() != REQUIRED_HEIGHT:
		_fail(
			"Visual probe dimensions must be %dx%d; found %dx%d."
			% [REQUIRED_WIDTH, REQUIRED_HEIGHT, image.get_width(), image.get_height()]
		)
		return

	var save_result := image.save_png(output_path)
	if save_result != OK:
		_fail("Visual probe could not save PNG: %s" % error_string(save_result))
		return

	print("Visual probe captured: %s" % output_path)
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)


func _draw() -> void:
	if not draw_probe_pattern:
		return
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#b86d36"))
	draw_rect(Rect2(size * Vector2(0.08, 0.14), size * Vector2(0.36, 0.26)), Color("#f4c56d"))
	draw_circle(size * Vector2(0.73, 0.34), minf(size.x, size.y) * 0.12, Color("#1f4652"))
	draw_colored_polygon(
		PackedVector2Array([
			size * Vector2(0.22, 0.82),
			size * Vector2(0.52, 0.51),
			size * Vector2(0.83, 0.82),
		]),
		Color("#6b2e45"),
	)
