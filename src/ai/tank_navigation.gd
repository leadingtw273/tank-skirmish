## 將原生導航路線轉成坦克車身的「需求」，不直接寫入任何載具控制欄位。
extends RefCounted

const NavControl :=  preload("res://src/ai/tank_navigation_control.gd")
const TurnSpace := preload("res://src/ai/tank_turn_space.gd")
const TerrainEntry := preload("res://src/ai/tank_terrain_entry.gd")
const Recovery := preload("res://src/ai/tank_recovery.gd")
const DrivingPredictor := preload("res://src/ai/tank_driving_predictor.gd")
const AGENT_NAME := &"TankNavigationAgent"
const MAP_READY_ITERATION := 0
const GOAL_REFRESH_SECONDS := 0.25
const GOAL_REFRESH_DISTANCE := 1.0
const TURN_IN_PLACE_RADIANS := deg_to_rad(32.0)
const RETRY_GOAL_DISTANCE := 3.0

var _tank: Node3D
var _agent: NavigationAgent3D
var _generation := -1
var _goal := Vector3.ZERO
var _last_route_goal := Vector3.ZERO
var _route_refresh_age := INF
var _status: StringName = &"waiting_map"
var _terminal := false
var _recovery := Recovery.new()
var _attempt_goal := Vector3.ZERO
var _predictor := DrivingPredictor.new()
var _trace_requested: Dictionary = {}
var _trace_selected: Dictionary = {}
var _trace_output: Dictionary = {}
var _trace_request_frame := -1
var _handoff_count := 0
var _handoff_reason: StringName = &""
var _handoff_frame := -1
var _rejoin_route_pending := true
var _locked_stop_goal := Vector3.ZERO
var _locked_stop_goal_valid := false
var _preserve_recovery_action := false
var _prediction_effort_scale := 1.0
var _terrain_entry := TerrainEntry.new()
var _turn_space := TurnSpace.new()
var _guide: Dictionary = {}
var _guide_passed := false
var _guide_route_wait := false
var _guide_disabled := false
var _guides_suspended_for_recovery := false
var _guide_map_iteration := -1
var _guide_metrics: Dictionary = {}
var _drive_started_usec := 0


func setup(tank: Node3D) -> void:
	dispose()
	_tank = tank
	_predictor.setup(tank)
	_turn_space.setup(tank)
	if _tank == null:
		return
	_agent = NavigationAgent3D.new()
	_agent.name = AGENT_NAME
	_agent.avoidance_enabled = false
	_agent.path_desired_distance = 3.0
	_agent.target_desired_distance = 0.5
	_tank.add_child(_agent)
	_agent.set_navigation_map(_tank.get_world_3d().navigation_map)
	clear()


func dispose() -> void:
	if is_instance_valid(_agent):
		_agent.queue_free()
	_agent = null
	_tank = null
	_predictor.setup(null)
	_turn_space.setup(null)
	clear()


func clear(preserve_episode := false, preserve_action := false) -> void:
	_cancel_guides(&"clear", preserve_episode and _guide_disabled, false)
	_guide_map_iteration = -1
	var keep_terminal_stuck := preserve_episode and _terminal and _status == &"stuck"
	_terrain_entry.reset()
	_prediction_effort_scale = 1.0
	_trace_requested = {}
	_trace_selected = {}
	_trace_output = {}
	_trace_request_frame = -1
	_handoff_count = 0
	_handoff_reason = &""
	_handoff_frame = -1
	_rejoin_route_pending = true
	_generation = -1
	_goal = Vector3.ZERO
	_last_route_goal = Vector3.ZERO
	_route_refresh_age = INF
	_status = &"stuck" if keep_terminal_stuck else &"waiting_map"
	_terminal = keep_terminal_stuck
	_attempt_goal = Vector3.ZERO
	if preserve_action and _recovery.phase != &"normal":
		_preserve_recovery_action = true
	elif preserve_episode:
		_recovery.cancel_action_preserving_episode(_horizontal(_stable_center()) if _tank != null else Vector3.ZERO, _forward_direction() if _tank != null else Vector3.LEFT)
	else:
		_preserve_recovery_action = false
		_locked_stop_goal_valid = false
		_recovery.reset()
	_predictor.reset()


