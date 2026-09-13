## 駕駛 trace v2 合約 smoke：descriptor、逐 physics frame、真實 contact、predictor 證據與 F4。
## 僅驗既有 query 的觀察結果；fixture 不額外發動 physics query 來製造 predictor 證據。
extends SceneTree

const Recorder := preload("res://src/debug/driving_trace_recorder.gd")
const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const TANK_SCENES := [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	preload("res://src/actors/tank/variants/tank2/tank2.tscn"),
	preload("res://src/actors/tank/variants/tank3/tank3.tscn"),
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]
const DT := 1.0 / 60.0
## Rotation keeps this as the single-segment default; session retention bounds total disk use.
const DEFAULT_LIMIT := 16 * 1024 * 1024

class FakeRuntime extends Node:
	@export var controlled_tank: Node3D

class FakeEncounter extends Node3D:
	var player_runtime: Node
	var enemy: Node3D
	var combat_ai: Node

class FakeAI extends Node:
	var navigation: Dictionary = {}

	func get_driving_trace_state() -> Dictionary:
		return {"navigation": navigation}

var _failures: Array[String] = []
var _cases := 0
var _test_dir := "user://driving_trace_v2_smoke_%d" % Time.get_ticks_usec()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_descriptors_and_pose()
	await _validate_v2_jsonl_and_shortcuts()
	await _validate_predictor_trace_toggle()
	if _cases != 3:
		_fail("completion sentinel: expected 3 completed cases, got %d" % _cases)
	if _failures.is_empty():
		print("DRIVING_TRACE_V2 PASS: descriptor/pose/contact/frame/prediction/F4/F9 cases=%d" % _cases)
		quit(0)
		return
	for failure in _failures:
		push_error("DRIVING_TRACE_V2 FAIL: %s" % failure)
	quit(1)


func _validate_descriptors_and_pose() -> void:
	for scene_index in TANK_SCENES.size():
		var tank := TANK_SCENES[scene_index].instantiate() as CharacterBody3D
		root.add_child(tank)
		await physics_frame
		## 非零 root/turret/gun，避免只有零值時局部/世界座標系混淆而假綠。
		tank.global_rotation.y = 0.31 + scene_index * 0.07
		tank.turret_pivot.rotation.y = 0.18
		tank.gun_pitch_pivot.rotation.z = -0.11
		await physics_frame
		if not tank.has_method(&"get_driving_trace_descriptor") or not tank.has_method(&"get_driving_trace_frame"):
			_fail("Tank%d must expose driving trace descriptor/frame APIs" % [scene_index + 1])
			tank.queue_free()
			await physics_frame
			continue
		var descriptor: Dictionary = tank.call(&"get_driving_trace_descriptor")
		var frame: Dictionary = tank.call(&"get_driving_trace_frame")
		var state: Dictionary = tank.call(&"get_driving_trace_state")
		var expected_map := _expected_shape_map(tank)
		var map: Array = descriptor.get("shape_map", []) as Array
		if String(descriptor.get("vehicle_type", "")) != "tank%d" % [scene_index + 1] or String(descriptor.get("scene", "")) != tank.scene_file_path \
				or String(descriptor.get("geometry_resource", "")) == "" or not (descriptor.get("physics", {}) is Dictionary):
			_fail("Tank%d descriptor must identify its exact vehicle type, scene, geometry and physics" % [scene_index + 1])
		if map.size() != expected_map.size():
			_fail("Tank%d shape_map size=%d must equal part convex shape count=%d" % [scene_index + 1, map.size(), expected_map.size()])
		else:
			for shape_index in map.size():
				var actual := map[shape_index] as Dictionary
				var expected := expected_map[shape_index] as Dictionary
				if int(actual.get("shape_index", -1)) != shape_index or actual.get("part_id") != expected.part_id \
						or actual.get("anchor") != expected.anchor or int(actual.get("part_shape_index", -1)) != expected.part_shape_index:
					_fail("Tank%d shape_map index %d is not the controller part ordering" % [scene_index + 1, shape_index])
		var angles := frame.get("angles", {}) as Dictionary
		var degrees := angles.get("degrees", {}) as Dictionary
		var required_angles := ["hull_world_yaw", "turret_local_yaw", "turret_world_yaw", "gun_local_pitch"]
		if angles.get("unit", "") != "radians" or not angles.has_all(required_angles) or not degrees.has_all(required_angles):
			_fail("Tank%d frame must expose radians plus matching degrees angles" % [scene_index + 1])
		elif not is_equal_approx(float(angles.hull_world_yaw), tank.global_rotation.y) \
				or not is_equal_approx(float(angles.turret_local_yaw), tank.turret_pivot.rotation.y) \
				or not is_equal_approx(float(angles.turret_world_yaw), tank.turret_pivot.global_rotation.y) \
				or not is_equal_approx(float(angles.gun_local_pitch), -tank.gun_pitch_pivot.rotation.z) \
				or not is_equal_approx(float(degrees.hull_world_yaw), rad_to_deg(float(angles.hull_world_yaw))):
			_fail("Tank%d frame angles must exactly preserve declared local/world radians and degrees" % [scene_index + 1])
		if not (frame.get("root_transform") is Transform3D) \
				or not frame.has_all(["id", "physics_frame", "position", "applied_input", "velocity"]):
			_fail("Tank%d frame must expose identity, physics state and Transform3D pose" % [scene_index + 1])
		if not (state.get("muzzle_transform") is Transform3D) or not bool(state.get("muzzle_valid", false)):
			_fail("Tank%d state must expose a valid muzzle transform separately from compact frame" % [scene_index + 1])
		tank.queue_free()
		await physics_frame
	_cases += 1


