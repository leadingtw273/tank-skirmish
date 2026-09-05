## 依坦克的血量比例切換車型提供的受損煙火，並在歸零時只讓砲管下垂。
## 砲塔的水平朝向不會被本元件改動。
extends Node
class_name TankDamageVisuals

const HealthComponent := preload("res://src/combat/damage/health_component.gd")
## 血量歸零時砲管向下垂的角度；數值由各車型的損傷場景提供。
@export_range(0.0, 45.0, 0.01) var depleted_gun_depression_degrees := 9.638463
## 車型專屬的歸零爆炸包裝場景。
@export var depleted_explosion_scene: PackedScene
## 不同受損階段交接時，新效果淡入所需的秒數。
@export_range(0.0, 3.0, 0.05) var damage_transition_seconds := 0.6
## 歸零爆炸相對於坦克原點的本地位置。
@export var depleted_explosion_local_offset := Vector3(0, 1.2, 0)
## 歸零爆炸的等比縮放倍率。
@export_range(0.1, 10.0, 0.05) var depleted_explosion_scale := 1.0
## 歸零爆炸播放後保留在場景中的秒數。
@export_range(0.1, 10.0, 0.1) var depleted_explosion_lifetime_seconds := 2.0

## 目前顯示的血量階段，供除錯與測試讀取：100、75、50、25 或 0。
var active_damage_stage := 100

var _health_component: HealthComponent
var _tank: Node3D
var _gun_pitch_pivot: Node3D
var _hull_anchor: Node3D
var _turret_anchor: Node3D
var _state_roots: Dictionary = {}
var _active_state_roots: Array[Node3D] = []
var _root_transition_serials: Dictionary = {}
var _gun_pitch_before_depletion := 0.0
var _is_depleted := false


func _ready() -> void:
	# TankController 會在自己的 _ready() 中建立正式砲塔／砲管樞紐；延後一拍再掛接特效。
	call_deferred("_bind_to_tank")


func _bind_to_tank() -> void:
	_tank = get_parent() as Node3D
	_health_component = _tank.get_node_or_null("HealthComponent") as HealthComponent
	var visual_recoil_pivot := _tank.get_node_or_null("VisualRecoilPivot") as Node3D
	var turret_pivot := _tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	_gun_pitch_pivot = _tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	_hull_anchor = get_node_or_null("HullDamageVFXAnchor") as Node3D
	_turret_anchor = get_node_or_null("TurretDamageVFXAnchor") as Node3D
	if _health_component == null or visual_recoil_pivot == null or turret_pivot == null \
			or _gun_pitch_pivot == null or _hull_anchor == null or _turret_anchor == null:
		push_error("TankDamageVisuals requires Tank health and recoil/turret/gun pivots.")
		return

	_state_roots = {
		75: [_hull_anchor.get_node("Damage75"), _turret_anchor.get_node("Damage75")],
		50: [_hull_anchor.get_node("Damage50"), _turret_anchor.get_node("Damage50")],
		25: [_hull_anchor.get_node("Damage25"), _turret_anchor.get_node("Damage25")],
		0: [_hull_anchor.get_node("Depleted"), _turret_anchor.get_node("Depleted")],
	}
	_hull_anchor.reparent(visual_recoil_pivot, false)
	_turret_anchor.reparent(turret_pivot, false)
	_health_component.health_changed.connect(_on_health_changed)
	_apply_health_state(_health_component.current_health, _health_component.maximum_health)


func _on_health_changed(current_health: float, maximum_health: float) -> void:
	_apply_health_state(current_health, maximum_health)


func _apply_health_state(current_health: float, maximum_health: float) -> void:
	var next_stage := _damage_stage_for_health(current_health, maximum_health)
	var next_state_roots: Array[Node3D] = []
	if _state_roots.has(next_stage):
		for state_root: Node3D in _state_roots[next_stage]:
			next_state_roots.append(state_root)
	for state_root in _active_state_roots:
		if not next_state_roots.has(state_root):
			_fade_out_state_root(state_root)
	for state_root in next_state_roots:
		if not _active_state_roots.has(state_root):
			_fade_in_state_root(state_root)
	_active_state_roots = next_state_roots
	active_damage_stage = next_stage
	_set_depleted_pose(next_stage == 0)