func drive(goal: Vector3, generation: int, stop_distance: float, delta: float) -> Dictionary:
	_drive_started_usec = Time.get_ticks_usec()
	_guide_metrics = {}
	if _tank == null or not is_instance_valid(_agent):
		return _command(0.0, 0.0, &"waiting_map")
	var map := _tank.get_world_3d().navigation_map
	if map.is_valid() and _agent.get_navigation_map() != map:
		_agent.set_navigation_map(map)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= MAP_READY_ITERATION:
		_status = &"waiting_map"
		return _command(0.0, 0.0, _status)
	## 地圖可能先同步空集合；所屬區域尚未完成首輪同步時不能鎖死成無路。
	for region in NavigationServer3D.map_get_regions(map):
		if NavigationServer3D.region_get_enabled(region) and NavigationServer3D.region_get_iteration_id(region) == 0:
			return _command(0.0, 0.0, &"waiting_map")
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if _guide_map_iteration != -1 and iteration != _guide_map_iteration:
		_cancel_guides(&"map_changed", _guide_disabled)
	_guide_map_iteration = iteration
	var horizontal_goal := _horizontal(goal)
	if _is_new_goal(horizontal_goal, generation):
		_start_goal(horizontal_goal, generation)
	elif _terminal:
		return _command(0.0, 0.0, _status)
	else:
		_route_refresh_age += maxf(delta, 0.0)
		_goal = horizontal_goal
		if _route_refresh_age >= GOAL_REFRESH_SECONDS and _last_route_goal.distance_to(horizontal_goal) >= GOAL_REFRESH_DISTANCE:
			_last_route_goal = horizontal_goal
			_route_refresh_age = 0.0
			_cancel_guides(&"goal_refresh", _guide_disabled)
			_agent.target_position = horizontal_goal
	var position := _horizontal(_stable_center())
	if _recovery.phase != &"normal":
		return _drive_recovery(delta, &"safe_nominal", stop_distance)
	var direct_distance := _horizontal_distance(position, horizontal_goal)
	var speed := absf(float(_tank.get("forward_speed")))
	if direct_distance <= maxf(stop_distance, 0.0):
		return _finish(&"arrived") if speed <= 0.1 else _command(0.0, 0.0, &"moving")
	_advance_guide()
	var leg_goal: Vector3 = _guide.get("point", horizontal_goal)
	var leg_stop := 0.0 if not _guide.is_empty() else stop_distance
	var next := _agent.get_next_path_position()
	## 世界原點是合法路徑點；無路由空路徑判定，不能把零座標當哨兵。
	var path := _agent.get_current_navigation_path()
	if path.is_empty():
		if _guide_route_wait:
			_guide_route_wait = false
			return _command(0.0, 0.0, &"waiting_route")
		if not _guide.is_empty():
			return _guide_route_failed()
		return _finish(&"no_path")
	_guide_route_wait = false
	if _guide.is_empty() and not _turn_space.has_plan() and not _guide_disabled:
		_turn_space.capture(path, map)
	next = _steering_target(position, path, _agent.get_current_navigation_path_index(), speed)
	var forward := _forward_direction()
	var nominal := _navigation_nominal(position,leg_goal,leg_stop,next,path,_agent.get_current_navigation_path_index(),
		_agent.is_navigation_finished(),_agent.is_target_reachable(),speed,forward)
	if StringName(nominal.status) in [&"arrived",&"partial_end",&"no_path"]:
		if not _guide.is_empty():
			return _guide_route_failed()
		return _finish(StringName(nominal.status))
	var movement := float(nominal.movement); var turn := float(nominal.turn); var braking := bool(nominal.braking)
	## 正常轉向有角度進展就不算卡住；轉向被牆阻擋則也必須能進入脫困。
	var contacts: Array[Dictionary] = _tank.call("get_recovery_contacts") if _tank.has_method("get_recovery_contacts") else []
	var safe := _predictor.choose(movement, turn, nominal.get("target", next), delta, false, true, nominal.get("continuation", {}))
	_feedback_prediction_effort(safe, delta)
	_remember_trace(movement, turn, safe)
	# Exhaustion remains unknown, but elapsed time without actual progress is
	# still observable. Keep this tick stopped; recovery runs on the next tick
	# so an exhausted prediction cannot start a second expensive query this frame.
	if StringName(safe.get("reason", &"")) == &"budget" and contacts.is_empty() and not bool(safe.get("contact", false)):
		_recovery.interrupt_confirmation(position)
		_recovery.observe(position, forward, 0.0 if braking else movement, turn, delta, contacts, false)
		if _recovery.phase != &"normal":
			_cancel_guides(&"recovery", true)
		else:
			_step_turn_space()
		_status = &"moving"
		return _command(0.0, 0.0, _status)
	_recovery.observe_confirmation(position, 0.0 if braking else movement, contacts, bool(safe.get("contact", false)), bool(safe.get("intervened", false)), delta)
	## 觀察原始需求，而非被安全檢查改成的零油門；否則預防性煞停會永久掩蓋受阻。
	_recovery.observe(position, forward, 0.0 if braking else movement, turn, delta, contacts, not bool(safe.get("intervened", false)))
	if _recovery.phase != &"normal":
		return _drive_recovery(delta, &"safe_nominal", stop_distance)
	_step_turn_space()
	_status = &"moving"
	return _command(float(safe.movement), float(safe.turn), _status)


