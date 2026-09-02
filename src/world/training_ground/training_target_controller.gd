## 管理訓練靶專屬的暫用血量文字，以及歸零後延遲回滿規則。
## 被包裝的完整實體仍自行擁有 HealthComponent 與 DamageReceiver。
extends Node
class_name TrainingTargetController

const HealthComponent := preload("res://src/combat/damage/health_component.gd")
const DamageReceiver := preload("res://src/combat/damage/damage_receiver.gd")

## 要套用訓練靶識別材質的完整實體。
@export var subject: Node3D
## 被包裝實體的血量元件。
@export var health_component: HealthComponent
## 被包裝實體的傷害接收元件。
@export var damage_receiver: DamageReceiver
## 第一版固定在坦克高度的暫用血量文字。
@export var health_label: Label3D
## 血量歸零後恢復至最大值的等待秒數。
@export_range(0.0, 30.0, 0.1) var reset_delay_seconds := 3.0
## 用來區別玩家坦克與訓練靶的整體材質。
@export var target_material: Material

var _reset_in_progress := false


func _ready() -> void:
	if subject == null or health_component == null or damage_receiver == null or health_label == null:
		push_error("TrainingTargetController requires its subject, health, receiver, and label references.")
		return
	health_component.health_changed.connect(_on_health_changed)
	health_component.depleted.connect(_on_depleted)
	_apply_target_material(subject)
	_update_label(health_component.current_health, health_component.maximum_health)


func _on_health_changed(current_health: float, maximum_health: float) -> void:
	_update_label(current_health, maximum_health)


func _on_depleted() -> void:
	if _reset_in_progress:
		return
	_reset_in_progress = true
	damage_receiver.enabled = false
	_reset_after_delay()


func _reset_after_delay() -> void:
	await get_tree().create_timer(maxf(reset_delay_seconds, 0.0)).timeout
	if not is_inside_tree() or health_component == null or damage_receiver == null:
		return
	health_component.reset_to_maximum()
	damage_receiver.enabled = true
	_reset_in_progress = false


func _update_label(current_health: float, maximum_health: float) -> void:
	health_label.text = "%d / %d" % [roundi(current_health), roundi(maximum_health)]


func _apply_target_material(node: Node) -> void:
	if target_material != null and node is MeshInstance3D:
		(node as MeshInstance3D).material_override = target_material
	for child: Node in node.get_children():
		_apply_target_material(child)
