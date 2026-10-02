## Legacy command curves only; contact forces remain the physical authority.
extends RefCounted

var forward_speed := 0.0
var reverse_speed := 0.0
var acceleration := 0.0
var deceleration := 0.0
var turn_speed := 0.0
var turn_response := 0.0
var turning_ratio := 1.0
var longitudinal := 0.0
var steering := 0.0 # Command-positive yaw, rad/s; physical yaw has the opposite sign.
var linear_acceleration := 0.0
var angular_acceleration := 0.0
var phase := "braking"

func configure(donor: Node) -> void:
	forward_speed = donor.movement_speed
	reverse_speed = donor.reverse_movement_speed
	acceleration = donor.engine_horsepower / donor.tank_mass_tonnes * 0.08
	deceleration = donor.brake_force_kilonewtons / donor.tank_mass_tonnes
	turn_speed = donor.turn_speed
	turn_response = donor.turn_response
	turning_ratio = donor.turning_movement_speed_ratio

func _approach(current: float, input: float, limit: float, accel: float, brake: float, dt: float) -> float:
	if is_zero_approx(input) or (not is_zero_approx(current) and signf(current) != signf(input)):
		return move_toward(current, 0.0, brake * dt)
	var target := input * limit
	return move_toward(current, target, (brake if absf(current) > absf(target) else accel) * dt)

func step(throttle: float, turn: float, _body_speed: float, delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta): return
	throttle = clampf(throttle, -1.0, 1.0)
	turn = clampf(turn, -1.0, 1.0)
	var before := longitudinal
	var before_yaw := steering
	var limit := (forward_speed if throttle >= 0.0 else reverse_speed) * lerpf(1.0, turning_ratio, absf(turn))
	phase = "reversing_brake" if throttle * longitudinal < 0.0 else ("braking" if is_zero_approx(throttle) else "driving")
	longitudinal = _approach(longitudinal, throttle, limit, acceleration, deceleration, delta)
	steering = _approach(steering, turn, turn_speed, acceleration * turn_response, deceleration * turn_response, delta)
	linear_acceleration = (longitudinal - before) / delta
	angular_acceleration = (steering - before_yaw) / delta

func snapshot() -> Dictionary:
	return {"longitudinal": longitudinal, "steering": steering, "phase": phase,
		"forward_limit": forward_speed, "reverse_limit": reverse_speed,
		"linear_acceleration": linear_acceleration, "angular_acceleration": angular_acceleration}
