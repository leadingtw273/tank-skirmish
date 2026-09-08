## 訓練場專屬組裝：登記敵方射擊、跟隨換車，以及玩家死亡後中央重生與短暫保護。
## AI 不知道三秒恢復規則；完整坦克也不必知道自己位於訓練場。
extends Node3D

## 現有玩家控制組裝節點，提供目前坦克與輸入啟用接口。
@export var player_runtime: Node
## 遊戲執行期組裝入口，負責重生玩家坦克並重綁既有執行期服務。
@export var gameplay_runtime: Node3D
## 現有戰鬥執行期，所有坦克共用同一套砲彈與傷害處理。
@export var combat_runtime: CombatRuntime
## 粉色射擊開關；命中後循環換敵車，與既有彈著／圓錐開關各自獨立。
@export var enemy_switch_target: StaticBody3D
## 可在編輯器調整的玩家重生世界位置與車身朝向。
@export var player_spawn_point: Node3D
## 玩家歸零後生成同款新車並恢復輸入的等待秒數。
@export_range(0.1, 30.0, 0.1) var player_respawn_seconds := 3.0
## 新車生成後可正常操作、但拒絕傷害的秒數。
@export_range(0.1, 10.0, 0.1) var player_invulnerability_seconds := 2.0
const PLAYER_INVULNERABILITY_BLINK_SECONDS := 0.15

@onready var enemy: Node3D = $Enemy
@onready var combat_ai: Node = $CombatAI
@onready var vision: Node = $Vision
const ENEMY_VARIANTS: Array[PackedScene] = [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	preload("res://src/actors/tank/variants/tank2/tank2.tscn"),
	preload("res://src/actors/tank/variants/tank3/tank3.tscn"),
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]
var _enemy_spawn_transform := Transform3D.IDENTITY
var _enemy_variant_index := -1
var _player_health: HealthComponent
var _respawn_remaining := -1.0
var _respawn_tank_scene: PackedScene
var _invulnerability_remaining := -1.0
var _invulnerability_elapsed := 0.0
var _protected_receiver: DamageReceiver
var _protected_receiver_was_enabled := true
var _protected_mesh_visibility: Dictionary[MeshInstance3D, bool] = {}


func _ready() -> void:
	if gameplay_runtime == null or player_spawn_point == null:
		push_error("TrainingCombatEncounter requires its GameplayRuntime and PlayerSpawnPoint.")
		return
	## 只記錄場景啟動時的姿態；交戰期間移位或轉向不會改變重置點。
	_enemy_spawn_transform = enemy.global_transform
	for index in ENEMY_VARIANTS.size():
		if ENEMY_VARIANTS[index].resource_path == enemy.scene_file_path:
			_enemy_variant_index = index
			break
	combat_runtime.register_shot_source(enemy)
	player_runtime.connect("controlled_tank_changed", _bind_player)
	_bind_player(player_runtime.get("controlled_tank") as Node3D)
	combat_runtime.impact_resolved.connect(_on_impact_resolved)


func _on_impact_resolved(event: ImpactEvent) -> void:
	if event == null:
		return
	## 命中事件早於傷害交付；這裡只記錄查看意圖，致死命中會在 AI 下次更新被 alive gate 取消。
	if event.collider == enemy and event.shot_event != null and event.shot_event.damage > 0.0:
		var receiver := enemy.get_node_or_null("DamageReceiver") as DamageReceiver
		if receiver != null and receiver.enabled:
			combat_ai.call("inspect_hit_position", event.position)
	## 沿用有效命中事件；避開物理查詢回呼當下直接增刪碰撞體。
	if is_instance_valid(enemy_switch_target) and event.collider == enemy_switch_target:
		_cycle_enemy.call_deferred()


func _cycle_enemy() -> void:
	## 完整車型重新實例化，自然回到該車型滿血、零速度與預設砲塔／砲管姿態。
	if _enemy_variant_index < 0:
		push_error("Enemy switch requires one of the four registered tank variants.")
		return
	var next_index := (_enemy_variant_index + 1) % ENEMY_VARIANTS.size()
	var replacement := ENEMY_VARIANTS[next_index].instantiate() as Node3D
	if replacement == null:
		push_error("Enemy switch could not instantiate the next tank variant.")
		return
	combat_ai.call("set_combat_enabled", false)
	var previous := enemy
	combat_runtime.unregister_shot_source(previous)
	remove_child(previous)
	previous.queue_free()
	replacement.name = "Enemy"
	## 加入樹前先套用初始姿態，讓坦克的 ready 在正確位置完成模型接線。
	replacement.transform = global_transform.affine_inverse() * _enemy_spawn_transform
	add_child(replacement)
	enemy = replacement
	_enemy_variant_index = next_index
	combat_ai.set("controlled_tank", enemy)
	vision.set("observer", enemy)
	combat_runtime.register_shot_source(enemy)
	## 玩家死亡恢復倒數仍由原協調器掌控，换敵不能提早解開暫停。
	combat_ai.call("set_combat_enabled", _respawn_remaining < 0.0 and is_instance_valid(_player_health)
		and _player_health.current_health > 0.0)


