## 有限的三秒坦克駕駛預測器；只讀取當幀 snapshot，絕不寫入坦克或導航狀態。
class_name TankDrivingPredictor
extends RefCounted
const NavigationControl := preload("res://src/ai/tank_navigation_control.gd")

const RigidMotion := preload("res://src/ai/rigid_motion_prediction.gd")
const BrakingSweep := preload("res://src/ai/rigid_braking_sweep.gd")
const FAR_WORK_USEC := 5500 # Leave headroom for near-only requests and result bookkeeping.
var _work_deadline_usec := 0
var native_segment_enabled := true
# Scheduling hint only: every skipped fast path still requires a fresh full terrain proof.
const LAYERED_RETRY_CALLS := 6
var _layered_retry_calls := 0

const Recovery := preload("res://src/ai/tank_recovery.gd")

const HORIZON_SECONDS := 3.0
const STEP_SECONDS := 0.1
const MAX_CANDIDATES := 12
const MAX_QUERIES := 4096
## 查詢上限是決定性主閘；時間閘只防止異常物理世界令單幀長卡。
const MAX_ELAPSED_USEC := 20000
const MAX_HITS := 32
const CONTACT_EPSILON := 0.001
const LOW_SPEED_METERS_PER_SECOND := 1.5
const FLOOR_RAY_HEIGHT := 1.0
const FLOOR_RAY_DEPTH := 6.0
const SUPPORT_NORMAL_MIN_Y := 0.7
const MAX_SWEEP_DISTANCE := 0.02

var _tank: Node3D
var _stats := _empty_stats(&"not-run")
## 僅供本機 recorder 診斷；關閉時不得改變既有查詢或決策路徑。
var _trace_enabled := false
var _trace_request_frame := -1
var _trace_candidates: Array[Dictionary] = []
var _trace_initial_contacts: Array[Dictionary] = []
var _trace_initial_truncated := false
var _trace_shape_parts: Array[Dictionary] = []


func setup(tank: Node3D) -> void:
	_tank = tank
	reset()


func reset() -> void:
	_stats = _empty_stats(&"reset")
	_layered_retry_calls = 0


func get_stats() -> Dictionary:
	return _stats.duplicate(true)


## allow_adjustment=false 供 nominal-only 呼叫端使用：只驗證原 command，不啟動候選選擇。
func choose(movement: float, turn: float, goal: Vector3, delta: float, allow_reverse: bool = false, allow_adjustment: bool = true, continuation: Dictionary = {}) -> Dictionary:
	return _choose(movement, turn, goal, delta, allow_reverse, allow_adjustment, false, continuation)


## Recovery 只在原命令不安全時，於同一份 snapshot／接觸集／查詢額度內找固定順序的 first-safe 車身候選。
func choose_recovery(movement: float, turn: float, goal: Vector3, delta: float) -> Dictionary:
	return _choose(movement, turn, goal, delta, false, true, true)


## Rejoining may execute a verified single step before its full handoff is clear.
## This does not change the nominal-only choose() contract or Recovery ordering.
func choose_handoff_step(movement: float, turn: float, goal: Vector3, delta: float) -> Dictionary:
	return _choose(movement, turn, goal, delta, false, false, false, {}, true)


## 選向使用同一次快照與共享預算跑完整有限 profile；continuation 傳入單一 candidate 時仍只看三秒。
func choose_escape_profile(blocked_forward: Vector3, candidates: Array[Dictionary], delta: float, continuation_state: Dictionary = {}) -> Dictionary:
	_layered_retry_calls = 0
	var started_usec := Time.get_ticks_usec()
	_stats = _empty_stats(&"invalid")
	_trace_begin()
	if _tank == null or not is_instance_valid(_tank) or _tank.get_world_3d() == null:
		return _escape_result(false, {}, &"invalid", started_usec)
	var snapshot: Dictionary = _tank.call(&"predictive_driving_snapshot")
	if snapshot.is_empty() or not _valid_snapshot(snapshot): return _escape_result(false, {}, &"invalid_snapshot", started_usec)
	_trace_prepare_shape_parts(snapshot)
	# Reuse geometry/support evidence only within this captured request, as normal driving does.
	var bounds: Array[Dictionary]
	if _tank.has_method(&"create_ground_motion_query"):
		var ground_query: RefCounted = _tank.call(&"create_ground_motion_query", snapshot)
		snapshot["ground_motion_query"] = ground_query
		if ground_query.get("diagnostic") is Dictionary: _stats["ground_diagnostic"] = ground_query.diagnostic
		bounds = ground_query.prediction_bounds()
	else:
		bounds = _part_local_bounds(snapshot.shapes as Array, snapshot.root_local_transforms as Array, snapshot.part_ranges as Array, snapshot.get("shape_vertices", []))
	var space := _tank.get_world_3d().direct_space_state
	var excluded := _supporting_floor_rids(space, snapshot, started_usec)
	var initial := _initial_contacts(space, snapshot, excluded, started_usec)
	if bool(initial.budget): return _escape_result(false, {}, &"budget", started_usec)
	var continuation := not continuation_state.is_empty() and StringName(continuation_state.get("phase", &"turning")) != &"selecting_escape"
	# The profile remains a full-horizon check. Its real next command also needs
	# the rigid braking envelope: profile kinematics do not bound suspension braking.
	if continuation and continuation_state.has("submitted_command") and _tank is RigidBody3D \
			and absf(delta - 1.0 / Engine.physics_ticks_per_second) <= 0.00001 \
			and (initial.contacts as Dictionary).is_empty() and bool(snapshot.get("approximate_rigid", false)):
		var captured := RigidMotion.capture(_tank as RigidBody3D, snapshot)
		if not captured.is_empty():
			var near_radius := 0.1
			for part: Dictionary in bounds: near_radius = maxf(near_radius, float(part.pivot_radius) + 0.01)
			var command: Dictionary = continuation_state.submitted_command
			var near := _probe_braking(snapshot, captured, near_radius, float(command.movement), float(command.turn), 1.0 / Engine.physics_ticks_per_second, started_usec)
			if not near.is_empty():
				if bool(near.budget): return _escape_result(false, {}, &"budget", started_usec)
				if not bool(near.safe): return _escape_result(false, {}, &"braking_blocked", started_usec)
				_stats.near_verified = true
	for candidate in candidates:
		if _budget_exhausted(started_usec): return _escape_result(false, candidate, &"budget", started_usec)
		var heading: Vector3 = continuation_state.get("heading", Vector3.ZERO) as Vector3
		if heading.is_zero_approx(): heading = blocked_forward.rotated(Vector3.UP, float(candidate.get("side",1.0))*float(candidate.get("angle",Recovery.ESCAPE_ANGLE))).normalized()
		var trace := _trace_candidate(0.0, 0.0); trace["profile_heading"] = heading; trace["profile_horizon"] = HORIZON_SECONDS if continuation else 10.0
		var probe := _probe_profile(space,snapshot,_snapshot_radius(snapshot.shapes as Array,snapshot.transforms as Array,snapshot.root as Transform3D),bounds,excluded,initial.contacts as Dictionary,heading,started_usec,HORIZON_SECONDS if continuation else 10.0,trace,continuation_state)
		trace["profile_phase"] = probe.get("phase", &"")
		trace["profile_positive_advance"] = float(probe.get("positive_advance", 0.0))
		_trace_finish_candidate(trace,probe)
		if bool(probe.budget): return _escape_result(false,candidate,&"budget",started_usec)
		if bool(probe.safe) and (continuation or float(probe.positive_advance) >= Recovery.PROGRESS_METRES):
			var action: Dictionary = probe.action
			return _escape_result(true,candidate,&"clear",started_usec,heading,float(action.movement),float(action.turn),StringName(probe.phase),float(probe.positive_advance))
	return _escape_result(false,{},&"blocked",started_usec)


