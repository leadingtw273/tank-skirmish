extends Node

var controlled_tank: Node3D


func set_controlled_tank(tank: Node3D) -> void:
	controlled_tank = tank


func _unhandled_input(event: InputEvent) -> void:
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
	controlled_tank.call("set_movement_input", movement_input)
	controlled_tank.call("set_turn_input", turn_input)
	if should_request_fire:
		controlled_tank.call("request_fire")


func _has_active_tank() -> bool:
	if controlled_tank != null and is_instance_valid(controlled_tank):
		return true
	push_error("PlayerController requires an active controlled_tank.")
	set_physics_process(false)
	set_process_unhandled_input(false)
	return false
