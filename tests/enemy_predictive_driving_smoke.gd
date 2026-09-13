## LEA-xxx P1--P5：3 秒完整姿態預測駕駛；command 僅作輸入，所有通過條件量測真實 physics。
extends SceneTree

const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const TANK_SCENES: Array[PackedScene] = [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	preload("res://src/actors/tank/variants/tank2/tank2.tscn"),
	preload("res://src/actors/tank/variants/tank3/tank3.tscn"),
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]
const DT := 1.0 / 60.0
const FORECAST_SECONDS := 3.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _p1_open_field_passthrough_four_real_tanks()
	await _p2_midcourse_wall_and_full_pose_sweeps()
	await _p3_mirrored_convex_corners_intervene_without_penetration()
	await _p4_real_rear_contact_rechecks_current_dynamic_shape()
	await _p5_hold_contact_survives_invalid_predictor()
	await _p5_bounded_recovery_and_lifecycle_cancellation()
	await _regression_arrived_normal_hold_preserves_arrived()
	if _failures.is_empty():
		print("PREDICTIVE_DRIVING PASS: P1 passthrough, P2 midcourse/full-pose, P3 mirrored convex, P4 dynamic contact, P5 bounded lifecycle.")
		quit(0)
		return
	for failure in _failures:
		push_error("PREDICTIVE_DRIVING FAIL: %s" % failure)
	quit(1)


## P1：四台正式車型在空曠地的輸入必須原樣通過，且每台都以真 physics 前進與轉向。
func _p1_open_field_passthrough_four_real_tanks() -> void:
	for model in TANK_SCENES.size():
		var fixture := await _open_fixture(model)
		if fixture.is_empty():
			_fail("P1 Tank%d fixture creation failed." % (model + 1))
			continue
		var tank := fixture.tank as CharacterBody3D
		var predictor := Predictor.new()
		predictor.setup(tank)
		var start := tank.global_position
		var yaw_start := tank.global_rotation.y
		var altered := false
		var max_speed_error := 0.0
		var max_angular_error := 0.0
		for unused in 120:
			## 與控制器同一純步進器的「下一物理步」比較真實控制器結果；不是把
			## choose 的回傳再同自己比較，因此可抓出預測／實際動力方程分岔。
			var expected: Dictionary = tank.predictive_driving_step(tank.forward_speed, tank.actual_angular_speed, 0.65, 0.25, DT)
			var choice: Dictionary = predictor.choose(0.65, 0.25, Vector3(-100.0, 0.0, 0.0), DT)
			altered = altered or bool(choice.get("intervened", false)) \
				or absf(float(choice.get("movement", 0.0)) - 0.65) > 0.0001 \
				or absf(float(choice.get("turn", 0.0)) - 0.25) > 0.0001
			tank.set_movement_input(float(choice.get("movement", 0.0)))
			tank.set_turn_input(float(choice.get("turn", 0.0)))
			await physics_frame
			max_speed_error = maxf(max_speed_error, absf(tank.forward_speed - float(expected.get("forward_speed", 0.0))))
			max_angular_error = maxf(max_angular_error, absf(tank.actual_angular_speed - float(expected.get("angular_speed", 0.0))))
		var moved := (start - tank.global_position).length()
		var turned := absf(angle_difference(yaw_start, tank.global_rotation.y))
		var stats: Dictionary = predictor.get_stats()
		print("PREDICTIVE_METRIC P1 tank=%d moved_m=%.3f turned_deg=%.2f altered=%s speed_error=%.5f angular_error=%.5f stats=%s" % [model + 1, moved, rad_to_deg(turned), altered, max_speed_error, max_angular_error, stats])
		if altered or moved < 0.10 or turned < deg_to_rad(0.5) or max_speed_error > 0.001 or max_angular_error > 0.001 or int(stats.get("query_count", 0)) <= 0:
			_fail("P1 Tank%d open-field command must pass through and match controller pure-step physics; moved=%.3f turn=%.2f speed_error=%.5f angular_error=%.5f altered=%s stats=%s." % [model + 1, moved, rad_to_deg(turned), max_speed_error, max_angular_error, altered, stats])
		predictor.reset()
		await _free_fixture(fixture)


