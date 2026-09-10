## 管理共用坦克移動、砲塔姿態、射擊事件、履帶動畫與視覺後座。
## 它不會實體化投射物或擁有世界戰鬥容器；CombatRuntime 消費其事件。
extends CharacterBody3D

@export_category("車型介面")
## 派生車型是否已提供完整視覺與動畫接線；TankBase 本身保持關閉。
@export var variant_interface_enabled := false
## 指向派生車型的完整匯入模型根節點。
@export var tank_model: Node3D
## 指向派生車型中要交給共用砲塔樞紐的視覺節點。
@export var tank_turret: Node3D
## 指向派生車型中要交給共用砲管樞紐的視覺節點。
@export var tank_gun: MeshInstance3D
## 匯入砲管模型中由砲尾指向砲口的本地座標軸；多數車型使用 -X，部分車型使用 -Y。
@export var tank_gun_forward_local_axis := Vector3.LEFT
## 指向派生車型的履帶 AnimationPlayer。
@export var tread_animation_player: AnimationPlayer
## 派生車型前進履帶動畫名稱。
@export var tread_forward_animation: StringName
## 派生車型倒車履帶動畫名稱。
@export var tread_backwards_animation: StringName
## 派生車型左轉履帶動畫名稱。
@export var tread_turning_left_animation: StringName
## 派生車型右轉履帶動畫名稱。
@export var tread_turning_right_animation: StringName
## 車型缺少倒車片段時，是否反向播放它提供的直行履帶動畫。
@export var reverse_tread_animation_playback := false
## 車型離線烘焙的真實部位幾何；共用 controller 不保存任何車型節點名稱。
@export var part_geometry: TankPartGeometry

@export_category("坦克視野")
## 車體周圍全向視野的水平半徑，單位公尺；近距也受遮擋限制。
@export_range(0.0, 1000.0, 0.1, "or_greater") var vision_near_radius := 50.0
## 沿砲塔前方的最遠水平視距，從車體中心計算，單位公尺。
@export_range(0.0, 1000.0, 0.1, "or_greater") var vision_far_radius := 150.0
## 遠距扇形的完整水平角度；30 度表示左右各 15 度。
@export_range(0.0, 360.0, 0.1) var vision_field_of_view_degrees := 30.0

@export_category("坦克移動")
## 滿前進輸入時車身的最高速度，單位為公尺／秒。
@export var movement_speed := 15.0
## 滿倒退輸入時車身的最高速度，單位為公尺／秒。
@export var reverse_movement_speed := 5.0
## 滿轉向輸入時車身偏航速度，單位為弧度／秒。
@export var turn_speed := 0.8
## 滿轉向輸入時保留的直線最高速度比例；0.5 代表降至原本的一半。
@export_range(0.0, 1.0, 0.05) var turning_movement_speed_ratio := 0.5
## 每次成功開砲時立即損失的目前前後移動速度比例；0.25 代表損失四分之一。
@export_range(0.0, 1.0, 0.05) var firing_movement_speed_loss_ratio := 0.25
## 坦克用於換算加速反應的質量，單位為公噸。
@export var tank_mass_tonnes := 60.0
## 引擎用於換算加速反應的額定輸出，單位為馬力。
@export var engine_horsepower := 1500.0
## 煞車系統用於換算減速度的最大制動力，單位為千牛頓。
@export var brake_force_kilonewtons := 240.0
## 將線性加減速換算為車身偏航反應的係數，單位為無單位倍率。
@export var turn_response := 0.4
## 在製作好的履帶動畫片段之間混合所用的秒數。
@export var tread_animation_blend_seconds := 0.12
## 履帶動畫以 1 倍速播放時所對應的坦克前後線速度，單位為公尺／秒。
@export_range(0.01, 100.0, 0.01) var tread_animation_reference_speed := 15.0
## 套用於履帶動畫最終播放倍率的微調係數。
@export_range(0.0, 4.0, 0.01) var tread_animation_speed_multiplier := 1.0

@export_category("坦克砲塔")
## 追蹤目標時砲塔的偏航速度，單位為弧度／秒。
@export var turret_turn_speed := 1.777778
## 砲塔／砲管相對車身可左右旋轉的最大角度；180 度代表不限制一般旋轉。
@export_range(0.0, 180.0, 0.5) var turret_max_yaw_degrees := 180.0
## 固定砲塔車型是否在砲管水平尚未對齊時，提供車身輔助轉向意圖。
@export var hull_aim_assist_enabled := false
## 車身輔助瞄準視為水平對齊的最大角差，單位為度。
@export_range(0.0, 5.0, 0.05) var hull_aim_alignment_tolerance_degrees := 0.25

@export_category("坦克砲管")
## 砲管仰角與俯角的追蹤速度，單位為弧度／秒。
@export var gun_pitch_speed := 1.2
## 砲管向上的最大仰角，單位為度。
@export_range(0.0, 45.0, 0.5) var gun_max_elevation_degrees := 20.0
## 砲管向下的最大俯角，單位為度。
@export_range(0.0, 45.0, 0.5) var gun_max_depression_degrees := 8.0

@export_category("視覺後座")
## 僅供視覺呈現、與射擊方向相反的最大後座位移，單位為公尺。
@export var visual_recoil_distance := 0.36
## 視覺坦克模型到達後座位移所需的秒數。
@export var visual_recoil_kick_seconds := 0.04
## 視覺坦克模型回到製作時靜止位置所需的秒數。
@export var visual_recoil_return_seconds := 0.18

@export_category("鏡頭")
## CameraController 可要求的最大游標前視距離，單位為公尺。
@export var max_camera_look_ahead_distance := 30.0

const MODEL_FORWARD_LOCAL_AXIS := Vector3.LEFT
const MIN_AIM_DISTANCE_SQUARED := 0.001
const TREAD_ANIMATION_MOTION_THRESHOLD := 0.01
const CONTACT_TREAD_ANIMATION_SCALE := 0.5
const TankMotionGuard := preload("res://src/actors/tank/geometry/tank_motion_guard.gd")
const TankContactResponse := preload("res://src/actors/tank/geometry/tank_contact_response.gd")
const MUZZLE_FLASH_SCENE := preload("res://src/vfx/muzzle/muzzle_flash_vfx.tscn")
const ShotEvent := preload("res://src/combat/shot_event.gd")
@export_category("坦克戰鬥")
## 每發砲彈命中時造成的傷害，單位為傷害點數；開火後會凍結到 ShotEvent。
@export_range(0.01, 100000.0, 0.01) var shell_damage := 25.0
## 兩次成功開火之間的最短時間，單位為秒；數值越小射速越快，裝填期間不接受或排隊開火。
@export_range(0.01, 60.0, 0.01, "or_greater") var fire_interval_seconds := 1.0
## 剩餘裝填時間依遊戲物理時間遞減；新生成的坦克可以立即開火。
var _fire_cooldown_remaining := 0.0

