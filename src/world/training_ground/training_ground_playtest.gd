## 將既有主場景的 World 替換為訓練場；不擁有或複製任何玩法 runtime 節點。
extends Node3D

const TRAINING_GROUND_SCENE := preload("res://src/world/training_ground/training_ground.tscn")


func _ready() -> void:
	var gameplay_runtime := get_node_or_null("Main") as Node3D
	var city_world := gameplay_runtime.get_node_or_null("World") as Node3D if gameplay_runtime != null else null
	var training_ground := TRAINING_GROUND_SCENE.instantiate() as Node3D
	if gameplay_runtime == null or city_world == null or training_ground == null:
		push_error("TrainingGroundPlaytest requires the existing main scene World and the training ground scene.")
		return

	var world_index := city_world.get_index()
	gameplay_runtime.remove_child(city_world)
	city_world.queue_free()
	training_ground.name = "World"
	gameplay_runtime.add_child(training_ground)
	gameplay_runtime.move_child(training_ground, world_index)