## P2：薄牆只位於 3 秒路徑中段；另以實際車尾與砲管支持面放牆，不能只檢 endpoint 或 hull。
func _p2_midcourse_wall_and_full_pose_sweeps() -> void:
	await _p2_thin_midcourse_wall()
	for pose in [&"rear", &"gun"]:
		await _p2_stationary_pose_sweep(pose)


func _p2_thin_midcourse_wall() -> void:
	var fixture := await _open_fixture(1)
	if fixture.is_empty():
		_fail("P2 thin-wall fixture creation failed.")
		return
	var tank := fixture.tank as CharacterBody3D
	## 將 4cm 薄牆置於 3 秒軌跡中段的第 20、21 個 0.1 秒 root 中點，而非
	## 三秒端點；完整車身令相鄰 endpoint 不可能保證 clear，故不虛構該前提。
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	var root: Transform3D = snapshot.root
	var speed := float(snapshot.forward_speed)
	var angular := float(snapshot.angular_speed)
	var segment_start := Vector3.ZERO
	var segment_end := Vector3.ZERO
	for step in 21:
		var state: Dictionary = tank.predictive_driving_step(speed, angular, 1.0, 0.0, 0.1)
		speed = float(state.forward_speed)
		angular = float(state.angular_speed)
		root = root.rotated_local(Vector3.UP, angular * 0.1)
		var next := root.origin + root.basis * Vector3.LEFT * speed * 0.1
		if step == 19:
			segment_start = root.origin
		if step == 20:
			segment_end = next
		root.origin = next
	var wall := _box(segment_start.lerp(segment_end, 0.5) + Vector3.UP * 2.0, Vector3(0.04, 5.0, 16.0))
	fixture.root.add_child(wall)
	await physics_frame
	var predictor := Predictor.new()
	predictor.setup(tank)
	var nominal: Dictionary = predictor.choose(1.0, 0.0, Vector3(-60.0, 0.0, 0.0), DT, false, false)
	var choice: Dictionary = predictor.choose(1.0, 0.0, Vector3(-60.0, 0.0, 0.0), DT)
	var stats: Dictionary = predictor.get_stats()
	print("PREDICTIVE_METRIC P2 thin_wall nominal=%s selected=%s stats=%s" % [nominal, choice, stats])
	if StringName(nominal.get("reason", &"")) != &"blocked" or not bool(choice.get("intervened", false)) or int(stats.get("query_count", 0)) <= 1 or bool(stats.get("at_cap", false)):
		_fail("P2 thin wall in the middle of a 3-second route must reject nominal and choose a non-budget safe adjustment; nominal=%s selected=%s stats=%s." % [nominal, choice, stats])
	else:
		## 只執行安全結果，實物不得穿過牆；這不是以輸出 command 冒充碰撞結果。
		for unused in 180:
			tank.set_movement_input(float(choice.get("movement", 0.0)))
			tank.set_turn_input(float(choice.get("turn", 0.0)))
			await physics_frame
			if _part_hits(tank, wall):
				_fail("P2 thin-wall safe choice penetrated the authored wall during true physics execution.")
				break
	await _free_fixture(fixture)


func _p2_stationary_pose_sweep(kind: StringName) -> void:
	var fixture := await _open_fixture(0)
	if fixture.is_empty():
		_fail("P2 %s fixture creation failed." % kind)
		return
	var tank := fixture.tank as CharacterBody3D
	if kind == &"gun":
		var turret := tank.get_node("VisualRecoilPivot/TurretPivot") as Node3D
		turret.rotation.y = deg_to_rad(75.0)
		tank.call("_sync_part_collision_shapes")
		await physics_frame
	var direction := Vector3.RIGHT if kind == &"rear" else Vector3.FORWARD
	var support := _support(tank, direction)
	var wall := _box(direction * (support + 0.08), Vector3(0.20 if absf(direction.x) > 0.5 else 10.0, 5.0, 10.0 if absf(direction.x) > 0.5 else 0.20))
	fixture.root.add_child(wall)
	await physics_frame
	if kind == &"rear":
		## 先由真實倒車建立同一棟 building 的接觸；後續轉動雖令 shape 中心
		## 朝外，車尾整個凸形掃掠仍不得被舊 contact 的「分離」捷徑放行。
		for unused in 90:
			tank.set_movement_input(-1.0)
			await physics_frame
			if tank.get_slide_collision_count() > 0:
				break
		tank.set_movement_input(0.0)
		if tank.get_slide_collision_count() <= 0 and not _part_hits(tank, wall):
			_fail("P2 rear sweep fixture must obtain a true rear building contact before predictive rotation.")
	var predictor := Predictor.new()
	predictor.setup(tank)
	var command_turn := -1.0 if kind == &"rear" else 1.0
	var choice: Dictionary = predictor.choose(0.0, command_turn, tank.global_position + Vector3.LEFT * 3.0, DT)
	print("PREDICTIVE_METRIC P2 pose=%s choice=%s stats=%s" % [kind, choice, predictor.get_stats()])
	if not bool(choice.get("intervened", false)):
		_fail("P2 %s sweep must intervene before rotating the current full pose into its wall; choice=%s." % [kind, choice])
	await _free_fixture(fixture)


