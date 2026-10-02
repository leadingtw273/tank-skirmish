extends SceneTree
## Explicit local promotion after candidate acceptance. Never erases the old map.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("res://artifacts-local/main_battlefield_"):
		push_error("Expected one reviewed local main_battlefield candidate")
		quit(1)
		return
	var target := "res://src/maps/main_battlefield/main_battlefield.tscn"
	var backup := "res://artifacts-local/main-before-publish-%d.tscn" % Time.get_unix_time_from_system()
	var candidate := load(args[0]) as PackedScene
	if candidate == null:
		quit(1)
		return
	var root_ := candidate.instantiate()
	var valid := root_.has_node("Roads/Junctions") and root_.has_node("Roads/Connections")
	root_.free()
	if not valid or DirAccess.copy_absolute(ProjectSettings.globalize_path(target), ProjectSettings.globalize_path(backup)) != OK:
		push_error("Candidate invalid or backup failed; main unchanged")
		quit(1)
		return
	var result := ResourceSaver.save(candidate, target)
	var evidence: String = args[0].get_basename() + "-layout.json"
	if result == OK and FileAccess.file_exists(evidence):
		result = DirAccess.copy_absolute(ProjectSettings.globalize_path(evidence), ProjectSettings.globalize_path("res://docs/maps/main-road-layout.json"))
	print("PUBLISH_MAIN_RESULT code=%d backup=%s" % [result, backup])
	quit(result)
