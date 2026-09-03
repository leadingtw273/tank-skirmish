## 僅供四車損傷工作台使用：經正式 HealthComponent 介面設定血量，並停用實體物理與碰撞。
extends Node

@export var tank: CharacterBody3D
@export_range(0, 100, 25) var health_percent := 100


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	if tank == null:
		push_error("HealthStagePreview requires a tank.")
		return
	var health := tank.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		push_error("HealthStagePreview requires the tank HealthComponent.")
		return
	health.reset_to_maximum()
	var preview_damage := health.maximum_health * (1.0 - float(health_percent) / 100.0)
	if preview_damage > 0.0:
		health.apply_damage(preview_damage)
	tank.set_physics_process(false)
	tank.collision_layer = 0
	tank.collision_mask = 0
	for node: Node in tank.find_children("*", "CollisionObject3D", true, false):
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