@export_category("瞄準擴散")
## 靜止時砲彈的圓錐半角，單位為度。
@export_range(0.0, 45.0, 0.01) var aim_spread_base_degrees := 0.2
## 依實際前後速度比例額外增加的圓錐半角，單位為度。
@export_range(0.0, 45.0, 0.01) var aim_spread_movement_add_degrees := 1.5
## 依實際車身偏航速度比例額外增加的圓錐半角，單位為度。
@export_range(0.0, 45.0, 0.01) var aim_spread_turn_add_degrees := 1.0
## 依砲塔相對車身的實際偏航速度比例額外增加的圓錐半角，單位為度。
@export_range(0.0, 45.0, 0.01) var aim_spread_turret_turn_add_degrees := 1.0
## 每次成功開火後加入目前擴散的圓錐半角，單位為度；只影響下一發及後續射擊。
@export_range(0.0, 45.0, 0.01) var aim_spread_fire_add_degrees := 0.2
## 開火額外擴散恢復的速度，單位為度／秒；與移動和轉向擴散分開調整。
@export_range(0.0, 90.0, 0.01) var aim_spread_fire_recovery_degrees_per_second := 0.4
## 擴散圓錐可達到的最大半角，單位為度。
@export_range(0.0, 45.0, 0.01) var aim_spread_cap_degrees := 2.5
## 擴散朝目標增加的速度，單位為度／秒。
@export_range(0.0, 90.0, 0.01) var aim_spread_grow_degrees_per_second := 4.0
## 靜止時擴散朝目標恢復的速度，單位為度／秒。
@export_range(0.0, 90.0, 0.01) var aim_spread_stationary_recovery_degrees_per_second := 1.2
## 移動時擴散朝目標恢復的速度，單位為度／秒。
@export_range(0.0, 90.0, 0.01) var aim_spread_moving_recovery_degrees_per_second := 0.6
## 目前實際套用到每發砲彈的圓錐半角，單位為度。
var current_spread_degrees := 0.2
## 尚未恢復的成功開火額外擴散；不包含移動、車身或砲塔造成的部分。
var _fire_spread_degrees := 0.0
var _aim_spread_rng := RandomNumberGenerator.new()

@export_category("砲口火焰")
## 已生成的砲口火焰在移除前的存活時間，單位為秒。
@export var muzzle_flash_lifetime_seconds := 0.25
## 套用至製作好的砲口火焰特效之等比縮放倍率。
@export var muzzle_flash_scale := 4.0

@onready var visual_recoil_pivot: Node3D = $VisualRecoilPivot
@onready var tank_visual_slot: Node3D = $VisualRecoilPivot/TankVisualSlot
@onready var hull_visual: Node3D = $VisualRecoilPivot/TankVisualSlot/HullVisual
@onready var turret_visual: Node3D = $VisualRecoilPivot/TurretPivot/TurretVisual
@onready var gun_visual: Node3D = $VisualRecoilPivot/TurretPivot/GunPitchPivot/GunVisual
@onready var tank_collision: CollisionShape3D = $CollisionShape3D
@onready var turret_pivot: Node3D = $VisualRecoilPivot/TurretPivot
@onready var gun_pitch_pivot: Node3D = $VisualRecoilPivot/TurretPivot/GunPitchPivot
@onready var muzzle_point: Marker3D = $VisualRecoilPivot/TurretPivot/GunPitchPivot/MuzzlePoint

## 為既有冒煙測試承載舊版 Dictionary 資料載荷的相容性通知。
signal shot_fired(legacy_shot: Dictionary)
## 每次有效開火請求時，供 CombatRuntime 消費的權威射擊通知。
signal shot_event_fired(shot_event: ShotEvent)

var movement_command := 0.0
var turn_command := 0.0
var forward_speed := 0.0
## 僅保存引擎／手動／車身輔助的持續偏航狀態；接觸 auto-yaw 不回寫到此值。
var angular_speed := 0.0
## 碰撞解算後沿坦克前後軸的實際線速度，供接地互動讀取，單位為公尺／秒。
var actual_linear_speed := 0.0
## 物理步驟中實際套用的總車身偏航角速度（含接觸 auto-yaw），供接地互動讀取，單位為弧度／秒。
var actual_angular_speed := 0.0
## 最近一次砲塔瞄準實際套用的相對車身偏航角速度，單位為弧度／秒。
var actual_turret_angular_speed := 0.0
var active_tread_animation := &""
var tread_animation_paused := true
var tread_animations_available := false
var visual_recoil_rest_local_position := Vector3.ZERO
var visual_recoil_tween: Tween
var hull_aim_turn_input := 0.0
var _part_collision_shapes: Array[CollisionShape3D] = []
## 在 bind 時一次保留每個離線 convex 的頂點；旋轉 guard 不會在 physics step 重建 debug mesh。
var _part_shape_vertices: Array[PackedVector3Array] = []
var _hull_anchor_local := Transform3D.IDENTITY
var _turret_anchor_local := Transform3D.IDENTITY
var _gun_anchor_local := Transform3D.IDENTITY
var _motion_guard := TankMotionGuard.new()
var _motion_guard_attempt_stats := {
	&"root": {"query_count": 0, "substeps": 0, "accepted_substeps": 0, "shape_count": 0, "blocked_reason": "no-attempt", "elapsed_usec": 0},
	&"turret": {"query_count": 0, "substeps": 0, "accepted_substeps": 0, "shape_count": 0, "blocked_reason": "no-attempt", "elapsed_usec": 0},
	&"gun": {"query_count": 0, "substeps": 0, "accepted_substeps": 0, "shape_count": 0, "blocked_reason": "no-attempt", "elapsed_usec": 0},
}
## 僅保留當前或前一 physics step 的真實 move_and_slide 接觸；不推動其他 body。
var _contact_records: Array[Dictionary] = []
var _contact_frames_since_contact := 2
var _contact_slide_velocity := Vector3.ZERO
var _contact_manual_turn_active := false
var _contact_auto_yaw_requested := 0.0
var _contact_auto_yaw_applied := 0.0
var _contact_reason := "no-contact"
var _contact_count := 0


func _ready() -> void:
	## 每次實例化都從此車型的 base 值開始，避免重生或場景覆用保留上次交戰擴散。
	current_spread_degrees = clampf(aim_spread_base_degrees, 0.0, maxf(aim_spread_cap_degrees, 0.0))
	_fire_spread_degrees = 0.0
	if not variant_interface_enabled:
		set_physics_process(false)
		return
	if not _has_valid_variant_interface():
		set_physics_process(false)
		return
	## 將匯入模型的砲塔與砲管轉交給常駐樞紐且保持世界姿態，之後才能獨立套用偏航與俯仰。
	visual_recoil_rest_local_position = visual_recoil_pivot.position
	# 匯入的砲塔與砲管保持原樣；常駐場景樞紐在啟動時接手，並保留製作時的世界座標轉換。
	turret_pivot.global_position = tank_turret.global_position
	tank_turret.reparent(turret_visual, true)
	gun_pitch_pivot.global_position = tank_gun.global_position
	tank_gun.reparent(gun_visual, true)
	if not _bind_part_geometry():
		set_physics_process(false)
		return
	var gun_aabb := tank_gun.get_aabb()
	var local_gun_forward := tank_gun_forward_local_axis.normalized()
	var local_muzzle := _aabb_endpoint(gun_aabb, local_gun_forward)
	var world_gun_forward := (tank_gun.global_transform.basis * local_gun_forward).normalized()
	muzzle_point.global_transform = Transform3D(
		_muzzle_basis(world_gun_forward),
		tank_gun.global_transform * local_muzzle,
	)
	_setup_tread_animations()