func _fade_in_state_root(state_root: Node3D) -> void:
	_next_transition_serial(state_root)
	state_root.visible = true
	var duration := maxf(damage_transition_seconds, 0.0)
	var tween: Tween
	for node: Node in state_root.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		# 受損煙火屬於坦克本體；使用本地座標，避免車體／砲塔轉向後只剩陰影而看不到粒子。
		particles.local_coords = true
		particles.amount_ratio = 0.0
		particles.emitting = true
		particles.restart()
		if tween == null:
			tween = create_tween().set_parallel(true)
		tween.tween_property(particles, "amount_ratio", 1.0, duration)
	for node: Node in state_root.find_children("*", "MeshInstance3D", true, false):
		var effect_mesh := node as MeshInstance3D
		effect_mesh.transparency = 1.0
		if tween == null:
			tween = create_tween().set_parallel(true)
		tween.tween_property(effect_mesh, "transparency", 0.0, duration)


func _fade_out_state_root(state_root: Node3D) -> void:
	var serial := _next_transition_serial(state_root)
	var duration := maxf(damage_transition_seconds, 0.0)
	var cleanup_delay := duration
	var tween: Tween
	for node: Node in state_root.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		particles.emitting = false
		var effective_lifetime := particles.lifetime / maxf(absf(particles.speed_scale), 0.001)
		cleanup_delay = maxf(cleanup_delay, effective_lifetime)
	for node: Node in state_root.find_children("*", "MeshInstance3D", true, false):
		var effect_mesh := node as MeshInstance3D
		if tween == null:
			tween = create_tween().set_parallel(true)
		tween.tween_property(effect_mesh, "transparency", 1.0, duration)
	get_tree().create_timer(cleanup_delay).timeout.connect(_finish_fade_out.bind(state_root, serial))


func _finish_fade_out(state_root: Node3D, serial: int) -> void:
	if not is_instance_valid(state_root) or int(_root_transition_serials.get(state_root, -1)) != serial:
		return
	state_root.visible = false
	for node: Node in state_root.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		particles.amount_ratio = 1.0
	for node: Node in state_root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).transparency = 0.0


func _next_transition_serial(state_root: Node3D) -> int:
	var serial := int(_root_transition_serials.get(state_root, 0)) + 1
	_root_transition_serials[state_root] = serial
	return serial


func _damage_stage_for_health(current_health: float, maximum_health: float) -> int:
	if maximum_health <= 0.0 or current_health <= 0.0:
		return 0
	var ratio := current_health / maximum_health
	if ratio <= 0.25:
		return 25
	if ratio <= 0.5:
		return 50
	if ratio <= 0.75:
		return 75
	return 100


func _set_depleted_pose(should_be_depleted: bool) -> void:
	if _gun_pitch_pivot == null or should_be_depleted == _is_depleted:
		return
	if should_be_depleted:
		_gun_pitch_before_depletion = _gun_pitch_pivot.rotation.z
		_gun_pitch_pivot.rotation.z = deg_to_rad(depleted_gun_depression_degrees)
		_play_depleted_explosion()
	else:
		_gun_pitch_pivot.rotation.z = _gun_pitch_before_depletion
	_is_depleted = should_be_depleted


func _play_depleted_explosion() -> void:
	var explosion := depleted_explosion_scene.instantiate() as Node3D if depleted_explosion_scene != null else null
	if explosion == null or _tank == null:
		push_error("TankDamageVisuals could not instantiate the depleted explosion.")
		return
	explosion.name = "TankDepletedExplosion"
	explosion.set("one_shot", true)
	explosion.set("autoplay", false)
	var host := get_tree().current_scene
	if host == null:
		host = _tank.get_parent()
	host.add_child(explosion, true)
	explosion.global_position = _tank.global_transform * depleted_explosion_local_offset
	explosion.scale = Vector3.ONE * maxf(depleted_explosion_scale, 0.1)
	explosion.set("autoplay", true)
	explosion.call("play")
	get_tree().create_timer(maxf(depleted_explosion_lifetime_seconds, 0.1)).timeout.connect(explosion.queue_free)
