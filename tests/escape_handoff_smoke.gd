## H2/H3 的有限脫困合約：真 Tank1 完整形狀 profile 與 Recovery 額度／生命週期。
## 不重播 H1 記錄，也不宣稱所有車型或地形都由此覆蓋。
extends SceneTree

const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const Recovery := preload("res://src/ai/tank_recovery.gd")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const DT := 1.0 / 60.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for side in [-1.0, 1.0]:
		await _validate_mirrored_gun_advance_block(side)
	_validate_locked_heading_and_bounded_handoff_failures()
	if _failures.is_empty():
		print("ESCAPE_HANDOFF PASS: mirrored gun profile rejects, heading remains locked, unsafe handoff uses three bounded attempts.")
		quit(0)
		return
	for failure in _failures:
		push_error("ESCAPE_HANDOFF FAIL: %s" % failure)
	quit(1)


## 無 contact 的鏡像障礙：先證明完整 10 秒 profile 可走，再只在該方向前移路徑放入 gun blocker。
## 單一候選不得以另一側替代；拒絕須是安全拒絕，而不是 query budget 偽綠。
func _validate_mirrored_gun_advance_block(side: float) -> void:
	var fixture := await _open_fixture()
	if fixture.is_empty():
		return
	var tank := fixture.tank as CharacterBody3D
	var predictor := Predictor.new()
	predictor.setup(tank)
	var forward := _forward(tank)
	var candidate := {"side": side, "angle": Recovery.ESCAPE_ANGLE}
	var clear: Dictionary = predictor.choose_escape_profile(forward, [candidate], DT)
	if not bool(clear.get("safe", false)) or float(clear.get("positive_advance", 0.0)) < Recovery.PROGRESS_METRES:
		_fail("Mirror %.0f open single-candidate profile must complete turn/settle/advance with >=%.1fm progress; result=%s." % [side, Recovery.PROGRESS_METRES, clear])
		await _free_fixture(fixture)
		return
	var heading := clear.get("heading", Vector3.ZERO) as Vector3
	if heading.is_zero_approx() or signf(forward.signed_angle_to(heading, Vector3.UP)) != signf(side):
		_fail("Mirror %.0f profile must retain its requested side heading; forward=%s heading=%s result=%s." % [side, forward, heading, clear])
		await _free_fixture(fixture)
		return
	## 已選 heading 的 continuation 以 Recovery 當前 phase/progress 起算；三秒安全窗不必完成整段 escape。
	var recovery := Recovery.new()
	recovery.reset(tank.stable_world_center(), forward)
	recovery.blocked_forward = forward
	recovery.select_escape(candidate)
	var continuation: Dictionary = predictor.choose_escape_profile(forward, [{"heading": heading}], DT, recovery.escape_profile_state())
	var continuation_trace := _first_profile_trace(continuation.get("stats", {}) as Dictionary)
	if not bool(continuation.get("safe", false)) or not is_equal_approx(float(continuation_trace.get("profile_horizon", 0.0)), Predictor.HORIZON_SECONDS) \
			or StringName(continuation_trace.get("profile_start_phase", &"")) != &"turning" or (continuation.get("heading", Vector3.ZERO) as Vector3).angle_to(heading) > 0.0001:
		_fail("Mirror %.0f selected-heading continuation must preserve Recovery phase/heading and accept a collision-free three-second window without requiring completion; result=%s trace=%s." % [side, continuation, continuation_trace])
		await _free_fixture(fixture)
		return
	## 牆面留足轉向淨空，只在轉完後約 0.8m 的正向前移讓 gun 首先碰撞。
	## 障礙只覆蓋 gun 最低 10cm，並明確高於兩側履帶的完整 world bounds。
	var gun_distance := _rotated_gun_support(tank, heading)
	var gun_band := _isolated_gun_band(tank)
	if not bool(gun_band.get("isolated", false)):
		_fail("Mirror %.0f fixture cannot isolate gun above both tracks; geometry=%s." % [side, gun_band])
		await _free_fixture(fixture)
		return
	var blocker_position: Vector3 = tank.stable_world_center() + heading * (gun_distance + 0.95)
	blocker_position.y = float(gun_band.center_y)
	var blocker := _box(blocker_position, Vector3(0.30, float(gun_band.height), 8.0))
	fixture.world.add_child(blocker)
	print("ESCAPE_HANDOFF_GUN_FIXTURE side=%.0f gun_y=[%.3f,%.3f] tracks_max_y=%.3f blocker_y=[%.3f,%.3f] advance_offset=%.3f" % [side, float(gun_band.gun_min_y), float(gun_band.gun_max_y), float(gun_band.track_max_y), float(gun_band.lower_y), float(gun_band.upper_y), gun_distance + 0.95])
	await physics_frame
	var blocked: Dictionary = predictor.choose_escape_profile(forward, [candidate], DT)
	var stats: Dictionary = blocked.get("stats", {}) as Dictionary
	if bool(blocked.get("safe", true)) or StringName(blocked.get("reason", &"")) == &"budget" or bool(stats.get("at_cap", false)):
		_fail("Mirror %.0f gun-blocked advance must reject its only complete profile without treating budget exhaustion as safe; result=%s." % [side, blocked])
	else:
		var profile_trace := _first_profile_trace(stats)
		if not profile_trace.has("profile_heading") or not profile_trace.has("profile_phase") or not profile_trace.has("profile_positive_advance"):
			_fail("Mirror %.0f profile rejection must retain heading, phase and projected advance diagnostics; trace=%s." % [side, profile_trace])
			await _free_fixture(fixture)
			return
		var blocker_data := profile_trace.get("first_blocker", {}) as Dictionary
		if blocker_data.get("part_id", "") != "gun":
			_fail("Mirror %.0f advance blocker must be observed through the full gun shape, not a hull-only shortcut; blocker=%s stats=%s." % [side, blocker_data, stats])
	await _free_fixture(fixture)