## 回傳與舊單一碰撞盒相同語意的固定車體中心，不從任一部位 shape 推導。
func stable_world_center() -> Vector3:
	return global_transform * part_geometry.stable_center if part_geometry != null else global_position


## 所有部位凸形在目前 root／砲塔／砲管姿態的世界轉換；Task 2 的候選姿態查詢共用此資料。
func part_shape_world_transforms() -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if part_geometry == null:
		return transforms
	for part in part_geometry.parts:
		var anchor_transform := _current_anchor_transform(part.anchor)
		for local_transform in part.convex_transforms:
			transforms.append(anchor_transform * part.anchor_transform * local_transform)
	return transforms


## 有限可見表面點的固定排序世界座標；不以包圍盒角點冒充模型表面。
func part_world_surface_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	if part_geometry == null:
		return points
	for part in part_geometry.parts:
		var part_transform := _current_anchor_transform(part.anchor) * part.anchor_transform
		for point in part.surface_points:
			points.append(part_transform * point)
	return points


## 使用完整凸形頂點的保守世界 bounds；與最多十二個 surface samples 分離。
func part_world_bounds() -> AABB:
	var has_point := false
	var minimum := Vector3.ZERO
	var maximum := Vector3.ZERO
	if part_geometry == null:
		return AABB()
	for part in part_geometry.parts:
		var part_transform := _current_anchor_transform(part.anchor) * part.anchor_transform
		for index in part.convex_shapes.size():
			var shape := part.convex_shapes[index]
			var shape_transform := part_transform * part.convex_transforms[index]
			for point in shape.points:
				var world_point := shape_transform * point
				if not has_point:
					minimum = world_point
					maximum = world_point
					has_point = true
				else:
					minimum = minimum.min(world_point)
					maximum = maximum.max(world_point)
	return AABB(minimum, maximum - minimum) if has_point else AABB()


## Task 2 可用的候選 root transform 入口；gun_pitch 是正仰角（等於 -GunPitchPivot.rotation.z）。
func candidate_part_shape_world_transforms(candidate_root: Transform3D, turret_yaw: float, gun_pitch: float) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if part_geometry == null:
		return transforms
	var hull_anchor := candidate_root * _hull_anchor_local
	var turret_anchor := candidate_root * _turret_anchor_local.rotated_local(Vector3.UP, turret_yaw)
	var gun_anchor := turret_anchor * _gun_anchor_local.rotated_local(Vector3.FORWARD, gun_pitch)
	for part in part_geometry.parts:
		var anchor_transform := hull_anchor if part.anchor == "hull" else turret_anchor if part.anchor == "turret" else gun_anchor
		for local_transform in part.convex_transforms:
			transforms.append(anchor_transform * part.anchor_transform * local_transform)
	return transforms


func _bind_part_geometry() -> bool:
	if part_geometry == null or not part_geometry.is_valid_geometry():
		push_error("Tank variant requires valid offline part geometry.")
		return false
	_hull_anchor_local = global_transform.affine_inverse() * _mechanical_global_transform(tank_model.global_transform)
	_turret_anchor_local = global_transform.affine_inverse() * _mechanical_global_transform(turret_pivot.global_transform)
	_gun_anchor_local = turret_pivot.global_transform.affine_inverse() * gun_pitch_pivot.global_transform
	for shape_node in _part_collision_shapes:
		shape_node.queue_free()
	_part_collision_shapes.clear()
	_part_shape_vertices.clear()
	var shape_index := 0
	for part in part_geometry.parts:
		for convex_index in part.convex_shapes.size():
			var collision := tank_collision if shape_index == 0 else CollisionShape3D.new()
			if shape_index > 0:
				collision.name = "PartCollision_%s_%d" % [part.id, convex_index]
				add_child(collision)
			collision.shape = part.convex_shapes[convex_index]
			_part_collision_shapes.append(collision)
			_part_shape_vertices.append(_convex_debug_vertices(part.convex_shapes[convex_index]))
			shape_index += 1
	_sync_part_collision_shapes()
	return not _part_collision_shapes.is_empty()


func _convex_debug_vertices(shape: ConvexPolygonShape3D) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	var debug_mesh := shape.get_debug_mesh()
	if debug_mesh == null or debug_mesh.get_surface_count() == 0:
		return vertices
	var arrays := debug_mesh.surface_get_arrays(0)
	var raw_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in raw_vertices:
		if not vertices.has(vertex):
			vertices.append(vertex)
	return vertices


func _current_anchor_transform(anchor: String) -> Transform3D:
	match anchor:
		"hull":
			return _mechanical_global_transform(tank_model.global_transform)
		"turret":
			return _mechanical_global_transform(turret_pivot.global_transform)
		"gun":
			return _mechanical_global_transform(gun_pitch_pivot.global_transform)
	return global_transform


func _mechanical_global_transform(visual_global: Transform3D) -> Transform3D:
	## 所有 visual anchor 都在 VisualRecoilPivot 下；移除當前 tween 位移並回復其靜止 transform。
	var current_recoil := Transform3D(visual_recoil_pivot.basis, visual_recoil_pivot.position)
	var rest_recoil := Transform3D(visual_recoil_pivot.basis, visual_recoil_rest_local_position)
	return global_transform * rest_recoil * current_recoil.affine_inverse() * global_transform.affine_inverse() * visual_global


func _sync_part_collision_shapes() -> void:
	if part_geometry == null:
		return
	var shape_index := 0
	for part in part_geometry.parts:
		var anchor_transform := _current_anchor_transform(part.anchor)
		for local_transform in part.convex_transforms:
			if shape_index >= _part_collision_shapes.size():
				return
			_part_collision_shapes[shape_index].global_transform = anchor_transform * part.anchor_transform * local_transform
			shape_index += 1


## 僅供 Task 2 fixture 讀取最近一筆 root／turret／gun guard 計數；不會逐幀輸出。
func get_motion_guard_attempt_stats(kind: StringName) -> Dictionary:
	return (_motion_guard_attempt_stats.get(kind, _empty_motion_guard_stats("unknown-kind")) as Dictionary).duplicate(true)


func _empty_motion_guard_stats(reason: String) -> Dictionary:
	return {
		"query_count": 0,
		"substeps": 0,
		"accepted_substeps": 0,
		"shape_count": 0,
		"blocked_reason": reason,
		"elapsed_usec": 0,
	}


func _record_motion_guard_noop(kind: StringName) -> void:
	_motion_guard_attempt_stats[kind] = _empty_motion_guard_stats("no-op")


