extends Node3D


func _ready() -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