## 純需求計算：不 refresh route、不呼叫 get_next_path_position，也不推進 NavigationAgent preview。
func _calculate_nominal(position: Vector3, goal: Vector3, stop_distance: float, next: Vector3, path: PackedVector3Array,
		path_index: int, navigation_finished: bool, target_reachable: bool, speed: float, forward: Vector3) -> Dictionary:
	var velocity := (_tank as RigidBody3D).linear_velocity if _tank is RigidBody3D else Vector3.ZERO
	var angular := (_tank as RigidBody3D).angular_velocity.y if _tank is RigidBody3D else 0.0
	return NavControl.nominal(position,goal,stop_distance,next,path,path_index,navigation_finished,target_reachable,
		speed,forward,velocity,angular,_control_parameters())


## 停車面敵也可能被玩家追撞，與行進共用預測及同一份有限脫困預算。
func hold(turn: float, delta: float, target_position: Vector3 = Vector3.INF, generation: int = -1) -> Dictionary:
	_guide_metrics = {}
	if not _guide.is_empty() or _turn_space.has_plan():
		_cancel_guides(&"hold", _guide_disabled)
	if not is_instance_valid(_tank):
		return _command(0.0, 0.0, &"holding")
	if target_position.is_finite() and _is_new_goal(_horizontal(target_position), generation):
		_start_goal(_horizontal(target_position), generation)
	if _terminal and _status == &"stuck":
		return _command(0.0, 0.0, &"stuck")
	if _recovery.phase != &"normal":
		return _drive_recovery(delta, &"safe_hold", 0.0, turn)
	var position := _horizontal(_stable_center())
	var forward := _forward_direction()
	var safe := _predictor.choose(0.0, turn, _stable_center() + forward * 3.0, delta)
	_remember_trace(0.0, turn, safe)
	var contacts: Array[Dictionary] = _tank.call("get_recovery_contacts") if _tank.has_method("get_recovery_contacts") else []
	var contact := bool(safe.get("contact", false)) or not contacts.is_empty()
	_recovery.observe_confirmation(position, 0.0, contacts, bool(safe.get("contact", false)), bool(safe.get("intervened", false)), delta)
	_recovery.observe(position, forward, 1.0 if contact else 0.0, turn, delta, contacts, not bool(safe.get("intervened", false)))
	if _recovery.phase != &"normal":
		return _drive_recovery(delta, &"safe_hold", 0.0, turn)
	return _command(float(safe.movement), float(safe.turn), &"moving" if contact or bool(safe.get("intervened", false)) else &"holding")


func get_prediction_stats() -> Dictionary:
	var stats := _predictor.get_stats()
	stats.merge(_guide_metrics, true)
	return stats


## 唯讀生命週期查詢；必須與 drive 的既有新 goal 邊界相同，不能推進 agent 或改額度。
func is_terminal_for_goal(goal: Vector3, generation: int) -> bool:
	return _terminal and not _is_new_goal(_horizontal(goal), generation)


