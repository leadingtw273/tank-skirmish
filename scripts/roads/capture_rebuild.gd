extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1500, 1200)
	var arguments := OS.get_cmdline_user_args()
	var scene_path := "res://src/maps/main_battlefield/main_battlefield.tscn" if arguments.is_empty() else arguments[0]
	var scene := load(scene_path).instantiate() as Node3D
	root.add_child(scene)
	if scene_path.contains("main_battlefield"):
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 320
		camera.position = Vector3(0, 320, 0.01)
		camera.basis = Basis.looking_at(-camera.position, Vector3.UP)
		camera.current = true
		scene.add_child(camera)
	for i: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var name_ := scene_path.get_file().get_basename()
	var path := "res://artifacts-local/%s.png" % name_
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts-local"))
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("REBUILD_CAPTURE %s result=%d" % [path, result])
	quit(result)
