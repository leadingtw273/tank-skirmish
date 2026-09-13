## Rotation regression red: a real low-cap v2 fixture must still accept F4 after filling.
## This deliberately uses Input.parse_input_event plus an unhandled-input boundary.
extends SceneTree

const Recorder := preload("res://src/debug/driving_trace_recorder.gd")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const TANK2 := preload("res://src/actors/tank/variants/tank2/tank2.tscn")

const LIMIT_BYTES := 256 * 1024
const FILL_FRAMES := 720
const SYNTHETIC_FILL_BYTES := 48 * 1024

class FakeRuntime extends Node:
	@export var controlled_tank: Node3D

class FakeEncounter extends Node3D:
	var player_runtime: Node
	var enemy: Node3D
	var combat_ai: Node

class FakeAI extends Node:
	func get_driving_trace_state() -> Dictionary:
		return {"navigation": {"route": [Vector3(0, 0, 0), Vector3(-40, 0, 0)], "index": 0, "end": Vector3(-40, 0, 0)}}

## The fixture owns only the input bridge: production's recorder still receives the
## event at its existing F4 boundary.  Input.parse_input_event is intentionally not
## replaced by a direct mark_problem call.
class InputBridge extends Node:
	var recorder: Node
	var saw_f4 := false

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
			saw_f4 = true
		recorder.call(&"_unhandled_key_input", event)

var _failures: Array[String] = []
var _test_dir := "user://driving_trace_rotation_smoke_%d" % Time.get_ticks_usec()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_rotation_retention_and_checkpoint()
	await _validate_tiny_cap_does_not_loop_or_lie()
	await _validate_oversized_event_stops_without_false_marker()
	if _failures.is_empty():
		print("DRIVING_TRACE_ROTATION PASS: rollover/pin/checkpoint/tiny-cap.")
		quit(0)
		return
	for failure in _failures:
		push_error("DRIVING_TRACE_ROTATION FAIL: %s" % failure)
	quit(1)


func _validate_rotation_retention_and_checkpoint() -> void:
	var fixture := await _fixture()
	if fixture.is_empty():
		_fail("real Tank1/Tank2 fixture creation failed")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_test_dir))
	var sentinel := _test_dir.path_join("user-sentinel.jsonl")
	var sentinel_file := FileAccess.open(sentinel, FileAccess.WRITE)
	sentinel_file.store_string("must-survive")
	sentinel_file.close()
	var recorder := Recorder.attach(fixture.encounter as Node, true, _test_dir, LIMIT_BYTES)
	if recorder == null:
		_fail("low-cap recorder attach failed")
		await _free_fixture(fixture)
		return
	var bridge := InputBridge.new()
	bridge.recorder = recorder
	root.add_child(bridge)
	bridge.set_process_unhandled_input(true)
	var first_path := String(recorder.call(&"get_log_path"))
	var naturally_rolled := false
	for unused in FILL_FRAMES:
		await physics_frame
		naturally_rolled = String(recorder.call(&"get_log_path")) != first_path
		if naturally_rolled:
			break
	if not naturally_rolled:
		_fail("true Tank fixture must naturally roll its first 256KiB segment; old recorder stops at cap")
	var f4 := InputEventKey.new()
	f4.keycode = KEY_F4
	f4.pressed = true
	Input.parse_input_event(f4)
	await process_frame
	for unused in 8:
		await physics_frame
	var first_marker := _find_marker_segment(_segments(_test_dir), "f4")
	if first_marker.is_empty():
		_fail("F4 after a naturally full segment must append a marker")
	elif _frame_count_after(String(first_marker.path), int(first_marker.marker_index)) < 3:
		_fail("F4 marker must be followed by continued physics frames")
	var first_marker_index := int(first_marker.get("segment_index", -1))
	if await _force_rollovers(recorder, 12) < 12:
		_fail("recorder must remain logging through more than ten forced finite rollovers")
	var after_first := _segments(_test_dir)
	if not _has_segment(after_first, first_marker_index) or not _has_segment(after_first, first_marker_index - 1):
		_fail("latest F4 segment and its preceding segment must survive later rollovers")
	var marker_seq_before_second := _max_marker_seq(_segments(_test_dir))
	var second_f4 := InputEventKey.new()
	second_f4.keycode = KEY_F4
	second_f4.pressed = true
	Input.parse_input_event(second_f4)
	await process_frame
	var second_marker_index := int(recorder.get("_segment_index"))
	if await _force_rollovers(recorder, 12) < 12:
		_fail("recorder must keep rotating after the second F4")
	recorder.call(&"stop")
	var segments := _segments(_test_dir)
	if not _has_segment(segments, second_marker_index) or not _has_segment(segments, second_marker_index - 1):
		_fail("second F4 must replace pin protection with its current segment and previous segment")
	if _max_marker_seq(segments) <= marker_seq_before_second:
		_fail("second F4 must write a newer marker that remains retained")
	_validate_segments(segments, sentinel)
	bridge.queue_free()
	recorder.queue_free()
	await physics_frame
	await _free_fixture(fixture)