## P3：左右鏡像單凸角只檢既有 geometry 支持面；安全修正必須真的產生進展且全程不重疊。
func _p3_mirrored_convex_corners_intervene_without_penetration() -> void:
	for sign_value in [-1.0, 1.0]:
		var fixture := await _open_fixture(0)
		if fixture.is_empty():
			_fail("P3 mirror %.0f fixture creation failed." % sign_value)
			continue
		var tank := fixture.tank as CharacterBody3D
		var front := _support_plane_point(tank, Vector3.LEFT)
		var side := _support(tank, Vector3(0.0, 0.0, sign_value))
		## 近表面離車鼻 8cm，避免以起始重疊假造「預判」；僅內側履帶前端被凸角咬住。
		var corner := _box(Vector3(front.x - 0.08 - 2.0, 2.0, sign_value * (side - 0.25 + 2.0)), Vector3(4.0, 5.0, 4.0))
		fixture.root.add_child(corner)
		await physics_frame
		if corner.global_position.x >= tank.global_position.x or _part_hits(tank, corner):
			_fail("P3 convex mirror %.0f fixture must begin clear with its building in the tank's -X forward half-space." % sign_value)
			await _free_fixture(fixture)
			continue
		var predictor := Predictor.new()
		predictor.setup(tank)
		var start := tank.global_position
		var intervened := false
		var penetrated := false
		var completed_adjustment_frames := 0
		var budget_frames := 0
		var last_choice: Dictionary = {}
		for unused in 240:
			var choice: Dictionary = predictor.choose(0.85, 0.0, Vector3(-50.0, 0.0, 0.0), DT)
			last_choice = choice
			intervened = intervened or bool(choice.get("intervened", false))
			var stats: Dictionary = choice.get("stats", {}) as Dictionary
			var budget := StringName(choice.get("reason", &"")) == &"budget" or bool(stats.get("at_cap", false))
			budget_frames += 1 if budget else 0
			if bool(choice.get("intervened", false)) and not budget:
				completed_adjustment_frames += 1
			tank.set_movement_input(float(choice.get("movement", 0.0)))
			tank.set_turn_input(float(choice.get("turn", 0.0)))
			await physics_frame
			penetrated = penetrated or _part_hits(tank, corner)
		var progress := (start - tank.global_position).length()
		var last_stats: Dictionary = last_choice.get("stats", {}) as Dictionary
		var last_budget := StringName(last_choice.get("reason", &"")) == &"budget" or bool(last_stats.get("at_cap", false))
		print("PREDICTIVE_METRIC P3 sign=%.0f progressed_m=%.3f intervened=%s adjustment_frames=%d budget_frames=%d final_reason=%s final_at_cap=%s penetrated=%s stats=%s" % [sign_value, progress, intervened, completed_adjustment_frames, budget_frames, last_choice.get("reason", ""), last_stats.get("at_cap", false), penetrated, predictor.get_stats()])
		if not intervened or completed_adjustment_frames < 10 or last_budget or progress < 0.5 or penetrated:
			_fail("P3 convex mirror %.0f needs >=10 completed non-budget safety adjustments, a non-budget final result, >=0.5m true progress, and no penetration; progress=%.3f intervened=%s completed=%d budget_frames=%d final=%s penetration=%s." % [sign_value, progress, intervened, completed_adjustment_frames, budget_frames, last_choice, penetrated])
		await _free_fixture(fixture)


