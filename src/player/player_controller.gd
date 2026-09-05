extends Node

var controlled_tank: Node3D
var left_shift_held := false
var _hull_aim_assist_was_active := false


func set_controlled_tank(tank: Node3D) -> void:
	if _hull_aim_assist_was_active and controlled_tank != null and is_instance_valid(controlled_tank) \
			and controlled_tank.has_method("stop_hull_aim_turn"):
		controlled_tank.call("stop_hull_aim_turn")
	controlled_tank = tank
	_hull_aim_assist_was_active = false


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null:
		var is_left_shift := (key_event.physical_keycode == KEY_SHIFT or key_event.keycode == KEY_SHIFT) \
			and key_event.location == KEY_LOCATION_LEFT
		if is_left_shift and not key_event.echo:
			left_shift_held = key_event.pressed
			if left_shift_held and _hull_aim_assist_was_active and _has_active_tank() \
					and controlled_tank.has_method("stop_hull_aim_turn"):
				controlled_tank.call("stop_hull_aim_turn")
				_hull_aim_assist_was_active = false
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _has_active_tank():
		controlled_tank.call("request_fire")


func _physics_process(_delta: float) -> void:
	var movement_input := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	var turn_input := float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D))
	apply_commands(movement_input, turn_input, false)


func apply_commands(movement_input: float, turn_input: float, should_request_fire: bool) -> void:
	if not _has_active_tank():
		return
	var manual_turn_input := clampf(turn_input, -1.0, 1.0)
	var effective_turn_input := manual_turn_input
	var using_hull_aim_assist := false
	if is_zero_approx(movement_input) and is_zero_approx(manual_turn_input) and not left_shift_held \
			and controlled_tank.has_method("get_hull_aim_turn_input"):
		var requested_hull_turn := clampf(float(controlled_tank.call("get_hull_aim_turn_input")), -1.0, 1.0)
		if not is_zero_approx(requested_hull_turn):
			effective_turn_input = requested_hull_turn
			using_hull_aim_assist = true
	if _hull_aim_assist_was_active and not using_hull_aim_assist and is_zero_approx(manual_turn_input) \
			and controlled_tank.has_method("stop_hull_aim_turn"):
		controlled_tank.call("stop_hull_aim_turn")
	controlled_tank.call("set_movement_input", movement_input)
	controlled_tank.call("set_turn_input", effective_turn_input)
	_hull_aim_assist_was_active = using_hull_aim_assist
	if should_request_fire:
		controlled_tank.call("request_fire")


func _has_active_tank() -> bool:
	if controlled_tank != null and is_instance_valid(controlled_tank):
		return true
	push_error("PlayerController requires an active controlled_tank.")
	_hull_aim_assist_was_active = false
	set_physics_process(false)
	set_process_unhandled_input(false)
	return false
