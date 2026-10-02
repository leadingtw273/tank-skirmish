## 固定砲塔：對準必須持續穩定，不是單幀經過目標。
extends "res://tests/rigid_tank_contact_smoke.gd"

const Controller := preload("res://src/player/player_controller.gd")
const Vehicles := [preload("res://src/actors/rigid_tank/variants/tank1.tscn"), preload("res://src/actors/rigid_tank/variants/tank4.tscn")]

func _run() -> void:
	for scene in Vehicles:
		for mode in ["left", "right", "manual-release", "shot"]:
			await _aim_case(scene, mode)
	await _clear()
	print("VARIANT_AIM failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _aim_case(scene: PackedScene, mode: String) -> void:
	await _reset()
	_floor()
	var tank = scene.instantiate()
	tank.position = Vector3(0, 1, 0)
	world.add_child(tank)
	await _frames(240)
	var controller := Controller.new()
	world.add_child(controller)
	controller.set_physics_process(false)
	controller.set_controlled_tank(tank)
	var target := Vector3(-100, 2, -100 if mode == "right" else 100)
	if mode == "manual-release":
		for frame in 60:
			tank.aim_turret_at(target, 1.0 / 60.0)
			controller.apply_commands(0.0, -1.0, false)
			await physics_frame
		_expect("manual-priority", tank._turn_input == 1.0, "adapter follows manual right")
	var stable := 0
	var best := 0
	var error := INF
	var yaw := INF
	var shot := false
	var finish := 900
	for frame in 900:
		tank.aim_turret_at(target, 1.0 / 60.0)
		tank.aim_gun_pitch_at_target(target, 1.0 / 60.0)
		controller.apply_commands(0.0, 0.0, mode == "shot" and frame == 30)
		shot = shot or tank.recoil_application_count > 0
		await physics_frame
		var forward: Vector3 = tank.muzzle_global_direction()
		var desired: Vector3 = target - tank.muzzle_global_position()
		forward.y = 0.0
		desired.y = 0.0
		error = absf(rad_to_deg(forward.normalized().signed_angle_to(desired.normalized(), Vector3.UP)))
		yaw = absf(tank.angular_velocity.dot(Vector3.UP))
		stable = stable + 1 if error <= 0.25 and yaw <= 0.01 else 0
		best = maxi(best, stable)
		if frame % 120 == 0:
			var donor: Node3D = tank.combat_tank
			var local_target: Vector3 = donor.global_basis.orthonormalized().inverse() * (target - tank.turret_pivot.global_position)
			var donor_error: float = rad_to_deg(angle_difference(tank.turret_pivot.rotation.y, atan2(local_target.z, -local_target.x)))
			print("AIM_TRACE ", scene.resource_path.get_file(), " ", mode, " frame=", frame, " error=", error, " donor_error=", donor_error, " yaw=", yaw, " input=", tank._turn_input, " budget=", tank.telemetry().side_budget_used)
		if stable >= 60 and (mode != "shot" or shot):
			finish = frame + 1
			break
	_expect("%s-%s" % [scene.resource_path.get_file(), mode], best >= 60 and (mode != "shot" or shot),
		"frames=%d stable=%d error=%.6f yaw=%.6f" % [finish, best, error, yaw])
	tank.cancel_aim()
	controller.apply_commands(0.0, 0.0, false)
	_expect("cancel", tank.get_hull_aim_turn_input() == 0.0 and tank._turn_input == 0.0, "no lingering assist")
	tank.get_node("HealthComponent").apply_damage(100.0)
	await _frames(2)
	tank.aim_turret_at(target, 1.0 / 60.0)
	controller.apply_commands(0.0, 0.0, false)
	_expect("death", tank.get_hull_aim_turn_input() == 0.0 and tank._turn_input == 0.0, "dead assist gated")