func _attempt_rotation_guard(
	kind: StringName,
	angle_delta: float,
	affected_anchors: Array[StringName],
	pivot: Vector3,
	candidate_transforms_at_fraction: Callable,
) -> float:
	if is_zero_approx(angle_delta):
		_record_motion_guard_noop(kind)
		return 0.0
	var start_transforms := part_shape_world_transforms()
	var shapes: Array[Dictionary] = []
	var shape_index := 0
	for part in part_geometry.parts:
		for convex_index in part.convex_shapes.size():
			if part.anchor in affected_anchors:
				if shape_index >= start_transforms.size() or shape_index >= _part_shape_vertices.size():
					_motion_guard_attempt_stats[kind] = _empty_motion_guard_stats("invalid-shape-cache")
					return 0.0
				var radius := 0.0
				for local_vertex in _part_shape_vertices[shape_index]:
					radius = maxf(radius, pivot.distance_to(start_transforms[shape_index] * local_vertex))
				shapes.append({
					"shape": part.convex_shapes[convex_index],
					"start_transform": start_transforms[shape_index],
					"radius": radius,
				})
			shape_index += 1
	if shapes.is_empty() or get_world_3d() == null:
		_motion_guard_attempt_stats[kind] = _empty_motion_guard_stats("no-affected-shapes")
		return 0.0
	_motion_guard.configure(get_world_3d().direct_space_state, get_rid(), collision_mask, get_tree().get_node_count())
	var result := _motion_guard.attempt(angle_delta, shapes, candidate_transforms_at_fraction)
	_motion_guard_attempt_stats[kind] = (result.stats as Dictionary).duplicate(true)
	return float(result.actual_angle)


func _candidate_transforms_for_anchors(
	candidate_root: Transform3D,
	candidate_turret_yaw: float,
	candidate_gun_pitch: float,
	affected_anchors: Array[StringName],
) -> Array[Transform3D]:
	var all_transforms := candidate_part_shape_world_transforms(candidate_root, candidate_turret_yaw, candidate_gun_pitch)
	var selected: Array[Transform3D] = []
	var shape_index := 0
	for part in part_geometry.parts:
		for unused in part.convex_shapes:
			if part.anchor in affected_anchors:
				selected.append(all_transforms[shape_index])
			shape_index += 1
	return selected


func _aabb_endpoint(bounds: AABB, direction: Vector3) -> Vector3:
	## 依車型提供的主要本地軸，取得砲管包圍盒最前端，而不是假設所有模型都沿 -X 建模。
	var endpoint := bounds.get_center()
	var bounds_end := bounds.position + bounds.size
	var absolute_direction := direction.abs()
	if absolute_direction.x >= absolute_direction.y and absolute_direction.x >= absolute_direction.z:
		endpoint.x = bounds_end.x if direction.x > 0.0 else bounds.position.x
	elif absolute_direction.y >= absolute_direction.z:
		endpoint.y = bounds_end.y if direction.y > 0.0 else bounds.position.y
	else:
		endpoint.z = bounds_end.z if direction.z > 0.0 else bounds.position.z
	return endpoint


func _muzzle_basis(world_forward: Vector3) -> Basis:
	## MuzzlePoint 固定以本地 -X 表示射擊方向，同時移除匯入模型可能帶入的非均勻縮放。
	var x_axis := -world_forward
	var up_hint := Vector3.UP
	if absf(x_axis.dot(up_hint)) > 0.99:
		up_hint = Vector3.FORWARD
	var z_axis := x_axis.cross(up_hint).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _has_valid_variant_interface() -> bool:
	## 車型差異只允許出現在派生場景的 NodePath 與動畫映射；共用層只檢查固定介面是否完整。
	if (
		tank_visual_slot == null
		or hull_visual == null
		or turret_visual == null
		or gun_visual == null
		or turret_pivot == null
		or gun_pitch_pivot == null
		or muzzle_point == null
		or tank_model == null
		or tank_turret == null
		or tank_gun == null
		or not tank_gun_forward_local_axis.is_finite()
		or tank_gun_forward_local_axis.is_zero_approx()
		or tread_animation_player == null
	):
		push_error("Tank variant interface is incomplete.")
		return false
	for clip: StringName in _tread_animation_clips().values():
		if clip.is_empty():
			push_error("Tank variant interface requires four tread animation mappings.")
			return false
	return true


func _physics_process(delta: float) -> void:
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)
	## 以動力與煞車積分線／角速度，碰撞後讀回實際線速度，再讓履帶依實際動態更新。
	var engine_acceleration := _engine_acceleration()
	var brake_acceleration := _brake_acceleration()
	var movement_speed_limit := _movement_speed_limit_for_turn(movement_command, turn_command)
	forward_speed = _approach_motion_speed(
		forward_speed,
		movement_command,
		movement_speed_limit,
		engine_acceleration,
		brake_acceleration,
		delta,
		true,
	)
	angular_speed = _approach_motion_speed(
		angular_speed,
		turn_command,
		turn_speed,
		engine_acceleration * turn_response,
		brake_acceleration * turn_response,
		delta,
	)
	var forward_direction := transform.basis * MODEL_FORWARD_LOCAL_AXIS
	var contact_normals := _contact_active_normals()
	## 接觸 auto-yaw 必須依旋轉前的意圖決定，避免本幀已旋轉姿態回饋進候選角度。
	var pre_rotation_intent_direction := _contact_intent_direction(forward_direction)
	var auto_yaw_gain := _contact_response_gain(pre_rotation_intent_direction, contact_normals)
	var auto_yaw_rate := _contact_auto_yaw_rate(pre_rotation_intent_direction, contact_normals, auto_yaw_gain)
	var base_requested_root_angle := angular_speed * delta
	_contact_auto_yaw_requested = 0.0
	if not _contact_manual_turn_active and is_zero_approx(turn_command) and is_zero_approx(hull_aim_turn_input):
		_contact_auto_yaw_requested = auto_yaw_rate * delta
	var requested_root_angle := base_requested_root_angle + _contact_auto_yaw_requested
	var root_candidate := func(fraction: float) -> Array[Transform3D]:
		return _candidate_transforms_for_anchors(
			global_transform.rotated_local(Vector3.UP, requested_root_angle * fraction),
			turret_pivot.rotation.y,
			-gun_pitch_pivot.rotation.z,
			[&"hull", &"turret", &"gun"],
		)
	var actual_root_angle := _attempt_rotation_guard(
		&"root",
		requested_root_angle,
		[&"hull", &"turret", &"gun"],
		global_position,
		root_candidate,
	)
	rotate_y(actual_root_angle)
	_contact_auto_yaw_applied = _contact_auto_yaw_requested * (actual_root_angle / requested_root_angle) if not is_zero_approx(requested_root_angle) else 0.0
	## 持續角速度排除本幀 guard 成功套用的接觸 auto-yaw；真實角速度仍保留完整總旋轉。
	angular_speed = (actual_root_angle - _contact_auto_yaw_applied) / delta if delta > 0.0 else 0.0
	actual_angular_speed = actual_root_angle / delta if delta > 0.0 else 0.0
	_sync_part_collision_shapes()
	## 旋轉完成後，移動、滑移與真實速度量測一律使用新車頭方向。
	forward_direction = transform.basis * MODEL_FORWARD_LOCAL_AXIS
	var intent_direction := _contact_intent_direction(forward_direction)
	var contact_gain := _contact_response_gain(intent_direction, contact_normals)
	velocity = forward_direction * forward_speed
	if not contact_normals.is_empty() and contact_gain > 0.0:
		var target_slide := Vector3.ZERO
		for normal in contact_normals:
			target_slide += TankContactResponse.slide_target(intent_direction, normal, movement_speed_limit, movement_command, contact_gain)
		target_slide = TankContactResponse.remove_inward_components(target_slide, contact_normals)
		var slide_speed_cap := maxf(movement_speed_limit, 0.0) * absf(movement_command) * TankContactResponse.SLIDE_SPEED_RATIO
		target_slide = target_slide.limit_length(slide_speed_cap)
		var response_rate := engine_acceleration if not target_slide.is_zero_approx() else brake_acceleration
		_contact_slide_velocity = _contact_slide_velocity.move_toward(target_slide, response_rate * delta)
		_contact_slide_velocity = TankContactResponse.remove_inward_components(_contact_slide_velocity, contact_normals)
		_contact_slide_velocity = _contact_slide_velocity.limit_length(slide_speed_cap)
		velocity.x = _contact_slide_velocity.x
		velocity.z = _contact_slide_velocity.z
		_contact_reason = "sliding-contact"
	else:
		_contact_slide_velocity = Vector3.ZERO
		if contact_normals.is_empty():
			_contact_reason = "no-active-contact"
		elif _contact_intent_pushes_inward(intent_direction, contact_normals):
			## 正面死區已確認接觸時不可把完整前進速度交回 move_and_slide，否則仍會沿牆滑動。
			velocity.x = 0.0
			velocity.z = 0.0
			_contact_reason = "dead-zone-blocked"
		else:
			_contact_reason = "dead-zone-or-outward"
	move_and_slide()
	var actual_forward_speed := get_real_velocity().dot(forward_direction)
	_capture_contact_records()
	if get_slide_collision_count() > 0 or _contact_frames_since_contact <= 1:
		forward_speed = actual_forward_speed
	actual_linear_speed = actual_forward_speed
	update_aim_spread(delta, actual_linear_speed, actual_angular_speed, actual_turret_angular_speed)
	var next_tread_animation := _tread_animation_for_motion(actual_forward_speed, actual_angular_speed)
	_update_tread_animation(
		next_tread_animation,
		_tread_animation_speed_scale(next_tread_animation, actual_forward_speed, actual_angular_speed),
	)


