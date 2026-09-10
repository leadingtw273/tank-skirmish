## 在指定區域內持續移除已死亡的真 TankController；不參與重生或其他遊戲流程。
extends Node

const TankController := preload("res://src/actors/tank/tank_controller.gd")
const HealthComponent := preload("res://src/combat/damage/health_component.gd")

@export var area: Area3D
@export var scene_root: Node


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or area == null or scene_root == null:
		return

	var wrecks: Dictionary = {}
	for body in area.get_overlapping_bodies():
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if not scene_root.is_ancestor_of(body):
			continue
		if not (body is TankController):
			continue
		var health := body.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_health > 0.0:
			continue
		wrecks[body.get_instance_id()] = body

	for wreck in wrecks.values():
		var wreck_node := wreck as Node
		if wreck_node != null and is_instance_valid(wreck_node) and not wreck_node.is_queued_for_deletion():
			wreck_node.queue_free()