func _choose(movement: float, turn: float, goal: Vector3, delta: float, allow_reverse: bool, allow_adjustment: bool, recovery_selection: bool, continuation: Dictionary = {}, handoff_step: bool = false) -> Dictionary:
	if recovery_selection or handoff_step or not allow_adjustment or movement <= 0.0:
		_layered_retry_calls = 0
	var started_usec := Time.get_ticks_usec()
	_stats = _empty_stats(&"invalid")
	_trace_begin()
	if _tank == null or not is_instance_valid(_tank) or _tank.get_world_3d() == null:
		return _result(0.0, 0.0, true, false, &"invalid", started_usec)
	var snapshot: Dictionary = _tank.call(&"predictive_driving_snapshot")
	if allow_adjustment and not recovery_selection and not continuation.is_empty(): snapshot["navigation_continuation"] = continuation.duplicate(true)
	if snapshot.is_empty() or not _valid_snapshot(snapshot):
		return _result(0.0, 0.0, true, false, &"invalid_snapshot", started_usec)
	_trace_prepare_shape_parts(snapshot)
	## 凸形頂點只在本次最新 snapshot 建一次 part-local AABB，全部候選共用。
	var part_bounds: Array[Dictionary]
	if _tank.has_method(&"create_ground_motion_query"):
		var ground_query: RefCounted = _tank.call(&"create_ground_motion_query", snapshot)
		snapshot["ground_motion_query"] = ground_query
		if ground_query.get("diagnostic") is Dictionary: _stats["ground_diagnostic"] = ground_query.diagnostic
		part_bounds = ground_query.prediction_bounds()
	else:
		part_bounds = _part_local_bounds(snapshot.shapes as Array, snapshot.root_local_transforms as Array, snapshot.part_ranges as Array, snapshot.get("shape_vertices", []))
	if part_bounds.is_empty():
		return _result(0.0, 0.0, true, false, &"invalid_snapshot", started_usec)
	var snapshot_radius := 0.1
	for part_bound in part_bounds:
		snapshot_radius = maxf(snapshot_radius, float(part_bound.pivot_radius) + 0.01)
	var space := _tank.get_world_3d().direct_space_state
	var excluded := _supporting_floor_rids(space, snapshot, started_usec)
	if _budget_exhausted(started_usec):
		return _result(0.0, 0.0, true, false, &"budget", started_usec)
	var initial := _initial_contacts(space, snapshot, excluded, started_usec)
	if bool(initial.budget):
		return _result(0.0, 0.0, true, false, &"budget", started_usec)
	var contact := not (initial.contacts as Dictionary).is_empty()
	if contact: _layered_retry_calls = 0
	if handoff_step and not contact and bool(snapshot.get("approximate_rigid", false)):
		var verified_step := _choose_handoff_step(snapshot, snapshot_radius, part_bounds, space, excluded, movement, turn, delta, started_usec)
		if not verified_step.is_empty(): return verified_step
	# Nominal-only calls include recovery handoff validation; retain their full horizon.
	if not recovery_selection and allow_adjustment and not contact and bool(snapshot.get("approximate_rigid", false)):
		if _layered_retry_calls > 0:
			_layered_retry_calls -= 1
			_stats["layered_schedule"] = &"terrain_retry"
		else:
			var layered := _choose_layered(snapshot, snapshot_radius, movement, turn, goal, delta, allow_reverse, allow_adjustment, started_usec)
			if not layered.is_empty(): return layered
			if movement > 0.0 and not str(_stats.get("near_unknown_reason", "")).is_empty():
				_layered_retry_calls = LAYERED_RETRY_CALLS
				_stats["layered_schedule"] = &"terrain_after_unknown"
	var nominal_trace := _trace_candidate(movement, turn)
	var nominal := _probe(space, snapshot, snapshot_radius, part_bounds, excluded, initial.contacts as Dictionary, movement, turn, started_usec, nominal_trace)
	var nominal_trace_index := _trace_finish_candidate(nominal_trace, nominal)
	if bool(nominal.budget):
		return _result(0.0, 0.0, true, contact, &"budget", started_usec)
	## Recovery 的安全原命令（包含確實遠離既有接觸）必須原樣直通。
	if bool(nominal.safe) and (recovery_selection or not contact):
		return _result(movement, turn, false, contact, &"clear", started_usec)
	## 靜止／煞車階段只檢查原命令，不能自行改成移動脫困。
	if recovery_selection and is_zero_approx(movement) and is_zero_approx(turn):
		return _result(0.0, 0.0, true, contact, &"blocked", started_usec)
	if not allow_adjustment:
		return _result(movement, turn, false, contact, &"clear" if bool(nominal.safe) else &"blocked", started_usec) if bool(nominal.safe) else _result(0.0, 0.0, true, contact, &"blocked", started_usec)
	var candidates := _recovery_candidates(movement, turn) if recovery_selection else _candidates(movement, turn, allow_reverse, contact)
	var best: Dictionary = {}
	for candidate in candidates:
		if _budget_exhausted(started_usec):
			return _result(0.0, 0.0, true, contact, &"budget", started_usec)
		var score := 0.0
		if not recovery_selection:
			score = _score(_command_root(snapshot, float(candidate.movement), float(candidate.turn), delta), snapshot.root as Transform3D, goal, initial.contacts as Dictionary)
			## best 已完整驗證安全；同分或低分不可能取代它，無須再跑三秒 probe。
			## 非有限分數不剪枝，Recovery 仍完全依原候選順序檢查。
			if not best.is_empty() and is_finite(score) and is_finite(float(best.score)) and score <= float(best.score):
				continue
		var is_nominal := is_equal_approx(float(candidate.movement), movement) and is_equal_approx(float(candidate.turn), turn)
		var candidate_trace := {} if is_nominal else _trace_candidate(float(candidate.movement), float(candidate.turn))
		var probe := nominal if is_nominal else _probe(
			space, snapshot, snapshot_radius, part_bounds, excluded, initial.contacts as Dictionary, float(candidate.movement), float(candidate.turn), started_usec, candidate_trace)
		var candidate_trace_index := nominal_trace_index if is_nominal else _trace_finish_candidate(candidate_trace, probe)
		if bool(probe.budget):
			return _result(0.0, 0.0, true, contact, &"budget", started_usec)
		if not bool(probe.safe):
			continue
		## Recovery 的候選順序就是策略；不可讓路線目標分數壓過必要的倒車或轉向。
		if recovery_selection:
			return _result(float(candidate.movement), float(candidate.turn), true, contact, &"contact_escape" if contact else &"risk", started_usec)
		## 三秒 probe 證明完整命令軌跡安全；選擇時只評分呼叫端本幀真正會執行的短段。
		_trace_set_score(candidate_trace_index, score)
		if best.is_empty() or score > float(best.score):
			best = {"movement": float(candidate.movement), "turn": float(candidate.turn), "score": score}
			## 已找到安全、會往 route goal 或離開接觸面的選項，不需為同一次命令窮舉剩餘候選。
			if score > 0.0:
				return _result(float(best.movement), float(best.turn), true, contact, &"contact_escape" if contact else &"risk", started_usec)
	if best.is_empty():
		return _result(0.0, 0.0, true, contact, &"blocked", started_usec)
	var changed := not is_equal_approx(float(best.movement), movement) or not is_equal_approx(float(best.turn), turn)
	return _result(float(best.movement), float(best.turn), changed, contact, &"contact_escape" if contact else &"risk", started_usec)


func _valid_snapshot(snapshot: Dictionary) -> bool:
	return snapshot.get("root") is Transform3D and (snapshot.get("root") as Transform3D).is_finite() \
		and snapshot.get("transforms") is Array and snapshot.get("root_local_transforms") is Array and snapshot.get("shapes") is Array \
		and (snapshot.transforms as Array).size() == (snapshot.shapes as Array).size() \
		and (snapshot.root_local_transforms as Array).size() == (snapshot.shapes as Array).size() \
		and snapshot.get("part_ranges") is Array and not (snapshot.part_ranges as Array).is_empty() and not (snapshot.shapes as Array).is_empty()


func _supporting_floor_rids(space: PhysicsDirectSpaceState3D, snapshot: Dictionary, started_usec: int) -> Array[RID]:
	# 同一道路 body 可能同時包含路面、護欄與橋底，不得以 RID 整體排除。
	# 真實履帶淺接觸由 narrow query 依接觸法線／深度區分。
	return [snapshot.self_rid as RID]


func _initial_contacts(space: PhysicsDirectSpaceState3D, snapshot: Dictionary, excluded: Array[RID], started_usec: int) -> Dictionary:
	var contacts: Dictionary = {}
	var ground_query := _ground_solver(snapshot, {}, started_usec)
	for record in snapshot.get("contacts", []):
		if record is Dictionary and record.get("rid") is RID:
			if ground_query != null and ground_query.has_method("is_traversable_contact"):
				var traversable: bool = ground_query.is_traversable_contact(record, snapshot.root as Transform3D)
				_stats.query_count = int(ground_query.queries)
				if bool(ground_query.at_cap): return {"contacts": contacts, "budget": true}
				if traversable: continue
			var known_normal := record.get("normal", Vector3.ZERO) as Vector3
			contacts[(record.rid as RID).get_id()] = {"rid": record.rid as RID, "normal": known_normal.normalized() if not known_normal.is_zero_approx() else Vector3.ZERO}
			if _trace_enabled:
				_trace_initial_contact({"source": "snapshot_contact", "collider_unknown": true})
	var shapes: Array = snapshot.shapes
	var transforms: Array = snapshot.transforms
	for index in shapes.size():
		if _budget_exhausted(started_usec):
			return {"contacts": contacts, "budget": true}
		if ground_query != null:
			ground_query.queries = int(_stats.query_count)
			var only_support: bool = ground_query._clear_shape(index, snapshot.root as Transform3D)
			_stats.query_count = int(ground_query.queries)
			if bool(ground_query.at_cap): return {"contacts": contacts, "budget": true}
			if only_support: continue
		for hit in _hits(space, shapes[index] as Shape3D, transforms[index] as Transform3D, excluded, &"narrow"):
			var rid: RID = hit.rid
			var normal := _contact_normal(hit, snapshot.root as Transform3D)
			contacts[rid.get_id()] = {"rid": rid, "normal": normal}
			if _trace_enabled:
				_trace_initial_contact(_trace_blocker_from_hit(&"initial_intersect_shape", index, hit, 0.0))
	return {"contacts": contacts, "budget": false}


