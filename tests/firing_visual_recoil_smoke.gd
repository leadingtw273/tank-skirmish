## F1–F4 的有限作者檢查；固定真姿態取樣，避免把原剛體後座誤判為動畫污染。
extends "res://tests/rigid_tank_contact_smoke.gd"

const Catalog := preload("res://src/actors/tank/tank_catalog.gd")
const Shot := preload("res://src/combat/shot_event.gd")
const CameraController := preload("res://src/camera/camera_controller.gd")
var shots: Array = []

func _run() -> void:
	for id in [&"tank1", &"tank2", &"tank3", &"tank4"]:
		await _vehicle(id)
	await _camera_contract()
	await _clear()
	print("FIRING_VISUAL_RECOIL failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _mechanical(donor: Node, tank: Node, target: Vector3) -> Dictionary:
	var root_shapes: Array[Transform3D] = []
	for shape in tank.collision_shapes:
		root_shapes.append(shape.global_transform)
	return {"muzzle": donor.muzzle_point.global_transform,
		"direction": donor.muzzle_global_direction(),
		"parts": donor.part_shape_world_transforms(), "root_shapes": root_shapes,
		"center": donor.stable_world_center(),
		"aim_pitch": donor._target_gun_pitch_for_world_target(target),
		"hull_aim": tank.get_hull_aim_turn_input(),
		"pivots": [donor.visual_recoil_pivot.transform, donor.turret_pivot.transform, donor.gun_pitch_pivot.transform],
		"impulse": tank.recoil_impulse, "impulse_count": tank.recoil_application_count,
		"pending": tank._pending_shots.duplicate()}

func _same_mechanical(a: Dictionary, b: Dictionary) -> bool:
	for key in ["muzzle", "center", "direction"]:
		if not a[key].is_equal_approx(b[key]): return false
	for key in ["parts", "root_shapes", "pivots"]:
		if a[key].size() != b[key].size(): return false
		for index in a[key].size():
			if not a[key][index].is_equal_approx(b[key][index]): return false
	return is_equal_approx(a.aim_pitch, b.aim_pitch) and is_equal_approx(a.hull_aim, b.hull_aim) \
		and a.impulse == b.impulse and a.impulse_count == b.impulse_count and a.pending == b.pending

func _roots(donor: Node) -> Array[Node3D]:
	return [donor.hull_visual, donor.turret_visual, donor.gun_visual]

func _rest_world(node: Node3D, rest: Transform3D) -> Transform3D:
	return (node.get_parent() as Node3D).global_transform * rest

func _vehicle(id: StringName) -> void:
	await _reset()
	_floor()
	var tank = Catalog.instantiate(id)
	tank.freeze = true
	tank.position = Vector3(7, 3, -5)
	world.add_child(tank)
	tank.set_process(false)
	var donor: Node = tank.combat_tank
	donor.set_process(false)
	donor.set_physics_process(false)
	if not donor.has_method("_update_firing_visual_recoil"):
		_expect(str(id) + " F1 visual-missing", false, "正式 rigid 尚無砲管／車體可見反作用")
		return
	var rests: Array[Transform3D] = []
	for node in _roots(donor): rests.append(node.transform)
	for yaw in [0.0, PI / 2.0, PI / 4.0]:
		donor._reset_firing_visual_recoil()
		tank.rotation = Vector3(0.035, 0.37, -0.02)
		donor.turret_pivot.rotation.y = yaw
		donor.gun_pitch_pivot.rotation.z = -0.12
		tank._sync_rigid_parts()
		var target: Vector3 = donor.muzzle_global_position() + donor.muzzle_global_direction() * 60.0
		var before := _mechanical(donor, tank, target)
		shots.clear()
		var callback := func(event): shots.append(event)
		tank.shot_event_fired.connect(callback)
		donor._fire_cooldown_remaining = 0.0
		donor.current_spread_degrees = 0.0
		tank._pending_shots.clear()
		tank.request_fire()
		var event: RefCounted = shots[0]
		var fired := _mechanical(donor, tank, target)
		tank.request_fire()
		_expect("%s yaw%.2f F1 single/cooldown" % [id, yaw], shots.size() == 1
			and tank._pending_shots.size() == 1 and donor._firing_recoil_elapsed == 0.0
			and event.muzzle_transform.is_equal_approx(before.muzzle), "原單發／快照；冷卻拒絕不重啟")
		var elapsed := 0.0
		for sample in [0.04, 0.05, 0.16]:
			donor._update_firing_visual_recoil(sample - elapsed)
			elapsed = sample
			tank._sync_rigid_parts()
			var after := _mechanical(donor, tank, target)
			var enabled_visuals: Array[Transform3D] = []
			for node in _roots(donor): enabled_visuals.append(node.global_transform)
			donor.firing_visual_recoil_enabled = false
			donor._apply_firing_visual_recoil()
			tank._sync_rigid_parts()
			var disabled := _mechanical(donor, tank, target)
			donor.firing_visual_recoil_enabled = true
			donor._apply_firing_visual_recoil()
			_expect("%s yaw%.2f F2 peak%.2f" % [id, yaw, sample], _same_mechanical(fired, after)
				and _same_mechanical(after, disabled) and event.muzzle_transform.is_equal_approx(before.muzzle)
				and donor.visual_recoil_tween == null, "同真姿態 A/B：muzzle／全 shapes／aim／event／impulse／pivots")
			var hull_rest := _rest_world(donor.hull_visual, rests[0])
			var common: Transform3D = enabled_visuals[0] * hull_rest.affine_inverse()
			var turret_rest := _rest_world(donor.turret_visual, rests[1])
			var gun_rest := _rest_world(donor.gun_visual, rests[2])
			var gun_delta: Vector3 = enabled_visuals[2].origin - (common * gun_rest).origin
			var body_delta: Vector3 = common * donor.stable_world_center() - donor.stable_world_center()
			var forward: Vector3 = donor.muzzle_global_direction()
			var horizontal := Vector3(forward.x, 0, forward.z).normalized()
			var common_matches := enabled_visuals[1].is_equal_approx(common * turret_rest)
			var gun_direction_matches := gun_delta.normalized().dot(-(common.basis * forward).normalized()) > 0.999
			var rises := (common.basis * horizontal).y > 0.0
			_expect("%s yaw%.2f F1 response%.2f" % [id, yaw, sample], common_matches and rises
				and body_delta.normalized().dot(-horizontal) > 0.999 and gun_direction_matches
				and body_delta.length() <= 0.2201 and gun_delta.length() <= 0.4501,
				"共用世界反作用；砲管相對砲塔反向退縮；無匯入 scale 倍增")
			if is_equal_approx(sample, 0.04):
				_expect(str(id) + " F1 gun peak distance", absf(gun_delta.length() - 0.45) < 0.0001, str(gun_delta.length()))
			if is_equal_approx(sample, 0.05):
				_expect(str(id) + " F1 body peak distance/angle", absf(body_delta.length() - 0.22) < 0.0001
					and absf(common.basis.get_rotation_quaternion().get_angle() - deg_to_rad(1.4)) < 0.0001, str(body_delta.length()))
		donor._update_firing_visual_recoil(1.0)
		var returned := true
		for index in 3: returned = returned and _roots(donor)[index].transform.is_equal_approx(rests[index])
		_expect(str(id) + " F1 return", returned and is_inf(donor._firing_recoil_elapsed), "三槽回 rest、不累積漂移")
		tank.shot_event_fired.disconnect(callback)
	# 真根位移／轉向與砲塔俯仰改變後，render 同影格重算，不快取世界位置。
	donor._fire_cooldown_remaining = 0.0
	tank.request_fire()
	donor._update_firing_visual_recoil(0.05)
	tank.position += Vector3(3, 0, 4)
	tank.rotation.y += 0.4
	donor.turret_pivot.rotation.y += 0.2
	donor.gun_pitch_pivot.rotation.z -= 0.03
	tank._sync_rigid_parts()
	var mechanical_moving := _mechanical(donor, tank, Vector3(-40, 8, 20))
	donor._apply_firing_visual_recoil()
	_expect(str(id) + " F4 moving pose", _same_mechanical(mechanical_moving, _mechanical(donor, tank, Vector3(-40, 8, 20)))
		and donor.hull_visual.global_position.distance_to(_rest_world(donor.hull_visual, rests[0]).origin) < 0.4,
		"真位移／轉向後仍跟隨當下 parent pose")
	donor._fire_cooldown_remaining = 0.0
	tank.request_fire()
	var restarted: bool = donor._firing_recoil_elapsed == 0.0
	for index in 3: restarted = restarted and _roots(donor)[index].transform.is_equal_approx(rests[index])
	_expect(str(id) + " F1 overlapping restart", restarted, "未回正時新 fire 取代舊動畫、不疊加 offset")
	for unused in 5:
		donor._fire_cooldown_remaining = 0.0
		tank.request_fire()
		donor._update_firing_visual_recoil(0.05)
		donor._update_firing_visual_recoil(1.0)
	var no_drift := true
	for index in 3: no_drift = no_drift and _roots(donor)[index].transform.is_equal_approx(rests[index])
	_expect(str(id) + " F1 repeated rest", no_drift, "重觸有界、回正不漂移")
	donor._fire_cooldown_remaining = 0.0
	tank.request_fire()
	donor._update_firing_visual_recoil(0.05)
	tank.get_node("HealthComponent").apply_damage(10000.0)
	var dead_rest := true
	for index in 3: dead_rest = dead_rest and _roots(donor)[index].transform.is_equal_approx(rests[index])
	_expect(str(id) + " F4 death", dead_rest and is_inf(donor._firing_recoil_elapsed), "死亡立即清理可見 offset、保留原垂炮姿態")
	tank.get_node("HealthComponent").reset_to_maximum()
	_expect(str(id) + " F4 reset", is_inf(donor._firing_recoil_elapsed), "復原不帶入舊反作用")
	donor._fire_cooldown_remaining = 0.0
	tank.request_fire()
	await _frames(3)
	_expect(str(id) + " F1 live render", not donor.gun_visual.transform.is_equal_approx(rests[2])
		and donor.is_processing(), "成功 fire 由真 render process 推進可見動畫")
	await _frames(30)
	var live_rest := true
	for index in 3: live_rest = live_rest and _roots(donor)[index].transform.is_equal_approx(rests[index])
	_expect(str(id) + " F1 live return", live_rest and not donor.is_processing(), "自然 render 完成後回 rest 並停止更新")

func _camera_contract() -> void:
	await _reset()
	var camera_default := CameraController.new()
	_expect("F3 script default", is_equal_approx(camera_default.fire_shake_kick_distance, 0.2), str(camera_default.fire_shake_kick_distance))
	camera_default.free()
	for scene_path in ["res://src/main.tscn", "res://src/maps/training_ground/training_ground_playtest.tscn"]:
		var scene := (load(scene_path) as PackedScene).instantiate()
		world.add_child(scene)
		var runtime: Node = scene.get_node("Main") if scene_path.contains("training_ground") else scene
		runtime.player_runtime.set_controls_enabled(false)
		var camera: Node3D = runtime.player_runtime.camera_controller
		camera.set_process(false)
		var camera_rest: Transform3D = camera.camera.transform
		var camera_size: float = camera.camera.size
		var player: Node = runtime.player_runtime.controlled_tank
		player.request_fire()
		_expect(scene_path + " F3 kick", absf(camera.camera_shake_pivot.position.length() - 0.2) < 0.0001
			and camera.camera_shake_pivot.rotation.is_zero_approx(), "玩家成功 fire 最大 0.2m、零 roll")
		camera._update_shot_recoil(0.1)
		_expect(scene_path + " F3 squared half", absf(camera.camera_shake_pivot.position.length() - 0.05) < 0.0001, "0.1s 剩四分之一")
		camera._update_shot_recoil(0.1)
		_expect(scene_path + " F3 identity", camera.camera_shake_pivot.transform.is_equal_approx(Transform3D.IDENTITY)
			and camera.camera.transform.is_equal_approx(camera_rest) and camera.camera.size == camera_size, "0.2s 回正、Camera3D 基準保持")
		var enemy = Catalog.instantiate(&"tank2")
		enemy.freeze = true
		world.add_child(enemy)
		enemy.request_fire()
		_expect(scene_path + " F3 enemy", camera.camera_shake_pivot.transform.is_equal_approx(Transform3D.IDENTITY), "敵車 fire 不觸發玩家 shake")
		enemy.queue_free()
		scene.queue_free()
		await _frames(2)