func _validate_v2_jsonl_and_shortcuts() -> void:
	var fixture := await _fixture()
	if fixture.is_empty():
		return
	var player := fixture.player as CharacterBody3D
	var recorder := Recorder.attach(fixture.encounter as Node, true, _test_dir)
	if recorder == null:
		_fail("v2 recorder forced attach failed")
		await _free_fixture(fixture)
		return
	## First observation registers both actors and enables their controller trace switches.
	recorder.call(&"_observe_events", fixture.encounter, DT)
	## Publish one real predictor result through the same navigation snapshot used by recorder.
	## A second observation with only generation changed must remain the same request event.
	var predictor := Predictor.new()
	predictor.setup(fixture.enemy as CharacterBody3D)
	var selected := predictor.choose(1.0, 0.0, (fixture.enemy as Node3D).global_position + Vector3.LEFT * 20.0, DT)
	var trace: Dictionary = (selected.get("stats", {}) as Dictionary).get("trace", {}) as Dictionary
	var ai := fixture.ai as FakeAI
	ai.navigation = {"request_frame": int(trace.get("request_frame", -1)), "generation": 1,
		"requested": {"movement": 1.0, "turn": 0.0}, "selected": selected, "output": selected}
	recorder.call(&"_observe_events", fixture.encounter, DT)
	ai.navigation["generation"] = 2
	recorder.call(&"_observe_events", fixture.encounter, DT)
	## F4 is the only custom diagnostic marker. Invoke the recorder input boundary directly
	## so headless smoke does not depend on platform key focus.
	var f4 := InputEventKey.new()
	f4.keycode = KEY_F4
	f4.pressed = true
	recorder.call(&"_unhandled_key_input", f4)
	for unused in 3:
		player.set_movement_input(1.0)
		await physics_frame
	player.set_movement_input(0.0)
	## True CharacterBody collision, then ensure its own-part / other-shape provenance reaches JSONL.
	var saw_contact := false
	for unused in 180:
		player.set_movement_input(1.0)
		await physics_frame
		saw_contact = saw_contact or not player.get_recovery_contacts().is_empty()
		if saw_contact:
			break
	player.set_movement_input(0.0)
	for unused in 3:
		await physics_frame
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	recorder.call(&"_unhandled_key_input", f9)
	var path := String(recorder.get_log_path())
	recorder.stop()
	if not FileAccess.file_exists(path):
		_fail("v2 recorder must create a JSONL file")
	else:
		_validate_v2_jsonl(path, saw_contact, int(trace.get("request_frame", -1)))
	recorder.queue_free()
	await physics_frame
	await _free_fixture(fixture)
	_cases += 1