## 回傳碰撞解算後沿坦克前後軸的實際線速度，供 TrackContactEffects 計算接地互動強度。
func get_actual_linear_speed() -> float:
	return actual_linear_speed


## 回傳物理步驟實際套用的車身偏航角速度，供 TrackContactEffects 計算原地旋轉強度。
func get_actual_angular_speed() -> float:
	return actual_angular_speed


## 回傳最近一次瞄準實際套用的砲塔相對車身偏航角速度，單位為弧度／秒。
func get_actual_turret_angular_speed() -> float:
	return actual_turret_angular_speed


## 回傳目前每發砲彈實際使用的圓錐半角，單位為度。
func get_current_spread_degrees() -> float:
	return current_spread_degrees


## 回傳以目前碰撞解算後的線／角速度計算的目標圓錐半角，單位為度。
func get_target_spread_degrees() -> float:
	return calculate_target_spread_degrees(actual_linear_speed, actual_angular_speed, actual_turret_angular_speed)


## 設定私有亂數器種子，僅供可重現的自動測試使用。
func set_aim_spread_seed(seed_value: int) -> void:
	_aim_spread_rng.seed = seed_value


## 以傳入的實際線／角速度計算目標擴散，供測試直接覆蓋物理輸入。
func calculate_target_spread_degrees(
	measured_linear_speed: float,
	measured_angular_speed: float,
	measured_turret_angular_speed := 0.0,
) -> float:
	var cap := maxf(aim_spread_cap_degrees, 0.0)
	var base := clampf(aim_spread_base_degrees, 0.0, cap)
	var linear_top_speed := movement_speed if measured_linear_speed >= 0.0 else reverse_movement_speed
	var speed_ratio := 0.0 if linear_top_speed <= 0.0 else clampf(absf(measured_linear_speed) / linear_top_speed, 0.0, 1.0)
	var turn_ratio := 0.0 if turn_speed <= 0.0 else clampf(absf(measured_angular_speed) / turn_speed, 0.0, 1.0)
	var turret_turn_ratio := 0.0 if turret_turn_speed <= 0.0 else clampf(absf(measured_turret_angular_speed) / turret_turn_speed, 0.0, 1.0)
	return minf(cap, base + maxf(aim_spread_movement_add_degrees, 0.0) * speed_ratio \
		+ maxf(aim_spread_turn_add_degrees, 0.0) * turn_ratio \
		+ maxf(aim_spread_turret_turn_add_degrees, 0.0) * turret_turn_ratio)


## 依 delta 朝實際速度對應的目標擴散逼近，供物理更新與單元測試共用。
func update_aim_spread(
	delta: float,
	measured_linear_speed: float,
	measured_angular_speed: float,
	measured_turret_angular_speed := 0.0,
) -> void:
	var cap := maxf(aim_spread_cap_degrees, 0.0)
	var target := calculate_target_spread_degrees(measured_linear_speed, measured_angular_speed, measured_turret_angular_speed)
	var step_delta := maxf(delta, 0.0)
	var total_spread := clampf(current_spread_degrees, 0.0, cap)
	var fire_spread := clampf(_fire_spread_degrees, 0.0, total_spread)
	var motion_spread := total_spread - fire_spread
	if motion_spread < target:
		motion_spread = move_toward(motion_spread, target, maxf(aim_spread_grow_degrees_per_second, 0.0) * step_delta)
	else:
		var linear_top_speed := movement_speed if measured_linear_speed >= 0.0 else reverse_movement_speed
		var speed_ratio := 0.0 if linear_top_speed <= 0.0 else clampf(absf(measured_linear_speed) / linear_top_speed, 0.0, 1.0)
		var recovery_rate := lerpf(
			maxf(aim_spread_stationary_recovery_degrees_per_second, 0.0),
			maxf(aim_spread_moving_recovery_degrees_per_second, 0.0),
			speed_ratio,
		)
		motion_spread = move_toward(motion_spread, target, recovery_rate * step_delta)
	fire_spread = move_toward(
		fire_spread,
		0.0,
		maxf(aim_spread_fire_recovery_degrees_per_second, 0.0) * step_delta,
	)
	_fire_spread_degrees = clampf(fire_spread, 0.0, maxf(cap - motion_spread, 0.0))
	current_spread_degrees = clampf(motion_spread + _fire_spread_degrees, 0.0, cap)


## 在砲口方向的圓錐內均勻取樣立體角，回傳本發砲彈的世界座標彈道方向。
func sample_shot_direction(muzzle_direction: Vector3) -> Vector3:
	var normalized_muzzle_direction := muzzle_direction.normalized()
	if normalized_muzzle_direction.is_zero_approx():
		return Vector3.ZERO
	var half_angle := deg_to_rad(clampf(current_spread_degrees, 0.0, maxf(aim_spread_cap_degrees, 0.0)))
	if is_zero_approx(half_angle):
		return normalized_muzzle_direction
	var cosine_theta := lerpf(cos(half_angle), 1.0, _aim_spread_rng.randf())
	var sine_theta := sqrt(maxf(0.0, 1.0 - cosine_theta * cosine_theta))
	var azimuth := _aim_spread_rng.randf_range(0.0, TAU)
	var muzzle_basis := _basis_with_x_axis(normalized_muzzle_direction)
	return (normalized_muzzle_direction * cosine_theta + muzzle_basis.y * cos(azimuth) * sine_theta \
		+ muzzle_basis.z * sin(azimuth) * sine_theta).normalized()


## 儲存介於 -1 到 1 的前進／倒退指令，供下一個物理步驟使用。
func set_movement_input(input_value: float) -> void:
	movement_command = clampf(input_value, -1.0, 1.0)


