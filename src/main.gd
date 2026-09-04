## 連接主場景的接地互動與世界特效，同時維持自適應視窗設定；不擁有戰鬥或地圖內容。
extends Node3D

@onready var player_runtime: Node = $PlayerRuntime
@onready var combat_runtime: CombatRuntime = $CombatRuntime
@onready var surface_effects: Node = $SurfaceEffects

var track_contact_effects: Node


func _ready() -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_bind_track_contact_effects($Tank)


## 以指定車型替換玩家坦克，保留世界位置與朝向，並重新接上所有既有玩法 runtime。
func replace_player_tank(tank_scene: PackedScene) -> Node3D:
	var previous_tank := get_node_or_null("Tank") as Node3D
	var replacement_tank := tank_scene.instantiate() as Node3D if tank_scene != null else null
	var replacement_contacts := replacement_tank.get_node_or_null("TrackContactEffects") as Node \
			if replacement_tank != null else null
	if previous_tank == null or replacement_tank == null or replacement_contacts == null \
			or not replacement_tank.has_signal("shot_event_fired") \
			or not replacement_contacts.has_signal("track_contact"):
		push_error("TankSkirmish requires a complete tank scene for player replacement.")
		if replacement_tank != null:
			replacement_tank.free()
		return null

	var previous_index := previous_tank.get_index()
	var previous_transform := previous_tank.global_transform
	previous_tank.name = "RetiredTank"
	replacement_tank.name = "Tank"
	add_child(replacement_tank)
	move_child(replacement_tank, previous_index)
	replacement_tank.global_transform = previous_transform

	if not bool(player_runtime.call("set_controlled_tank", replacement_tank)):
		push_error("TankSkirmish could not bind PlayerRuntime to the replacement tank.")
		replacement_tank.queue_free()
		previous_tank.name = "Tank"
		return null
	combat_runtime.unregister_shot_source(previous_tank)
	combat_runtime.register_shot_source(replacement_tank)
	combat_runtime.shot_sources = [replacement_tank]
	_bind_track_contact_effects(replacement_tank)
	previous_tank.queue_free()
	return replacement_tank


func _bind_track_contact_effects(tank: Node3D) -> bool:
	var next_contacts := tank.get_node_or_null("TrackContactEffects") as Node if tank != null else null
	if next_contacts == null or surface_effects == null or not next_contacts.has_signal("track_contact") \
			or not surface_effects.has_method("consume_track_contact"):
		push_error("TankSkirmish requires TrackContactEffects and SurfaceEffects wiring.")
		return false
	if track_contact_effects != null and is_instance_valid(track_contact_effects) \
			and track_contact_effects.is_connected("track_contact", surface_effects.consume_track_contact):
		track_contact_effects.disconnect("track_contact", surface_effects.consume_track_contact)
	track_contact_effects = next_contacts
	if not track_contact_effects.is_connected("track_contact", surface_effects.consume_track_contact):
		track_contact_effects.connect("track_contact", surface_effects.consume_track_contact)
	return true


func _exit_tree() -> void:
	if track_contact_effects != null and surface_effects != null \
			and track_contact_effects.is_connected("track_contact", surface_effects.consume_track_contact):
		track_contact_effects.disconnect("track_contact", surface_effects.consume_track_contact)
