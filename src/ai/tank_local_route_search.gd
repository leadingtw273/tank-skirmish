## 有限兩段路候選搜尋；只回傳中繼點，不發出車身或砲塔命令。
extends RefCounted

const MAX_DISTANCE := 60.0
const SAVING_METRES := 2.0
const FRACTIONS := [0.4, 0.6, 0.8, 1.0, 1.2]
const OFFSETS := [4.0, -4.0, 8.0, -8.0, 12.0, -12.0, 16.0, -16.0]

var _candidates: Array[Vector3] = []
var _index := 0
var _goal := Vector3.ZERO
var _stop_distance := 0.0


func begin(start: Vector3, goal: Vector3, stop_distance: float, original_length: float) -> void:
	clear()
	_goal = goal
	_stop_distance = stop_distance
	start.y = 0.0
	goal.y = 0.0
	var axis := goal - start
	if axis.length() > MAX_DISTANCE or axis.is_zero_approx():
		return
	var normal := Vector3(-axis.z, 0.0, axis.x).normalized()
	for fraction in FRACTIONS:
		for offset in OFFSETS:
			var point: Vector3 = start + axis * float(fraction) + normal * float(offset)
			if start.distance_to(point) + point.distance_to(goal) + SAVING_METRES < original_length:
				_candidates.append(point)
	_candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return start.distance_to(a) + a.distance_to(goal) < start.distance_to(b) + b.distance_to(goal))


## 每幀最多一個候選；40個候選結束即回退，不作無界重試。
func step(clearance: RefCounted) -> Dictionary:
	if _index >= _candidates.size():
		return {"status": &"failed"}
	var point := _candidates[_index]
	_index += 1
	if clearance.can_route_via(point, _goal, _stop_distance):
		return {"status": &"found", "point": point}
	return {"status": &"pending"} if _index < _candidates.size() else {"status": &"failed"}


func clear() -> void:
	_candidates.clear()
	_index = 0
	_goal = Vector3.ZERO
	_stop_distance = 0.0