func _validate_tiny_cap_does_not_loop_or_lie() -> void:
	var fixture := await _fixture()
	if fixture.is_empty():
		_fail("tiny-cap fixture creation failed")
		return
	var directory := _test_dir.path_join("tiny")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var sentinel := directory.path_join("user-sentinel.jsonl")
	var sentinel_file := FileAccess.open(sentinel, FileAccess.WRITE)
	sentinel_file.store_string("must-survive")
	sentinel_file.close()
	var recorder := Recorder.attach(fixture.encounter as Node, true, directory, 128)
	if recorder != null:
		var bridge := InputBridge.new()
		bridge.recorder = recorder
		root.add_child(bridge)
		var f4 := InputEventKey.new()
		f4.keycode = KEY_F4
		f4.pressed = true
		Input.parse_input_event(f4)
		await process_frame
		for unused in 8:
			await physics_frame
		recorder.call(&"stop")
		bridge.queue_free()
		recorder.queue_free()
		await physics_frame
	var segments := _segments(directory)
	if segments.size() > 1:
		_fail("tiny cap must not create unbounded empty segment files; got %d" % segments.size())
	for segment in segments:
		if int((segment as Dictionary).get("bytes", 0)) > 128 or int((segment as Dictionary).get("marker_count", 0)) > 0:
			_fail("tiny cap must remain within cap and never claim a successful marker")
	if FileAccess.get_file_as_string(sentinel) != "must-survive":
		_fail("tiny-cap recorder must not delete unrelated sentinel")
	await _free_fixture(fixture)


func _validate_oversized_event_stops_without_false_marker() -> void:
	var fixture := await _fixture()
	if fixture.is_empty():
		_fail("oversized-event fixture creation failed")
		return
	var directory := _test_dir.path_join("oversized")
	var recorder := Recorder.attach(fixture.encounter as Node, true, directory, LIMIT_BYTES)
	if recorder == null:
		_fail("normal 256KiB cap must attach before oversized-event check")
	else:
		recorder.call(&"_emit", &"oversized", {"blob": "x".repeat(LIMIT_BYTES + 1)})
		await physics_frame
		if not bool(recorder.get("_stopped")) or _segments(directory).size() > 1:
			_fail("one event exceeding cap must stop without creating replacement segments")
		var bridge := InputBridge.new()
		bridge.recorder = recorder
		root.add_child(bridge)
		var f4 := InputEventKey.new()
		f4.keycode = KEY_F4
		f4.pressed = true
		Input.parse_input_event(f4)
		await process_frame
		if not _find_marker_segment(_segments(directory), "f4").is_empty():
			_fail("stopped oversized-event recorder must not claim a successful F4 marker")
		bridge.queue_free()
		recorder.queue_free()
		await physics_frame
	await _free_fixture(fixture)


