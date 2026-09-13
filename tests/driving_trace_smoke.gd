## 駕駛 trace JSONL：真 Tank1 碰牆，驗 recorder 僅觀察、不改路由或控制。
extends SceneTree

const Recorder := preload("res://src/debug/driving_trace_recorder.gd")
const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const DT := 1.0 / 60.0

class FakeRuntime extends Node:
	@export var controlled_tank: Node3D

class FakeEncounter extends Node3D:
	var player_runtime: Node
	var enemy: Node3D
	var combat_ai: Node

var _failures: Array[String] = []
var _test_dir := "user://driving_trace_smoke_%d" % Time.get_ticks_usec()
var _completed_cases := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_trace_lifecycle_and_real_contact()
	await _validate_disabled_invalid_and_limit()
	if _completed_cases != 2:
		_fail("smoke did not complete both cases; completed=%d" % _completed_cases)
	if _failures.is_empty():
		print("DRIVING_TRACE PASS: cases=%d JSONL session/sample/events/contact/multi/limit/read-only." % _completed_cases)
		quit(0)
		return
	for failure in _failures:
		push_error("DRIVING_TRACE FAIL: %s" % failure)
	quit(1)


func _validate_trace_lifecycle_and_real_contact() -> void:
	var fixture := await _fixture()
	if fixture.is_empty():
		_fail("fixture creation failed")
		return
	var encounter := fixture.encounter as Node
	var player := fixture.player as CharacterBody3D
	var runtime := fixture.runtime as FakeRuntime
	var ai := fixture.ai as Node
	## attach 前後不得改既有 command、route index 或 attempts；不等 physics，避免正常世界更新混入。
	ai.call("_ensure_navigation")
	var nav := ai.get("_navigation") as RefCounted
	var before: Dictionary = nav.get_driving_trace_state()
	var command_before := [player.movement_command, player.turn_command]
	var disabled := Recorder.attach(encounter, false, _test_dir.path_join("disabled"))
	if disabled != null:
		_fail("headless auto attach must remain disabled unless force=true")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_test_dir.path_join("disabled"))):
		_fail("headless auto attach must not create a trace directory or file")
	var recorder := Recorder.attach(encounter, true, _test_dir, 33_554_432)
	if recorder == null:
		_fail("forced recorder attach failed")
		await _free(fixture)
		return
	var after: Dictionary = nav.get_driving_trace_state()
	if before.get("index") != after.get("index") or before.get("attempts") != after.get("attempts") \
			or command_before != [player.movement_command, player.turn_command]:
		_fail("attach must not mutate route index, recovery attempts, or body commands")
	## 真 NavigationAgent 路徑：route_change 必須攜帶實際路點，sample 則不可重複整條 route。
	for unused in 3:
		await physics_frame
	var route_result: Dictionary = nav.drive(Vector3(-60, 0, 0), 41, 1.0, DT)
	var driven: Dictionary = nav.get_driving_trace_state()
	if route_result.get("status") == &"no_path" or (driven.get("route", []) as Array).is_empty():
		_fail("route trace fixture must create a real non-empty NavigationAgent path")
	## 第二 encounter 共用同一檔；換 player actor 會產生 actor_change，不能混用 identity。
	var second := FakeEncounter.new()
	second.name = "EncounterTwo"
	var second_runtime := FakeRuntime.new()
	var second_player := TANK1.instantiate() as CharacterBody3D
	second_player.name = "PlayerTwo"
	second_player.position = Vector3(0, 0, 30)
	second_runtime.controlled_tank = second_player
	second.player_runtime = second_runtime
	second.enemy = fixture.enemy as Node3D
	second.combat_ai = ai
	fixture.world.add_child(second)
	second.add_child(second_runtime)
	fixture.world.add_child(second_player)
	if Recorder.attach(second, true, _test_dir, 33_554_432) != recorder:
		_fail("multiple encounters must register on one process recorder/file")
	## 真車撞固定前牆；contact begin/end 來自 controller snapshot，非 fake contacts。
	var saw_real_contact := false
	for unused in 180:
		player.set_movement_input(1.0)
		await physics_frame
		saw_real_contact = saw_real_contact or not player.get_recovery_contacts().is_empty()
		if saw_real_contact:
			break
	player.set_movement_input(0.0)
	for unused in 12:
		await physics_frame
	## 真 actor replacement event，不直接偽造 actor id。
	var replacement := TANK1.instantiate() as CharacterBody3D
	replacement.name = "PlayerReplacement"
	fixture.world.add_child(replacement)
	replacement.global_position = player.global_position + Vector3(0, 0, 12)
	runtime.controlled_tank = replacement
	for unused in 12:
		await physics_frame
	recorder.mark_problem("smoke-marker")
	var path := String(recorder.get_log_path())
	recorder.stop()
	if path.is_empty() or not FileAccess.file_exists(path):
		_fail("forced recorder must expose an existing JSONL path")
	else:
		_validate_jsonl(path, saw_real_contact)
	recorder.queue_free()
	await physics_frame
	await _free(fixture)
	_completed_cases += 1


