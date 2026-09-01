## 連接主場景的接地互動與世界特效，同時維持自適應視窗設定；不擁有戰鬥或地圖內容。
extends Node3D

@onready var track_contact_effects: Node = $Tank/TrackContactEffects
@onready var surface_effects: Node = $SurfaceEffects


func _ready() -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if track_contact_effects == null or surface_effects == null \
			or not track_contact_effects.has_signal("track_contact") \
			or not surface_effects.has_method("consume_track_contact"):
		push_error("TankSkirmish requires TrackContactEffects and SurfaceEffects wiring.")
		return
	if not track_contact_effects.is_connected("track_contact", surface_effects.consume_track_contact):
		track_contact_effects.connect("track_contact", surface_effects.consume_track_contact)


func _exit_tree() -> void:
	if track_contact_effects != null and surface_effects != null \
			and track_contact_effects.is_connected("track_contact", surface_effects.consume_track_contact):
		track_contact_effects.disconnect("track_contact", surface_effects.consume_track_contact)
