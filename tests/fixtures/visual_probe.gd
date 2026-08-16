extends Node2D

const EXPECTED_WIDTH := 1920
const EXPECTED_HEIGHT := 1080
const PROBE_SCENE := "res://tests/fixtures/visual_probe.tscn"


func _ready() -> void:
	var target_scene := _target_scene()
	if target_scene.is_empty():
		push_error("Visual probe requires --target-scene=<res:// scene path>.")
		get_tree().quit(1)
		return
	if target_scene != PROBE_SCENE:
		var packed_scene := load(target_scene) as PackedScene
		if packed_scene == null:
			push_error("Visual probe could not load target scene: %s" % target_scene)
			get_tree().quit(2)
			return
		var instance := packed_scene.instantiate()
		if instance == null:
			push_error("Visual probe could not instantiate target scene: %s" % target_scene)
			get_tree().quit(3)
			return
		add_child(instance)

	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	var capture_path := _capture_path()
	if capture_path.is_empty():
		push_error("Visual probe requires --capture-out=<absolute PNG path>.")
		get_tree().quit(4)
		return

	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("Visual probe could not read the viewport texture.")
		get_tree().quit(5)
		return
	if image.get_width() != EXPECTED_WIDTH or image.get_height() != EXPECTED_HEIGHT:
		push_error("Visual probe captured %dx%d; expected 1920x1080." % [image.get_width(), image.get_height()])
		get_tree().quit(6)
		return

	var save_error := image.save_png(capture_path)
	if save_error != OK:
		push_error("Visual probe could not write PNG: %s" % error_string(save_error))
		get_tree().quit(7)
		return

	print("Visual probe wrote PNG: %s" % capture_path)
	get_tree().quit(0)


func _draw() -> void:
	if _target_scene() != PROBE_SCENE:
		return
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("d17a31"))
	draw_rect(Rect2(96.0, 96.0, viewport_size.x - 192.0, viewport_size.y - 192.0), Color("f4c45f"))
	draw_circle(viewport_size * 0.5, minf(viewport_size.x, viewport_size.y) * 0.18, Color("315c78"))
	draw_rect(Rect2(viewport_size * 0.5 - Vector2(240.0, 40.0), Vector2(480.0, 80.0)), Color("f7e2b5"))


func _capture_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-out="):
			return argument.trim_prefix("--capture-out=")
	return ""


func _target_scene() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--target-scene="):
			return argument.trim_prefix("--target-scene=")
	return ""