## 與 drive／hold 共用的純 retry 邊界；不得讀寫 NavigationAgent 或生命週期狀態。
func _is_new_goal(goal: Vector3, generation: int) -> bool:
	if _terminal and _status == &"stuck":
		return _locked_stop_goal_valid and _horizontal_distance(goal, _locked_stop_goal) >= RETRY_GOAL_DISTANCE
	return generation != _generation or _horizontal_distance(goal, _attempt_goal) >= RETRY_GOAL_DISTANCE


## 只讀已完成的決策，不以診斷取樣推進 NavigationAgent 路點。
func get_driving_trace_state() -> Dictionary:
	var path := _agent.get_current_navigation_path() if is_instance_valid(_agent) else PackedVector3Array()
	return {
		"status": _trace_output.get("status", _status), "goal": _goal,
		"generation": _generation, "terminal": _terminal,
		"turn_space": {"active": _guide.duplicate(true), "passed": _guide_passed,
			"final_goal": _goal, "planner": _turn_space.get_trace(), "cost": _guide_metrics.duplicate()},
		"route": Array(path), "index": _agent.get_current_navigation_path_index() if is_instance_valid(_agent) else -1,
		"end": path[path.size() - 1] if not path.is_empty() else null,
		"request_frame": _trace_request_frame, "requested": _trace_requested.duplicate(true),
		"selected": _trace_selected.duplicate(true), "output": _trace_output.duplicate(true),
		"recovery_phase": _recovery.phase, "attempts": _recovery.attempts,
		"terrain_entry": {"phase": _terrain_entry.phase, "entry": _terrain_entry.entry,
			"heading": _terrain_entry.heading, "staging": _terrain_entry.staging, "exit_distance": _terrain_entry.exit_distance},
		"recovery": {"blocked_origin": _recovery.blocked_origin, "escape_heading": _recovery.escape_heading,
			"advance_origin": _recovery.advance_origin, "advance_metres": _recovery.positive_advance,
			"phase": String(_recovery.phase), "handoff_count": _handoff_count, "handoff_reason": String(_handoff_reason), "handoff_frame": _handoff_frame,
			"episode_active": _recovery.episode_active, "confirmation_active": _recovery.confirmation_active,
			"confirmation_elapsed": _recovery.confirmation_elapsed, "confirmation_origin": _recovery.confirmation_origin,
			"locked_stop_goal": _locked_stop_goal if _locked_stop_goal_valid else null},
	}


func _remember_trace(movement: float, turn: float, selected: Dictionary) -> void:
	_trace_request_frame = Engine.get_physics_frames()
	_trace_requested = {"movement": movement, "turn": turn}
	_trace_selected = selected


## 同目標在追擊／holding 間切換只取消當前動作，不重新發給兩次脫困額度。
func cancel_movement_preserving_budget() -> void:
	_cancel_guides(&"cancel", _guide_disabled)
	if _terminal and _status == &"stuck":
		return
	_recovery.cancel_action_preserving_episode(_horizontal(_stable_center()), _forward_direction())
	_preserve_recovery_action = false
	_rejoin_route_pending = true
	_predictor.reset()
	_terminal = false
	_route_refresh_age = INF
	if is_instance_valid(_agent):
		_agent.target_position = _goal


func _start_goal(goal: Vector3, generation: int) -> void:
	_cancel_guides(&"new_goal", false, false)
	_terrain_entry.reset()
	var unlocks_stuck := _terminal and _status == &"stuck" and _locked_stop_goal_valid and _horizontal_distance(goal, _locked_stop_goal) >= RETRY_GOAL_DISTANCE
	_generation = generation
	_goal = goal
	_last_route_goal = goal
	_route_refresh_age = 0.0
	_terminal = false
	_status = &"moving"
	_attempt_goal = goal
	if unlocks_stuck:
		_locked_stop_goal_valid = false
		_preserve_recovery_action = false
		_recovery.reset(_horizontal(_stable_center()), _forward_direction())
	elif not (_preserve_recovery_action and _recovery.phase != &"normal"):
		_recovery.cancel_action_preserving_episode(_horizontal(_stable_center()), _forward_direction())
	_rejoin_route_pending = true
	_predictor.reset()
	_agent.target_position = goal


