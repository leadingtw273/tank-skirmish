## 描述一次投射物碰撞、供 CombatRuntime 呈現的不可變資料。
## 它只承載碰撞事實；不會生成特效或變更被命中的碰撞器。
extends RefCounted
class_name ImpactEvent

var _shot_event: ShotEvent
var _collider: Object
var _position: Vector3
var _normal: Vector3

## 造成此次命中的完整射擊資料。
var shot_event: ShotEvent:
	get:
		return _shot_event

## 被投射物射線命中的物理物件。
var collider: Object:
	get:
		return _collider

## 世界座標中的碰撞點，單位為公尺。
var position: Vector3:
	get:
		return _position

## 碰撞點上正規化的世界座標表面法線。
var normal: Vector3:
	get:
		return _normal


func _init(new_shot_event: ShotEvent, new_collider: Object, new_position: Vector3, new_normal: Vector3) -> void:
	## 在碰撞當下凍結射擊、碰撞器與世界座標資料，並正規化法線讓後續特效位移具有固定尺度。
	_shot_event = new_shot_event
	_collider = new_collider
	_position = new_position
	_normal = new_normal.normalized()


## 回傳每項必要的碰撞事實是否都可供戰鬥消費端使用。
func is_valid() -> bool:
	return _shot_event != null and _shot_event.is_valid() and is_instance_valid(_collider) \
		and _position.is_finite() and _normal.is_finite() and not _normal.is_zero_approx()