func _probe(space: PhysicsDirectSpaceState3D, snapshot: Dictionary, radius: float, part_bounds: Array[Dictionary], excluded: Array[RID], old_contacts: Dictionary, movement: float, turn: float, started_usec: int, trace_candidate: Dictionary = {}) -> Dictionary:
	if _tank.has_method(&"create_ground_motion_query"):
		return _probe_ground_motion(snapshot, radius, movement, turn, started_usec, trace_candidate, old_contacts)
	var root: Transform3D = snapshot.root
	var vertical_speed := float(snapshot.get("vertical_speed", 0.0))
	var speed := float(snapshot.forward_speed)
	var angular := float(snapshot.angular_speed)
	var shapes: Array = snapshot.shapes
	var local_transforms: Array = snapshot.root_local_transforms
	if is_zero_approx(movement) and is_zero_approx(turn) and is_zero_approx(speed) and is_zero_approx(angular):
		## 形狀固定不動時，initial full-shape query 已是整段三秒的同一姿態證明。
		if _trace_enabled and not old_contacts.is_empty():
			_trace_first_blocker(trace_candidate, {"source": "stationary_initial_contact", "collider_unknown": true})
		return {"safe": old_contacts.is_empty(), "budget": false, "final_root": root}
	for outer_step in range(ceili(HORIZON_SECONDS / STEP_SECONDS)):
		var preview: Dictionary = _tank.call(&"predictive_driving_step", speed, angular, movement, turn, STEP_SECONDS)
		if not preview.has("angular_speed"):
			return {"safe": false, "budget": false, "final_root": root}
		## 平移由 cast_motion 完整掃掠；只有旋轉外弧才需把 0.1 秒段再切細。
		var angular_sweep := radius * maxf(absf(angular), absf(float(preview.angular_speed))) * STEP_SECONDS
		var substeps := maxi(1, ceili(angular_sweep / MAX_SWEEP_DISTANCE))
		var sub_delta := STEP_SECONDS / float(substeps)
		var segment_roots: Array[Transform3D] = []
		var segment_start := root
		for unused_substep in substeps:
			if _budget_exhausted(started_usec):
				return {"safe": false, "budget": true, "final_root": root}
			var state: Dictionary = _tank.call(&"predictive_driving_step", speed, angular, movement, turn, sub_delta)
			if not state.has("forward_speed") or not state.has("angular_speed"):
				return {"safe": false, "budget": false, "final_root": root}
			speed = float(state.forward_speed)
			angular = float(state.angular_speed)
			root.basis = Basis(Vector3.UP, angular * sub_delta) * root.basis
			root.origin += root.basis * Vector3.LEFT * speed * sub_delta
			if _tank.has_method(&"predict_ground_pose"):
				var terrain: Dictionary = _tank.call(&"predict_ground_pose", root, sub_delta, vertical_speed)
				if not bool(terrain.get("safe", false)):
					return {"safe": false, "budget": false, "final_root": root}
				root = terrain.root
				vertical_speed = float(terrain.vertical_speed)
			segment_roots.append(root)
		var gap_metrics := _segment_gap_metrics(segment_start, segment_roots)
		var active_parts: Array[Dictionary] = []
		for part_bound in part_bounds:
			var bound := _segment_bound(part_bound, segment_start, segment_roots, float(gap_metrics.translation), float(gap_metrics.half_sine))
			if not _hits(space, bound.shape as Shape3D, bound.transform as Transform3D, excluded, &"broad").is_empty():
				active_parts.append(part_bound)
		if active_parts.is_empty():
			continue
		var active_shapes: Array[int] = []
		for part_bound in active_parts:
			if int(part_bound.count) == 1:
				active_shapes.append(int(part_bound.start))
				continue
			for child_bound in part_bound.children as Array:
				var child_segment_bound := _segment_bound(child_bound as Dictionary, segment_start, segment_roots, float(gap_metrics.translation), float(gap_metrics.half_sine))
				if not _hits(space, child_segment_bound.shape as Shape3D, child_segment_bound.transform as Transform3D, excluded, &"broad").is_empty():
					active_shapes.append(int((child_bound as Dictionary).index))
		if active_shapes.is_empty():
			continue
		var previous_root := segment_start
		for substep_index in segment_roots.size():
			var candidate_root: Transform3D = segment_roots[substep_index]
			if _budget_exhausted(started_usec):
				return {"safe": false, "budget": true, "final_root": root}
			for index in active_shapes:
				var previous_transform: Transform3D = previous_root * (local_transforms[index] as Transform3D)
				var transform: Transform3D = candidate_root * (local_transforms[index] as Transform3D)
				## 命中的 child 維持原本完整 sweep 加 endpoint，沒有降低形狀精度。
				if old_contacts.is_empty():
					if _trace_enabled:
						var sweep_prediction_time := float(outer_step) * STEP_SECONDS + float(substep_index + 1) * sub_delta
						var sweep := _sweep_hit_fraction(space, shapes[index] as Shape3D, previous_transform, transform, excluded)
						if float(sweep.fraction) < 1.0 - CONTACT_EPSILON:
							_trace_first_blocker(trace_candidate, _trace_cast_blocker(index, sweep_prediction_time, sweep))
							return {"safe": false, "budget": false, "final_root": root}
					elif _sweep_hits(space, shapes[index] as Shape3D, previous_transform, transform, excluded):
						return {"safe": false, "budget": false, "final_root": root}
				for hit in _hits(space, shapes[index] as Shape3D, transform, excluded, &"narrow"):
					var rid: RID = hit.rid
					var old: Dictionary = old_contacts.get(rid.get_id(), {})
					if old.is_empty() or not _old_contact_separates(old, shapes[index] as Shape3D, snapshot.transforms[index] as Transform3D, transform):
						if _trace_enabled:
							var narrow_prediction_time := float(outer_step) * STEP_SECONDS + float(substep_index + 1) * sub_delta
							_trace_first_blocker(trace_candidate, _trace_blocker_from_hit(&"intersect_shape", index, hit, narrow_prediction_time))
						return {"safe": false, "budget": false, "final_root": root}
			previous_root = candidate_root
	# 最後一段的查詢也可能用盡額度；不能把未完成查詢回傳的空集合當成安全。
	var exhausted := _budget_exhausted(started_usec)
	return {"safe": not exhausted, "budget": exhausted, "final_root": root}


## 共用解算已驗完完整路徑，不再對同一平移重跑另一套 sweep。
func _ground_solver(snapshot: Dictionary, old_contacts: Dictionary, started_usec: int) -> RefCounted:
	if not _tank.has_method(&"create_ground_motion_query"): return null
	var solver: RefCounted = snapshot.get("ground_motion_query")
	if solver == null:
		solver = _tank.call(&"create_ground_motion_query", snapshot)
	solver.at_cap = false
	solver.capture_blocker = _trace_enabled
	solver.blocker = {}
	# 不把含 solver 本身的 snapshot 綁回 callback，避免 RefCounted 循環持有。
	if solver.has_method("reset_prediction"): solver.reset_prediction()
	var contact_snapshot := {"shapes": snapshot.shapes, "transforms": snapshot.transforms}
	solver.set_contact_policy(Callable() if old_contacts.is_empty() else _ground_old_contact_allowed.bind(contact_snapshot, old_contacts))
	solver.queries = int(_stats.query_count)
	solver.query_limit = MAX_QUERIES
	solver.deadline_usec = mini(started_usec + MAX_ELAPSED_USEC, _work_deadline_usec) if _work_deadline_usec > 0 else started_usec + MAX_ELAPSED_USEC
	return solver


func _probe_ground_motion(snapshot: Dictionary, radius: float, movement: float, turn: float, started_usec: int, trace_candidate: Dictionary, old_contacts: Dictionary = {}) -> Dictionary:
	var solver := _ground_solver(snapshot, old_contacts, started_usec)
	var root: Transform3D = snapshot.root
	var speed := float(snapshot.forward_speed)
	var angular := float(snapshot.angular_speed)
	var vertical := float(snapshot.get("vertical_speed", 0.0))
	var grounded := bool(snapshot.get("grounded", false))
	var continuation: Dictionary = (snapshot.get("navigation_continuation", {}) as Dictionary).duplicate(true)
	for outer_step in ceili(HORIZON_SECONDS / STEP_SECONDS):
		if outer_step > 0 and not continuation.is_empty():
			var drift: Vector3 = solver.get("_drift") if solver.has_method("prediction_drift") else Vector3.ZERO
			var command := NavigationControl.forecast(root,speed,angular,-root.basis.x*speed+drift,continuation)
			movement = float(command.movement)
			turn = float(command.turn)
		var preview: Dictionary = solver.predictive_driving_step(speed, angular, movement, turn, STEP_SECONDS) if solver.has_method("predictive_driving_step") else _tank.call(&"predictive_driving_step", speed, angular, movement, turn, STEP_SECONDS)
		if not preview.has("angular_speed"): return {"safe": false, "budget": false, "final_root": root}
		var count := maxi(1, ceili(radius * maxf(absf(angular), absf(float(preview.angular_speed))) * STEP_SECONDS / MAX_SWEEP_DISTANCE))
		var dt := STEP_SECONDS / count
		var result: Dictionary = {}
		var native_count := ceili(STEP_SECONDS * Engine.physics_ticks_per_second)
		if native_segment_enabled and count > native_count and solver.has_method("try_terrain_segment"):
			result = _native_ground_segment(solver, root, speed, angular, movement, turn, native_count, STEP_SECONDS / native_count, vertical, grounded)
		if result.is_empty():
			result = _ground_segment(solver, root, speed, angular, movement, turn, count, dt, vertical, grounded)
		_stats.query_count = int(solver.queries)
		if outer_step == ceili(HORIZON_SECONDS / STEP_SECONDS) - 1:
			_stats["last_segment_safe"] = bool(result.get("safe", false))
			_stats["last_segment_cap"] = bool(solver.at_cap)
		if not bool(result.get("safe", false)) or _budget_exhausted(started_usec):
			if _trace_enabled: _trace_first_blocker(trace_candidate, _trace_ground_blocker(solver, outer_step * STEP_SECONDS + float(result.get("elapsed", 0.0))))
			return {"safe": false, "budget": bool(solver.at_cap) or _budget_exhausted(started_usec), "final_root": root}
		root = result.root
		speed = float(result.speed)
		angular = float(result.angular)
		vertical = float(result.vertical_speed)
		grounded = bool(result.grounded)
	return {"safe": true, "budget": false, "final_root": root}