func _validate_disabled_invalid_and_limit() -> void:
	var fixture := await _fixture()
	if fixture.is_empty():
		_fail("limit fixture creation failed")
		return
	var encounter := fixture.encounter as Node
	## 非 user:// 目錄要安全拒絕，不拋遊戲 error；headless auto attach 同樣不建立檔案。
	if Recorder.attach(encounter, true, "/tmp/not-allowed-driving-trace") != null:
		_fail("invalid non-user directory must be rejected safely")
	var limit_dir := _test_dir.path_join("limit")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(limit_dir))
	var sentinel := limit_dir.path_join("existing.jsonl")
	var sentinel_file := FileAccess.open(sentinel, FileAccess.WRITE)
	sentinel_file.store_string("preserve")
	sentinel_file.close()
	## Header+checkpoint may themselves exceed 4 KiB after v2 rotation metadata; that
	## is an explicit safe attach failure, not a reason to create empty segments.
	const SMALL_LIMIT := 4_096
	var recorder := Recorder.attach(encounter, true, limit_dir, SMALL_LIMIT)
	if recorder == null:
		var generated := 0
		var directory := DirAccess.open(ProjectSettings.globalize_path(limit_dir))
		if directory != null:
			for filename in directory.get_files():
				if filename == "existing.jsonl":
					continue
				generated += 1
				var candidate := limit_dir.path_join(filename)
				if FileAccess.get_size(candidate) > SMALL_LIMIT:
					_fail("failed small-cap attach must not leave an over-cap segment")
		if generated > 1 or FileAccess.get_file_as_string(sentinel) != "preserve":
			_fail("failed small-cap attach must not loop files or alter existing log; files=%d" % generated)
	else:
		for unused in 30:
			await physics_frame
		var path := String(recorder.get_log_path())
		recorder.stop()
		if path == sentinel or not FileAccess.file_exists(path) or FileAccess.get_size(path) > SMALL_LIMIT:
			_fail("limit recorder must stop within cap and never overwrite existing logs; path=%s bytes=%d" % [path, FileAccess.get_size(path) if FileAccess.file_exists(path) else -1])
		var retained := FileAccess.get_file_as_string(sentinel)
		if retained != "preserve":
			_fail("limit test must preserve pre-existing user log")
		recorder.queue_free()
	await physics_frame
	await _free(fixture)
	_completed_cases += 1


