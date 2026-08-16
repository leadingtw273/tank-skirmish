extends Node2D


func _ready() -> void:
	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
			break

	if output_path.is_empty():
		push_error("Visual probe requires --out=<absolute png path>.")
		get_tree().quit(1)
		return

	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("Visual probe could not read the viewport image.")
		get_tree().quit(1)
		return

	var save_result := image.save_png(output_path)
	if save_result != OK:
		push_error("Visual probe could not save PNG: %s" % error_string(save_result))
		get_tree().quit(1)
		return

	print("Visual probe captured: %s" % output_path)
	get_tree().quit(0)


func _draw() -> void:
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