# Native-rate motion is an alternate approximation, accepted only after a complete
# conservative swept-volume proof. Unknown geometry retains the original fine path.
func _native_ground_segment(solver: RefCounted, root: Transform3D, speed: float, angular: float, movement: float, turn: float, count: int, dt: float, vertical: float, grounded: bool) -> Dictionary:
	var saved_drift: Vector3 = solver.get("_drift")
	var states: Array[Dictionary] = []
	for unused in count:
		var state: Dictionary = solver.predictive_driving_step(speed, angular, movement, turn, dt)
		if not state.has("forward_speed") or not state.has("angular_speed"):
			solver.set("_drift", saved_drift)
			return {}
		speed = float(state.forward_speed)
		angular = float(state.angular_speed)
		state["drift"] = solver.prediction_drift(dt)
		states.append(state)
	var result: Dictionary = solver.try_terrain_segment(root, states, dt, vertical, grounded)
	if result.is_empty(): solver.set("_drift", saved_drift)
	return result


func _ground_segment(solver: RefCounted, root: Transform3D, speed: float, angular: float, movement: float, turn: float, count: int, dt: float, vertical: float, grounded: bool) -> Dictionary:
	solver.blocker = {}
	var states: Array[Dictionary] = []
	var path: Array[Transform3D] = []
	var planned := root
	for unused in count:
		var state: Dictionary = solver.predictive_driving_step(speed, angular, movement, turn, dt) if solver.has_method("predictive_driving_step") else _tank.call(&"predictive_driving_step", speed, angular, movement, turn, dt)
		if not state.has("forward_speed") or not state.has("angular_speed"): return {"safe": false}
		speed = float(state.forward_speed)
		angular = float(state.angular_speed)
		var drift: Vector3 = solver.prediction_drift(dt) if solver.has_method("prediction_drift") else Vector3.ZERO
		state["drift"] = drift
		states.append(state)
	# Native support sampling avoids costly failed continuous-plane proofs at mesh seams.
	# It uses exactly the original states and keeps the complete segment sweep.
	if solver.has_method("try_terrain_segment"):
		var terrain_segment: Dictionary = solver.try_terrain_segment(root, states, dt, vertical, grounded)
		if not terrain_segment.is_empty(): return terrain_segment
	if grounded and solver.has_method("try_flat_segment"):
		var flat: Dictionary = solver.try_flat_segment(root, states, dt)
		if not flat.is_empty(): return flat
	# The legacy flat fallback alone consumes this path; successful segment proofs need no duplicate integration.
	if grounded and is_zero_approx(vertical):
		for state: Dictionary in states:
			planned.basis = Basis(Vector3.UP, float(state.angular_speed) * dt) * planned.basis
			path.append(planned)
			planned.origin += planned.basis * Vector3.LEFT * float(state.forward_speed) * dt + (state.get("drift", Vector3.ZERO) as Vector3)
			path.append(planned)
	if grounded and is_zero_approx(vertical) and solver.flat_path_clear(root, path):
		return {"safe": not solver.at_cap, "root": planned, "speed": speed, "angular": angular, "vertical_speed": 0.0, "grounded": true}
	if solver.at_cap: return {"safe": false}
	var elapsed := 0.0
	for state in states:
		solver.blocker = {}
		elapsed += dt
		var rotated := Transform3D(Basis(Vector3.UP, float(state.angular_speed) * dt) * root.basis, root.origin)
		var result: Dictionary = {"safe": false}
		if is_zero_approx(float(state.angular_speed)) or solver.clear_pose(rotated):
			result = solver.advance(rotated, rotated.basis * Vector3.LEFT * float(state.forward_speed) * dt + (state.get("drift", Vector3.ZERO) as Vector3), dt, vertical, grounded)
		if not bool(result.get("safe", false)): return {"safe": false, "elapsed": elapsed}
		root = result.root
		vertical = float(result.vertical_speed)
		grounded = bool(result.grounded)
	return {"safe": true, "root": root, "speed": speed, "angular": angular, "vertical_speed": vertical, "grounded": grounded}


func _ground_old_contact_allowed(index: int, candidate: Transform3D, rid: RID, _pairs: PackedVector3Array, snapshot: Dictionary, old_contacts: Dictionary) -> bool:
	var old: Dictionary = old_contacts.get(rid.get_id(), {})
	return not old.is_empty() and _old_contact_separates(old, snapshot.shapes[index] as Shape3D, snapshot.transforms[index] as Transform3D, candidate)


