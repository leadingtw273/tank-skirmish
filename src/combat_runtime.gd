## 將坦克射擊事件轉為投射物，並將投射物命中轉為暫時性的世界特效。
## 它只擁有執行期的戰鬥子節點；不會決定坦克的開火時機或控制玩家輸入。
extends Node3D
class_name CombatRuntime

const PROJECTILE_SCENE := preload("res://src/projectile.tscn")
const IMPACT_VFX_SCENE := preload("res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_05.tscn")
const TankProjectile := preload("res://src/projectile.gd")
const ShotEvent := preload("res://src/shot_event.gd")
const ImpactEvent := preload("res://src/impact_event.gd")
@export_category("場景連接")
## 會發出公開 shot_event_fired signal、供此戰鬥執行期消費的節點。
@export var shot_sources: Array[Node]
## 接收執行期 TankProjectile 節點的父節點。
@export var projectiles: Node3D
## 接收暫時性命中特效節點的父節點。
@export var effects: Node3D

@export_category("命中呈現")
## 已實體化的命中特效在主動畫播放完畢後移除前的存活時間，單位為秒。
@export var impact_vfx_lifetime_seconds := 1.3
## 沿命中法線的偏移量，單位為公尺，用來避免視覺特效穿入表面。
@export var impact_vfx_surface_offset := 0.05

var _registered_shot_sources: Array[Node] = []


func _ready() -> void:
	## 先確認兩個執行期容器存在，才逐一連接場景提供的射擊來源，避免生成無主節點。
	if projectiles == null or effects == null:
		push_error("CombatRuntime requires injected Projectiles and Effects containers.")
		return
	for shot_source in shot_sources:
		register_shot_source(shot_source)


func _exit_tree() -> void:
	## 複製註冊清單後解除連接，因為解除時會同步從原清單移除元素。
	for shot_source in _registered_shot_sources.duplicate():
		unregister_shot_source(shot_source)


## 連接一個啟用中的 shot_event_fired 來源；刻意忽略重複註冊。
func register_shot_source(shot_source: Node) -> void:
	if shot_source == null or not is_instance_valid(shot_source) or not shot_source.has_signal("shot_event_fired"):
		push_error("CombatRuntime requires an active shot_event_fired source.")
		return
	if _registered_shot_sources.has(shot_source):
		return
	if not shot_source.is_connected("shot_event_fired", _on_shot_fired):
		shot_source.connect("shot_event_fired", _on_shot_fired)
	var release_callback := _on_shot_source_tree_exiting.bind(shot_source)
	if not shot_source.tree_exiting.is_connected(release_callback):
		shot_source.tree_exiting.connect(release_callback)
	_registered_shot_sources.append(shot_source)


## 中斷先前註冊的射擊來源，並釋放其生命週期回呼。
func unregister_shot_source(shot_source: Node) -> void:
	if shot_source == null or not _registered_shot_sources.has(shot_source):
		return
	if is_instance_valid(shot_source):
		if shot_source.is_connected("shot_event_fired", _on_shot_fired):
			shot_source.disconnect("shot_event_fired", _on_shot_fired)
		var release_callback := _on_shot_source_tree_exiting.bind(shot_source)
		if shot_source.tree_exiting.is_connected(release_callback):
			shot_source.tree_exiting.disconnect(release_callback)
	_registered_shot_sources.erase(shot_source)


func _on_shot_source_tree_exiting(shot_source: Node) -> void:
	## 射擊來源先於戰鬥容器離開場景時，主動清除它的 signal 與生命週期回呼。
	unregister_shot_source(shot_source)


func _on_shot_fired(shot_event: ShotEvent) -> void:
	## 將不可變 ShotEvent 轉成暫時投射物，先完成初始化與 signal 連接，再掛入容器以啟動生命週期。
	if shot_event == null or not shot_event.is_valid():
		push_error("CombatRuntime rejected an invalid ShotEvent.")
		return
	var projectile := PROJECTILE_SCENE.instantiate() as TankProjectile
	if projectile == null:
		push_error("CombatRuntime could not instantiate projectile.tscn.")
		return
	projectile.name = "Projectile"
	projectile.initialize(shot_event)
	projectile.impact_detected.connect(_on_projectile_impact)
	projectiles.add_child(projectile, true)
	projectile.global_transform = Transform3D(_basis_with_x_axis(shot_event.direction), shot_event.muzzle_transform.origin)


func _on_projectile_impact(impact_event: ImpactEvent) -> void:
	## 命中特效沿世界座標表面法線微移，避免穿模，並由 SceneTree 計時器在播放後釋放。
	if impact_event == null or not impact_event.is_valid():
		return
	var impact := IMPACT_VFX_SCENE.instantiate() as Node3D
	impact.name = "ImpactVFX"
	impact.set("one_shot", true)
	impact.set("autoplay", true)
	effects.add_child(impact, true)
	impact.global_position = impact_event.position + impact_event.normal * impact_vfx_surface_offset
	get_tree().create_timer(impact_vfx_lifetime_seconds).timeout.connect(impact.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	## 依射擊方向建立正交基底供特效與投射物朝向本地 X 軸；近乎垂直時切換參考上軸避免退化。
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
