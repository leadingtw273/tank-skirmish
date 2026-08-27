extends RefCounted
class_name ImpactEvent

var _shot_event: ShotEvent
var _collider: Object
var _position: Vector3
var _normal: Vector3

var shot_event: ShotEvent:
	get:
		return _shot_event

var collider: Object:
	get:
		return _collider

var position: Vector3:
	get:
		return _position

var normal: Vector3:
	get:
		return _normal


func _init(new_shot_event: ShotEvent, new_collider: Object, new_position: Vector3, new_normal: Vector3) -> void:
	_shot_event = new_shot_event
	_collider = new_collider
	_position = new_position
	_normal = new_normal.normalized()


func is_valid() -> bool:
	return _shot_event != null and _shot_event.is_valid() and is_instance_valid(_collider) \
		and _position.is_finite() and _normal.is_finite() and not _normal.is_zero_approx()