## P4：玩家車先以真物理從後方接觸；前方空時敵車須實際駛離，前方牆時不可硬推穿牆。
func _p4_real_rear_contact_rechecks_current_dynamic_shape() -> void:
	await _p4_rear_contact_case(false)
	await _p4_rear_contact_case(true)


func _p4_rear_contact_case(front_blocked: bool) -> void:
	var fixture := await _open_fixture(1)
	if fixture.is_empty():
		_fail("P4 fixture creation failed.")
		return
	var tank := fixture.tank as CharacterBody3D
	var player := TANK_SCENES[2].instantiate() as CharacterBody3D
	fixture.root.add_child(player)
	await physics_frame
	player.global_position = Vector3(8.0, 0.0, 0.0)
	var wall: StaticBody3D = null
	if front_blocked:
		var front_plane := _support_plane_point(tank, Vector3.LEFT)
		wall = _box(Vector3(front_plane.x - 0.35, 2.0, 0.0), Vector3(0.5, 5.0, 14.0))
		fixture.root.add_child(wall)
	await physics_frame
	if front_blocked and (wall.global_position.x >= tank.global_position.x or _part_hits(tank, wall)):
		_fail("P4 blocked fixture must begin clear with its wall in the tank's -X forward half-space.")
		await _free_fixture(fixture)
		return
	## 由真車執行靠近，不以設定 contact flag 或 teleport 穿入的方式構造案例。
	var saw_contact := false
	for unused in 180:
		player.set_movement_input(1.0)
		await physics_frame
		saw_contact = saw_contact or player.get_slide_collision_count() > 0 or tank.get_slide_collision_count() > 0
		if saw_contact:
			break
	player.set_movement_input(0.0)
	var predictor := Predictor.new()
	predictor.setup(tank)
	var start := tank.global_position
	var dynamic_contact := false
	var penetrated := false
	for unused in 180:
		var choice: Dictionary = predictor.choose(0.7, 0.0, Vector3(-40.0, 0.0, 0.0), DT)
		dynamic_contact = dynamic_contact or bool(choice.get("contact", false))
		tank.set_movement_input(float(choice.get("movement", 0.0)))
		tank.set_turn_input(float(choice.get("turn", 0.0)))
		await physics_frame
		penetrated = penetrated or (wall != null and _part_hits(tank, wall))
	var forward_progress := start.x - tank.global_position.x
	print("PREDICTIVE_METRIC P4 blocked=%s true_contact=%s dynamic_contact=%s progress_x=%.3f penetrated=%s stats=%s" % [front_blocked, saw_contact, dynamic_contact, forward_progress, penetrated, predictor.get_stats()])
	if not saw_contact or not dynamic_contact:
		_fail("P4 rear-contact case must observe actual tank contact and classify the current dynamic obstacle; blocked=%s contact=%s dynamic=%s." % [front_blocked, saw_contact, dynamic_contact])
	elif not front_blocked and forward_progress < 0.10:
		_fail("P4 rear contact with clear front must physically drive away; forward progress=%.3f." % forward_progress)
	elif front_blocked and (penetrated or forward_progress > 0.60):
		_fail("P4 rear contact with front wall must not hard-drive through it; progress=%.3f penetration=%s." % [forward_progress, penetrated])
	await _free_fixture(fixture)