func _probe_profile(space: PhysicsDirectSpaceState3D, snapshot: Dictionary, radius: float, part_bounds: Array[Dictionary], excluded: Array[RID], old_contacts: Dictionary, heading: Vector3, started_usec: int, horizon: float, trace_candidate: Dictionary, continuation_state: Dictionary = {}) -> Dictionary:
	var solver := _ground_solver(snapshot, old_contacts, started_usec)
	var grounded := bool(snapshot.get("grounded", false))
	var root: Transform3D = snapshot.root
	var vertical_speed := float(snapshot.get("vertical_speed", 0.0))
	var speed := float(snapshot.forward_speed)
	var angular := float(snapshot.angular_speed)
	var shapes: Array = snapshot.shapes
	var local_transforms: Array = snapshot.root_local_transforms
	var phase: StringName = StringName(continuation_state.get("phase", &"turning"))
	if phase == &"selecting_escape": phase = &"turning"
	var phase_elapsed := float(continuation_state.get("phase_elapsed", 0.0))
	var attempt_elapsed := float(continuation_state.get("attempt_elapsed", 0.0))
	var advance_origin: Vector3 = continuation_state.get("advance_origin", root.origin) as Vector3
	var advance := float(continuation_state.get("positive_advance", 0.0))
	trace_candidate["profile_start_phase"] = phase
	trace_candidate["profile_start_phase_elapsed"] = phase_elapsed
	trace_candidate["profile_start_attempt_elapsed"] = attempt_elapsed
	var last_action := {"movement":0.0,"turn":0.0}
	var deceleration := maxf(float(_tank.get("brake_force_kilonewtons")) / maxf(float(_tank.get("tank_mass_tonnes")), .001), .001)
	for outer_step in range(ceili(horizon / STEP_SECONDS)):
		var forward := root.basis * Vector3.LEFT; forward.y = 0.0; forward = forward.normalized()
		advance = maxf(0.0, (root.origin - advance_origin).dot(heading)) if phase != &"turning" and phase != &"align_settling" else 0.0
		attempt_elapsed += STEP_SECONDS
		var action := Recovery.escape_transition(phase,phase_elapsed,attempt_elapsed,forward,heading,speed,angular,
			advance,deceleration,float(_tank.get("movement_speed")),STEP_SECONDS)
		if bool(action.failed):
			return {"safe":false,"budget":false,"deadline":true,"final_root":root,"phase":phase,"positive_advance":advance,"action":action}
		phase_elapsed = float(action.phase_elapsed)
		if StringName(action.phase) != phase:
			phase = StringName(action.phase)
			if phase == &"advancing": advance_origin = root.origin; advance = 0.0
		last_action = action
		if phase == &"rejoining": return {"safe": advance >= Recovery.PROGRESS_METRES, "budget": false, "final_root":root, "phase":phase, "positive_advance":advance, "action":last_action}
		var movement := float(action.movement); var turn := float(action.turn)
		var preview: Dictionary = _tank.call(&"predictive_driving_step", speed, angular, movement, turn, STEP_SECONDS)
		if not preview.has("angular_speed"): return {"safe":false,"budget":false,"final_root":root,"phase":phase,"positive_advance":advance,"action":last_action}
		var substeps := maxi(1, ceili(radius * maxf(absf(angular),absf(float(preview.angular_speed))) * STEP_SECONDS / MAX_SWEEP_DISTANCE))
		var sub_delta := STEP_SECONDS / float(substeps); var roots: Array[Transform3D] = []; var start := root
		if solver != null:
			var terrain: Dictionary = {}
			var native_count := ceili(STEP_SECONDS * Engine.physics_ticks_per_second)
			if native_segment_enabled and bool(snapshot.get("approximate_rigid", false)) and substeps > native_count and solver.has_method("try_terrain_segment"):
				terrain = _native_ground_segment(solver, root, speed, angular, movement, turn, native_count, STEP_SECONDS / native_count, vertical_speed, grounded)
			if terrain.is_empty():
				terrain = _ground_segment(solver, root, speed, angular, movement, turn, substeps, sub_delta, vertical_speed, grounded)
			_stats.query_count = int(solver.queries)
			if not bool(terrain.get("safe", false)) or _budget_exhausted(started_usec):
				if _trace_enabled: _trace_first_blocker(trace_candidate, _trace_ground_blocker(solver, outer_step * STEP_SECONDS + float(terrain.get("elapsed", 0.0))))
				return {"safe": false, "budget": bool(solver.at_cap) or _budget_exhausted(started_usec), "final_root": root, "phase": phase, "positive_advance": advance, "action": last_action}
			root = terrain.root
			speed = float(terrain.speed)
			angular = float(terrain.angular)
			vertical_speed = float(terrain.vertical_speed)
			grounded = bool(terrain.grounded)
			continue
		for unused in substeps:
			if _budget_exhausted(started_usec): return {"safe":false,"budget":true,"final_root":root,"phase":phase,"positive_advance":advance,"action":last_action}
			var state: Dictionary = _tank.call(&"predictive_driving_step",speed,angular,movement,turn,sub_delta)
			if not state.has("forward_speed") or not state.has("angular_speed"): return {"safe":false,"budget":false,"final_root":root,"phase":phase,"positive_advance":advance,"action":last_action}
			speed = float(state.forward_speed)
			angular = float(state.angular_speed)
			root.basis = Basis(Vector3.UP, angular * sub_delta) * root.basis
			root.origin += root.basis * Vector3.LEFT * speed * sub_delta
			if _tank.has_method(&"predict_ground_pose"):
				var terrain: Dictionary = _tank.call(&"predict_ground_pose", root, sub_delta, vertical_speed)
				if not bool(terrain.get("safe", false)):
					return {"safe": false, "budget": false, "final_root": root, "phase": phase, "positive_advance": advance, "action": last_action}
				root = terrain.root
				vertical_speed = float(terrain.vertical_speed)
			roots.append(root)
		var metrics := _segment_gap_metrics(start,roots); var active: Array[int] = []
		for part in part_bounds:
			var bound := _segment_bound(part,start,roots,float(metrics.translation),float(metrics.half_sine))
			if not _hits(space,bound.shape as Shape3D,bound.transform as Transform3D,excluded,&"broad").is_empty():
				if int(part.count)==1: active.append(int(part.start))
				else:
					for child in part.children as Array:
						var child_bound := _segment_bound(child as Dictionary,start,roots,float(metrics.translation),float(metrics.half_sine))
						if not _hits(space,child_bound.shape as Shape3D,child_bound.transform as Transform3D,excluded,&"broad").is_empty(): active.append(int((child as Dictionary).index))
		var previous := start
		for index_root in roots.size():
			var candidate_root: Transform3D=roots[index_root]
			for index in active:
				var from := previous*(local_transforms[index] as Transform3D); var to := candidate_root*(local_transforms[index] as Transform3D)
				if old_contacts.is_empty():
					if _trace_enabled:
						var sweep := _sweep_hit_fraction(space, shapes[index] as Shape3D, from, to, excluded)
						if float(sweep.fraction) < 1.0 - CONTACT_EPSILON:
							_trace_first_blocker(trace_candidate, _trace_cast_blocker(index, float(outer_step) * STEP_SECONDS + float(index_root + 1) * sub_delta, sweep))
							return {"safe":false,"budget":bool(sweep.budget),"final_root":root,"phase":phase,"positive_advance":advance,"action":last_action}
					elif _sweep_hits(space,shapes[index] as Shape3D,from,to,excluded): return {"safe":false,"budget":false,"final_root":root,"phase":phase,"positive_advance":advance,"action":last_action}
				for hit in _hits(space,shapes[index] as Shape3D,to,excluded,&"narrow"):
					var old: Dictionary=old_contacts.get((hit.rid as RID).get_id(),{})
					if old.is_empty() or not _old_contact_separates(old,shapes[index] as Shape3D,snapshot.transforms[index] as Transform3D,to):
						if _trace_enabled: _trace_first_blocker(trace_candidate, _trace_blocker_from_hit(&"intersect_shape", index, hit, float(outer_step) * STEP_SECONDS + float(index_root + 1) * sub_delta))
						return {"safe":false,"budget":false,"final_root":root,"phase":phase,"positive_advance":advance,"action":last_action}
			previous=candidate_root
	var final_forward := root.basis*Vector3.LEFT; final_forward.y=0.0
	advance=maxf(0.0,(root.origin-advance_origin).dot(heading))
	var exhausted := _budget_exhausted(started_usec)
	# 選向須完成整套動作；continuation 只須完整走完安全的三秒預測窗。
	return {"safe":not continuation_state.is_empty() and not exhausted,"budget":exhausted,"final_root":root,"phase":phase,"positive_advance":advance,"action":last_action}


func _escape_result(safe: bool, candidate: Dictionary, reason: StringName, started_usec: int, heading := Vector3.ZERO, movement := 0.0, turn := 0.0, phase: StringName = &"", advance := 0.0) -> Dictionary:
	_stats.reason=reason; _stats.elapsed_usec=Time.get_ticks_usec()-started_usec; _trace_attach()
	return {"safe":safe,"side":float(candidate.get("side",0.0)),"angle":float(candidate.get("angle",0.0)),"heading":heading,"movement":movement,"turn":turn,"phase":phase,"positive_advance":advance,"reason":reason,"stats":get_stats()}


func _hits(space: PhysicsDirectSpaceState3D, shape: Shape3D, transform: Transform3D, excluded: Array[RID], kind: StringName = &"narrow") -> Array:
	if int(_stats.query_count) >= MAX_QUERIES:
		_stats.at_cap = true
		return []
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = transform
	query.margin = 0.002
	query.collision_mask = int(_tank.collision_mask)
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits := space.intersect_shape(query, MAX_HITS)
	_stats.query_count = int(_stats.query_count) + 1
	_stats["broad_queries" if kind == &"broad" else "narrow_queries"] = int(_stats.get("broad_queries" if kind == &"broad" else "narrow_queries", 0)) + 1
	if hits.size() >= MAX_HITS:
		_stats.at_cap = true
	if kind == &"narrow" and not hits.is_empty() and _tank.has_method(&"shape_has_only_ground_contacts"):
		_stats.query_count = int(_stats.query_count) + 1
		if bool(_tank.call(&"shape_has_only_ground_contacts", shape, transform, excluded)):
			return []
	return hits


func _sweep_hits(space: PhysicsDirectSpaceState3D, shape: Shape3D, from: Transform3D, to: Transform3D, excluded: Array[RID]) -> bool:
	if int(_stats.query_count) >= MAX_QUERIES:
		_stats.at_cap = true
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = from
	query.motion = to.origin - from.origin
	query.margin = 0.002
	query.collision_mask = int(_tank.collision_mask)
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var fractions := space.cast_motion(query)
	_stats.query_count = int(_stats.query_count) + 1
	_stats.narrow_queries = int(_stats.narrow_queries) + 1
	return fractions.size() >= 1 and float(fractions[0]) < 1.0 - CONTACT_EPSILON


func _sweep_hit_fraction(space: PhysicsDirectSpaceState3D, shape: Shape3D, from: Transform3D, to: Transform3D, excluded: Array[RID]) -> Dictionary:
	if int(_stats.query_count) >= MAX_QUERIES:
		_stats.at_cap = true
		return {"fraction": 0.0, "queried": false, "budget": true}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = from
	query.motion = to.origin - from.origin
	query.margin = 0.002
	query.collision_mask = int(_tank.collision_mask)
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var fractions := space.cast_motion(query)
	_stats.query_count = int(_stats.query_count) + 1
	_stats.narrow_queries = int(_stats.narrow_queries) + 1
	return {"fraction": float(fractions[0]) if fractions.size() >= 1 else 1.0, "queried": true, "budget": false}


func _old_contact_separates(old: Dictionary, shape: Shape3D, initial: Transform3D, candidate: Transform3D) -> bool:
	var normal: Vector3 = old.normal
	var convex := shape as ConvexPolygonShape3D
	if not normal.is_finite() or convex == null or convex.points.is_empty():
		return false
	## 不能只看 shape origin：所有凸形頂點都須往接觸法線外側，避免車尾旋入同一 body。
	for point in convex.points:
		if normal.dot(candidate * point - initial * point) <= CONTACT_EPSILON:
			return false
	return true


func _contact_normal(hit: Dictionary, root: Transform3D) -> Vector3:
	var collider := hit.get("collider") as Node3D
	if collider != null:
		var normal := root.origin - collider.global_position
		normal.y = 0.0
		if not normal.is_zero_approx():
			return normal.normalized()
	return Vector3.ZERO