func _bind_player(tank: Node3D) -> void:
	## 換車解除舊血量訂閱，再把同一個 AI 指向新玩家；不重建敵方或整個 runtime。
	if is_instance_valid(_player_health) and _player_health.depleted.is_connected(_on_player_depleted):
		_player_health.depleted.disconnect(_on_player_depleted)
	_player_health = tank.get_node("HealthComponent") as HealthComponent
	_player_health.depleted.connect(_on_player_depleted)
	if _invulnerability_remaining > 0.0:
		## 無敵中命中換車靶，剩餘保護接到新車，但不重新計時。
		_protect_player(tank)
	combat_ai.call("set_target", tank)
	## 飛行中的砲彈可能在死亡倒數時擊毀換車靶；換車只重綁，不得提前解除原暫停。
	var recovering := _respawn_remaining >= 0.0
	player_runtime.call("set_controls_enabled", not recovering)
	combat_ai.call("set_combat_enabled", not recovering)
	if not recovering and _player_health.current_health <= 0.0:
		_on_player_depleted()


func _on_player_depleted() -> void:
	## HealthComponent 的 depleted 每次歸零只發出一次，因此不需要另一套死亡事件系統。
	_finish_player_protection()
	var tank := player_runtime.get("controlled_tank") as Node3D
	_respawn_tank_scene = load(tank.scene_file_path) as PackedScene
	player_runtime.call("set_controls_enabled", false)
	combat_ai.call("set_combat_enabled", false)
	_respawn_remaining = player_respawn_seconds


func _physics_process(delta: float) -> void:
	_update_player_protection(delta)
	if _respawn_remaining < 0.0:
		return
	_respawn_remaining -= delta
	if _respawn_remaining > 0.0:
		return
	_respawn_remaining = -1.0
	_respawn_player.call_deferred()


func _respawn_player() -> void:
	var replacement := gameplay_runtime.call("respawn_player_tank", _respawn_tank_scene,
		player_spawn_point.global_transform) as Node3D
	if replacement == null:
		push_error("TrainingCombatEncounter could not spawn the replacement player tank.")
		return
	## Main 已重綁 PlayerRuntime 與鏡頭，_bind_player 也已恢復操作／敵方交戰。
	_invulnerability_remaining = player_invulnerability_seconds
	_invulnerability_elapsed = 0.0
	_protect_player(replacement)


func _protect_player(tank: Node3D) -> void:
	_restore_protected_player()
	_protected_receiver = tank.get_node("DamageReceiver") as DamageReceiver
	_protected_receiver_was_enabled = _protected_receiver.enabled
	_protected_receiver.enabled = false
	for node: Node in tank.find_children("*", "MeshInstance3D", true, false):
		if not node.is_in_group("effect_mesh"):
			var mesh := node as MeshInstance3D
			_protected_mesh_visibility[mesh] = mesh.visible
	_update_protection_visibility()


func _update_player_protection(delta: float) -> void:
	if _invulnerability_remaining < 0.0:
		return
	_invulnerability_remaining -= delta
	_invulnerability_elapsed += delta
	if _invulnerability_remaining <= 0.0:
		_finish_player_protection()
	else:
		_update_protection_visibility()


func _update_protection_visibility() -> void:
	var blink_visible := int(_invulnerability_elapsed / PLAYER_INVULNERABILITY_BLINK_SECONDS) % 2 == 1
	for mesh: MeshInstance3D in _protected_mesh_visibility:
		if is_instance_valid(mesh):
			mesh.visible = _protected_mesh_visibility[mesh] and blink_visible


func _restore_protected_player() -> void:
	if is_instance_valid(_protected_receiver):
		_protected_receiver.enabled = _protected_receiver_was_enabled
	_protected_receiver = null
	for mesh: MeshInstance3D in _protected_mesh_visibility:
		if is_instance_valid(mesh):
			mesh.visible = _protected_mesh_visibility[mesh]
	_protected_mesh_visibility.clear()


func _finish_player_protection() -> void:
	_restore_protected_player()
	_invulnerability_remaining = -1.0
	_invulnerability_elapsed = 0.0


func _exit_tree() -> void:
	_finish_player_protection()
	## 只解除本場交戰所建立的連接，不能把其他射擊來源一起清空。
	if is_instance_valid(combat_runtime) and combat_runtime.impact_resolved.is_connected(_on_impact_resolved):
		combat_runtime.impact_resolved.disconnect(_on_impact_resolved)
	if is_instance_valid(_player_health) and _player_health.depleted.is_connected(_on_player_depleted):
		_player_health.depleted.disconnect(_on_player_depleted)
	if is_instance_valid(player_runtime) and player_runtime.is_connected("controlled_tank_changed", _bind_player):
		player_runtime.disconnect("controlled_tank_changed", _bind_player)
	if is_instance_valid(combat_runtime) and is_instance_valid(enemy):
		combat_runtime.unregister_shot_source(enemy)
