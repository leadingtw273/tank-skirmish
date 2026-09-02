## 由坦克發出、供 CombatRuntime 消費的不可變射擊資料。
## 它只描述一次砲口狀態；不會實體化投射物或視覺特效。
extends RefCounted
class_name ShotEvent

var _muzzle_transform: Transform3D
var _direction: Vector3
var _shooter_rid: RID
var _damage: float

## 請求這次射擊當下砲口的世界座標轉換。
var muzzle_transform: Transform3D:
	get:
		return _muzzle_transform

## 正規化的世界座標射擊方向。
var direction: Vector3:
	get:
		return _direction

## 要排除的物理 RID，避免投射物立即命中發射它的坦克。
var shooter_rid: RID:
	get:
		return _shooter_rid

## 開火當下凍結的傷害值；投射物只攜帶此快照，不自行決定傷害。
var damage: float:
	get:
		return _damage


func _init(
	new_muzzle_transform: Transform3D,
	new_direction: Vector3,
	new_shooter_rid: RID,
	new_damage: float = 25.0,
) -> void:
	## 建構時立即正規化射擊方向，讓事件消費端可直接以砲口當下的世界座標快照建立投射物。
	_muzzle_transform = new_muzzle_transform
	_direction = new_direction.normalized()
	_shooter_rid = new_shooter_rid
	_damage = new_damage


## 回傳此事件是否包含有限的砲口座標轉換、方向與射手 RID。
func is_valid() -> bool:
	return _muzzle_transform.is_finite() and not _direction.is_zero_approx() \
		and _shooter_rid.is_valid() and _damage > 0.0


## 產生僅供舊版 shot_fired signal 使用的相容性資料載荷。
func to_legacy_dictionary() -> Dictionary:
	return {
		"muzzle_transform": _muzzle_transform,
		"shooter_rid": _shooter_rid,
	}