func _snapshot_radius(shapes: Array, transforms: Array, root: Transform3D) -> float:
	var radius := 0.1
	for index in shapes.size():
		var convex := shapes[index] as ConvexPolygonShape3D
		if convex == null:
			return 1000.0
		for point in convex.points:
			radius = maxf(radius, root.origin.distance_to((transforms[index] as Transform3D) * point))
	return radius + 0.01


func _root_transforms(root: Transform3D, local_transforms: Array) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for local_transform in local_transforms:
		transforms.append(root * (local_transform as Transform3D))
	return transforms


func _part_local_bounds(shapes: Array, local_transforms: Array, part_ranges: Array, cached_vertices: Array = []) -> Array[Dictionary]:
	var bounds: Array[Dictionary] = []
	for part_range in part_ranges:
		var has_point := false
		var minimum := Vector3.ZERO
		var maximum := Vector3.ZERO
		var start := int(part_range.get("start", 0))
		var count := int(part_range.get("count", 0))
		var children: Array[Dictionary] = []
		for index in range(start, start + count):
			var convex := shapes[index] as ConvexPolygonShape3D
			var child_minimum := Vector3.ZERO
			var child_maximum := Vector3.ZERO
			var child_has_point := false
			var vertices: PackedVector3Array = cached_vertices[index] if cached_vertices.size() == shapes.size() else convex.points
			for point in vertices:
				var local_point := (local_transforms[index] as Transform3D) * point
				minimum = local_point if not has_point else minimum.min(local_point)
				maximum = local_point if not has_point else maximum.max(local_point)
				has_point = true
				child_minimum = local_point if not child_has_point else child_minimum.min(local_point)
				child_maximum = local_point if not child_has_point else child_maximum.max(local_point)
				child_has_point = true
			if child_has_point:
				var child_aabb := AABB(child_minimum, child_maximum - child_minimum)
				var child_radius := 0.0
				for endpoint in 8:
					child_radius = maxf(child_radius, child_aabb.get_endpoint(endpoint).length())
				children.append({"index": index, "aabb": child_aabb, "pivot_radius": child_radius})
		if has_point:
			var aabb := AABB(minimum, maximum - minimum)
			var pivot_radius := 0.0
			for endpoint in 8:
				pivot_radius = maxf(pivot_radius, aabb.get_endpoint(endpoint).length())
			bounds.append({"start": start, "count": count, "aabb": aabb, "pivot_radius": pivot_radius, "children": children})
	return bounds


func _segment_gap_metrics(segment_start: Transform3D, segment_roots: Array[Transform3D]) -> Dictionary:
	var previous := segment_start
	var maximum_translation := 0.0
	var maximum_half_sine := 0.0
	for pose in segment_roots:
		maximum_translation = maxf(maximum_translation, pose.origin.distance_to(previous.origin))
		var cosine := clampf(previous.basis.x.dot(pose.basis.x), -1.0, 1.0)
		maximum_half_sine = maxf(maximum_half_sine, sin(acos(cosine) * 0.5))
		previous = pose
	return {"translation": maximum_translation, "half_sine": maximum_half_sine}


func _segment_bound(part_bound: Dictionary, segment_start: Transform3D, segment_roots: Array[Transform3D], maximum_translation: float, maximum_half_sine: float) -> Dictionary:
	var swept: AABB = segment_start * (part_bound.aabb as AABB)
	for pose in segment_roots:
		swept = swept.merge(pose * (part_bound.aabb as AABB))
	var margin := maximum_translation + 2.0 * float(part_bound.pivot_radius) * maximum_half_sine + 0.002
	## union 含所有端點；此 grow 包住端點間的平移與 root yaw 弧，另加 shape query margin。
	var size := swept.size + Vector3.ONE * margin * 2.0
	var shape := BoxShape3D.new()
	shape.size = size
	return {"shape": shape, "transform": Transform3D(Basis.IDENTITY, swept.get_center())}


func _candidates(movement: float, turn: float, allow_reverse: bool, contact: bool) -> Array[Dictionary]:
	var low_forward := minf(LOW_SPEED_METERS_PER_SECOND / maxf(float(_tank.movement_speed), 0.01), 1.0)
	var low_movement := signf(movement) * low_forward
	var candidates: Array[Dictionary] = [{"movement": movement, "turn": turn}, {"movement": low_movement, "turn": turn * 0.5}, {"movement": low_movement, "turn": 0.0}]
	if contact:
		candidates.append({"movement": low_forward, "turn": 0.0})
	candidates.append_array([{"movement": low_forward, "turn": -0.4}, {"movement": low_forward, "turn": 0.4}, {"movement": 0.0, "turn": -0.4}, {"movement": 0.0, "turn": 0.4}, {"movement": 0.0, "turn": 0.0}])
	if allow_reverse:
		candidates.append({"movement": -minf(LOW_SPEED_METERS_PER_SECOND / maxf(float(_tank.reverse_movement_speed), 0.01), 1.0), "turn": 0.0})
	var unique: Array[Dictionary] = []
	for candidate in candidates:
		if unique.size() >= MAX_CANDIDATES:
			break
		if not is_finite(float(candidate.movement)) or not is_finite(float(candidate.turn)):
			continue
		var duplicate := false
		for prior in unique:
			duplicate = duplicate or (is_equal_approx(float(prior.movement), float(candidate.movement)) and is_equal_approx(float(prior.turn), float(candidate.turn)))
		if not duplicate:
			unique.append({"movement": clampf(float(candidate.movement), -1.0, 1.0), "turn": clampf(float(candidate.turn), -1.0, 1.0)})
	return unique


func _recovery_candidates(movement: float, turn: float) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var low_turn := 0.0
	if not is_zero_approx(movement):
		var low_movement := signf(movement) * minf(absf(movement), 0.1)
		low_turn = clampf(turn, -0.2, 0.2)
		candidates = [
			{"movement": low_movement, "turn": low_turn}, {"movement": low_movement, "turn": 0.0},
			{"movement": low_movement, "turn": -0.2}, {"movement": low_movement, "turn": 0.2},
			{"movement": 0.0, "turn": -0.2}, {"movement": 0.0, "turn": 0.2},
		]
	else:
		low_turn = signf(turn) * minf(absf(turn), 0.2)
		candidates = [{"movement": 0.0, "turn": low_turn}, {"movement": 0.0, "turn": -low_turn}]
	return _unique_candidates(candidates, MAX_CANDIDATES - 1)


