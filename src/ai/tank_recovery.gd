## 有限次受阻恢復；物理查詢與導航交接由 Predictor／Navigation 擁有。
extends RefCounted

const STUCK_SECONDS := 3.0
const PROGRESS_METRES := .5
const PROGRESS_RADIANS := deg_to_rad(3.0)
const MAX_ATTEMPTS := 3
const ATTEMPT_SECONDS := 16.0
const REVERSE_METRES := 2.0
const REVERSE_SECONDS := 2.0
const REVERSE_SPEED := 1.5
const STOP_SPEED := .1
const ESCAPE_ANGLE := deg_to_rad(30.0)
const ALIGN_TOLERANCE := deg_to_rad(3.0)
const TURN_SECONDS := 7.0
const ESCAPE_METRES := 2.0
const ESCAPE_SECONDS := 2.5
const STOP_ANGULAR_SPEED := .02

var phase: StringName = &"normal"
var attempts := 0
var blocked_origin := Vector3.ZERO
var blocked_forward := Vector3.LEFT
var escape_heading := Vector3.ZERO
var advance_origin := Vector3.ZERO
var positive_advance := 0.0
var rejoin_reason: StringName = &""
var episode_active := false
var confirmation_active := false
var confirmation_elapsed := 0.0
var confirmation_origin := Vector3.ZERO
var _elapsed := 0.0
var _attempt_elapsed := 0.0
var _origin := Vector3.ZERO
var _forward := Vector3.LEFT
var _observed_side := 0.0
var _attempt_side := 1.0
var _failed_heading := Vector3.ZERO

func reset(position := Vector3.ZERO, forward := Vector3.LEFT) -> void:
	phase = &"normal"; attempts = 0; blocked_origin = position; blocked_forward = forward
	escape_heading = Vector3.ZERO; advance_origin = Vector3.ZERO; positive_advance = 0.0; rejoin_reason = &""; _failed_heading = Vector3.ZERO; _attempt_side = 1.0
	episode_active = false; interrupt_confirmation(position)
	reset_progress(position, forward)


func cancel_action_preserving_episode(position: Vector3, forward: Vector3) -> void:
	phase = &"normal"; escape_heading = Vector3.ZERO; advance_origin = Vector3.ZERO; positive_advance = 0.0
	_attempt_elapsed = 0.0; _failed_heading = Vector3.ZERO; _attempt_side = 1.0
	interrupt_confirmation(position)
	reset_progress(position, forward)


func interrupt_confirmation(position := Vector3.ZERO) -> void:
	confirmation_active = false; confirmation_elapsed = 0.0; confirmation_origin = position


func observe_confirmation(position: Vector3, nominal_movement: float, contacts: Array[Dictionary], predictor_contact: bool, intervened: bool, delta: float) -> void:
	if not episode_active or phase != &"normal" or nominal_movement <= .05 or not contacts.is_empty() or predictor_contact or intervened:
		interrupt_confirmation(position)
		return
	if not confirmation_active:
		confirmation_active = true; confirmation_origin = position; confirmation_elapsed = 0.0
	confirmation_elapsed += maxf(delta, 0.0)
	if confirmation_elapsed >= STUCK_SECONDS and _horizontal_distance(position, confirmation_origin) >= PROGRESS_METRES:
		attempts = 0; episode_active = false; _failed_heading = Vector3.ZERO; _attempt_side = 1.0; interrupt_confirmation(position)

func reset_progress(position: Vector3, forward: Vector3) -> void:
	_elapsed = 0.0; _origin = position; _forward = forward; _observed_side = 0.0

func observe(position: Vector3, forward: Vector3, movement: float, turn: float, delta: float, contacts: Array[Dictionary] = [], allow_heading_progress := true) -> void:
	if phase != &"normal": return
	if absf(movement) <= .05 and absf(turn) <= .05: reset_progress(position, forward); return
	var preferred_side := _preferred_side(position, forward, contacts)
	if not is_zero_approx(preferred_side): _observed_side = preferred_side
	if position.distance_to(_origin) >= PROGRESS_METRES or (allow_heading_progress and forward.angle_to(_forward) >= PROGRESS_RADIANS):
		reset_progress(position, forward)
		if not is_zero_approx(preferred_side): _observed_side = preferred_side
		return
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= STUCK_SECONDS: _start_attempt(position, forward)