func _validate_predictor_trace_toggle() -> void:
	var fixture := await _fixture()
	if fixture.is_empty():
		return
	var tank := fixture.player as CharacterBody3D
	if not tank.has_method(&"set_driving_trace_enabled") or not tank.has_method(&"is_driving_trace_enabled"):
		_fail("controller must expose driving trace enable switch")
		await _free_fixture(fixture)
		return
	## Bring the real Tank1 to the authored wall before probing: this guarantees a
	## finite, genuine blocker rather than relying on a far-horizon distance guess.
	for unused in 180:
		tank.set_movement_input(1.0)
		await physics_frame
		if not tank.get_recovery_contacts().is_empty():
			break
	tank.set_movement_input(0.0)
	await physics_frame
	var predictor := Predictor.new()
	predictor.setup(tank)
	tank.call(&"set_driving_trace_enabled", false)
	var off := predictor.choose(1.0, 0.0, tank.global_position + Vector3.LEFT * 20.0, DT)
	tank.call(&"set_driving_trace_enabled", true)
	var on := predictor.choose(1.0, 0.0, tank.global_position + Vector3.LEFT * 20.0, DT)
	var off_stats := off.get("stats", {}) as Dictionary
	var on_stats := on.get("stats", {}) as Dictionary
	if float(off.get("movement", NAN)) != float(on.get("movement", NAN)) or float(off.get("turn", NAN)) != float(on.get("turn", NAN)) \
			or off.get("reason") != on.get("reason") or int(off_stats.get("query_count", -1)) != int(on_stats.get("query_count", -2)):
		_fail("trace off/on must preserve movement/turn/reason/query_count; off=%s on=%s" % [off, on])
	if off_stats.has("trace"):
		_fail("disabled predictor stats must not allocate trace payload")
	var trace := on_stats.get("trace", {}) as Dictionary
	var candidates: Array = trace.get("candidates", []) as Array
	if int(trace.get("request_frame", -1)) < 0 or candidates.is_empty() or not trace.has("initial_contacts"):
		_fail("enabled predictor stats must expose bounded trace request_frame/candidates/initial_contacts")
	else:
		var blocked := false
		for candidate_value in candidates:
			var candidate := candidate_value as Dictionary
			if not candidate.has_all(["movement", "turn", "safe", "budget"]):
				_fail("trace candidate must retain movement/turn/safe/budget")
			if candidate.has("first_blocker"):
				var blocker := candidate.first_blocker as Dictionary
				blocked = true
				if blocker.get("source", "") == "cast_motion":
					if not bool(blocker.get("collider_unknown", false)) or not blocker.has("safe_fraction"):
						_fail("cast_motion blocker must declare unknown collider and safe fraction")
				elif blocker.get("source", "") == "stationary_initial_contact":
					if not bool(blocker.get("collider_unknown", false)):
						_fail("stationary initial contact must remain explicitly unknown")
				elif not blocker.has_all(["shape_index", "collider_id", "collider_shape", "prediction_time_seconds"]):
					_fail("shape-query blocker must identify shape/collider/time")
				elif blocker.get("source", "") == "intersect_shape" and blocker.get("part_id", null) == null:
					_fail("intersect_shape blocker must map the Tank shape to hull/turret/gun part")
		if not blocked:
			_fail("wall fixture must yield at least one predictor candidate with actual blocker evidence")
	await _free_fixture(fixture)
	_cases += 1


