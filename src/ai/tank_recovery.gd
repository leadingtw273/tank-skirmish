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
const ESCAPE_ANGLE := deg_to_rad(30.0)
const ALIGN_TOLERANCE := deg_to_rad(3.0)
const TURN_SECONDS := 3.0
const ESCAPE_METRES := 2.0
const ESCAPE_SECONDS := 2.5
const STOP_ANGULAR_SPEED := 0.02

var phase: StringName = &"normal"
var attempts := 0
var _elapsed := 0.0
var _origin := Vector3.ZERO
var _forward := Vector3.LEFT
var _escape_forward := Vector3.ZERO
var _observed_escape_forward := Vector3.ZERO


func reset(position := Vector3.ZERO, forward := Vector3.LEFT) -> void:
	phase = &"normal"
	attempts = 0
	_escape_forward = Vector3.ZERO
	reset_progress(position, forward)


func reset_progress(position: Vector3, forward: Vector3) -> void:
	_elapsed = 0.0
	_origin = position
	_forward = forward
	_observed_escape_forward = Vector3.ZERO


func observe(position: Vector3, forward: Vector3, movement: float, turn: float, delta: float, contacts: Array[Dictionary] = [], allow_heading_progress: bool = true) -> void:
	if phase != &"normal":
		return
	if absf(movement) <= 0.05 and absf(turn) <= 0.05:
		reset_progress(position, forward)
		return
	var observed := _choose_escape_forward(position, forward, contacts)
	# 預測介入的原地調向不能反覆洗掉停滯計時；正常路徑轉向仍算進展。
	if position.distance_to(_origin) >= PROGRESS_METRES or (allow_heading_progress and forward.angle_to(_forward) >= PROGRESS_RADIANS):
		reset_progress(position, forward)
		_observed_escape_forward = observed
		return
	if not observed.is_zero_approx():
		## 保存本次無進展觀測窗中的接觸；物理碰撞不保證每幀都回報。
		_observed_escape_forward = observed
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= STUCK_SECONDS:
		if attempts >= MAX_ATTEMPTS:
			phase = &"blocked"
		else:
			attempts += 1
			phase = &"braking"
			_escape_forward = _observed_escape_forward
		_elapsed = 0.0


## 回傳空字典表示正常導航；側轉與前移完成並停穩後才交回原生導航。
func drive(position: Vector3, forward: Vector3, speed: float, reverse_limit: float, deceleration: float, delta: float, forward_limit: float = 15.0, angular_speed: float = 0.0) -> Dictionary:
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
		if _escape_forward.is_zero_approx():
			_finish_attempt(position, forward, command)
		else:
			phase = &"turning"
			_elapsed = 0.0
	elif phase == &"turning":
		_elapsed += maxf(delta, 0.0)
		var error := forward.signed_angle_to(_escape_forward, Vector3.UP)
		if _elapsed >= TURN_SECONDS:
			## 另一側也被阻擋時不強行前進；停穩後交回導航，保留有限次數。
			phase = &"escape_settling"
		elif absf(error) <= ALIGN_TOLERANCE:
			phase = &"align_settling"
			_elapsed = 0.0
		elif absf(speed) <= STOP_SPEED:
			command.turn = clampf(error / ESCAPE_ANGLE, -0.5, 0.5)
	elif phase == &"align_settling":
		_elapsed += maxf(delta, 0.0)
		if _elapsed >= TURN_SECONDS:
			phase = &"escape_settling"
		elif absf(speed) <= STOP_SPEED and absf(angular_speed) <= STOP_ANGULAR_SPEED:
			phase = &"advancing"
			reset_progress(position, forward)
	elif phase == &"advancing":
		_elapsed += maxf(delta, 0.0)
		var remaining := maxf(ESCAPE_METRES - position.distance_to(_origin), 0.0)
		var stopping_distance := speed * speed / (2.0 * maxf(deceleration, 0.001))
		var error := forward.signed_angle_to(_escape_forward, Vector3.UP)
		if remaining <= stopping_distance + 0.1 or _elapsed >= ESCAPE_SECONDS or absf(error) > deg_to_rad(10.0):
			phase = &"escape_settling"
		else:
			command.movement = clampf(REVERSE_SPEED / maxf(forward_limit, 0.01), 0.0, 1.0)
			command.turn = clampf(error / ESCAPE_ANGLE, -0.3, 0.3)
	elif phase == &"escape_settling" and absf(speed) <= STOP_SPEED and absf(angular_speed) <= STOP_ANGULAR_SPEED:
		_finish_attempt(position, forward, command)
	return command


func _finish_attempt(position: Vector3, forward: Vector3, command: Dictionary) -> void:
	phase = &"normal"
	_escape_forward = Vector3.ZERO
	reset_progress(position, forward)
	command.replan = true


func _choose_escape_forward(position: Vector3, forward: Vector3, contacts: Array[Dictionary]) -> Vector3:
	var side := Vector3.UP.cross(forward).normalized()
	var strongest := 0.0
	var away := 0.0
	var point_strength := 0.0
	var point_away := 0.0
	for contact in contacts:
		var normal: Vector3 = contact.get("normal", Vector3.ZERO)
		normal.y = 0.0
		if normal.is_zero_approx() or normal.normalized().dot(forward) > 0.1:
			continue
		## 側牆直接取外法線；正面牆角則由接觸點位於左／右履帶判斷避開方向。
		var lateral := normal.normalized().dot(side)
		if absf(lateral) > strongest:
			strongest = absf(lateral)
			away = signf(lateral)
		var point: Vector3 = contact.get("position", position)
		var point_side := -(point - position).dot(side)
		if absf(point_side) > point_strength:
			point_strength = absf(point_side)
			point_away = signf(point_side)
	## 真正的側牆法線優先；不能讓公尺單位的接觸點偏移蓋過單位法線。
	if strongest < 0.1:
		if point_strength < 0.1:
			return Vector3.ZERO
		away = point_away
	return forward.rotated(Vector3.UP, away * ESCAPE_ANGLE).normalized()
