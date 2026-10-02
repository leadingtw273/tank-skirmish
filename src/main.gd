## 連接主場景的接地互動與世界特效，同時維持自適應視窗設定；不擁有戰鬥或地圖內容。
extends Node3D

const TankCatalog := preload("res://src/actors/tank/tank_catalog.gd")

@onready var player_runtime: Node = $PlayerRuntime
@onready var combat_runtime: CombatRuntime = $CombatRuntime
@onready var surface_effects: Node = $SurfaceEffects
@onready var player_spawn_group: Node3D = $PlayerSpawnGroup

var track_contact_effects: Node
## 相容舊測試與既有呼叫方的 PackedScene 入口；正式組裝使用 startup_player_id。
@export var startup_player_scene: PackedScene
## 主圖與訓練場的正式初始玩家車型；避免以場景路徑保存車型狀態。
@export_enum("tank1", "tank2", "tank3", "tank4") var startup_player_id := "tank2"


func _ready() -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_bind_track_contact_effects($PlayerSpawnGroup/Tank)
	var initial_tank := player_spawn_group.get_node_or_null("Tank") as Node3D
	if initial_tank != null and StringName(initial_tank.get("vehicle_id")) != StringName(startup_player_id):
		replace_player_vehicle(StringName(startup_player_id))
	elif startup_player_scene != null:
		replace_player_tank(startup_player_scene)


## 以指定車型替換玩家坦克，保留世界位置與朝向，並重新接上所有既有玩法 runtime。
func replace_player_tank(tank_scene: PackedScene) -> Node3D:
	var previous_tank := player_spawn_group.get_node_or_null("Tank") as Node3D
	if previous_tank == null:
		push_error("TankSkirmish requires its current player tank for replacement.")
		return null
	return _replace_player_tank_at(tank_scene, previous_tank.global_transform)


## 正式車型入口：以穩定 ID 替換，保留目前世界姿態與所有 runtime 接線。
func replace_player_vehicle(vehicle_id: StringName) -> Node3D:
	var previous_tank := player_spawn_group.get_node_or_null("Tank") as Node3D
	if previous_tank == null:
		push_error("TankSkirmish requires its current player tank for replacement.")
		return null
	return _replace_player_vehicle_at(vehicle_id, previous_tank.global_transform)


## 訓練場重生：以協調器已保存的車型與出生姿態生成新車，並重設鏡頭。
func respawn_player_tank(tank_scene: PackedScene, spawn_transform: Transform3D) -> Node3D:
	var replacement := _replace_player_tank_at(tank_scene, spawn_transform)
	if replacement != null:
		player_runtime.get("camera_controller").call("reset_to_initial_view")
	return replacement


## 正式訓練場重生入口：以保存的穩定 ID 生成同款車並重設鏡頭。
func respawn_player_vehicle(vehicle_id: StringName, spawn_transform: Transform3D) -> Node3D:
	var replacement := _replace_player_vehicle_at(vehicle_id, spawn_transform)
	if replacement != null:
		player_runtime.get("camera_controller").call("reset_to_initial_view")
	return replacement


func _replace_player_vehicle_at(vehicle_id: StringName, spawn_transform: Transform3D) -> Node3D:
	var tank_scene := TankCatalog.scene(vehicle_id)
	if tank_scene == null:
		return null
	return _replace_player_tank_at(tank_scene, spawn_transform)


func _replace_player_tank_at(tank_scene: PackedScene, spawn_transform: Transform3D) -> Node3D:
	var previous_tank := player_spawn_group.get_node_or_null("Tank") as Node3D
	var replacement_tank := tank_scene.instantiate() as Node3D if tank_scene != null else null
	var replacement_contacts := replacement_tank.get_node_or_null("TrackContactEffects") as Node \
			if replacement_tank != null else null
	if replacement_tank == null or replacement_contacts == null \
			or not replacement_tank.has_signal("shot_event_fired") \
			or not replacement_contacts.has_signal("track_contact"):
		push_error("TankSkirmish requires a complete tank scene for player replacement.")
		if replacement_tank != null:
			replacement_tank.free()
		return null

	var previous_index := previous_tank.get_index() if previous_tank != null else -1
	var previous_health := previous_tank.get_node_or_null("HealthComponent") as HealthComponent \
			if previous_tank != null else null
	var retain_wreck := previous_health != null and previous_health.current_health <= 0.0
	if previous_tank != null:
		previous_tank.name = "PlayerWreck" if retain_wreck else "RetiredTank"
	replacement_tank.name = "Tank"
	## ready 也必須看見正式出生姿態，不先在原點初始化後再瞬移。
	replacement_tank.transform = player_spawn_group.global_transform.affine_inverse() * spawn_transform
	player_spawn_group.add_child(replacement_tank)
	if previous_index >= 0:
		player_spawn_group.move_child(replacement_tank, previous_index)

	if not bool(player_runtime.call("set_controlled_tank", replacement_tank)):
		push_error("TankSkirmish could not bind PlayerRuntime to the replacement tank.")
		replacement_tank.queue_free()
		if previous_tank != null:
			previous_tank.name = "Tank"
		return null
	if previous_tank != null:
		combat_runtime.unregister_shot_source(previous_tank)
	combat_runtime.register_shot_source(replacement_tank)
	_bind_track_contact_effects(replacement_tank)
	if previous_tank == null:
		return replacement_tank
	if retain_wreck:
		previous_tank.add_to_group("player_wreck")
		previous_tank.call("set_movement_input", 0.0)
		previous_tank.call("stop_hull_aim_turn")
		previous_tank.call("cancel_aim")
		previous_tank.set_physics_process(false)
		if previous_tank is CharacterBody3D:
			previous_tank.velocity = Vector3.ZERO
		var tread_animation := previous_tank.get("tread_animation_player") as AnimationPlayer
		if tread_animation != null:
			tread_animation.pause()
	else:
		if previous_tank is CollisionObject3D:
			previous_tank.collision_layer = 0
			previous_tank.collision_mask = 0
		previous_tank.process_mode = Node.PROCESS_MODE_DISABLED
		player_spawn_group.remove_child(previous_tank)
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