func _validate_v2_jsonl(path: String, saw_contact: bool, expected_request_frame: int) -> void:
	var types := {}
	var frame_count := 0
	var marker_f4 := false
	var marker_f9 := false
	var contact_has_provenance := false
	var prediction_count := 0
	var fresh_prediction := false
	var prediction_has_trace := false
	var prediction_request_matches := false
	var prediction_observed := false
	var prediction_cached_contract := false
	var session_limit := -1
	var file := FileAccess.open(path, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var json := JSON.new()
		if json.parse(line) != OK or not json.data is Dictionary:
			_fail("v2 JSONL line must parse")
			continue
		var row := json.data as Dictionary
		types[row.get("type", "")] = true
		if row.get("type") == "session":
			session_limit = int(row.get("limit_bytes", -1))
			if int(row.get("schema_version", -1)) != 2:
				_fail("v2 session must declare schema_version=2")
		if row.get("type") == "actor_change" and not ((row.get("descriptor", {}) as Dictionary).has("shape_map")):
			_fail("v2 actor_change must carry descriptor")
		if row.get("type") == "frame":
			frame_count += 1
			var player := row.get("player", {}) as Dictionary
			var enemy := row.get("enemy", {}) as Dictionary
			if not row.has("delta") or not player.has_all(["physics_frame", "root_transform", "angles", "applied_input"]) or not enemy.has_all(["physics_frame", "root_transform", "angles", "applied_input"]):
				_fail("every frame must carry compact player/enemy state and delta")
			elif not _json_numbers(player.get("root_transform")):
				_fail("frame root transform must serialize as finite JSON numeric arrays")
		if row.get("type") == "contact_begin":
			var contact := row.get("contact", {}) as Dictionary
			contact_has_provenance = contact.has_all(["shape_index", "part_id", "collider_id", "collider_shape_index"])
		if row.get("type") == "prediction":
			prediction_count += 1
			var request_frame := int(row.get("request_frame", -1))
			var observed_frame := int(row.get("observed_frame", -1))
			prediction_request_matches = prediction_request_matches or request_frame == expected_request_frame
			prediction_observed = prediction_observed or observed_frame >= 0
			prediction_cached_contract = prediction_cached_contract or bool(row.get("cached", true)) == (request_frame != observed_frame)
			fresh_prediction = fresh_prediction or not bool(row.get("cached", true))
			var selected := row.get("selected", {}) as Dictionary
			var trace := (selected.get("stats", {}) as Dictionary).get("trace", {}) as Dictionary
			prediction_has_trace = not (trace.get("candidates", []) as Array).is_empty()
		if row.get("type") == "marker":
			marker_f4 = marker_f4 or String((row.get("marker", row) as Dictionary).get("label", row.get("label", ""))) == "f4"
			marker_f9 = marker_f9 or String((row.get("marker", row) as Dictionary).get("label", row.get("label", ""))) == "f9"
	file.close()
	if session_limit != DEFAULT_LIMIT:
		_fail("default recorder cap must remain 128MiB, got %d" % session_limit)
	for required in ["session", "actor_change", "frame", "marker", "session_end"]:
		if not types.has(required):
			_fail("v2 JSONL missing %s" % required)
	if frame_count < 3 or not marker_f4 or marker_f9:
		_fail("F4 must write f4 marker and at least 3 continued physics frames; F9 must not write custom marker")
	if not saw_contact or not contact_has_provenance:
		_fail("true Tank wall contact must include own part and other collider shape provenance")
	if prediction_count != 1 or not prediction_request_matches or not prediction_observed or not prediction_cached_contract \
			or not fresh_prediction or not prediction_has_trace:
		_fail("one fresh request_frame must emit exactly one prediction with matching request/observed/cached and selected.stats.trace; count=%d request=%s observed=%s cached=%s fresh=%s trace=%s" % [prediction_count, prediction_request_matches, prediction_observed, prediction_cached_contract, fresh_prediction, prediction_has_trace])


func _expected_shape_map(tank: CharacterBody3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in tank.part_geometry.parts:
		for part_shape_index in part.convex_shapes.size():
			result.append({"part_id": part.id, "anchor": part.anchor, "part_shape_index": part_shape_index})
	return result


func _fixture() -> Dictionary:
	var world := Node3D.new()
	var encounter := FakeEncounter.new()
	var runtime := FakeRuntime.new()
	var ai := FakeAI.new()
	var player := TANK_SCENES[0].instantiate() as CharacterBody3D
	var enemy := TANK_SCENES[1].instantiate() as CharacterBody3D
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
	## Local positions avoid querying global transforms before the fixture has completed tree entry.
	player.position = Vector3(0, 2, 0)
	enemy.position = Vector3(20, 2, 20)
	var front := _support_plane(player, Vector3.LEFT)
	## 牆右面與真凸形支撐面留 10cm，避免 fixture 初始重疊；後續必須由實際前進取得 contact。
	var wall := _box(Vector3(front.x - 0.35, 2, 0), Vector3(0.5, 5, 16))
	world.add_child(wall)
	var enemy_front := _support_plane(enemy, Vector3.LEFT)
	world.add_child(_box(Vector3(enemy.global_position.x + enemy_front.x - 0.35, 2, enemy.global_position.z), Vector3(0.5, 5, 16)))
	for unused in 3:
		await physics_frame
	return {"world": world, "encounter": encounter, "player": player, "enemy": enemy, "ai": ai}


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


func _support_plane(tank: CharacterBody3D, direction: Vector3) -> Vector3:
	var best := -INF
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points:
				best = maxf(best, direction.dot(transforms[index] * point))
			index += 1
	return direction.normalized() * best


func _json_numbers(value: Variant) -> bool:
	if value is Array:
		if (value as Array).is_empty():
			return false
		for item in value as Array:
			if not _json_numbers(item):
				return false
		return true
	if value is Dictionary:
		if (value as Dictionary).is_empty():
			return false
		for item in (value as Dictionary).values():
			if not _json_numbers(item):
				return false
		return true
	return (value is float or value is int) and is_finite(float(value))


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.world as Node).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