## 選定方向不能逐幀偷換；三次不安全 handoff 必須收斂到 terminal，reset 必須清掉新狀態。
func _validate_locked_heading_and_bounded_handoff_failures() -> void:
	var recovery := Recovery.new()
	var forward := Vector3.LEFT
	recovery.reset(Vector3.ZERO, forward)
	recovery.observe(Vector3.ZERO, forward, 1.0, 0.0, Recovery.STUCK_SECONDS + DT, [])
	_reach_escape_selection(recovery, forward)
	if not recovery.needs_escape_selection():
		_fail("Contact-free stalled recovery must enter explicit escape selection instead of returning normal; phase=%s." % recovery.phase)
		return
	var candidates := recovery.escape_candidates()
	if candidates.is_empty():
		_fail("Contact-free escape selection must retain finite left/right candidates.")
		return
	recovery.select_escape(candidates[0])
	var locked := recovery.escape_heading
	for unused in 12:
		recovery.drive(Vector3.ZERO, forward, 0.0, 5.0, 4.0, DT, 15.0, 0.0)
		if recovery.escape_heading.angle_to(locked) > 0.0001:
			_fail("Selected escape heading must not switch sides during continuation; expected=%s actual=%s." % [locked, recovery.escape_heading])
			return
	## 模擬已完成真前移而 nominal-only route 仍不安全的 rejoining；前兩輪不得 normal，第三輪才 terminal。
	recovery.phase = &"rejoining"
	recovery.positive_advance = Recovery.PROGRESS_METRES
	if not recovery.handoff_ready():
		_fail("Recovery must expose rejoining only after real positive advance reaches the fixed threshold.")
		return
	recovery.reject_handoff(&"unsafe_nominal", Vector3.ZERO, forward)
	if recovery.phase == &"normal" or recovery.phase == &"blocked" or recovery.attempts != 2:
		_fail("First unsafe handoff must consume only the remaining attempt and stay under recovery control; phase=%s attempts=%d." % [recovery.phase, recovery.attempts])
		return
	_recovery_to_selection(recovery, forward)
	if not recovery.needs_escape_selection():
		_fail("Second bounded attempt must reach selection without returning normal; phase=%s." % recovery.phase)
		return
	var second := recovery.escape_candidates()
	if second.is_empty():
		_fail("Second attempt must retain an alternate finite heading after the failed first heading.")
		return
	recovery.select_escape(second[0])
	recovery.phase = &"rejoining"
	recovery.positive_advance = Recovery.PROGRESS_METRES
	recovery.reject_handoff(&"unsafe_nominal", Vector3.ZERO, forward)
	if recovery.phase == &"blocked" or recovery.attempts != 3:
		_fail("Second unsafe handoff must retain the third bounded attempt; phase=%s attempts=%d." % [recovery.phase, recovery.attempts])
		return
	_recovery_to_selection(recovery, forward)
	if not recovery.needs_escape_selection():
		_fail("Third bounded attempt must reach selection without returning normal; phase=%s." % recovery.phase)
		return
	var third := recovery.escape_candidates()
	if third.is_empty():
		_fail("Third attempt must retain a finite candidate after prior failed headings.")
		return
	recovery.select_escape(third[0])
	recovery.phase = &"rejoining"
	recovery.positive_advance = Recovery.PROGRESS_METRES
	recovery.reject_handoff(&"unsafe_nominal", Vector3.ZERO, forward)
	if recovery.phase != &"blocked" or recovery.attempts != Recovery.MAX_ATTEMPTS:
		_fail("Third unsafe handoff must terminal-stuck at the fixed three-attempt limit; phase=%s attempts=%d." % [recovery.phase, recovery.attempts])
		return
	## cancellation / target-or-vehicle lifecycle full reset: no heading, progress or old handoff reason may leak.
	recovery.reset(Vector3(4.0, 0.0, 2.0), Vector3.FORWARD)
	if recovery.phase != &"normal" or recovery.attempts != 0 or not recovery.escape_heading.is_zero_approx() \
			or not is_zero_approx(recovery.positive_advance) or recovery.rejoin_reason != &"":
		_fail("Full lifecycle reset must clear escape heading, progress, handoff reason and attempts; phase=%s attempts=%d heading=%s progress=%.3f reason=%s." % [recovery.phase, recovery.attempts, recovery.escape_heading, recovery.positive_advance, recovery.rejoin_reason])


