## Immutable firing data emitted by Tank and consumed by CombatRuntime.
## It describes one muzzle state only; it does not instantiate projectiles or visual effects.
extends RefCounted
class_name ShotEvent

var _muzzle_transform: Transform3D
var _direction: Vector3
var _shooter_rid: RID

## World transform of the muzzle at the moment this shot was requested.
var muzzle_transform: Transform3D:
	get:
		return _muzzle_transform

## Normalized world-space firing direction.
var direction: Vector3:
	get:
		return _direction

## Physics RID to exclude so the projectile cannot immediately hit its firing Tank.
var shooter_rid: RID:
	get:
		return _shooter_rid


func _init(new_muzzle_transform: Transform3D, new_direction: Vector3, new_shooter_rid: RID) -> void:
	_muzzle_transform = new_muzzle_transform
	_direction = new_direction.normalized()
	_shooter_rid = new_shooter_rid


## Returns whether this event contains a finite muzzle transform, direction, and shooter RID.
func is_valid() -> bool:
	return _muzzle_transform.is_finite() and not _direction.is_zero_approx() and _shooter_rid.is_valid()


## Produces the compatibility payload used only by the legacy shot_fired signal.
func to_legacy_dictionary() -> Dictionary:
	return {
		"muzzle_transform": _muzzle_transform,
		"shooter_rid": _shooter_rid,
	}
