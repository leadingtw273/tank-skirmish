@tool
extends VFXFireController
class_name VFXAreaEffect

## Sets the resolution of the effect mesh. Lower values are better for performance
@export var resolution: Vector2 = Vector2(16,16):
	set(value):
		resolution = value
		var mesh : MeshInstance3D = get_node("WaveMesh")
		if mesh != null:
			mesh.mesh.set("subdivide_width", resolution.x)
			mesh.mesh.set("subdivide_depth", resolution.y)

@export var speed: float = 1.0:
	set(value):
		speed = value
		var mesh : MeshInstance3D = get_node("WaveMesh")
		mesh.mesh.surface_get_material(0).set_shader_parameter("speed", speed)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