func _unique_candidates(candidates: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var unique: Array[Dictionary] = []
	for candidate in candidates:
		if unique.size() >= limit:
			break
		if not is_finite(float(candidate.movement)) or not is_finite(float(candidate.turn)):
			continue
		var duplicate := false
		for prior in unique:
			duplicate = duplicate or (is_equal_approx(float(prior.movement), float(candidate.movement)) and is_equal_approx(float(prior.turn), float(candidate.turn)))
		if not duplicate:
			unique.append({"movement": clampf(float(candidate.movement), -1.0, 1.0), "turn": clampf(float(candidate.turn), -1.0, 1.0)})
	return unique


func _score(final_root: Transform3D, initial_root: Transform3D, goal: Vector3, contacts: Dictionary) -> float:
	var progress := Vector2(goal.x - initial_root.origin.x, goal.z - initial_root.origin.z).length() - Vector2(goal.x - final_root.origin.x, goal.z - final_root.origin.z).length()
	var separation := 0.0
	for item in contacts.values():
		var normal: Vector3 = item.normal
		separation += normal.dot(final_root.origin - initial_root.origin)
	var initial_to_goal := goal - initial_root.origin
	initial_to_goal.y = 0.0
	var final_to_goal := goal - final_root.origin
	final_to_goal.y = 0.0
	var initial_forward := initial_root.basis * Vector3.LEFT
	initial_forward.y = 0.0
	var final_forward := final_root.basis * Vector3.LEFT
	final_forward.y = 0.0
	var initial_heading := initial_forward.normalized().dot(initial_to_goal.normalized()) if not initial_forward.is_zero_approx() and not initial_to_goal.is_zero_approx() else 0.0
	var final_heading := final_forward.normalized().dot(final_to_goal.normalized()) if not final_forward.is_zero_approx() and not final_to_goal.is_zero_approx() else 0.0
	## 行程進展與接觸分離優先；朝向只取相對初姿態的改善，靜止煞車不會憑絕對朝向得分。
	return progress + separation * 4.0 + (final_heading - initial_heading) * 0.05


func _command_root(snapshot: Dictionary, movement: float, turn: float, delta: float) -> Transform3D:
	var root: Transform3D = snapshot.root
	var execution_delta := clampf(delta, 0.0, STEP_SECONDS)
	if is_zero_approx(execution_delta):
		return root
	var state: Dictionary = _tank.call(&"predictive_driving_step", float(snapshot.forward_speed), float(snapshot.angular_speed), movement, turn, execution_delta)
	if not state.has("forward_speed") or not state.has("angular_speed"):
		return root
	root = root.rotated_local(Vector3.UP, float(state.angular_speed) * execution_delta)
	root.origin += root.basis * Vector3.LEFT * float(state.forward_speed) * execution_delta
	return root


## trace 只收既有查詢的回傳 scalar；碰撞物件路徑及 JSON 化由 recorder 在計時區外處理。
func _trace_begin() -> void:
	_trace_enabled = _tank != null and is_instance_valid(_tank) and _tank.has_method(&"is_driving_trace_enabled") and bool(_tank.call(&"is_driving_trace_enabled"))
	_trace_request_frame = Engine.get_physics_frames() if _trace_enabled else -1
	_trace_candidates.clear()
	_trace_initial_contacts.clear()
	_trace_initial_truncated = false
	_trace_shape_parts.clear()


func _trace_prepare_shape_parts(snapshot: Dictionary) -> void:
	if not _trace_enabled:
		return
	_trace_shape_parts.resize((snapshot.shapes as Array).size())
	for shape_index in _trace_shape_parts.size():
		_trace_shape_parts[shape_index] = {}
	for part_range in snapshot.part_ranges as Array:
		var part: Dictionary = {}
		if part_range.has("part_id"):
			part["part_id"] = part_range.part_id
		if part_range.has("anchor"):
			part["anchor"] = part_range.anchor
		for shape_index in range(int(part_range.get("start", 0)), int(part_range.get("start", 0)) + int(part_range.get("count", 0))):
			if shape_index >= 0 and shape_index < _trace_shape_parts.size():
				_trace_shape_parts[shape_index] = part


func _trace_candidate(movement: float, turn: float) -> Dictionary:
	if not _trace_enabled:
		return {}
	return {"movement": movement, "turn": turn}


func _trace_finish_candidate(candidate: Dictionary, probe: Dictionary) -> int:
	if not _trace_enabled:
		return -1
	candidate["safe"] = bool(probe.safe)
	candidate["budget"] = bool(probe.budget)
	_trace_candidates.append(candidate)
	return _trace_candidates.size() - 1


func _trace_set_score(candidate_index: int, score: float) -> void:
	if _trace_enabled and candidate_index >= 0 and candidate_index < _trace_candidates.size():
		var candidate: Dictionary = _trace_candidates[candidate_index]
		candidate["score"] = score
		_trace_candidates[candidate_index] = candidate


func _trace_first_blocker(candidate: Dictionary, blocker: Dictionary) -> void:
	if _trace_enabled and not candidate.is_empty() and not candidate.has("first_blocker"):
		candidate["first_blocker"] = blocker


func _trace_part(shape_index: int) -> Dictionary:
	return _trace_shape_parts[shape_index] if shape_index >= 0 and shape_index < _trace_shape_parts.size() else {}


func _trace_ground_blocker(solver: RefCounted, prediction_time: float) -> Dictionary:
	var evidence: Dictionary = solver.blocker
	var index := int(evidence.get("shape_index", -1))
	var part := _trace_part(index)
	return {
		"source": evidence.get("source", &"query_budget" if solver.at_cap else &"ground_support"),
		"shape_index": index, "part_id": part.get("part_id", null), "anchor": part.get("anchor", null),
		"prediction_time_seconds": prediction_time, "safe_fraction": evidence.get("safe_fraction"),
		"collider_id": null, "collider_shape": null, "collider_unknown": true,
	}


func _trace_blocker_from_hit(source: StringName, shape_index: int, hit: Dictionary, prediction_time_seconds: float) -> Dictionary:
	var part := _trace_part(shape_index)
	return {
		"source": str(source), "shape_index": shape_index,
		"part_id": part.get("part_id", null), "anchor": part.get("anchor", null),
		"prediction_time_seconds": prediction_time_seconds,
		"collider_id": hit.get("collider_id", null), "collider_shape": hit.get("shape", null),
		"collider_unknown": not hit.has("collider_id"), "safe_fraction": null,
	}


func _trace_cast_blocker(shape_index: int, prediction_time_seconds: float, sweep: Dictionary) -> Dictionary:
	var part := _trace_part(shape_index)
	if not bool(sweep.queried):
		return {
			"source": "query_budget", "shape_index": shape_index,
			"part_id": part.get("part_id", null), "anchor": part.get("anchor", null),
			"prediction_time_seconds": prediction_time_seconds,
			"collider_id": null, "collider_shape": null, "collider_unknown": true, "safe_fraction": null,
			"queried": false, "budget": true,
		}
	return {
		"source": "cast_motion", "shape_index": shape_index,
		"part_id": part.get("part_id", null), "anchor": part.get("anchor", null),
		"prediction_time_seconds": prediction_time_seconds,
		"collider_id": null, "collider_shape": null, "collider_unknown": true, "safe_fraction": float(sweep.fraction),
		"queried": true, "budget": false,
	}


func _trace_initial_contact(contact: Dictionary) -> void:
	if not _trace_enabled:
		return
	if _trace_initial_contacts.size() >= 8:
		_trace_initial_truncated = true
		return
	_trace_initial_contacts.append(contact)


func _trace_attach() -> void:
	if _trace_enabled:
		_stats.trace = {
			"request_frame": _trace_request_frame,
			"candidates": _trace_candidates,
			"initial_contacts": _trace_initial_contacts,
			"initial_contacts_truncated": _trace_initial_truncated,
		}


func _budget_exhausted(started_usec: int) -> bool:
	if _work_deadline_usec > 0 and Time.get_ticks_usec() >= _work_deadline_usec: return true
	if int(_stats.query_count) >= MAX_QUERIES or bool(_stats.at_cap):
		return true
	return started_usec > 0 and Time.get_ticks_usec() - started_usec >= MAX_ELAPSED_USEC


func _result(movement: float, turn: float, intervened: bool, contact: bool, reason: StringName, started_usec: int) -> Dictionary:
	_stats.reason = reason
	_stats.elapsed_usec = Time.get_ticks_usec() - started_usec
	## 所有安全決策與 elapsed 都已固定後才封裝，get_stats 的 deep copy 不在查詢計時路徑內。
	_trace_attach()
	return {"movement": movement, "turn": turn, "intervened": intervened, "contact": contact, "reason": reason, "stats": get_stats()}


func _empty_stats(reason: StringName) -> Dictionary:
	return {"near_verified": false, "far_status": &"not_run", "prediction_mode": &"legacy", "query_count": 0, "broad_queries": 0, "narrow_queries": 0, "elapsed_usec": 0, "reason": reason, "at_cap": false, "horizon_seconds": HORIZON_SECONDS, "step_seconds": STEP_SECONDS}


func _choose_handoff_step(snapshot: Dictionary, radius: float, bounds: Array[Dictionary], space: PhysicsDirectSpaceState3D, excluded: Array[RID], movement: float, turn: float, delta: float, started_usec: int) -> Dictionary:
	var dt := 1.0 / Engine.physics_ticks_per_second
	if absf(delta - dt) > 0.00001 or not (_tank is RigidBody3D): return {}
	var captured := RigidMotion.capture(_tank as RigidBody3D, snapshot)
	if captured.is_empty(): return {}
	var trace := _trace_candidate(movement, turn)
	trace["phase"] = "handoff_near"
	var near := _probe_braking(snapshot, captured, radius, movement, turn, dt, started_usec)
	if _trace_enabled: trace["braking_profiles"] = (_stats.get("braking_profiles", {}) as Dictionary).duplicate(true)
	if near.is_empty():
		trace["near_unknown_reason"] = str(_stats.get("near_unknown_reason", "unknown"))
		_trace_finish_candidate(trace, {"safe": false, "budget": false})
		return {}
	_trace_finish_candidate(trace, near)
	if bool(near.budget) or _budget_exhausted(started_usec):
		_stats["handoff_validation"] = "hard_budget"
		return _result(0.0, 0.0, true, false, &"budget", started_usec)
	if not bool(near.safe): return _result(0.0, 0.0, true, false, &"blocked", started_usec)
	_stats.near_verified = true
	_stats.prediction_mode = &"layered_handoff"
	var far_trace := _trace_candidate(movement, turn)
	far_trace["phase"] = "handoff_full_horizon"
	_work_deadline_usec = mini(started_usec + MAX_ELAPSED_USEC, Time.get_ticks_usec() + FAR_WORK_USEC)
	var far := _probe(space, snapshot, radius, bounds, excluded, {}, movement, turn, started_usec, far_trace)
	_work_deadline_usec = 0
	_trace_finish_candidate(far_trace, far)
	# A soft far deadline cannot revoke the near certificate. The actual shared
	# query/time ceiling still prevents this request from issuing a command.
	_stats.at_cap = int(_stats.query_count) >= MAX_QUERIES
	if bool(_stats.at_cap) or Time.get_ticks_usec() - started_usec >= MAX_ELAPSED_USEC:
		_stats.near_verified = false
		_stats.far_status = &"unknown"
		_stats["handoff_validation"] = "hard_budget"
		return _result(0.0, 0.0, true, false, &"budget", started_usec)
	if not bool(far.budget) and bool(far.safe):
		_stats.far_status = &"clear"
		_stats["handoff_validation"] = "full_horizon_clear"
		return _result(movement, turn, false, false, &"clear", started_usec)
	_stats.far_status = &"unknown" if bool(far.budget) else &"blocked"
	_stats["handoff_validation"] = "far_soft_unknown" if bool(far.budget) else "far_blocked"
	return _result(movement, turn, false, false, &"near_only", started_usec)

# Flat-only finite model: whole hull/turret/gun sweep plus calibrated pose reserve.
func _choose_layered(snapshot: Dictionary, radius: float, movement: float, turn: float, goal: Vector3, delta: float, allow_reverse: bool, allow_adjustment: bool, started_usec: int) -> Dictionary:
	var dt := 1.0 / Engine.physics_ticks_per_second
	if absf(delta - dt) > 0.00001 or not (_tank is RigidBody3D): return {}
	var captured := RigidMotion.capture(_tank as RigidBody3D, snapshot)
	if captured.is_empty(): return {}
	captured.config.braking_feedforward = true
	var desired: Array[Dictionary] = [{"movement": movement, "turn": turn}]
	if allow_adjustment:
		for candidate in _candidates(movement, turn, allow_reverse, false):
			if not (is_equal_approx(float(candidate.movement), movement) and is_equal_approx(float(candidate.turn), turn)):
				desired.append(candidate)
	var best: Dictionary = {}
	var near_known := false
	var candidate_unknown := false
	var last_near_usec := 0
	for candidate in desired:
		# Leave the existing terrain fallback time when no near result is known.
		# The nominal dual-stop probe always finishes before this soft check.
		# Admit another unknown candidate only when the previous near cost fits the
		# remaining soft window. This estimate never changes the hard safety cap.
		if candidate_unknown and not near_known and best.is_empty() and Time.get_ticks_usec() - started_usec + last_near_usec > FAR_WORK_USEC: break
		if not best.is_empty() and Time.get_ticks_usec() >= started_usec + FAR_WORK_USEC: break
		var trace := _trace_candidate(float(candidate.movement), float(candidate.turn))
		var near_started_usec := Time.get_ticks_usec()
		var near := _probe_braking(snapshot, captured, radius, float(candidate.movement), float(candidate.turn), dt, started_usec)
		last_near_usec = Time.get_ticks_usec() - near_started_usec
		if _trace_enabled: trace["braking_profiles"] = (_stats.get("braking_profiles", {}) as Dictionary).duplicate(true)
		if near.is_empty():
			trace["near_unknown_reason"] = str(_stats.get("near_unknown_reason", "unknown"))
			_trace_finish_candidate(trace, {"safe": false, "budget": false})
			if best.is_empty():
				# A mesh witness rejects this trajectory, not every other command.
				# Request-wide support/model unknown still uses the terrain fallback.
				var failure: Dictionary = _stats.get("near_failure_detail", {})
				if str(_stats.get("near_unknown_reason", "")) == "braking_sweep:B16" and not (failure.get("mesh_oriented_failure", {}) as Dictionary).is_empty():
					candidate_unknown = true
					continue
				return {}
			break
		near_known = true
		_trace_finish_candidate(trace, near)
		if bool(near.budget):
			if best.is_empty(): return _result(0.0, 0.0, true, false, &"budget", started_usec)
			break
		if not bool(near.safe): continue
		var score := _score(_command_root(snapshot, float(candidate.movement), float(candidate.turn), delta), snapshot.root as Transform3D, goal, {})
		var is_nominal := is_equal_approx(float(candidate.movement), movement) and is_equal_approx(float(candidate.turn), turn)
		var risk := &"unknown"
		if (is_nominal or score > 0.0) and Time.get_ticks_usec() < started_usec + FAR_WORK_USEC:
			_work_deadline_usec = started_usec + FAR_WORK_USEC
			var far := _probe_ground_motion(snapshot, radius, float(candidate.movement), float(candidate.turn), started_usec, {}, {})
			_work_deadline_usec = 0
			if not bool(far.budget): risk = &"clear" if bool(far.safe) else &"blocked"
			# Soft far exhaustion never invalidates an already checked near path.
			_stats.at_cap = int(_stats.query_count) >= MAX_QUERIES
		if risk == &"blocked": score -= 0.05
		if best.is_empty() or score > float(best.score):
			best = {"movement": candidate.movement, "turn": candidate.turn, "score": score, "risk": risk}
		if (is_nominal or score > 0.0) and risk != &"blocked": break
	if not best.is_empty():
		_stats.near_verified = true
		_stats.far_status = best.risk
		_stats.prediction_mode = &"layered_flat"
		var changed := not is_equal_approx(float(best.movement), movement) or not is_equal_approx(float(best.turn), turn)
		return _result(float(best.movement), float(best.turn), changed, false, &"risk" if changed else &"clear", started_usec)
	if near_known:
		_stats.prediction_mode = &"layered_flat"
		# Zero input is the existing fallback, not a claim of verified safe stopping.
		return _result(0.0, 0.0, true, false, &"blocked", started_usec)
	return {}


func _probe_braking(snapshot: Dictionary, captured: Dictionary, radius: float, movement: float, turn: float, dt: float, started_usec: int) -> Dictionary:
	_stats["braking_profiles"] = {"feedforward": {"outcome": "not_run"}, "feedback_only": {"outcome": "not_run"}}
	_stats.erase("near_failure_detail")
	_stats.erase("near_unknown_reason")
	# Reject a known unsupported flat domain before constructing its two braking trajectories.
	# This is only an early fallback; the complete BrakingSweep remains authoritative.
	var support_solver := _ground_solver(snapshot, {}, started_usec)
	var support: Dictionary = support_solver._support(snapshot.root as Transform3D, 0.0)
	_stats.query_count = int(support_solver.queries)
	if support_solver.at_cap or _budget_exhausted(started_usec): return {"safe": false, "budget": true}
	var hits: Array = support.get("raw_hits", [])
	if not bool(support.get("supported", false)) or hits.size() != 4:
		_stats["near_unknown_reason"] = "initial_support"
		return {}
	var floor_y: float = hits[0].hit.position.y
	for record: Dictionary in hits:
		if (record.hit.normal as Vector3).distance_to(Vector3.UP) > 0.000001 or absf((record.hit.position as Vector3).y - floor_y) > 0.00001:
			_stats["near_unknown_reason"] = "mixed_support"
			return {}
	# Both calibrated trajectories must clear: nominal drive feedforward can overstate
	# braking during intermittent spring contact. The feedback-only release adds its
	# longer stopping path without discarding the nominal turning trajectory.
	for feedforward in [true, false]:
		var checked := _probe_braking_model(snapshot, captured, radius, movement, turn, dt, started_usec, feedforward)
		var profile_key := "feedforward" if feedforward else "feedback_only"
		var profile: Dictionary = _stats.braking_profiles[profile_key]
		profile["outcome"] = "unknown" if checked.is_empty() else ("budget" if bool(checked.budget) else ("safe" if bool(checked.safe) else "unsafe"))
		if checked.is_empty():
			_stats["near_failure_detail"] = (snapshot.ground_motion_query as RefCounted).diagnostic.duplicate(true)
			_stats["near_unknown_reason"] = "braking_sweep:" + str((snapshot.ground_motion_query as RefCounted).diagnostic.get("braking_unknown", "missing"))
			return checked
		if bool(checked.budget) or not bool(checked.safe): return checked
	return {"safe": true, "budget": false}


func _probe_braking_model(snapshot: Dictionary, captured: Dictionary, radius: float, movement: float, turn: float, dt: float, started_usec: int, feedforward: bool) -> Dictionary:
	var model_started := Time.get_ticks_usec()
	assert(int(captured.physics_frame) == Engine.get_physics_frames())
	var model := RigidMotion.new()
	var parameters: Dictionary = captured.config.duplicate()
	parameters.braking_feedforward = feedforward
	model.initialize(parameters, captured.initial)
	var path: Array[Transform3D] = [snapshot.root as Transform3D]
	var tail := INF
	var vertex_speed := model.velocity.length() + radius * absf(model.angular)
	for tick in 900:
		if tick % 12 == 0 and _budget_exhausted(started_usec): return {"safe": false, "budget": true}
		model.step(movement if tick == 0 else 0.0, turn if tick == 0 else 0.0, tick > 0, dt)
		path.append(model.root)
		vertex_speed = maxf(vertex_speed, model.velocity.length() + radius * absf(model.angular))
		if tick % 6 == 0:
			tail = model.remaining_vertex_travel(radius, dt)
			if tail <= 0.002: break
	if tail > 0.002: return {"safe": false, "budget": false}
	var solver := _ground_solver(snapshot, {}, started_usec)
	# Finite flat pose calibration scales with motion; stationary snapshots are exact.
	var reserve := 0.01 + 0.08 * vertex_speed + tail
	var sweep_started := Time.get_ticks_usec()
	var checked := BrakingSweep.check(solver, snapshot.root as Transform3D, path, reserve, vertex_speed)
	var profiles: Dictionary = _stats.get("braking_profiles", {})
	profiles["feedforward" if feedforward else "feedback_only"] = {"model_usec": sweep_started-model_started, "sweep_usec": Time.get_ticks_usec()-sweep_started, "at_cap": solver.at_cap, "queries": solver.queries, "stages": solver.diagnostic.get("braking_profile", {}).duplicate(), "unknown": checked.is_empty()}
	_stats["braking_profiles"] = profiles
	_stats.query_count = int(solver.queries)
	if bool(solver.at_cap) or _budget_exhausted(started_usec): return {"safe": false, "budget": true}
	if checked.is_empty(): return {}
	return {"safe": bool(checked.safe), "budget": false}
