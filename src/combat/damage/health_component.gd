## 保存一個實體的最大與目前血量，並發出血量變更及歸零通知。
## 它不知道受傷來源、命中特效或歸零後要採取的遊戲規則。
extends Node
class_name HealthComponent

signal health_changed(current_health: float, maximum_health: float)
signal depleted

## 此實體的最大血量；進入場景時目前血量會初始化為此值。
@export_range(1.0, 100000.0, 1.0) var maximum_health := 100.0

var _current_health := 0.0

## 唯讀的目前血量。
var current_health: float:
	get:
		return _current_health


func _ready() -> void:
	reset_to_maximum()


## 套用正數傷害並回報是否真的扣到血；血量已歸零時不重複發出 depleted。
func apply_damage(amount: float) -> bool:
	if amount <= 0.0 or _current_health <= 0.0:
		return false
	_current_health = maxf(_current_health - amount, 0.0)
	health_changed.emit(_current_health, maximum_health)
	if is_zero_approx(_current_health):
		depleted.emit()
	return true


## 只把目前血量恢復為最大值，不處理位置、速度或其他實體狀態。
func reset_to_maximum() -> void:
	_current_health = maxf(maximum_health, 1.0)
	health_changed.emit(_current_health, maximum_health)
