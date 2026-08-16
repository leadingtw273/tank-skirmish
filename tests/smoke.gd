extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"


func _init() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		push_error("Unable to load main scene: %s" % MAIN_SCENE)
		quit(1)
		return

	var instance := packed_scene.instantiate()
	if instance == null:
		push_error("Unable to instantiate main scene: %s" % MAIN_SCENE)
		quit(1)
		return

	root.add_child(instance)
	print("Tank Skirmish smoke validation passed.")
	quit(0)