func _finish(status: StringName) -> Dictionary:
	_status = status
	_terminal = true
	## terminal stuck 要保留本輪受阻／attempt 診斷；clear／新目標仍會完整 reset。
	if status == &"stuck" and not _locked_stop_goal_valid:
		_locked_stop_goal = _goal; _locked_stop_goal_valid = true
	if status == &"stuck":
		_preserve_recovery_action = false
	if status != &"stuck":
		if _recovery.episode_active:
			_recovery.cancel_action_preserving_episode(_horizontal(_stable_center()), _forward_direction())
		else:
			_recovery.reset()
		_predictor.reset()
	return _command(0.0, 0.0, status)


func _command(movement: float, turn: float, status: StringName) -> Dictionary:
	var result := {"movement": clampf(movement, -1.0 if status == &"recovering" else 0.0, 1.0), "turn": clampf(turn, -1.0, 1.0), "status": status,
		"route": &"navmesh"}
	_trace_output = result.duplicate()
	return result


func _stable_center() -> Vector3:
	if _tank.has_method("stable_world_center"):
		return _tank.call("stable_world_center") as Vector3
	return _tank.global_position


func _drive_recovery(delta: float, handoff_reason: StringName = &"safe_nominal", stop_distance := 0.0, hold_turn := 0.0) -> Dictionary:
	if not _guide_disabled:
		_cancel_guides(&"recovery", true)
	var mass := maxf(float(_tank.get("tank_mass_tonnes")), 0.001)
	var deceleration := maxf(float(_tank.get("brake_force_kilonewtons")) / mass, 0.001)
	var result := _recovery.drive(_horizontal(_stable_center()), _forward_direction(),
		float(_tank.get("forward_speed")), float(_tank.get("reverse_movement_speed")), deceleration, delta,
		float(_tank.get("movement_speed")), float(_tank.get("actual_angular_speed")))
	if result.get("status") == &"stuck":
		return _finish(&"stuck")
	_status = &"recovering"
	if _recovery.needs_escape_selection():
		var selected := _predictor.choose_escape_profile(_recovery.blocked_forward, _recovery.escape_candidates(), delta, _recovery.escape_profile_state())
		_remember_trace(0.0, 0.0, selected)
		if bool(selected.safe): _recovery.select_escape(selected)
		## Budget means unverified, not a failed escape; wait within the same bounded attempt.
		elif StringName(selected.reason) != &"budget": _recovery.reject_handoff(StringName(selected.reason), _horizontal(_stable_center()), _forward_direction())
		_rejoin_route_pending = true
		return _command(0.0, 0.0, _status)
	if _recovery.handoff_ready():
		if _rejoin_route_pending:
			_agent.target_position = _goal
			_rejoin_route_pending = false
		var nominal := _rejoin_nominal(stop_distance,hold_turn,handoff_reason == &"safe_hold")
		if StringName(nominal.status) in [&"arrived",&"partial_end",&"no_path"]:
			_recovery.accept_handoff(handoff_reason, _horizontal(_stable_center())); _handoff_count += 1; _handoff_reason=handoff_reason; _handoff_frame=Engine.get_physics_frames()
			_preserve_recovery_action = false
			return _finish(StringName(nominal.status))
		var checked := _predictor.choose_handoff_step(float(nominal.movement), float(nominal.turn), _agent.get_next_path_position(), delta)
		_feedback_prediction_effort(checked, delta)
		_remember_trace(float(nominal.movement), float(nominal.turn), checked)
		if StringName(checked.get("reason", &"")) == &"near_only":
			# Execute only this proved step; full handoff remains pending.
			return _command(float(checked.movement), float(checked.turn), _status)
		if StringName(checked.get("reason", &"blocked")) == &"clear":
			if handoff_reason == &"safe_hold" or float(nominal.movement) > 0.0 and float(checked.movement) > 0.0:
				_recovery.accept_handoff(handoff_reason, _horizontal(_stable_center())); _handoff_count += 1; _handoff_reason = handoff_reason; _handoff_frame = Engine.get_physics_frames()
				_preserve_recovery_action = false
				if handoff_reason == &"safe_nominal":
					_resume_guides_after_handoff()
				return _command(float(checked.movement), float(checked.turn), &"holding" if handoff_reason == &"safe_hold" else &"moving")
			## 安全原地朝向仍由 rejoining 持有，不消耗 attempt。
			return _command(float(checked.movement),float(checked.turn),_status)
		if StringName(checked.get("reason", &"")) == &"budget": return _command(0.0, 0.0, _status)
		_recovery.reject_handoff(&"unsafe_nominal", _horizontal(_stable_center()), _forward_direction())
		_rejoin_route_pending = true
		return _command(0.0, 0.0, _status)
	if _recovery.phase in [&"braking",&"reversing",&"settling"]:
		var checked_recovery := _predictor.choose_recovery(float(result.get("movement",0.0)),float(result.get("turn",0.0)),_goal,delta)
		_remember_trace(float(result.get("movement",0.0)),float(result.get("turn",0.0)),checked_recovery)
		return _command(float(checked_recovery.get("movement",0.0)),float(checked_recovery.get("turn",0.0)),_status)
	var state := _recovery.escape_profile_state()
	state["submitted_command"] = {"movement": float(result.get("movement", 0.0)), "turn": float(result.get("turn", 0.0))}
	var waiting := _recovery.escape_heading.is_zero_approx()
	var safe := _predictor.choose_escape_profile(_recovery.blocked_forward, [{"heading": _recovery.escape_heading}], delta, state) if not waiting else {"movement":0.0,"turn":0.0,"reason":&"waiting"}
	if waiting:
		_remember_trace(float(result.get("movement", 0.0)), float(result.get("turn", 0.0)), safe)
		return _command(0.0, 0.0, _status)
	if not waiting and not safe.has("safe"):
		safe = safe.duplicate(true); safe["reason"] = &"invalid_continuation_result"; safe["missing_safe"] = true
		_remember_trace(float(result.get("movement", 0.0)), float(result.get("turn", 0.0)), safe)
		return _command(0.0, 0.0, _status)
	_remember_trace(float(result.get("movement", 0.0)), float(result.get("turn", 0.0)), safe)
	if StringName(safe.get("reason", &"")) == &"braking_blocked":
		_recovery.settle_before_handoff()
		return _command(0.0, 0.0, _status)
	if not waiting and not bool(safe.get("safe", false)) and _recovery.phase != &"braking" and _recovery.phase != &"reversing" and _recovery.phase != &"settling": return _command(0.0,0.0,_status)
	return _command(float(result.get("movement", 0.0)), float(result.get("turn", 0.0)), _status)


