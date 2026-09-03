@tool
extends Node3D
class_name VFXFireController

@export var emitting : bool = true:
	set(value):
		emitting = value
		if Engine.is_editor_hint():
			if emitting:
				play()
			else:
				stop()

@export var one_shot : bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return

func play():
	_set_particles(true)
	
	if one_shot:
		await get_tree().create_timer(_get_longest_lifetime()).timeout
		emitting = false

func stop():
	_set_particles(false)

func _set_particles(state : bool):
	for p in _get_particles():
		p.emitting = state
	for m in _get_effect_mesh():
		m.visible = state

### System

func _get_particles(root: Node = self) -> Array[GPUParticles3D]:
	var result: Array[GPUParticles3D] = []
	
	for child in root.get_children():
		if child is  GPUParticles3D:
			result.append(child)
	
	return result

func _get_effect_mesh(root: Node = self)  -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	
	for child in root.get_children():
		if child is MeshInstance3D:
			if child.is_in_group("effect_mesh"):
				result.append(child)
	
	return result

func _get_longest_lifetime() -> float:
	var longest: float = 0.0
	for p in _get_particles():
		longest = max(longest, p.lifetime)
	return longest
