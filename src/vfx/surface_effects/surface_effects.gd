## 擁有世界層地表互動的持續特效；不辨識載具類型或地表材質。
extends Node3D

const TREAD_DUST_SCENE := preload("res://src/vfx/tread_dust/tread_dust_vfx.tscn")

@export_category("履帶煙塵")
## 套用至每個接地點煙塵的等比粒子尺寸倍率。
@export_range(0.1, 4.0, 0.05) var tread_dust_scale := 0.85
## 接觸停止後，既有煙塵自然散去所需的秒數。
@export_range(0.1, 5.0, 0.05) var tread_dust_lifetime_seconds := 1.2
## 滿運動強度時，每個接地點持續維持的粒子數量。
@export_range(2, 128, 1) var tread_dust_emission_amount := 28
## 實際線速度或角速度達到此值時才讓已接地的發射器產生新煙塵。
@export_range(0.01, 5.0, 0.01) var tread_dust_activation_speed := 0.15
## 沿命中地表法線將煙塵抬高的距離，避免粒子生成時嵌入碰撞表面。
@export_range(0.0, 1.0, 0.01) var surface_normal_offset := 0.05

var _emitters: Dictionary[String, Node3D] = {}


## 消費 TrackContactEffects 的通用接地回報；每個來源與接地點只會建立一個可重複更新的發射器。
func consume_track_contact(
		source_id: StringName,
		contact_id: StringName,
		active: bool,
		world_position: Vector3,
		ground_normal: Vector3,
		intensity: float,
		_source_velocity: Vector3,
		source_motion_speed: float,
) -> void:
	var emitter_key := _emitter_key(source_id, contact_id)
	var emitter := _emitters.get(emitter_key) as Node3D
	if not active:
		if emitter != null and is_instance_valid(emitter):
			emitter.call("set_motion_intensity", 0.0)
		return
	if emitter == null or not is_instance_valid(emitter):
		emitter = _create_emitter(source_id, contact_id)
		if emitter == null:
			return
	var resolved_normal := ground_normal.normalized() if not ground_normal.is_zero_approx() else Vector3.UP
	emitter.global_position = world_position + resolved_normal * maxf(surface_normal_offset, 0.0)
	emitter.call("set_dust_parameters", tread_dust_scale, tread_dust_lifetime_seconds, tread_dust_emission_amount)
	var emission_intensity := clampf(intensity, 0.0, 1.0) if source_motion_speed >= tread_dust_activation_speed else 0.0
	emitter.call("set_motion_intensity", emission_intensity)


## 回傳既有持續發射器，供場景整合測試確認接地點不會在每個物理幀重新建立。
func get_emitter(source_id: StringName, contact_id: StringName) -> Node3D:
	return _emitters.get(_emitter_key(source_id, contact_id)) as Node3D


func _create_emitter(source_id: StringName, contact_id: StringName) -> Node3D:
	var emitter := TREAD_DUST_SCENE.instantiate() as Node3D
	if emitter == null:
		push_error("SurfaceEffects could not instantiate tread_dust_vfx.tscn.")
		return null
	emitter.name = "TrackDust_%s_%s" % [source_id, contact_id]
	add_child(emitter, true)
	_emitters[_emitter_key(source_id, contact_id)] = emitter
	return emitter


func _emitter_key(source_id: StringName, contact_id: StringName) -> String:
	return "%s:%s" % [source_id, contact_id]