func needs_escape_selection() -> bool: return phase == &"selecting_escape"
func escape_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for side in [_attempt_side, -_attempt_side]:
		for angle in [ESCAPE_ANGLE, ESCAPE_ANGLE * 2.0]:
			var heading := blocked_forward.rotated(Vector3.UP, side * angle).normalized()
			if _failed_heading.is_zero_approx() or heading.angle_to(_failed_heading) > ALIGN_TOLERANCE: result.append({"side": side, "angle": angle})
	return result
func select_escape(candidate: Dictionary) -> void:
	escape_heading = blocked_forward.rotated(Vector3.UP, float(candidate.get("side", _attempt_side)) * float(candidate.get("angle", ESCAPE_ANGLE))).normalized()
	phase = &"turning"; _elapsed = 0.0
func handoff_ready() -> bool: return phase == &"rejoining" and positive_advance >= PROGRESS_METRES
func accept_handoff(reason: StringName, position := advance_origin) -> void:
	rejoin_reason = reason; phase = &"normal"; escape_heading = Vector3.ZERO; interrupt_confirmation(position); reset_progress(position, blocked_forward)
func reject_handoff(reason: StringName, position: Vector3, forward: Vector3) -> void: rejoin_reason = reason; _fail_attempt(position, forward)
func escape_profile_state() -> Dictionary:
	return {"heading":escape_heading,"phase":phase,"advance_origin":advance_origin,"positive_advance":positive_advance,
		"phase_elapsed":_elapsed,"attempt_elapsed":_attempt_elapsed}

## 真車與 staged profile 共用；期限與可觀測狀態由呼叫端持有。
static func escape_action(current: StringName, forward: Vector3, heading: Vector3, speed: float, angular: float, advance: float, deceleration: float, forward_limit: float) -> Dictionary:
	var error := forward.signed_angle_to(heading, Vector3.UP)
	if current == &"turning": return {"phase": &"align_settling" if absf(error) <= ALIGN_TOLERANCE else &"turning", "movement": 0.0, "turn": clampf(error / ESCAPE_ANGLE, -.5, .5)}
	if current == &"align_settling": return {"phase": &"advancing" if absf(speed) <= STOP_SPEED and absf(angular) <= STOP_ANGULAR_SPEED else &"align_settling", "movement": 0.0, "turn": 0.0}
	if current == &"advancing":
		if ESCAPE_METRES - advance <= speed * speed / (2.0 * maxf(deceleration,.001)) + .1 or absf(error) > deg_to_rad(10.0): return {"phase": &"escape_settling", "movement": 0.0, "turn": 0.0}
		return {"phase": &"advancing", "movement": clampf(REVERSE_SPEED / maxf(forward_limit,.01),0.0,1.0), "turn": clampf(error / ESCAPE_ANGLE,-.3,.3)}
	if current == &"escape_settling": return {"phase": &"rejoining" if absf(speed) <= STOP_SPEED and absf(angular) <= STOP_ANGULAR_SPEED else &"escape_settling", "movement": 0.0, "turn": 0.0}
	return {"phase": current, "movement": 0.0, "turn": 0.0}

## 真車與 Predictor 的唯一 escape phase/deadline transition。attempt_elapsed 已包含本 frame delta；
## 回傳的 phase_elapsed 則在這裡只累加一次，呼叫端不可再次計時。
static func escape_transition(current: StringName, phase_elapsed: float, attempt_elapsed: float, forward: Vector3,
		heading: Vector3, speed: float, angular: float, advance: float, deceleration: float,
		forward_limit: float, delta: float) -> Dictionary:
	if attempt_elapsed >= ATTEMPT_SECONDS:
		return {"phase":current,"phase_elapsed":phase_elapsed,"movement":0.0,"turn":0.0,"failed":true}
	var elapsed := phase_elapsed + maxf(delta, 0.0)
	if current == &"turning" and elapsed >= TURN_SECONDS:
		return {"phase":current,"phase_elapsed":elapsed,"movement":0.0,"turn":0.0,"failed":true}
	if current == &"advancing" and elapsed >= ESCAPE_SECONDS:
		return {"phase":&"escape_settling","phase_elapsed":0.0,"movement":0.0,"turn":0.0,"failed":false}
	var action := escape_action(current, forward, heading, speed, angular, advance, deceleration, forward_limit)
	var next_phase := StringName(action.phase)
	return {"phase":next_phase,"phase_elapsed":0.0 if next_phase != current else elapsed,
		"movement":float(action.movement),"turn":float(action.turn),"failed":false}

