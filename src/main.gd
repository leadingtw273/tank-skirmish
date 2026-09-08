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
	if previous_tank == null:
		push_error("TankSkirmish requires its current player tank for replacement.")
		return null
	return _replace_player_tank_at(tank_scene, previous_tank.global_transform)


## 訓練場重生：先重綁新車，再清除擋住出生形狀的玩家殘骸並重設鏡頭。
func respawn_player_tank(tank_scene: PackedScene, spawn_transform: Transform3D) -> Node3D:
	var replacement := _replace_player_tank_at(tank_scene, spawn_transform)
	if replacement != null:
		_clear_spawn_wrecks(replacement)
		player_runtime.get("camera_controller").call("reset_to_initial_view")
	return replacement


func _replace_player_tank_at(tank_scene: PackedScene, spawn_transform: Transform3D) -> Node3D:
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
	var previous_health := previous_tank.get_node_or_null("HealthComponent") as HealthComponent
	var retain_wreck := previous_health != null and previous_health.current_health <= 0.0
	previous_tank.name = "PlayerWreck" if retain_wreck else "RetiredTank"
	replacement_tank.name = "Tank"
	## ready 也必須看見正式出生姿態，不先在原點初始化後再瞬移。
	replacement_tank.transform = global_transform.affine_inverse() * spawn_transform
	add_child(replacement_tank)
	move_child(replacement_tank, previous_index)

	if not bool(player_runtime.call("set_controlled_tank", replacement_tank)):
		push_error("TankSkirmish could not bind PlayerRuntime to the replacement tank.")
		replacement_tank.queue_free()
		previous_tank.name = "Tank"
		return null
	combat_runtime.unregister_shot_source(previous_tank)
	combat_runtime.register_shot_source(replacement_tank)
	_bind_track_contact_effects(replacement_tank)
	if retain_wreck:
		previous_tank.add_to_group("player_wreck")
		previous_tank.call("set_movement_input", 0.0)
		previous_tank.call("stop_hull_aim_turn")
		previous_tank.call("cancel_aim")
		previous_tank.set_physics_process(false)
		(previous_tank as CharacterBody3D).velocity = Vector3.ZERO
		var tread_animation := previous_tank.get("tread_animation_player") as AnimationPlayer
		if tread_animation != null:
			tread_animation.pause()
	else:
		previous_tank.queue_free()
	return replacement_tank


func _clear_spawn_wrecks(replacement: Node3D) -> void:
	var collision_shape := replacement.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.exclude = [replacement.get_rid()]
	## 先列出完整重疊結果再處理，避免只清第一個殘骸或誤刪附近未相交的物件。
	var hits := get_world_3d().direct_space_state.intersect_shape(query, get_tree().get_node_count())
	var obstructing_wrecks: Array[CollisionObject3D] = []
	for hit: Dictionary in hits:
		var wreck := hit.get("collider") as CollisionObject3D
		if wreck != null and wreck.get_parent() == self and wreck.is_in_group("player_wreck") \
				and not obstructing_wrecks.has(wreck):
			obstructing_wrecks.append(wreck)
	for wreck in obstructing_wrecks:
		wreck.collision_layer = 0
		wreck.collision_mask = 0
		wreck.queue_free()


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