## 儲存介於 -1 到 1 的車身轉向指令，供下一個物理步驟使用。
func set_turn_input(input_value: float) -> void:
	turn_command = clampf(input_value, -1.0, 1.0)


## PlayerController 提供的 A/D 來源通知；AI 不讀鍵盤且維持 false。
func set_manual_turn_active(active: bool) -> void:
	_contact_manual_turn_active = active


## 控制停用或換車時清除短暫接觸資料，避免離牆後殘留反應。
func clear_contact_response_state() -> void:
	_contact_records.clear()
	_contact_frames_since_contact = 2
	_contact_slide_velocity = Vector3.ZERO
	_contact_manual_turn_active = false
	_contact_auto_yaw_requested = 0.0
	_contact_auto_yaw_applied = 0.0
	_contact_count = 0
	_contact_reason = "cleared"


## 僅供有限 smoke 讀取最近一次接觸反應；不逐幀輸出。
func get_contact_response_stats() -> Dictionary:
	return {
		"active": _contact_frames_since_contact <= 1 and not _contact_records.is_empty(),
		"contact_count": _contact_count,
		"auto_yaw_requested": _contact_auto_yaw_requested,
		"auto_yaw_applied": _contact_auto_yaw_applied,
		"slide_velocity": _contact_slide_velocity,
		"reason": _contact_reason,
	}


func _contact_active_normals() -> Array[Vector3]:
	var normals: Array[Vector3] = []
	if _contact_frames_since_contact > 1:
		return normals
	for record in _contact_records:
		var normal := TankContactResponse.horizontal_normal(record.normal as Vector3)
		if not normal.is_zero_approx() and not normals.has(normal):
			normals.append(normal)
	return normals


func _contact_intent_direction(forward_direction: Vector3) -> Vector3:
	if is_zero_approx(movement_command):
		return Vector3.ZERO
	var horizontal := Vector3(forward_direction.x, 0.0, forward_direction.z)
	return horizontal.normalized() * signf(movement_command) if not horizontal.is_zero_approx() else Vector3.ZERO


func _contact_response_gain(intent_direction: Vector3, normals: Array[Vector3]) -> float:
	var gain := 0.0
	for normal in normals:
		gain = maxf(gain, TankContactResponse.response_gain(intent_direction, normal))
	return gain


func _contact_intent_pushes_inward(intent_direction: Vector3, normals: Array[Vector3]) -> bool:
	if intent_direction.is_zero_approx():
		return false
	for normal in normals:
		if intent_direction.dot(normal) < -TankContactResponse.HORIZONTAL_EPSILON:
			return true
	return false


func _contact_auto_yaw_rate(intent_direction: Vector3, normals: Array[Vector3], gain: float) -> float:
	if intent_direction.is_zero_approx() or normals.is_empty() or gain <= 0.0:
		return 0.0
	var radius := _contact_conservative_radius()
	var moment := 0.0
	for record in _contact_records:
		var normal := TankContactResponse.horizontal_normal(record.normal as Vector3)
		if normal.is_zero_approx():
			continue
		moment += TankContactResponse.auto_yaw_moment(record.position as Vector3, stable_world_center(), normal, intent_direction, movement_command, radius, gain)
	return clampf(moment, -1.0, 1.0) * minf(deg_to_rad(12.0), turn_speed * 0.35)


func _contact_conservative_radius() -> float:
	if part_geometry == null:
		return 1.0
	var radius := 0.0
	for transform in part_shape_world_transforms():
		radius = maxf(radius, stable_world_center().distance_to(transform.origin))
	return maxf(radius, 0.001)


func _capture_contact_records() -> void:
	var captured: Array[Dictionary] = []
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var normal := TankContactResponse.horizontal_normal(collision.get_normal())
		if normal.is_zero_approx():
			continue
		captured.append({"position": collision.get_position(), "normal": normal, "rid": collision.get_collider_rid()})
	if captured.is_empty():
		_contact_frames_since_contact += 1
		if _contact_frames_since_contact > 1:
			_contact_records.clear()
	else:
		_contact_records = captured
		_contact_frames_since_contact = 0
	_contact_count = _contact_records.size()


## 回傳供 CameraController 使用且不為負值的鏡頭前視上限，單位為公尺。
func get_max_camera_look_ahead_distance() -> float:
	return maxf(max_camera_look_ahead_distance, 0.0)


func _engine_acceleration() -> float:
	## 依遊戲化馬力／質量換算直線加速度，單位為公尺／秒平方。
	return engine_horsepower / tank_mass_tonnes * 0.08


func _brake_acceleration() -> float:
	## 依制動力／質量換算煞車減速度，單位為公尺／秒平方。
	return brake_force_kilonewtons / tank_mass_tonnes


func _braking_distance(speed: float) -> float:
	## 回傳以目前煞車減速度估計的煞停距離，單位為公尺。
	return speed * speed / (2.0 * _brake_acceleration())


func _movement_speed_limit_for_turn(movement_input: float, turn_input: float) -> float:
	## 依目前前進或倒退指令選擇速度上限，再依轉向輸入強度平滑降低；滿轉向時使用 Inspector 設定的保留比例。
	var turn_strength := clampf(absf(turn_input), 0.0, 1.0)
	var base_speed_limit := movement_speed if movement_input >= 0.0 else reverse_movement_speed
	return base_speed_limit * lerpf(1.0, turning_movement_speed_ratio, turn_strength)


func _apply_firing_movement_speed_loss() -> void:
	## 成功開砲的當下只削減線速度；保留前後方向，且不影響車身角速度。
	var retained_speed_ratio := 1.0 - clampf(firing_movement_speed_loss_ratio, 0.0, 1.0)
	forward_speed *= retained_speed_ratio
	velocity *= retained_speed_ratio


func _approach_motion_speed(
		current_speed: float,
		input_direction: float,
		maximum_speed: float,
	acceleration: float,
	braking_acceleration: float,
	delta: float,
	brake_when_above_limit: bool = false,
) -> float:
	## 依輸入漸進逼近目標；反向先煞停，線速度超過轉彎上限時可選擇以煞車反應降速。
	if is_zero_approx(input_direction) or (not is_zero_approx(current_speed) and signf(current_speed) != signf(input_direction)):
		return move_toward(current_speed, 0.0, braking_acceleration * delta)
	var target_speed := input_direction * maximum_speed
	var response := braking_acceleration if brake_when_above_limit and absf(current_speed) > absf(target_speed) else acceleration
	return move_toward(current_speed, target_speed, response * delta)


func _setup_tread_animations() -> void:
	## 使用派生車型明確提供的播放器與片段映射，避免共用層依賴素材內部命名。
	if tread_animation_player == null:
		push_error("Tank tread animation setup failed: the variant has no AnimationPlayer.")
		return

	for clip: StringName in _tread_animation_clips().values():
		var animation: Animation = tread_animation_player.get_animation(clip)
		if animation == null:
			push_error("Tank tread animation setup failed: missing clip %s." % clip)
			return
		animation.loop_mode = Animation.LOOP_LINEAR

	tread_animations_available = true


func _tread_animation_clips() -> Dictionary:
	return {
		"forward": tread_forward_animation,
		"backwards": tread_backwards_animation,
		"turning_left": tread_turning_left_animation,
		"turning_right": tread_turning_right_animation,
	}


