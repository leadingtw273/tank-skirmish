## 將既有主場景的 World 替換為訓練場；不擁有或複製任何玩法 runtime 節點。
extends Node3D

const TRAINING_GROUND_SCENE := preload("res://src/world/training_ground/training_ground.tscn")

var _gameplay_runtime: Node3D


func _ready() -> void:
	_gameplay_runtime = get_node_or_null("Main") as Node3D
	var city_world := _gameplay_runtime.get_node_or_null("World") as Node3D if _gameplay_runtime != null else null
	var training_ground := TRAINING_GROUND_SCENE.instantiate() as Node3D
	if _gameplay_runtime == null or city_world == null or training_ground == null:
		push_error("TrainingGroundPlaytest requires the existing main scene World and the training ground scene.")
		return

	var world_index := city_world.get_index()
	_gameplay_runtime.remove_child(city_world)
	city_world.queue_free()
	training_ground.name = "World"
	_gameplay_runtime.add_child(training_ground)
	_gameplay_runtime.move_child(training_ground, world_index)
	_connect_tank_replacement_targets(training_ground)


func _connect_tank_replacement_targets(training_ground: Node3D) -> void:
	var targets := training_ground.get_node_or_null("Targets") as Node3D
	if targets == null:
		push_error("TrainingGroundPlaytest requires training targets.")
		return
	for target: Node in targets.get_children():
		var controller := target.get_node_or_null("TrainingTargetController") as TrainingTargetController
		if controller == null:
			continue
		controller.target_depleted.connect(_on_target_depleted)


func _on_target_depleted(subject: Node3D) -> void:
	var tank_scene := load(subject.scene_file_path) as PackedScene if subject != null else null
	if tank_scene == null or _gameplay_runtime == null or not _gameplay_runtime.has_method("replace_player_tank"):
		push_error("TrainingGroundPlaytest could not resolve the destroyed target tank scene.")
		return
	_gameplay_runtime.call("replace_player_tank", tank_scene)