func _validate_jsonl(path: String, saw_real_contact: bool) -> void:
	var types := {}
	var encounters := {}
	var actor_paths := {}
	var contact_has_fields := false
	var route_has_point := false
	var sequence := -1
	var time_ms := -1
	var file := FileAccess.open(path, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var json := JSON.new()
		if json.parse(line) != OK or not (json.data is Dictionary):
			_fail("every JSONL line must parse: %s" % line)
			continue
		var row := json.data as Dictionary
		if not row.has_all(["type", "seq", "t_ms", "frame"]) or int(row.seq) <= sequence or int(row.t_ms) < time_ms:
			_fail("JSONL common sequence/time fields must be monotonic: %s" % row)
		sequence = int(row.seq)
		time_ms = int(row.t_ms)
		types[row.type] = true
		if row.has("encounter") and row.encounter is Dictionary:
			encounters[(row.encounter as Dictionary).get("id", 0)] = true
		if row.type == "sample":
			if not row.has_all(["player", "enemy", "relative"]) or not (row.relative as Dictionary).has_all(["player_to_enemy", "distance", "xz_distance"]):
				_fail("sample must contain player/enemy/relative vector and distances")
			var navigation := (row.get("ai", {}) as Dictionary).get("navigation", {}) as Dictionary
			if navigation.has("route"):
				_fail("sample must not dump navigation.route every interval")
		if row.type == "actor_change":
			actor_paths[String((row.actor as Dictionary).get("path", ""))] = true
		if row.type == "state_change":
			var state := row.get("state", {}) as Dictionary
			var navigation := state.get("navigation", {}) as Dictionary
			if state.has("route") or state.has("submit_frame") or navigation.has("route") or navigation.has("submit_frame"):
				_fail("state_change must contain discrete state only, not route or submit_frame")
		if row.type == "route_change":
			var route := row.get("route", {}) as Dictionary
			if not route.has_all(["path", "index", "end"]):
				_fail("route_change must contain path/index/end")
			elif not (route.get("path", []) as Array).is_empty():
				route_has_point = true
		if row.type == "contact_begin":
			var contact := row.get("contact", {}) as Dictionary
			contact_has_fields = contact.has_all(["position", "normal", "rid", "collider_id", "collider_path", "age"])
	file.close()
	for required in ["session", "sample", "actor_change", "contact_begin", "contact_end", "state_change", "route_change", "marker", "session_end"]:
		if not types.has(required):
			_fail("JSONL missing required event type %s" % required)
	if encounters.size() < 2 or actor_paths.size() < 3 or not route_has_point:
		_fail("multi-encounter and replacement actor identities must remain distinct")
	if not saw_real_contact or not contact_has_fields:
		_fail("true Tank1 wall contact must log begin/end normal/position/rid/collider id/path/age")


func _fixture() -> Dictionary:
	var world := Node3D.new()
	var ground := _box(Vector3(0, -0.5, 0), Vector3(160, 1, 160))
	var encounter := FakeEncounter.new()
	encounter.name = "EncounterOne"
	var runtime := FakeRuntime.new()
	var player := TANK1.instantiate() as CharacterBody3D
	var enemy := TANK1.instantiate() as CharacterBody3D
	var vision := TankVision.new()
	var ai := TankCombatAI.new()
	var region := _open_navigation_region()
	world.add_child(region)
	world.add_child(ground)
	world.add_child(encounter)
	world.add_child(player)
	world.add_child(enemy)
	encounter.add_child(runtime)
	encounter.add_child(vision)
	encounter.add_child(ai)
	runtime.controlled_tank = player
	encounter.enemy = enemy
	encounter.combat_ai = ai
	vision.observer = enemy
	ai.controlled_tank = enemy
	ai.vision = vision
	ai.set_physics_process(false)
	root.add_child(world)
	## 進樹後重綁 fake runtime property；recorder 透過 Node.get 讀取，不靠 child 名稱推斷。
	runtime.controlled_tank = player
	encounter.player_runtime = runtime
	encounter.enemy = enemy
	encounter.combat_ai = ai
	if runtime.get("controlled_tank") != player:
		_fail("fake runtime must expose controlled_tank through Node.get for recorder")
	player.global_position = Vector3.ZERO
	enemy.global_position = Vector3(-30, 0, 0)
	var front := _support_plane(player, Vector3.LEFT)
	var wall := _box(Vector3(front.x - 0.35, 2, 0), Vector3(0.5, 5, 16))
	world.add_child(wall)
	for unused in 3:
		await physics_frame
	if _part_hits(player, wall):
		world.queue_free()
		await physics_frame
		return {}
	return {"world": world, "encounter": encounter, "runtime": runtime, "player": player, "enemy": enemy, "ai": ai}


func _open_navigation_region() -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-160, 0, -160), Vector3(160, 0, -160), Vector3(160, 0, 160), Vector3(-160, 0, 160)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	return region


func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new(); body.collision_layer = 1; body.position = position
	var shape := BoxShape3D.new(); shape.size = size
	var collision := CollisionShape3D.new(); collision.shape = shape
	body.add_child(collision)
	return body


func _support_plane(tank: CharacterBody3D, direction: Vector3) -> Vector3:
	var best := -INF; var transforms: Array[Transform3D] = tank.part_shape_world_transforms(); var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points: best = maxf(best, direction.dot(transforms[index] * point))
			index += 1
	return direction.normalized() * best


func _part_hits(tank: CharacterBody3D, body: StaticBody3D) -> bool:
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms(); var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape; query.transform = transforms[index]; query.collision_mask = 1; query.exclude = [tank.get_rid()]
			for hit in tank.get_world_3d().direct_space_state.intersect_shape(query, 16):
				if hit.get("collider") == body: return true
			index += 1
	return false


func _free(fixture: Dictionary) -> void:
	(fixture.world as Node).queue_free()
	await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