func _tread_animation_for_motion(actual_forward_speed: float, actual_angular_speed: float) -> StringName:
	## 以實際角速度優先選擇履帶片段，僅在線／角速度高於門檻時持續播放。
	if absf(actual_angular_speed) > TREAD_ANIMATION_MOTION_THRESHOLD:
		return tread_turning_left_animation if actual_angular_speed > 0.0 else tread_turning_right_animation
	if actual_forward_speed > TREAD_ANIMATION_MOTION_THRESHOLD:
		return tread_forward_animation
	if actual_forward_speed < -TREAD_ANIMATION_MOTION_THRESHOLD:
		return tread_backwards_animation
	return &""


func _tread_animation_speed_scale(next_animation: StringName, actual_forward_speed: float, actual_angular_speed: float = 0.0) -> float:
	## 直行依縮小後的實際線速度與 Inspector 基準速度播放；轉向依實際角速度與最高偏航速度同步。
	## 接觸緩移僅減少履帶視覺繞動，不改真實位移、接觸反應或散布輸入。
	var visual_multiplier := tread_animation_speed_multiplier * (CONTACT_TREAD_ANIMATION_SCALE if _contact_reason == "sliding-contact" else 1.0)
	if absf(actual_angular_speed) > TREAD_ANIMATION_MOTION_THRESHOLD:
		return absf(actual_angular_speed) / maxf(absf(turn_speed), 0.001) * visual_multiplier
	var speed_scale := absf(actual_forward_speed) / tread_animation_reference_speed * visual_multiplier
	if reverse_tread_animation_playback and actual_forward_speed < 0.0:
		return -speed_scale
	return speed_scale


func _update_tread_animation(next_animation: StringName, animation_speed_scale: float = 1.0) -> void:
	## 只在狀態改變時交給播放器混合；靜止則暫停而不重設目前影格，恢復時可延續既有片段。
	if not tread_animations_available or tread_animation_player == null:
		return
	tread_animation_player.speed_scale = animation_speed_scale
	if next_animation.is_empty():
		if not tread_animation_paused:
			tread_animation_player.pause()
			tread_animation_paused = true
		return
	if next_animation == active_tread_animation:
		if tread_animation_paused:
			tread_animation_player.play()
			tread_animation_paused = false
		return

	tread_animation_player.play(next_animation, tread_animation_blend_seconds)
	active_tread_animation = next_animation
	tread_animation_paused = false


## 取消控制端的瞄準意圖，保留目前姿態；供失去視野或停用控制時使用。
func cancel_aim() -> void:
	actual_turret_angular_speed = 0.0
	_record_motion_guard_noop(&"turret")
	hull_aim_turn_input = 0.0


## 在此影格中只將砲塔偏航轉向世界座標目標。
func aim_turret_at(target_position: Vector3, delta: float) -> void:
	actual_turret_angular_speed = 0.0
	if _is_target_inside_turret_dead_zone(target_position):
		hull_aim_turn_input = 0.0
		_record_motion_guard_noop(&"turret")
		return
	var target_direction := target_position - turret_pivot.global_position
	target_direction.y = 0.0
	if target_direction.length_squared() <= MIN_AIM_DISTANCE_SQUARED:
		hull_aim_turn_input = 0.0
		_record_motion_guard_noop(&"turret")
		return

	var maximum_yaw := deg_to_rad(clampf(turret_max_yaw_degrees, 0.0, 180.0))
	var previous_local_yaw := turret_pivot.rotation.y
	if maximum_yaw < PI:
		## 固定砲塔車型只讓砲管相對車身小幅左右擺動，不追蹤完整世界方位。
		var local_target_direction := global_transform.basis.orthonormalized().inverse() * target_direction
		var desired_local_target_yaw := atan2(local_target_direction.z, -local_target_direction.x)
		var limited_local_target_yaw := clampf(desired_local_target_yaw, -maximum_yaw, maximum_yaw)
		var requested_local_yaw := rotate_toward(turret_pivot.rotation.y, limited_local_target_yaw, turret_turn_speed * delta)
		var requested_turret_angle := requested_local_yaw - previous_local_yaw
		var fixed_turret_candidate := func(fraction: float) -> Array[Transform3D]:
			return _candidate_transforms_for_anchors(
				global_transform,
				previous_local_yaw + requested_turret_angle * fraction,
				-gun_pitch_pivot.rotation.z,
				[&"turret", &"gun"],
			)
		var actual_turret_angle := _attempt_rotation_guard(
			&"turret",
			requested_turret_angle,
			[&"turret", &"gun"],
			turret_pivot.global_position,
			fixed_turret_candidate,
		)
		turret_pivot.rotation.y = previous_local_yaw + actual_turret_angle
		_record_actual_turret_angular_speed(previous_local_yaw, delta)
		_update_hull_aim_turn_input(desired_local_target_yaw)
		_sync_part_collision_shapes()
		return

	hull_aim_turn_input = 0.0
	var target_yaw := atan2(target_direction.z, -target_direction.x)
	var previous_world_yaw := turret_pivot.global_rotation.y
	var requested_world_yaw := rotate_toward(previous_world_yaw, target_yaw, turret_turn_speed * delta)
	var requested_turret_angle := angle_difference(previous_world_yaw, requested_world_yaw)
	var world_turret_candidate := func(fraction: float) -> Array[Transform3D]:
		return _candidate_transforms_for_anchors(
			global_transform,
			previous_local_yaw + requested_turret_angle * fraction,
			-gun_pitch_pivot.rotation.z,
			[&"turret", &"gun"],
		)
	var actual_turret_angle := _attempt_rotation_guard(
		&"turret",
		requested_turret_angle,
		[&"turret", &"gun"],
		turret_pivot.global_position,
		world_turret_candidate,
	)
	turret_pivot.global_rotation.y = previous_world_yaw + actual_turret_angle
	_record_actual_turret_angular_speed(previous_local_yaw, delta)
	_sync_part_collision_shapes()


func _record_actual_turret_angular_speed(previous_local_yaw: float, delta: float) -> void:
	if delta <= 0.0:
		return
	actual_turret_angular_speed = angle_difference(previous_local_yaw, turret_pivot.rotation.y) / delta


func _update_hull_aim_turn_input(local_target_yaw: float) -> void:
	## 車身只補水平角差；砲管已對齊就立即停止，不要求砲管回到中央。
	if not hull_aim_assist_enabled:
		hull_aim_turn_input = 0.0
		return
	var horizontal_error := angle_difference(turret_pivot.rotation.y, local_target_yaw)
	var tolerance := deg_to_rad(maxf(hull_aim_alignment_tolerance_degrees, 0.0))
	hull_aim_turn_input = 0.0 if absf(horizontal_error) <= tolerance else signf(horizontal_error)


## 回傳固定砲塔車型目前要求的車身轉向意圖；未啟用或已對齊時為 0。
func get_hull_aim_turn_input() -> float:
	return hull_aim_turn_input if hull_aim_assist_enabled else 0.0


## 供玩家或 AI 輔助瞄準在對齊或被抑制時立即清除既有車身旋轉慣性。
func stop_hull_aim_turn() -> void:
	turn_command = 0.0
	angular_speed = 0.0
	actual_angular_speed = 0.0


