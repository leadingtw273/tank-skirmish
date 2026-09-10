@tool
## 可在編輯器擺放的盒形區域；size 同時驅動偵測盒與僅編輯器顯示的提示。
extends Area3D

@export var size: Vector3 = Vector3(24.0, 8.0, 24.0):
	set(value):
		size = value
		_sync_size()


func _ready() -> void:
	_sync_size()


func _sync_size() -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		var box_shape := collision_shape.shape as BoxShape3D
		if box_shape != null:
			box_shape.size = size

	var editor_preview := get_node_or_null("EditorPreview") as MeshInstance3D
	if editor_preview != null:
		var box_mesh := editor_preview.mesh as BoxMesh
		if box_mesh != null:
			box_mesh.size = size
		editor_preview.visible = Engine.is_editor_hint()
