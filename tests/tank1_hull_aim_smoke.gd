extends SceneTree

const TANK1_SCENE := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const TANK2_SCENE := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const TANK4_SCENE := preload("res://src/actors/tank/variants/tank4/tank4.tscn")
const PLAYER_CONTROLLER_SCRIPT := preload("res://src/player/player_controller.gd")


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var tank1 = TANK1_SCENE.instantiate()
	var player_controller = PLAYER_CONTROLLER_SCRIPT.new()
	root.add_child(tank1)
	root.add_child(player_controller)
	player_controller.set_controlled_tank(tank1)
	await process_frame
	await process_frame

	var yaw_pivot := tank1.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var outside_target := yaw_pivot.global_position + Vector3.FORWARD * 100.0
	tank1.aim_turret_at(outside_target, 10.0)
	var requested_hull_turn := float(tank1.get_hull_aim_turn_input())
	if is_zero_approx(requested_hull_turn):
		_fail("Tank1 must request hull rotation when horizontal aim cannot align.")
		return
	player_controller.apply_commands(0.0, 0.0, false)
	if not is_equal_approx(float(tank1.turn_command), requested_hull_turn):
		_fail("PlayerController must apply Tank1 hull-aim input when manual steering and Left Shift are idle.")
		return

	player_controller.apply_commands(0.0, -1.0, false)
	if not is_equal_approx(float(tank1.turn_command), -1.0):
		_fail("Manual A/D steering must override hull aim assist.")
		return

	tank1.aim_turret_at(outside_target, 10.0)
	player_controller.apply_commands(0.0, 0.0, false)
	tank1.angular_speed = 0.25
	player_controller.apply_commands(1.0, 0.0, false)
	if not is_equal_approx(float(tank1.movement_command), 1.0) \
			or not is_zero_approx(float(tank1.turn_command)) \
			or not is_zero_approx(float(tank1.angular_speed)):
		_fail("W/S movement must continue while suppressing and immediately stopping hull aim assist.")
		return
	tank1.aim_turret_at(outside_target, 10.0)
	player_controller.apply_commands(-1.0, 0.0, false)
	if not is_equal_approx(float(tank1.movement_command), -1.0) \
			or not is_zero_approx(float(tank1.turn_command)):
		_fail("Reverse movement must also suppress hull aim assist.")
		return

	tank1.aim_turret_at(outside_target, 10.0)
	player_controller.apply_commands(0.0, 0.0, false)
	tank1.angular_speed = 0.25
	var horizontal_direction: Vector3 = tank1.muzzle_global_direction()
	horizontal_direction.y = 0.0
	horizontal_direction = horizontal_direction.normalized()
	var aligned_high_target: Vector3 = tank1.muzzle_global_position() + horizontal_direction * 100.0 + Vector3.UP * 100.0
	tank1.aim_turret_at(aligned_high_target, 10.0)
	player_controller.apply_commands(0.0, 0.0, false)
	if not is_zero_approx(float(tank1.get_hull_aim_turn_input())) \
			or not is_zero_approx(float(tank1.turn_command)) \
			or not is_zero_approx(float(tank1.angular_speed)):
		_fail("Horizontal alignment must immediately stop hull aim even while vertical aim is not aligned.")
		return

	tank1.aim_turret_at(outside_target, 10.0)
	player_controller.apply_commands(0.0, 0.0, false)
	tank1.angular_speed = 0.25
	var left_shift_press := InputEventKey.new()
	left_shift_press.physical_keycode = KEY_SHIFT
	left_shift_press.location = KEY_LOCATION_LEFT
	left_shift_press.pressed = true
	player_controller._unhandled_input(left_shift_press)
	player_controller.apply_commands(0.0, 0.0, false)
	if not is_zero_approx(float(tank1.turn_command)) or not is_zero_approx(float(tank1.angular_speed)):
		_fail("Left Shift must suppress and immediately stop automatic hull aim.")
		return
	player_controller.apply_commands(0.0, 1.0, false)
	if not is_equal_approx(float(tank1.turn_command), 1.0):
		_fail("Left Shift must not suppress manual A/D steering.")
		return

	var tank2 = TANK2_SCENE.instantiate()
	root.add_child(tank2)
	await process_frame
	await process_frame
	var tank2_pivot := tank2.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	tank2.aim_turret_at(tank2_pivot.global_position + Vector3.FORWARD * 100.0, 10.0)
	if not is_zero_approx(float(tank2.get_hull_aim_turn_input())):
		_fail("Tank2 must not opt into fixed-turret hull aim assist.")
		return

	var tank4 = TANK4_SCENE.instantiate()
	root.add_child(tank4)
	await process_frame
	await process_frame
	var tank4_pivot := tank4.get_node("VisualRecoilPivot/TurretPivot") as Node3D
	var tank4_fixed_turret := tank4.get_node_or_null(
		"VisualRecoilPivot/TankVisualSlot/HullVisual/Tank4Model/AgentTeamScaleRoot/Tank_Turret"
	) as Node3D
	if not tank4.hull_aim_assist_enabled \
			or not is_equal_approx(float(tank4.turret_max_yaw_degrees), 6.0) \
			or not is_equal_approx(float(tank4.gun_max_depression_degrees), 10.0) \
			or not is_equal_approx(float(tank4.gun_max_elevation_degrees), 20.0) \
			or tank4.tank_turret.name != &"Tank4GunYawAdapter" \
			or tank4_fixed_turret == null:
		_fail("Tank4 must keep its upper body fixed and limit gun aim to yaw ±6°, pitch -10°/+20°.")
		return
	tank4.aim_turret_at(tank4_pivot.global_position + Vector3.FORWARD * 100.0, 10.0)
	if not is_equal_approx(absf(tank4_pivot.rotation.y), deg_to_rad(6.0)) \
			or is_zero_approx(float(tank4.get_hull_aim_turn_input())):
		_fail("Tank4 must request hull rotation after its gun reaches the horizontal aim limit.")
		return

	print("Fixed-turret hull aim assist smoke validation passed for Tank1 and Tank4.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
