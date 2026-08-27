extends RefCounted
class_name ShotEvent

var _muzzle_transform: Transform3D
var _direction: Vector3
var _shooter_rid: RID

var muzzle_transform: Transform3D:
	get:
		return _muzzle_transform

var direction: Vector3:
	get:
		return _direction

var shooter_rid: RID:
	get:
		return _shooter_rid


func _init(new_muzzle_transform: Transform3D, new_direction: Vector3, new_shooter_rid: RID) -> void:
	_muzzle_transform = new_muzzle_transform
	_direction = new_direction.normalized()
	_shooter_rid = new_shooter_rid


func is_valid() -> bool:
	return _muzzle_transform.is_finite() and not _direction.is_zero_approx() and _shooter_rid.is_valid()


func to_legacy_dictionary() -> Dictionary:
	return {
		"muzzle_transform": _muzzle_transform,
		"shooter_rid": _shooter_rid,
	}
