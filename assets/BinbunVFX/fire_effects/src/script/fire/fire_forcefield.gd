@tool
extends VFXFireController

@export var radius: float = 1:
	set(value):
		radius = value
		if Engine.is_editor_hint():
			var mesh : MeshInstance3D = get_node("FieldMesh")
			mesh.mesh.set("radius", radius)

@export var height: float = 2:
	set(value):
		height = value
		if Engine.is_editor_hint():
			var mesh : MeshInstance3D = get_node("FieldMesh")
			mesh.mesh.set("height", height)


@export var hemisphere: bool = false:
	set(value):
		hemisphere = value
		if Engine.is_editor_hint():
			var mesh : MeshInstance3D = get_node("FieldMesh")
			mesh.mesh.set("is_hemisphere", hemisphere)