func _rejoin_nominal(stop_distance: float, hold_turn: float, is_hold: bool) -> Dictionary:
	if is_hold: return {"movement":0.0,"turn":hold_turn,"braking":false,"status":&"holding"}
	var path := _agent.get_current_navigation_path()
	## target_position refresh 後 NavigationServer 可能要到下一個 physics sync 才發布 route；
	## rejoining 必須持有控制等待，不能把這個短暫空窗冒充正式 no_path handoff。
	if path.is_empty(): return {"movement":0.0,"turn":0.0,"braking":false,"status":&"waiting_route"}
	return _navigation_nominal(_horizontal(_stable_center()),_goal,stop_distance,_steering_target(_horizontal(_stable_center()), path, _agent.get_current_navigation_path_index(), absf(float(_tank.get("forward_speed")))),path,
		_agent.get_current_navigation_path_index(),_agent.is_navigation_finished(),_agent.is_target_reachable(),
		absf(float(_tank.get("forward_speed"))),_forward_direction())


func _forward_direction() -> Vector3:
	return _horizontal(_tank.global_transform.basis * Vector3.LEFT).normalized()


static func _horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return _horizontal(a).distance_to(_horizontal(b))


## 沿既有路線前視，不把密集的網格邊界頂點當成原地轉向目標。
func _steering_target(position: Vector3, path: PackedVector3Array, index: int, speed: float) -> Vector3:
	return NavControl.steering_target(position,path,index,speed)


