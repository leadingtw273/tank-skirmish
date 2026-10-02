## LEA-176：真訓練場剛體敵車首次看見目標時的有限轉向追擊重現。
## 僅一次設定場景內既有 Enemy／玩家的初始姿態；之後不可替 AI 寫輸入或改剛體 velocity。
extends SceneTree

const PLAYTEST := preload("res://src/maps/training_ground/training_ground_playtest.tscn")
const FIXTURE_ENEMY_POSITION := Vector3(0.0, 0.0, -100.0)
const FIXTURE_PLAYER_POSITION := Vector3(75.0, 0.0, -100.0)
const FIXTURE_HULL_YAW := deg_to_rad(147.0) ## 玩家在 +X；車頭與它相差 33 度。
const FIXTURE_TURRET_YAW := deg_to_rad(33.0) ## 維持遠距 30 度 FOV 內的真實視線。
const MAX_FRAMES := 240
const MIN_INITIAL_TURN_DEGREES := 32.0
const MIN_ACTUAL_YAW_DEGREES := 15.0
const MIN_ACTUAL_DISPLACEMENT_METRES := 2.0
const MAX_CONSECUTIVE_BUDGET_FRAMES := 29
const MAX_BUDGET_RATIO := 0.05

var _failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	root.add_child(scene)
	var encounter := scene.get_node_or_null("Encounter") as Node3D
	var enemy := encounter.get_node_or_null("Enemy") as RigidBody3D if encounter != null else null
	var vision := encounter.get_node_or_null("Vision") as Node if encounter != null else null
	var ai := encounter.get_node_or_null("CombatAI") as Node if encounter != null else null
	var player_runtime := scene.get_node_or_null("Main/PlayerRuntime") as Node
	var player := player_runtime.get("controlled_tank") as RigidBody3D if player_runtime != null else null
	if enemy == null or player == null or vision == null or ai == null:
		_fail("fixture requires the actual training Encounter/Enemy, Vision, CombatAI, and Main player rigid tank.")
		await _finish(scene)
		return
	# 測試初始化先等真導航區域同步，避免出生首幀空地圖鎖住 no_path。
	ai.set_physics_process(false)
	var region := scene.get_node("NavigationRegion3D") as NavigationRegion3D
	var map := scene.get_world_3d().navigation_map
	for tick in 120:
		if NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 and NavigationServer3D.map_get_closest_point_owner(map, FIXTURE_ENEMY_POSITION).is_valid():
			break
		await physics_frame
	## 空曠左側仍是完整 training_ground 的地面、導航與所有碰撞負載；不移除任何場景物件。
	_apply_initial_pose(enemy, FIXTURE_ENEMY_POSITION, FIXTURE_HULL_YAW, FIXTURE_TURRET_YAW)
	_apply_initial_pose(player, FIXTURE_PLAYER_POSITION, 0.0, 0.0)
	ai.set_physics_process(true)
	## 僅開啟既有 read-only trace 載荷，以取回 AI 已完成的 prediction 統計；不影響 AI 輸入或剛體物理。
	enemy.call("set_driving_trace_enabled", true)
	var initial_center := enemy.call("stable_world_center") as Vector3
	var initial_yaw := enemy.global_rotation.y
	var initial_goal := player.call("stable_world_center") as Vector3
	var initial_forward := enemy.global_basis * Vector3.LEFT
	initial_forward.y = 0.0
	var target_offset := initial_goal - initial_center
	target_offset.y = 0.0
	var initial_turn_degrees := rad_to_deg(initial_forward.normalized().angle_to(target_offset.normalized())) if not target_offset.is_zero_approx() else 0.0
	if initial_turn_degrees <= MIN_INITIAL_TURN_DEGREES:
		_fail("fixture must start with a navigation turn angle >%.1fdeg; got %.2fdeg." % [MIN_INITIAL_TURN_DEGREES, initial_turn_degrees])

	var visible_frames := 0
	var turn_request_frames := 0
	var prediction_samples := 0
	var prediction_query_total := 0
	var prediction_elapsed_total_usec := 0
	var prediction_elapsed_max_usec := 0
	var budget_frames := 0
	var consecutive_budget_frames := 0
	var max_consecutive_budget_frames := 0
	var max_yaw_degrees := 0.0
	var max_displacement := 0.0
	for frame in MAX_FRAMES:
		await physics_frame
		var state := ai.call("get_driving_trace_state") as Dictionary
		var navigation := state.get("navigation", {}) as Dictionary
		var requested := navigation.get("requested", {}) as Dictionary
		var selected := navigation.get("selected", {}) as Dictionary
		var stats := selected.get("stats", {}) as Dictionary
		var visible := bool(vision.call("can_see", player))
		visible_frames += 1 if visible else 0
		turn_request_frames += 1 if absf(float(requested.get("turn", 0.0))) > 0.001 else 0
		if not stats.is_empty():
			prediction_samples += 1
			prediction_query_total += int(stats.get("query_count", 0))
			var elapsed_usec := int(stats.get("elapsed_usec", 0))
			prediction_elapsed_total_usec += elapsed_usec
			prediction_elapsed_max_usec = maxi(prediction_elapsed_max_usec, elapsed_usec)
			var budget := StringName(selected.get("reason", &"")) == &"budget" or bool(stats.get("at_cap", false))
			if budget:
				budget_frames += 1
				consecutive_budget_frames += 1
				max_consecutive_budget_frames = maxi(max_consecutive_budget_frames, consecutive_budget_frames)
			else:
				consecutive_budget_frames = 0
		var yaw_degrees := rad_to_deg(absf(angle_difference(initial_yaw, enemy.global_rotation.y)))
		max_yaw_degrees = maxf(max_yaw_degrees, yaw_degrees)
		max_displacement = maxf(max_displacement, initial_center.distance_to(enemy.call("stable_world_center") as Vector3))

	var budget_ratio := float(budget_frames) / float(prediction_samples) if prediction_samples > 0 else 1.0
	var final_state := ai.call("get_driving_trace_state") as Dictionary
	print("RIGID_TRAINING_PURSUIT_METRIC frames=%d initial_turn_deg=%.2f visible_frames=%d turn_request_frames=%d yaw_deg=%.2f displacement_m=%.3f prediction_samples=%d prediction_queries=%d prediction_elapsed_total_usec=%d prediction_elapsed_max_usec=%d budget_frames=%d budget_ratio=%.4f max_consecutive_budget_frames=%d final_state=%s" % [MAX_FRAMES, initial_turn_degrees, visible_frames, turn_request_frames, max_yaw_degrees, max_displacement, prediction_samples, prediction_query_total, prediction_elapsed_total_usec, prediction_elapsed_max_usec, budget_frames, budget_ratio, max_consecutive_budget_frames, final_state])
	if visible_frames <= 0:
		_fail("fixture must observe the real player through TankVision at least once.")
	if turn_request_frames <= 0:
		_fail("navigation must issue at least one nonzero turn request after first visibility.")
	if prediction_samples <= 0 or prediction_query_total <= 0:
		_fail("prediction must run with nonzero query work; samples=%d queries=%d." % [prediction_samples, prediction_query_total])
	if max_yaw_degrees < MIN_ACTUAL_YAW_DEGREES:
		_fail("actual rigid hull must turn >=%.1fdeg; got %.2fdeg." % [MIN_ACTUAL_YAW_DEGREES, max_yaw_degrees])
	if max_displacement < MIN_ACTUAL_DISPLACEMENT_METRES:
		_fail("actual rigid hull must pursue >=%.1fm; got %.3fm." % [MIN_ACTUAL_DISPLACEMENT_METRES, max_displacement])
	if max_consecutive_budget_frames >= MAX_CONSECUTIVE_BUDGET_FRAMES + 1:
		_fail("prediction budget must not persist for >=30 frames; max_consecutive=%d." % max_consecutive_budget_frames)
	if budget_ratio >= MAX_BUDGET_RATIO:
		_fail("prediction budget ratio must remain <5%%; got %.4f." % budget_ratio)
	await _finish(scene)


func _apply_initial_pose(tank: RigidBody3D, position: Vector3, hull_yaw: float, turret_yaw: float) -> void:
	## 唯一允許的 fixture 操作：開跑前一次性擺位；不寫 command、velocity 或任何 AI state。
	tank.global_transform = Transform3D(Basis(Vector3.UP, hull_yaw), position)
	var turret := tank.get("turret_pivot") as Node3D
	if turret != null:
		turret.rotation.y = turret_yaw
		tank.call("_sync_rigid_parts")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish(scene: Node3D) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	if _failures.is_empty():
		print("RIGID_TRAINING_PURSUIT PASS: visible first-turn pursuit stayed within prediction budget.")
		quit(0)
		return
	for failure in _failures:
		push_error("RIGID_TRAINING_PURSUIT FAIL: %s" % failure)
	quit(1)