func _force_rollovers(recorder: Node, expected: int) -> int:
	var rotations := 0
	var last_path := String(recorder.call(&"get_log_path"))
	for attempt in expected * 12:
		recorder.call(&"_emit", &"test_fill", {"ordinal": attempt, "blob": "x".repeat(SYNTHETIC_FILL_BYTES)})
		await physics_frame
		var current := String(recorder.call(&"get_log_path"))
		if current != last_path:
			rotations += 1
			last_path = current
			if rotations >= expected:
				break
	return rotations


func _segments(directory: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(ProjectSettings.globalize_path(directory))
	if dir == null:
		return result
	for filename in dir.get_files():
		if not filename.ends_with(".jsonl") or filename == "user-sentinel.jsonl":
			continue
		var path := directory.path_join(filename)
		var rows := _rows(path)
		if rows.is_empty():
			result.append({"path": path, "bytes": FileAccess.get_size(path), "rows": rows})
			continue
		var header := rows[0] as Dictionary
		var marker_index := -1
		var marker_count := 0
		var marker_seq := -1
		for index in rows.size():
			var row := rows[index] as Dictionary
			if row.get("type") == "marker" and row.get("label") == "f4":
				marker_index = index
				marker_count += 1
				marker_seq = int(row.get("seq", -1))
		result.append({"path": path, "bytes": FileAccess.get_size(path), "rows": rows,
			"segment_index": int(header.get("segment_index", -1)), "marker_index": marker_index, "marker_count": marker_count, "marker_seq": marker_seq})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("segment_index", -1)) < int(b.get("segment_index", -1)))
	return result


