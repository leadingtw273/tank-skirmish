extends StaticBody3D

@export var target_material: Material

@onready var tank_model: Node3D = $Tank2


func _ready() -> void:
	_apply_target_material(tank_model)


func _apply_target_material(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = target_material
	for child: Node in node.get_children():
		_apply_target_material(child)