## 計算超時時降低下一次「需求」，完整安全預測及其預算保持不變。
func _feedback_prediction_effort(result: Dictionary, delta: float) -> void:
	if StringName(result.get("reason", &"")) == &"budget":
		_prediction_effort_scale = maxf(0.125, _prediction_effort_scale * 0.5)
	elif StringName(result.get("reason", &"")) == &"clear":
		_prediction_effort_scale = minf(1.0, _prediction_effort_scale + maxf(delta, 0.0) * 0.1)


func _control_parameters() -> Dictionary:
	return {"speed":float(_tank.movement_speed),"turn_ratio":float(_tank.turning_movement_speed_ratio),
		"deceleration":maxf(float(_tank.brake_force_kilonewtons)/maxf(float(_tank.tank_mass_tonnes),0.001),0.001),"effort":1.0}

func _navigation_nominal(position: Vector3, goal: Vector3, stop_distance: float, next: Vector3, path: PackedVector3Array,
		index: int, finished: bool, reachable: bool, speed: float, forward: Vector3) -> Dictionary:
	var guided := _terrain_entry.guide(_tank,path,index,position,speed)
	var params := _control_parameters()
	if guided.is_empty():
		var result := _calculate_nominal(position,goal,stop_distance,next,path,index,finished,reachable,speed,forward)
		result.target = next
		result.continuation = {"mode":&"route","params":params,"path":path,"index":index,"goal":goal,"stop":stop_distance}
		return result
	var result := NavControl.cross_action(position,forward,(_tank as RigidBody3D).angular_velocity.y,
		guided.target,_terrain_entry.heading,guided.phase,params)
	result.target = guided.target
	result.continuation = {"mode":&"cross","params":params,"target":guided.target,"heading":_terrain_entry.heading,"phase":guided.phase}
	return result


## 導引點只是本輪原路線的偏好；切換不開新 goal，也不重置預測／地形跨越／脫困。
func _advance_guide() -> void:
	if _guide_disabled:
		return
	if not _guide.is_empty() and not _guide_passed and _horizontal_distance(_tank.global_position, _guide.point) <= 0.8:
		_guide_passed = true
		_turn_space.note_passed(_guide)
	if _terrain_entry.phase != &"":
		return
	if not _guide.is_empty() and not _guide_passed:
		return
	var next_guide := _turn_space.take_next(_tank.global_position)
	if next_guide.is_empty() and _guide.is_empty():
		return
	_guide = next_guide
	_guide_passed = false
	_agent.target_position = _guide.get("point", _goal)
	_guide_route_wait = true


func _cancel_guides(reason: StringName, disable := false, retarget := true) -> void:
	if reason == &"recovery" and disable and not _guide_disabled and not _turn_space.is_disabled():
		_guides_suspended_for_recovery = true
	elif reason != &"recovery":
		_guides_suspended_for_recovery = false
	var had_guide := not _guide.is_empty()
	_guide.clear()
	_guide_passed = false
	_guide_disabled = disable
	_turn_space.reset(disable, reason)
	_guide_metrics = {}
	_guide_route_wait = had_guide and retarget
	if retarget and is_instance_valid(_agent):
		_agent.target_position = _goal


func _resume_guides_after_handoff() -> void:
	if not _guides_suspended_for_recovery:
		return
	_guides_suspended_for_recovery = false
	_cancel_guides(&"recovery_rejoined", false, false)


func _guide_route_failed() -> Dictionary:
	_cancel_guides(&"guide_route_failed", true)
	# This frame is the single waiting frame; the next empty final route uses
	# the existing finite no_path result.
	_guide_route_wait = false
	return _command(0.0, 0.0, &"waiting_route")


func _step_turn_space() -> void:
	var stats := _predictor.get_stats()
	var hint := _turn_space.step(_drive_started_usec + DrivingPredictor.MAX_ELAPSED_USEC,
		maxi(0, DrivingPredictor.MAX_QUERIES - int(stats.get("query_count", 0))))
	_guide_metrics = {
		"hint_elapsed_usec": int(hint.get("elapsed_usec", 0)),
		"hint_query_count": int(hint.get("query_count", 0)),
		"combined_elapsed_usec": Time.get_ticks_usec() - _drive_started_usec,
		"combined_query_count": int(stats.get("query_count", 0)) + int(hint.get("query_count", 0)),
	}