func _reach_escape_selection(recovery: RefCounted, forward: Vector3) -> void:
	_recovery_to_selection(recovery, forward)


func _recovery_to_selection(recovery: RefCounted, forward: Vector3) -> void:
	## braking -> reversing -> settling -> selecting_escape；沒有把 profile 結果偽造成真車移動。
	recovery.drive(Vector3.ZERO, forward, 0.0, 5.0, 4.0, DT, 15.0, 0.0)
	recovery.drive(Vector3.ZERO, forward, 0.0, 5.0, 4.0, DT, 15.0, 0.0)
	recovery.drive(Vector3.RIGHT * Recovery.REVERSE_METRES, forward, 0.0, 5.0, 4.0, DT, 15.0, 0.0)
	recovery.drive(Vector3.RIGHT * Recovery.REVERSE_METRES, forward, 0.0, 5.0, 4.0, DT, 15.0, 0.0)


func _open_fixture() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0)))
	var tank := TANK1.instantiate() as CharacterBody3D
	world.add_child(tank)
	await physics_frame
	await physics_frame
	tank.call(&"set_driving_trace_enabled", true)
	if not tank.get_recovery_contacts().is_empty():
		_fail("Open escape fixture must start with no contact.")
		world.queue_free()
		await physics_frame
		return {}
	return {"world": world, "tank": tank}


func _rotated_gun_support(tank: CharacterBody3D, heading: Vector3) -> float:
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	var forward := _forward(tank)
	var yaw := forward.signed_angle_to(heading, Vector3.UP)
	var root_transform: Transform3D = (snapshot.root as Transform3D).rotated_local(Vector3.UP, yaw)
	var maximum := -INF
	for part_range in snapshot.part_ranges as Array:
		if str(part_range.get("part_id", "")) != "gun":
			continue
		for index in range(int(part_range.start), int(part_range.start) + int(part_range.count)):
			var shape := (snapshot.shapes as Array)[index] as ConvexPolygonShape3D
			var local: Transform3D = (snapshot.root_local_transforms as Array)[index]
			for point in shape.points:
				maximum = maxf(maximum, heading.dot(root_transform * local * point - tank.stable_world_center()))
	return maximum


func _isolated_gun_band(tank: CharacterBody3D) -> Dictionary:
	var snapshot: Dictionary = tank.predictive_driving_snapshot()
	var gun_min_y := INF
	var gun_max_y := -INF
	var track_max_y := -INF
	for part_range in snapshot.part_ranges as Array:
		var part_id := str(part_range.get("part_id", ""))
		if part_id != "gun" and part_id != "left_track" and part_id != "right_track":
			continue
		for index in range(int(part_range.start), int(part_range.start) + int(part_range.count)):
			var shape := (snapshot.shapes as Array)[index] as ConvexPolygonShape3D
			var transform: Transform3D = (snapshot.transforms as Array)[index]
			for point in shape.points:
				var y := (transform * point).y
				if part_id == "gun":
					gun_min_y = minf(gun_min_y, y)
					gun_max_y = maxf(gun_max_y, y)
				else:
					track_max_y = maxf(track_max_y, y)
	var height := minf(0.10, maxf(gun_max_y - gun_min_y, 0.01))
	var lower_y := gun_min_y
	var upper_y := lower_y + height
	return {"isolated": is_finite(gun_min_y) and is_finite(track_max_y) and lower_y > track_max_y + 0.05,
		"gun_min_y": gun_min_y, "gun_max_y": gun_max_y, "track_max_y": track_max_y,
		"lower_y": lower_y, "upper_y": upper_y, "center_y": (lower_y + upper_y) * 0.5, "height": height}


func _first_profile_trace(stats: Dictionary) -> Dictionary:
	var trace: Dictionary = stats.get("trace", {}) as Dictionary
	var candidates: Array = trace.get("candidates", []) as Array
	return candidates[0] as Dictionary if not candidates.is_empty() else {}


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


func _forward(tank: CharacterBody3D) -> Vector3:
	var result := tank.global_basis * Vector3.LEFT
	result.y = 0.0
	return result.normalized()


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.world as Node3D).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
