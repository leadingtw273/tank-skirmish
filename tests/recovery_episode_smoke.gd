## E1/E3 最小 episode 額度合約：只使用既有 Recovery 公開 API 與欄位。
extends SceneTree

const Recovery := preload("res://src/ai/tank_recovery.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var recovery := Recovery.new()
	var forward := Vector3.LEFT
	recovery.reset(Vector3.ZERO, forward)
	## 舊碼上第二次失敗即 terminal；新合約必須仍可啟動第三次。
	recovery.attempts = 2
	recovery.phase = &"rejoining"
	recovery.reject_handoff(&"unsafe_nominal", Vector3.ZERO, forward)
	if recovery.attempts != 3 or recovery.phase == &"blocked":
		_fail("第三次額度必須可用：第二次 unsafe handoff 後不可 terminal；phase=%s attempts=%d." % [recovery.phase, recovery.attempts])
	## handoff 回 normal 是立即恢復駕駛，不等於事件已確認完成或額度洗回零。
	recovery.reset(Vector3.ZERO, forward)
	recovery.attempts = 1
	recovery.episode_active = true
	recovery.phase = &"rejoining"
	recovery.advance_origin = Vector3(2.0, 0.0, 0.0)
	recovery.accept_handoff(&"safe_nominal")
	if recovery.phase != &"normal" or recovery.attempts != 1:
		_fail("handoff 在未完成 episode confirmation 前必須保留已用額度；phase=%s attempts=%d." % [recovery.phase, recovery.attempts])
	## 連續安全正向時間不足三秒，或已滿三秒但位移不足 .5m，都不能補額度。
	for unused in 180:
		recovery.observe_confirmation(Vector3.ZERO, 1.0, [], false, false, 1.0 / 60.0)
	if recovery.attempts != 1 or not recovery.episode_active:
		_fail("confirmation 位移不足 .5m 時不可清 episode；attempts=%d active=%s." % [recovery.attempts, recovery.episode_active])
	recovery.observe_confirmation(Vector3(Recovery.PROGRESS_METRES, 0.0, 0.0), 1.0, [], false, false, 1.0 / 60.0)
	if recovery.attempts != 0 or recovery.episode_active:
		_fail("連續安全三秒且水平前進 .5m 後必須結束 episode；attempts=%d active=%s." % [recovery.attempts, recovery.episode_active])
	## contact/intervention/hold 都只重啟確認窗，不能直接補額度。
	recovery.reset(Vector3.ZERO, forward)
	recovery.attempts = 1
	recovery.episode_active = true
	recovery.observe_confirmation(Vector3.ZERO, 1.0, [], false, false, 1.0)
	recovery.observe_confirmation(Vector3.ZERO, 1.0, [{"normal": Vector3.FORWARD}], false, false, 1.0)
	recovery.observe_confirmation(Vector3.ZERO, 0.0, [], false, false, 1.0)
	if recovery.attempts != 1 or recovery.confirmation_active:
		_fail("contact 或 hold 中斷 confirmation 時必須保留額度並停止計時；attempts=%d confirming=%s." % [recovery.attempts, recovery.confirmation_active])
	_validate_cross_episode_failed_heading_reset(forward)
	if _failures.is_empty():
		print("RECOVERY_EPISODE PASS: third attempt remains available and handoff preserves episode budget.")
		quit(0)
		return
	for failure in _failures:
		push_error("RECOVERY_EPISODE FAIL: %s" % failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


## A 的失敗 heading 只能在 A 未完成時過濾；確認完成後 B 必須等同 full-reset control。
func _validate_cross_episode_failed_heading_reset(forward: Vector3) -> void:
	var actual := Recovery.new()
	var failed_heading := forward.rotated(Vector3.UP, Recovery.ESCAPE_ANGLE).normalized()
	actual.reset(Vector3.ZERO, forward)
	actual.attempts = 1
	actual.episode_active = true
	actual.phase = &"rejoining"
	actual.set("_failed_heading", failed_heading)
	if _candidate_has_heading(actual.escape_candidates(), forward, failed_heading):
		_fail("Episode A 未成功前必須持續排除已失敗 heading。")
	actual.accept_handoff(&"safe_nominal", Vector3.ZERO)
	for frame in 181:
		actual.observe_confirmation(Vector3(-0.6 * float(frame + 1) / 181.0, 0.0, 0.0), 1.0, [], false, false, 1.0 / 60.0)
	var blocked_position := Vector3(100.0, 0.0, 100.0)
	actual.reset_progress(blocked_position, forward)
	for unused in 181:
		actual.observe(blocked_position, forward, 1.0, 0.0, 1.0 / 60.0)
	var control := Recovery.new()
	control.reset(blocked_position, forward)
	for unused in 181:
		control.observe(blocked_position, forward, 1.0, 0.0, 1.0 / 60.0)
	var actual_candidates := actual.escape_candidates()
	var control_candidates := control.escape_candidates()
	if actual.attempts != 1 or actual_candidates != control_candidates or actual_candidates.size() != 4 \
			or not _candidate_has_heading(actual_candidates, forward, failed_heading):
		_fail("Episode B 必須從 attempts=1 與完整四候選開始，等同 full reset；actual=%s control=%s attempts=%d failed=%s." % [actual_candidates, control_candidates, actual.attempts, actual.get("_failed_heading")])


func _candidate_has_heading(candidates: Array[Dictionary], forward: Vector3, heading: Vector3) -> bool:
	for candidate in candidates:
		var candidate_heading := forward.rotated(Vector3.UP, float(candidate.get("side", 0.0)) * float(candidate.get("angle", 0.0))).normalized()
		if candidate_heading.angle_to(heading) <= 0.0001:
			return true
	return false