func _target_gun_pitch_for_world_target(target_position: Vector3) -> float:
	## 以砲口到目標的水平距離和高度差求仰角，再限制在製作時設定的俯仰範圍。
	if _is_target_inside_turret_dead_zone(target_position):
		return -gun_pitch_pivot.rotation.z
	var target_direction := target_position - muzzle_global_position()
	var horizontal_distance := Vector2(target_direction.x, target_direction.z).length()
	if horizontal_distance * horizontal_distance + target_direction.y * target_direction.y <= MIN_AIM_DISTANCE_SQUARED:
		return -gun_pitch_pivot.rotation.z
	var target_pitch := atan2(target_direction.y, horizontal_distance)
	return clampf(
		target_pitch,
		-deg_to_rad(maxf(gun_max_depression_degrees, 0.0)),
		deg_to_rad(maxf(gun_max_elevation_degrees, 0.0)),
	)


func _is_target_inside_turret_dead_zone(target_position: Vector3) -> bool:
	## 只比較水平 XZ 距離；目標太靠近砲塔時不更新姿態，避免方位與仰角在零向量附近跳動。
	var offset := target_position - turret_pivot.global_position
	return Vector2(offset.x, offset.z).length_squared() <= 9.0


## 在仰角限制內，只將砲管俯仰轉向世界座標目標。
func aim_gun_pitch_at_target(target_position: Vector3, delta: float) -> void:
	var minimum_pitch := -deg_to_rad(maxf(gun_max_depression_degrees, 0.0))
	var maximum_pitch := deg_to_rad(maxf(gun_max_elevation_degrees, 0.0))
	var current_pitch := -gun_pitch_pivot.rotation.z
	var target_pitch := _target_gun_pitch_for_world_target(target_position)
	var next_pitch := move_toward(current_pitch, target_pitch, maxf(gun_pitch_speed, 0.0) * maxf(delta, 0.0))
	var requested_pitch_angle := clampf(next_pitch, minimum_pitch, maximum_pitch) - current_pitch
	var gun_candidate := func(fraction: float) -> Array[Transform3D]:
		return _candidate_transforms_for_anchors(
			global_transform,
			turret_pivot.rotation.y,
			current_pitch + requested_pitch_angle * fraction,
			[&"gun"],
		)
	var actual_pitch_angle := _attempt_rotation_guard(
		&"gun",
		requested_pitch_angle,
		[&"gun"],
		gun_pitch_pivot.global_position,
		gun_candidate,
	)
	gun_pitch_pivot.rotation.z = -(current_pitch + actual_pitch_angle)
	_sync_part_collision_shapes()


## 回傳 MuzzlePoint 目前的世界座標投射物起點。
func muzzle_global_position() -> Vector3:
	return muzzle_point.global_position


## 回傳沿 MuzzlePoint 本地 -X 軸的正規化世界座標射擊方向。
func muzzle_global_direction() -> Vector3:
	return (-muzzle_point.global_transform.basis.x).normalized()


## 當連接有效時，發出一個 ShotEvent、舊版相容性資料載荷、砲口火焰與視覺後座。
func request_fire() -> void:
	if _fire_cooldown_remaining > 0.0:
		return
	if gun_pitch_pivot == null or muzzle_point == null:
		push_error("Tank cannot fire: MuzzlePoint wiring is missing.")
		return
	var muzzle_position := muzzle_global_position()
	var muzzle_direction := muzzle_global_direction()
	if muzzle_direction.is_zero_approx():
		push_error("Tank cannot fire: MuzzlePoint has no valid forward direction.")
		return

	_fire_cooldown_remaining = maxf(0.01, fire_interval_seconds)
	_apply_firing_movement_speed_loss()
	_spawn_muzzle_flash(muzzle_position, muzzle_direction)
	var shot_muzzle_transform := muzzle_point.global_transform
	var shot_direction := sample_shot_direction(muzzle_direction)
	var shot_event := ShotEvent.new(shot_muzzle_transform, shot_direction, get_rid(), shell_damage)
	shot_event_fired.emit(shot_event)
	shot_fired.emit(shot_event.to_legacy_dictionary())
	var cap := maxf(aim_spread_cap_degrees, 0.0)
	var old_total := clampf(current_spread_degrees, 0.0, cap)
	var new_total := clampf(old_total + maxf(aim_spread_fire_add_degrees, 0.0), 0.0, cap)
	_fire_spread_degrees = clampf(_fire_spread_degrees, 0.0, old_total) + maxf(new_total - old_total, 0.0)
	current_spread_degrees = new_total
	_play_visual_recoil(muzzle_direction)


func _play_visual_recoil(muzzle_direction: Vector3) -> void:
	## 將世界座標的反射擊方向轉回車身本地座標，使後座會隨車身朝向移動且不影響實際碰撞。
	if visual_recoil_pivot == null:
		push_error("Tank visual recoil requires a VisualRecoilPivot.")
		return
	if visual_recoil_tween != null and visual_recoil_tween.is_valid():
		visual_recoil_tween.kill()
	visual_recoil_pivot.position = visual_recoil_rest_local_position
	var local_recoil_direction := global_transform.basis.inverse() * -muzzle_direction.normalized()
	var recoil_target := visual_recoil_rest_local_position + local_recoil_direction * maxf(visual_recoil_distance, 0.0)
	visual_recoil_tween = create_tween()
	visual_recoil_tween.tween_property(visual_recoil_pivot, "position", recoil_target, maxf(visual_recoil_kick_seconds, 0.0))
	visual_recoil_tween.tween_property(visual_recoil_pivot, "position", visual_recoil_rest_local_position, maxf(visual_recoil_return_seconds, 0.0))
	visual_recoil_tween.tween_callback(_reset_visual_recoil)


func _reset_visual_recoil() -> void:
	## Tween 被中斷或完成後都回寫製作時的本地靜止位置，避免視覺模型累積偏移。
	visual_recoil_pivot.position = visual_recoil_rest_local_position


func _spawn_muzzle_flash(muzzle_position: Vector3, muzzle_direction: Vector3) -> void:
	## 將一次性特效掛到砲口以承接生命週期，仍以世界座標快照定位並由計時器在壽命結束後釋放。
	var muzzle_flash := MUZZLE_FLASH_SCENE.instantiate() as Node3D
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.set("one_shot", true)
	muzzle_flash.set("autoplay", true)
	muzzle_point.add_child(muzzle_flash, true)
	var flash_basis := _basis_with_x_axis(muzzle_direction).scaled(Vector3.ONE * muzzle_flash_scale)
	muzzle_flash.global_transform = Transform3D(flash_basis, muzzle_position)
	get_tree().create_timer(muzzle_flash_lifetime_seconds).timeout.connect(muzzle_flash.queue_free)


func _basis_with_x_axis(x_axis: Vector3) -> Basis:
	## 讓素材的本地 X 軸對齊砲口方向；接近垂直時改用後方軸建立穩定的正交座標系。
	var normalized_x := x_axis.normalized()
	var reference_up := Vector3.UP if absf(normalized_x.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var z_axis := normalized_x.cross(reference_up).normalized()
	var y_axis := z_axis.cross(normalized_x).normalized()
	return Basis(normalized_x, y_axis, z_axis)
