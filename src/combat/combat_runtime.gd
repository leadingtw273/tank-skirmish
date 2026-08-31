## 將坦克射擊事件轉為投射物，並將投射物命中轉為暫時性的世界特效。
## 它只擁有執行期的戰鬥子節點；不會決定坦克的開火時機或控制玩家輸入。
extends Node3D
class_name CombatRuntime

const PROJECTILE_SCENE := preload("res://src/combat/projectile.tscn")
const IMPACT_VFX_SCENE := preload("res://src/vfx/impacts/impact_explosion_vfx.tscn")
const MUZZLE_SMOKE_VFX_SCENE := preload("res://src/vfx/muzzle/muzzle_smoke_vfx.tscn")
const TankProjectile := preload("res://src/combat/projectile.gd")
const ShotEvent := preload("res://src/combat/shot_event.gd")
const ImpactEvent := preload("res://src/combat/impact_event.gd")
@export_category("場景連接")
## 會發出公開 shot_event_fired signal、供此戰鬥執行期消費的節點。
@export var shot_sources: Array[Node]
## 接收執行期 TankProjectile 節點的父節點。
@export var projectiles: Node3D
## 接收暫時性命中特效節點的父節點。
@export var effects: Node3D

@export_category("命中呈現")
## 命中爆炸特效的等比例尺寸倍率；1.0 代表 wrapper 製作時大小。
@export_range(0.1, 10.0, 0.05) var impact_vfx_scale := 1.0
## 已實體化的命中特效在移除前的存活時間，單位為秒。
@export var impact_vfx_lifetime_seconds := 1.3
## 沿命中法線的偏移量，單位為公尺，用來避免視覺特效穿入表面。
@export var impact_vfx_surface_offset := 0.05

@export_category("砲口硝煙")
## 砲口硝煙的均勻尺寸倍率，單位為原廠特效比例倍數。
@export_range(0.1, 5.0, 0.05) var muzzle_smoke_scale := 1.0
## 砲口硝煙沿 ShotEvent 射擊方向的前方偏移量，單位為公尺。
@export var muzzle_smoke_forward_offset := 0.9
## 已實體化砲口硝煙在釋放前的存活時間，單位為秒。
@export var muzzle_smoke_lifetime_seconds := 1.2

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
	_spawn_muzzle_smoke(shot_event)


func _spawn_muzzle_smoke(shot_event: ShotEvent) -> void:
	## 以 ShotEvent 的世界座標快照建立一次性硝煙，使它由 Effects 擁有且不跟隨射擊坦克移動。
	var muzzle_smoke := MUZZLE_SMOKE_VFX_SCENE.instantiate() as Node3D
	if muzzle_smoke == null:
		push_error("CombatRuntime could not instantiate muzzle_smoke_vfx.tscn.")
		return
	muzzle_smoke.name = "MuzzleSmokeVFX"
	var smoke_particles := muzzle_smoke.get_node_or_null("SmokeBigVFX_01/Smoke") as GPUParticles3D
	var source_process_material := smoke_particles.process_material as ParticleProcessMaterial if smoke_particles != null else null
	if smoke_particles == null or source_process_material == null:
		push_error("CombatRuntime requires MuzzleSmokeVFX to provide Smoke particles with a ParticleProcessMaterial.")
		muzzle_smoke.queue_free()
		return
	## 每次開火各自持有運動材質，讓煙霧用世界射擊方向移動；面片仍可獨立完整面向攝影機。
	var smoke_process_material := source_process_material.duplicate(true) as ParticleProcessMaterial
	smoke_process_material.direction = shot_event.direction
	smoke_particles.process_material = smoke_process_material
	smoke_particles.one_shot = true
	effects.add_child(muzzle_smoke, true)
	var smoke_position := shot_event.muzzle_transform.origin + shot_event.direction * muzzle_smoke_forward_offset
	var smoke_basis := Basis.IDENTITY.scaled(Vector3.ONE * muzzle_smoke_scale)
	muzzle_smoke.global_transform = Transform3D(smoke_basis, smoke_position)
	## One Shot 播放結束後會自行把 Emitting 切回 false；每次生成時由執行期明確重新播放。
	smoke_particles.restart()
	get_tree().create_timer(muzzle_smoke_lifetime_seconds).timeout.connect(muzzle_smoke.queue_free)


func _on_projectile_impact(impact_event: ImpactEvent) -> void:
	## 命中特效沿世界座標表面法線微移，避免穿模，並由 SceneTree 計時器在播放後釋放。
	if impact_event == null or not impact_event.is_valid():
		return
	var impact := IMPACT_VFX_SCENE.instantiate() as Node3D
	impact.name = "ImpactVFX"
	impact.set("one_shot", true)
	## 先停用自動播放，避免 GPU 粒子在命中位置與尺寸套用前就以原始倍率發射。
	impact.set("autoplay", false)
	effects.add_child(impact, true)
	_apply_impact_vfx_scale(impact, impact_vfx_scale)
	impact.global_position = impact_event.position + impact_event.normal * impact_vfx_surface_offset
	impact.set("autoplay", true)
	impact.call("play")
	get_tree().create_timer(impact_vfx_lifetime_seconds).timeout.connect(impact.queue_free)


func _apply_impact_vfx_scale(impact: Node3D, scale_factor: float) -> void:
	## GPUParticles3D 不繼承父節點縮放；逐一複製並縮放本次爆炸的網格與運動材質，避免污染 vendor 資源。
	for child in impact.get_children():
		var particles := child as GPUParticles3D
		if particles == null:
			continue
		var scaled_mesh := particles.draw_pass_1.duplicate(true) as Mesh if particles.draw_pass_1 != null else null
		if scaled_mesh is SphereMesh:
			var sphere := scaled_mesh as SphereMesh
			var original_radius := sphere.radius
			var original_height := sphere.height
			if scale_factor >= 1.0:
				sphere.height = original_height * scale_factor
				sphere.radius = original_radius * scale_factor
			else:
				sphere.radius = original_radius * scale_factor
				sphere.height = original_height * scale_factor
		elif scaled_mesh is QuadMesh:
			var quad := scaled_mesh as QuadMesh
			quad.size *= scale_factor
		if scaled_mesh != null:
			particles.draw_pass_1 = scaled_mesh
		var scaled_motion := particles.process_material.duplicate(true) as ParticleProcessMaterial \
				if particles.process_material is ParticleProcessMaterial else null
		if scaled_motion != null:
			scaled_motion.initial_velocity_min *= scale_factor
			scaled_motion.initial_velocity_max *= scale_factor
			scaled_motion.damping_min *= scale_factor
			scaled_motion.damping_max *= scale_factor
			scaled_motion.gravity *= scale_factor
			particles.process_material = scaled_motion
	var decal := impact.get_node_or_null("Decal") as Decal
	if decal != null:
		decal.size *= scale_factor
	var light := impact.get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.omni_range *= scale_factor
		light.light_size *= scale_factor


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	## 依射擊方向建立正交基底供特效與投射物朝向本地 X 軸；近乎垂直時切換參考上軸避免退化。
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