func _rows(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	while file != null and not file.eof_reached():
		var json := JSON.new()
		if json.parse(file.get_line()) == OK and json.data is Dictionary:
			result.append(json.data as Dictionary)
	if file != null:
		file.close()
	return result


func _find_marker_segment(segments: Array[Dictionary], label: String, after_sequence: int = -1) -> Dictionary:
	for segment in segments:
		if int(segment.get("marker_count", 0)) > 0 and int(segment.get("marker_seq", -1)) > after_sequence:
			return segment
	return {}


func _has_segment(segments: Array[Dictionary], index: int) -> bool:
	for segment in segments:
		if int(segment.get("segment_index", -1)) == index:
			return true
	return false


func _segment_for_path(segments: Array[Dictionary], path: String) -> Dictionary:
	for segment in segments:
		if String(segment.get("path", "")) == path:
			return segment
	return {}


func _max_marker_seq(segments: Array[Dictionary]) -> int:
	var result := -1
	for segment in segments:
		result = max(result, int(segment.get("marker_seq", -1)))
	return result


func _validate_segments(segments: Array[Dictionary], sentinel: String) -> void:
	if segments.size() > 10 or segments.is_empty():
		_fail("session must retain one to ten recorder-owned segments, got %d" % segments.size())
	if FileAccess.get_file_as_string(sentinel) != "must-survive":
		_fail("rotation must never delete unrelated sentinel")
	var session_id := ""
	var previous_seq := -1
	var previous_ms := -1
	for list_index in segments.size():
		var segment := segments[list_index] as Dictionary
		if int(segment.get("bytes", LIMIT_BYTES + 1)) > LIMIT_BYTES:
			_fail("every retained segment must stay within configured cap")
		var rows := segment.get("rows", []) as Array
		if rows.size() < 2:
			_fail("every retained segment needs session header and checkpoint")
			continue
		var header := rows[0] as Dictionary
		var checkpoint := rows[1] as Dictionary
		if header.get("type") != "session" or int(header.get("schema_version", -1)) != 2 or not header.has_all(["session_id", "segment_index", "previous_segment", "retention", "limit_bytes"]):
			_fail("segment header must declare schema2 session/segment/previous/retention/cap")
		if session_id.is_empty(): session_id = String(header.get("session_id", ""))
		if String(header.get("session_id", "")) != session_id or int(header.get("segment_index", -1)) != int(segment.get("segment_index", -2)):
			_fail("all headers must use one session id and matching segment index")
		if int(header.get("segment_index", -1)) == 0 and String(header.get("previous_segment", "")) != "":
			_fail("segment zero must have empty previous_segment")
		elif int(header.get("segment_index", -1)) > 0 and String(header.get("previous_segment", "")).is_empty():
			_fail("non-initial segment must identify its previous segment")
		var retention := header.get("retention", {}) as Dictionary
		if int(retention.get("recent_segments", -1)) != 8 or not bool(retention.get("marker_keeps_previous", false)):
			_fail("header retention contract must be recent=8 and marker previous=true")
		if checkpoint.get("type") != "checkpoint" or String(checkpoint.get("session_id", "")) != session_id or int(checkpoint.get("segment_index", -1)) != int(segment.get("segment_index", -2)):
			_fail("second row must be the matching session checkpoint")
		else:
			_validate_checkpoint(checkpoint)
		for row_value in rows:
			var row := row_value as Dictionary
			if int(row.get("seq", -1)) <= previous_seq or int(row.get("t_ms", -1)) < previous_ms:
				_fail("seq and t_ms must be globally monotonic across retained segments")
			previous_seq = int(row.get("seq", -1)); previous_ms = int(row.get("t_ms", -1))
		if list_index == segments.size() - 1 and not _has_session_end(rows):
			_fail("final stopped segment must contain normal session_end")


func _validate_checkpoint(checkpoint: Dictionary) -> void:
	var encounters := checkpoint.get("encounters", []) as Array
	if encounters.is_empty():
		_fail("checkpoint must include registered encounter")
		return
	var item := encounters[0] as Dictionary
	for role in ["player", "enemy"]:
		var actor := item.get(role, {}) as Dictionary
		var descriptor := actor.get("descriptor", {}) as Dictionary
		var state := actor.get("state", {}) as Dictionary
		if not actor.has("identity") or (descriptor.get("shape_map", []) as Array).is_empty() or not state.has_all(["root_transform", "position", "angles"]):
			_fail("checkpoint %s requires identity/shape_map/pose" % role)
	var ai := item.get("ai", {}) as Dictionary
	if not (ai.get("navigation", {}) as Dictionary).has("route") or not item.has("contacts"):
		_fail("checkpoint must preserve AI navigation route and contacts")


func _has_session_end(rows: Array) -> bool:
	for row_value in rows:
		var row := row_value as Dictionary
		if row.get("type") == "session_end" and row.get("reason") == "stopped":
			return true
	return false


func _marker_index(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	var index := 0
	while not file.eof_reached():
		var json := JSON.new()
		if json.parse(file.get_line()) == OK and json.data is Dictionary:
			var row := json.data as Dictionary
			if row.get("type") == "marker" and row.get("label") == "f4":
				file.close()
				return index
		index += 1
	file.close()
	return -1


func _frame_count_after(path: String, marker_index: int) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	var index := 0
	var frames := 0
	while not file.eof_reached():
		var json := JSON.new()
		if json.parse(file.get_line()) == OK and json.data is Dictionary and index > marker_index:
			frames += 1 if (json.data as Dictionary).get("type") == "frame" else 0
		index += 1
	file.close()
	return frames


func _fixture() -> Dictionary:
	var world := Node3D.new()
	var encounter := FakeEncounter.new()
	var runtime := FakeRuntime.new()
	var ai := FakeAI.new()
	var player := TANK1.instantiate() as CharacterBody3D
	var enemy := TANK2.instantiate() as CharacterBody3D
	world.add_child(_box(Vector3(0, -0.5, 0), Vector3(160, 1, 160)))
	world.add_child(encounter)
	world.add_child(player)
	world.add_child(enemy)
	encounter.add_child(runtime)
	encounter.add_child(ai)
	runtime.controlled_tank = player
	encounter.player_runtime = runtime
	encounter.enemy = enemy
	encounter.combat_ai = ai
	root.add_child(world)
	player.position = Vector3(0, 2, 0)
	enemy.position = Vector3(20, 2, 20)
	for unused in 3:
		await physics_frame
	return {"world": world, "encounter": encounter}


func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = position
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.world as Node).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
