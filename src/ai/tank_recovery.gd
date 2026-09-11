## 只處理有限次受阻恢復，不尋找捷徑、不直接改載具物理。
extends RefCounted

const STUCK_SECONDS := 3.0
const PROGRESS_METRES := 0.5
const PROGRESS_RADIANS := deg_to_rad(3.0)
const MAX_ATTEMPTS := 2
const REVERSE_METRES := 2.0
const REVERSE_SECONDS := 2.0
const REVERSE_SPEED := 1.5
const STOP_SPEED := 0.1

var phase: StringName = &"normal"
var attempts := 0
var _elapsed := 0.0
var _origin := Vector3.ZERO
var _forward := Vector3.LEFT


func reset(position := Vector3.ZERO, forward := Vector3.LEFT) -> void:
	phase = &"normal"
	attempts = 0
	reset_progress(position, forward)


func reset_progress(position: Vector3, forward: Vector3) -> void:
	_elapsed = 0.0
	_origin = position
	_forward = forward


func observe(position: Vector3, forward: Vector3, movement: float, turn: float, delta: float) -> void:
	if phase != &"normal":
		return
	if absf(movement) <= 0.05 and absf(turn) <= 0.05:
		reset_progress(position, forward)
		return
	if position.distance_to(_origin) >= PROGRESS_METRES or forward.angle_to(_forward) >= PROGRESS_RADIANS:
		reset_progress(position, forward)
		return
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= STUCK_SECONDS:
		if attempts >= MAX_ATTEMPTS:
			phase = &"blocked"
		else:
			attempts += 1
			phase = &"braking"
		_elapsed = 0.0


## 回傳空字典表示正常導航；replan 只在一次倒車後停穩時送出一次。
func drive(position: Vector3, forward: Vector3, speed: float, reverse_limit: float, deceleration: float, delta: float) -> Dictionary:
	if phase == &"normal":
		return {}
	if phase == &"blocked":
		return {"movement": 0.0, "turn": 0.0, "status": &"stuck"}
	var command := {"movement": 0.0, "turn": 0.0, "status": &"recovering"}
	if phase == &"braking":
		if absf(speed) <= STOP_SPEED:
			phase = &"reversing"
			reset_progress(position, forward)
	elif phase == &"reversing":
		_elapsed += maxf(delta, 0.0)
		var remaining := maxf(REVERSE_METRES - position.distance_to(_origin), 0.0)
		var stopping_distance := speed * speed / (2.0 * maxf(deceleration, 0.001))
		if remaining <= stopping_distance + 0.1 or _elapsed >= REVERSE_SECONDS:
			phase = &"settling"
		else:
			command.movement = -clampf(REVERSE_SPEED / maxf(reverse_limit, 0.01), 0.0, 1.0)
	elif phase == &"settling" and absf(speed) <= STOP_SPEED:
		phase = &"normal"
		reset_progress(position, forward)
		command.replan = true
	return command