## P5（真實 fixture）：hold 時 controller snapshot 的真接觸是 recovery 需求的權威；
## 即使 predictor fail-closed 回報 contact=false，也不能每幀洗掉停滯觀察窗。
func _p5_hold_contact_survives_invalid_predictor() -> void:
	var fixture := await _open_fixture(1)
	if fixture.is_empty():
		_fail("P5 hold-contact fixture creation failed.")
		return
	var tank := fixture.tank as CharacterBody3D
	var front_plane := _support_plane_point(tank, Vector3.LEFT)
	var wall := _box(Vector3(front_plane.x - 0.30, 2.0, 0.0), Vector3(0.5, 5.0, 16.0))
	fixture.root.add_child(wall)
	await physics_frame
	if wall.global_position.x >= tank.global_position.x or _part_hits(tank, wall):
		_fail("P5 hold fixture must begin clear with its real-contact wall in the tank's -X forward half-space.")
		await _free_fixture(fixture)
		return
	var navigation := TankNavigation.new()
	navigation.setup(tank)
	## 僅讓 predictor 無 tank，以覆蓋 invalid fail-closed contract；接觸紀錄一律由真車撞牆取得。
	var predictor := navigation.get("_predictor") as RefCounted
	predictor.call("setup", null)
	var saw_real_contact := false
	var saw_recovering := false
	var last: Dictionary = {}
	for unused in 210:
		## 維持真實撞牆，讓下一次 hold 讀到 controller 的 snapshot contacts；不偽造 contacts 陣列。
		tank.set_movement_input(1.0)
		tank.set_turn_input(0.0)
		await physics_frame
		saw_real_contact = saw_real_contact or not tank.get_recovery_contacts().is_empty()
		last = navigation.hold(0.0, DT, Vector3(-80.0, 0.0, 0.0), 31)
		saw_recovering = saw_recovering or last.get("status", &"") == &"recovering"
		if saw_recovering:
			break
	print("PREDICTIVE_METRIC P5 hold_invalid real_contact=%s recovering=%s final=%s prediction_stats=%s" % [saw_real_contact, saw_recovering, last, navigation.get_prediction_stats()])
	if not saw_real_contact or StringName(navigation.get_prediction_stats().get("reason", &"")) != &"invalid" or not saw_recovering:
		_fail("P5 hold must retain real controller contact demand through predictor invalid fail-closed result; contact=%s recovering=%s final=%s stats=%s." % [saw_real_contact, saw_recovering, last, navigation.get_prediction_stats()])
	navigation.dispose()
	await _free_fixture(fixture)


## P5（真實 fixture）：同目標 phase cancel 不重給兩次額度；stuck 保持停車，只有新目標才重置。
func _p5_bounded_recovery_and_lifecycle_cancellation() -> void:
	var fixture := await _open_fixture(1)
	if fixture.is_empty():
		_fail("P5 fixture creation failed.")
		return
	var tank := fixture.tank as CharacterBody3D
	var wall := _box(Vector3(-10.0, 2.0, 0.0), Vector3(1.0, 5.0, 20.0))
	fixture.root.add_child(wall)
	await physics_frame
	var navigation := TankNavigation.new()
	navigation.setup(tank)
	var reverse_attempts := 0
	var was_reversing := false
	var cancelled_same_goal := false
	var final: Dictionary = {}
	for unused in 1800:
		final = navigation.drive(Vector3(-80.0, 0.0, 0.0), 11, 3.0, DT)
		tank.set_movement_input(float(final.get("movement", 0.0)))
		tank.set_turn_input(float(final.get("turn", 0.0)))
		var reversing := float(final.get("movement", 0.0)) < -0.05
		if reversing and not was_reversing:
			reverse_attempts += 1
			if reverse_attempts == 1:
				## 模擬追擊／holding 同目標切換：只取消 phase，不能重設 attempts。
				navigation.cancel_movement_preserving_budget()
				cancelled_same_goal = true
		was_reversing = reversing
		await physics_frame
		if final.get("status", &"") == &"stuck":
			break
	var stats_before := navigation.get_prediction_stats()
	var same_goal_hold: Dictionary = navigation.hold(0.0, DT, Vector3(-80.0, 0.0, 0.0), 11)
	var changed_goal_hold: Dictionary = navigation.hold(0.0, DT, Vector3(-70.0, 0.0, 10.0), 12)
	print("PREDICTIVE_METRIC P5 attempts=%d cancelled_same_goal=%s final=%s same_goal_hold=%s changed_goal_hold=%s stats_before_reset=%s" % [reverse_attempts, cancelled_same_goal, final, same_goal_hold, changed_goal_hold, stats_before])
	if not cancelled_same_goal or final.get("status", &"") != &"stuck" or reverse_attempts != 3 \
		or same_goal_hold.get("status", &"") != &"stuck" or changed_goal_hold.get("status", &"") == &"stuck":
		_fail("P5 same-goal cancel must preserve the three-attempt budget and stuck hold; only changed target may reset it. attempts=%d cancelled=%s final=%s same=%s changed=%s." % [reverse_attempts, cancelled_same_goal, final, same_goal_hold, changed_goal_hold])
	navigation.clear()
	var stats_after_clear := navigation.get_prediction_stats()
	if not stats_after_clear.is_empty() and int(stats_after_clear.get("query_count", 0)) != 0:
		_fail("P5 navigation clear must cancel predictor state; stats=%s." % stats_after_clear)
	## 換控制車與 dispose 都必須清掉舊 predictor，不能讓舊車的接觸／候選留存。
	var replacement := TANK_SCENES[2].instantiate() as CharacterBody3D
	fixture.root.add_child(replacement)
	replacement.global_position = Vector3(30.0, 0.0, 30.0)
	await physics_frame
	navigation.setup(replacement)
	var stats_after_replacement := navigation.get_prediction_stats()
	if not stats_after_replacement.is_empty() and int(stats_after_replacement.get("query_count", 0)) != 0:
		_fail("P5 controlled-tank replacement must reset predictor state; stats=%s." % stats_after_replacement)
	navigation.dispose()
	await _free_fixture(fixture)