func drive(position: Vector3, forward: Vector3, speed: float, reverse_limit: float, deceleration: float, delta: float, forward_limit := 15.0, angular_speed := 0.0) -> Dictionary:
	if phase == &"normal": return {}
	if phase == &"blocked": return {"movement":0.0,"turn":0.0,"status":&"stuck"}
	_tick_attempt(delta)
	if phase == &"blocked": return {"movement":0.0,"turn":0.0,"status":&"stuck"}
	var command := {"movement":0.0,"turn":0.0,"status":&"recovering"}
	if phase == &"braking":
		if absf(speed) <= STOP_SPEED: phase = &"reversing"; reset_progress(position,forward)
	elif phase == &"reversing":
		_elapsed += delta
		if REVERSE_METRES-position.distance_to(_origin) <= speed*speed/(2.0*maxf(deceleration,.001))+.1 or _elapsed >= REVERSE_SECONDS: phase = &"settling"
		else: command.movement = -clampf(REVERSE_SPEED/maxf(reverse_limit,.01),0.0,1.0)
	elif phase == &"settling" and absf(speed) <= STOP_SPEED: phase = &"selecting_escape"
	elif phase != &"selecting_escape" and phase != &"rejoining":
		var transition := escape_transition(phase,_elapsed,_attempt_elapsed,forward,escape_heading,speed,angular_speed,
			positive_advance,deceleration,forward_limit,delta)
		if bool(transition.failed):
			_fail_attempt(position,forward)
		else:
			var prior_phase := phase
			phase = StringName(transition.phase); _elapsed = float(transition.phase_elapsed)
			if phase == &"advancing" and prior_phase != phase: advance_origin = position
			command.movement = float(transition.movement); command.turn = float(transition.turn)
	if not advance_origin.is_zero_approx():
		var offset := position-advance_origin; offset.y=0.0; positive_advance=maxf(0.0,offset.dot(escape_heading))
	return command

func _tick_attempt(delta: float) -> void:
	_attempt_elapsed += maxf(delta,0.0)
	if _attempt_elapsed >= ATTEMPT_SECONDS: _fail_attempt(_origin,_forward)
func _start_attempt(position: Vector3, forward: Vector3) -> void:
	if attempts >= MAX_ATTEMPTS: phase=&"blocked"; return
	if not is_zero_approx(_observed_side): _attempt_side = _observed_side
	attempts += 1; episode_active=true; interrupt_confirmation(position); blocked_origin=position; blocked_forward=forward; escape_heading=Vector3.ZERO; advance_origin=Vector3.ZERO; positive_advance=0.0; _attempt_elapsed=0.0; _elapsed=0.0; phase=&"braking"
func _fail_attempt(position: Vector3, forward: Vector3) -> void:
	_failed_heading=escape_heading
	if attempts >= MAX_ATTEMPTS: phase=&"blocked"; return
	_start_attempt(position,forward)
static func _preferred_side(position: Vector3, forward: Vector3, contacts: Array[Dictionary]) -> float:
	var side := Vector3.UP.cross(forward).normalized()
	var strongest := 0.0
	var away := 0.0
	var point_strength := 0.0
	var point_away := 0.0
	for contact in contacts:
		var normal := contact.get("normal",Vector3.ZERO) as Vector3; normal.y=0.0
		if normal.is_zero_approx() or normal.normalized().dot(forward) > .1: continue
		var lateral := normal.normalized().dot(side)
		if absf(lateral) > strongest:
			strongest=absf(lateral); away=signf(lateral)
		var point := contact.get("position",position) as Vector3
		var point_side := -(point-position).dot(side)
		if absf(point_side) > point_strength:
			point_strength=absf(point_side); point_away=signf(point_side)
	## 單位法線的最強側向分量優先；正面接觸才退回接觸點位於車身哪一側。
	if strongest >= .1: return away
	if point_strength >= .1: return point_away
	return 0.0


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