## CombatAI 的 arrived 終止狀態經正常（無接觸）hold 不得降格為 holding。
func _regression_arrived_normal_hold_preserves_arrived() -> void:
	var fixture := await _open_fixture(1)
	if fixture.is_empty():
		_fail("Arrived-hold fixture creation failed.")
		return
	var tank := fixture.tank as CharacterBody3D
	var vision := TankVision.new()
	var ai := TankCombatAI.new()
	vision.observer = tank
	ai.controlled_tank = tank
	ai.vision = vision
	fixture.root.add_child(vision)
	fixture.root.add_child(ai)
	ai.set_physics_process(false)
	ai.call("_ensure_navigation")
	## 正式 CombatAI 提交 arrived；其內部會呼叫正常無接觸 hold，回傳 holding 不能覆寫 arrived。
	ai.call("_submit_navigation_intent", {"movement": 0.0, "turn": 0.0, "status": &"arrived"}, tank.stable_world_center() + Vector3.LEFT * 10.0, DT)
	var navigation := ai.get("_navigation") as RefCounted
	var stats: Dictionary = navigation.get_prediction_stats() if navigation != null else {}
	print("PREDICTIVE_METRIC arrived_hold ai_status=%s movement=%.3f turn=%.3f stats=%s" % [ai.movement_status, tank.movement_command, tank.turn_command, stats])
	if ai.movement_status != &"arrived" or not is_zero_approx(tank.movement_command):
		_fail("Normal no-contact hold after arrived must retain the actual CombatAI arrived status; status=%s movement=%.3f stats=%s." % [ai.movement_status, tank.movement_command, stats])
	await _free_fixture(fixture)


func _open_fixture(model: int) -> Dictionary:
	var world := Node3D.new()
	var ground := _box(Vector3(0.0, -0.5, 0.0), Vector3(220.0, 1.0, 220.0))
	var region := _open_navigation_region()
	var tank := TANK_SCENES[model].instantiate() as CharacterBody3D
	if tank == null:
		return {}
	world.add_child(ground)
	world.add_child(region)
	world.add_child(tank)
	root.add_child(world)
	tank.global_position = Vector3.ZERO
	tank.global_rotation = Vector3.ZERO
	for unused in 3:
		await physics_frame
	return {"root": world, "tank": tank}


func _open_navigation_region() -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(100, 0, -100), Vector3(100, 0, 100), Vector3(-100, 0, 100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	return region


func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _support(tank: CharacterBody3D, direction: Vector3) -> float:
	var result := -INF
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points:
				result = maxf(result, direction.dot(transforms[index] * point))
			index += 1
	return result


## _support 是方向投影，不可直接當 world coordinate；例如 LEFT 的 x plane 是 -support。
func _support_plane_point(tank: CharacterBody3D, direction: Vector3) -> Vector3:
	return direction.normalized() * _support(tank, direction)


func _part_hits(tank: CharacterBody3D, body: StaticBody3D) -> bool:
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = transforms[index]
			query.collision_mask = 1
			query.exclude = [tank.get_rid()]
			for hit in tank.get_world_3d().direct_space_state.intersect_shape(query, 16):
				if hit.get("collider") == body:
					return true
			index += 1
	return false


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.root as Node).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
