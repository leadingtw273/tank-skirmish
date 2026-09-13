## 訓練場本機駕駛診斷 JSONL；只讀既有 trace snapshot，絕不參與 AI 或物理決策。
class_name DrivingTraceRecorder
extends Node

const RECORDER_NAME := &"DrivingTraceRecorder"
const SAMPLE_SECONDS := 0.1
const FLUSH_SECONDS := 1.0
const SCHEMA_VERSION := 2
const DEFAULT_LIMIT_BYTES := 16 * 1024 * 1024
const RETAIN_SEGMENT_COUNT := 8

var _encounters: Array[WeakRef] = []
var _file: FileAccess
var _log_path := ""
var _limit_bytes := DEFAULT_LIMIT_BYTES
var _written_bytes := 0
var _directory := ""
var _session_id := ""
var _segment_index := -1
var _segments: Array[Dictionary] = []
var _pinned_marker_path := ""
var _pinned_previous_path := ""
var _source_hash_cache := {}
var _scene_path_cache := ""
var _scene_hash_cache := ""
var _sequence := 0
var _started_usec := 0
var _sample_age := 0.0
var _flush_age := 0.0
var _stopped := false
var _actors := {}
var _contacts := {}
var _states := {}
var _routes := {}
var _prediction_frames := {}
var _descriptors := {}
var _collision_objects := {}


static func attach(encounter: Node, force: bool = false, directory: String = "user://driving_traces", limit_bytes: int = DEFAULT_LIMIT_BYTES) -> Node:
	if encounter == null or not is_instance_valid(encounter):
		return null
	if not force and (DisplayServer.get_name() == "headless" or not OS.is_debug_build()):
		return null
	if not directory.begins_with("user://"):
		push_warning("DrivingTraceRecorder only writes below user://.")
		return null
	var root := encounter.get_tree().root
	var recorder := root.get_node_or_null(String(RECORDER_NAME)) as DrivingTraceRecorder
	if recorder == null:
		recorder = DrivingTraceRecorder.new()
		recorder.name = RECORDER_NAME
		recorder.process_physics_priority = 1000
		recorder._limit_bytes = max(limit_bytes, 1)
		root.add_child(recorder)
		if not recorder._open_log(directory, encounter):
			recorder.queue_free()
			return null
	recorder._register(encounter)
	return recorder


func get_log_path() -> String:
	return _log_path


func mark_problem(label: String = "manual") -> void:
	if _stopped:
		return
	if not _emit(&"marker", {"label": label}):
		return
	if not _flush():
		return
	_pinned_marker_path = _log_path
	_pinned_previous_path = _previous_segment_path()
	print("DRIVING_TRACE marker=%s frame=%d file=%s" % [label, Engine.get_physics_frames(), _log_path])
	if not _cleanup_segments():
		return


func stop() -> void:
	if _stopped:
		return
	_emit(&"session_end", {"reason": "stopped"})
	_flush()
	_stopped = true
	_disable_actor_traces()
	if _file != null:
		_file.close()
		_file = null


func _exit_tree() -> void:
	stop()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4 \
			and not event.alt_pressed and not event.ctrl_pressed and not event.meta_pressed and not event.shift_pressed:
		mark_problem("f4")
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _stopped:
		return
	_sample_age += maxf(delta, 0.0)
	_flush_age += maxf(delta, 0.0)
	for encounter in _live_encounters():
		_observe_events(encounter, delta)
	if _sample_age >= SAMPLE_SECONDS:
		_sample_age = fmod(_sample_age, SAMPLE_SECONDS)
		for encounter in _live_encounters():
			_emit_sample(encounter)
	if _flush_age >= FLUSH_SECONDS:
		_flush_age = 0.0
		_flush()


func _open_log(directory: String, encounter: Node) -> bool:
	var absolute := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		push_warning("DrivingTraceRecorder could not create its user directory.")
		return false
	_directory = directory
	_started_usec = Time.get_ticks_usec()
	_session_id = "%s-%06d" % [Time.get_datetime_string_from_system(true).replace(":", "-"), _started_usec % 1_000_000]
	_source_hash_cache = _source_hashes()
	_scene_path_cache = _scene_path(encounter)
	_scene_hash_cache = FileAccess.get_sha256(_scene_path_cache) if not _scene_path_cache.is_empty() else ""
	var pending := _prepare_segment(encounter, 0, "")
	if pending.is_empty():
		push_warning("DrivingTraceRecorder could not open an initial trace segment.")
		return false
	_file = pending.file as FileAccess
	_log_path = str(pending.path)
	_written_bytes = int(pending.written_bytes)
	_segment_index = 0
	_segments.append({"path": _log_path, "index": _segment_index, "closed": false})
	return true


func _prepare_segment(encounter: Node, segment_index: int, previous_segment: String) -> Dictionary:
	var pending := _open_segment_file(segment_index)
	if pending.is_empty():
		return {}
	var pending_file := pending.file as FileAccess
	var written := 0
	var header := _write_bootstrap_line(pending_file, &"session", _session_header(segment_index, previous_segment), written)
	if not bool(header.get("ok", false)):
		pending_file.close()
		return {}
	written = int(header.written_bytes)
	var checkpoint := _write_bootstrap_line(pending_file, &"checkpoint", _checkpoint_payload(encounter, segment_index), written)
	if not bool(checkpoint.get("ok", false)):
		pending_file.close()
		return {}
	pending_file.flush()
	if pending_file.get_error() != OK:
		push_warning("DrivingTraceRecorder could not flush a trace segment bootstrap.")
		pending_file.close()
		return {}
	pending["written_bytes"] = int(checkpoint.written_bytes)
	return pending


func _open_segment_file(segment_index: int) -> Dictionary:
	for suffix in range(1000):
		var candidate := _directory.path_join("driving-%s-%03d-%03d.jsonl" % [_session_id, segment_index, suffix])
		if FileAccess.file_exists(candidate):
			continue
		var pending_file := FileAccess.open(candidate, FileAccess.WRITE)
		if pending_file != null:
			return {"file": pending_file, "path": candidate}
	push_warning("DrivingTraceRecorder could not allocate a unique trace segment.")
	return {}


func _session_header(segment_index: int, previous_segment: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"marker_key": "F4",
		"reconstruction": "observed_states_and_commands_not_deterministic_replay",
		"coordinates": {"position": "world_metres", "angles": "radians_with_explicit_degrees", "basis": "column_vectors_x_y_z", "tank_forward_local": Vector3.LEFT},
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"source_sha256": _source_hash_cache,
		"utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info(),
		"scene_path": _scene_path_cache,
		"scene_sha256": _scene_hash_cache,
		"limit_bytes": _limit_bytes,
		"session_id": _session_id,
		"segment_index": segment_index,
		"previous_segment": previous_segment,
		"retention": {"recent_segments": RETAIN_SEGMENT_COUNT, "marker_keeps_previous": true},
	}


func _checkpoint_payload(initial_encounter: Node, segment_index: int) -> Dictionary:
	var encounters: Array = []
	var included := {}
	var sources: Array[Node] = [initial_encounter]
	for encounter in _live_encounters():
		sources.append(encounter)
	for encounter in sources:
		if not is_instance_valid(encounter) or included.has(encounter.get_instance_id()):
			continue
		included[encounter.get_instance_id()] = true
		var player := _player(encounter)
		var enemy := encounter.get("enemy") as Node3D
		var player_state := _controller_state(player)
		var enemy_state := _controller_state(enemy)
		encounters.append({
			"encounter": _identity(encounter),
			"player": _checkpoint_actor(player, player_state),
			"enemy": _checkpoint_actor(enemy, enemy_state),
			"ai": _ai_state(encounter),
			"contacts": {"player": _contacts_with_age(player_state), "enemy": _contacts_with_age(enemy_state)},
		})
	return {"session_id": _session_id, "segment_index": segment_index, "encounters": encounters}


func _checkpoint_actor(actor: Node3D, state: Dictionary) -> Dictionary:
	var descriptor := {}
	if is_instance_valid(actor):
		descriptor = _descriptors.get(actor.get_instance_id(), {}) as Dictionary
		if descriptor.is_empty() and actor.has_method(&"get_driving_trace_descriptor"):
			descriptor = actor.call(&"get_driving_trace_descriptor") as Dictionary
			var geometry_path := str(descriptor.get("geometry_resource", ""))
			descriptor["geometry_sha256"] = FileAccess.get_sha256(geometry_path) if not geometry_path.is_empty() else ""
	return {"identity": _identity(actor), "descriptor": descriptor, "state": state}


func _register(encounter: Node) -> void:
	for item in _encounters:
		if item.get_ref() == encounter:
			return
	_encounters.append(weakref(encounter))
	_index_colliders(encounter.get_tree().current_scene if is_instance_valid(encounter.get_tree().current_scene) else encounter)


func _live_encounters() -> Array[Node]:
	var live: Array[Node] = []
	var retained: Array[WeakRef] = []
	for item in _encounters:
		var encounter := item.get_ref() as Node
		if is_instance_valid(encounter):
			live.append(encounter)
			retained.append(item)
	_encounters = retained
	return live


func _observe_events(encounter: Node, delta: float) -> void:
	var key := _encounter_key(encounter)
	var encounter_identity := _identity(encounter)
	var player := _player(encounter)
	var enemy := encounter.get("enemy") as Node3D
	_observe_actor(key, encounter_identity, &"player", player)
	_observe_actor(key, encounter_identity, &"enemy", enemy)
	var ai := _ai_state(encounter)
	_observe_state("%s:ai" % key, {"encounter": encounter_identity, "role": "ai", "state": _ai_transition(ai)})
	var navigation := ai.get("navigation", {}) as Dictionary
	var route: Variant = navigation.get("route", [])
	_observe_route("%s:enemy" % key, encounter_identity, _identity(enemy), route, navigation)
	_observe_prediction(key, encounter_identity, enemy, navigation)
	_emit(&"frame", {"encounter": encounter_identity, "delta": delta,
		"player": _controller_frame(player), "enemy": _controller_frame(enemy),
		"ai": {"submit_frame": ai.get("submit_frame", -1), "submitted": ai.get("submitted", {}),
			"request_frame": navigation.get("request_frame", -1), "status": ai.get("status", ""),
			"terminal": navigation.get("terminal", false)}})


func _observe_actor(encounter_key: String, encounter: Dictionary, role: StringName, actor: Node3D) -> void:
	var actor_key := "%s:%s" % [encounter_key, role]
	var identity := _identity(actor)
	var previous := _actors.get(actor_key, {}) as Dictionary
	if JSON.stringify(_json_value(previous)) != JSON.stringify(_json_value(identity)):
		_actors[actor_key] = identity
		var descriptor: Dictionary = {}
		if is_instance_valid(actor):
			if actor.has_method(&"set_driving_trace_enabled"):
				actor.call(&"set_driving_trace_enabled", true)
			if actor.has_method(&"get_driving_trace_descriptor"):
				descriptor = actor.call(&"get_driving_trace_descriptor") as Dictionary
				var geometry_path := str(descriptor.get("geometry_resource", ""))
				descriptor["geometry_sha256"] = FileAccess.get_sha256(geometry_path) if not geometry_path.is_empty() else ""
			_descriptors[actor.get_instance_id()] = descriptor
			if actor is CollisionObject3D:
				_collision_objects[(actor as CollisionObject3D).get_rid().get_id()] = weakref(actor)
		_emit(&"actor_change", {"encounter": encounter, "role": role, "actor": identity, "descriptor": descriptor})
	var state := _controller_state(actor)
	_observe_contacts(actor_key, encounter, role, identity, _contacts_with_age(state))
	_observe_state(actor_key, {"encounter": encounter, "role": role, "actor": identity, "state": {"motion_guard": _discrete_state(state.get("motion_guard", {}) as Dictionary), "contact_response": _discrete_state(state.get("contact_response", {}) as Dictionary)}})


func _observe_contacts(actor_key: String, encounter: Dictionary, role: StringName, actor: Dictionary, values: Array) -> void:
	var current := {}
	for item in values:
		if item is Dictionary:
			var contact := item as Dictionary
			var contact_key := "%s:%s:%s:%s" % [contact.get("rid", 0), contact.get("collider_id", 0), contact.get("local_shape_index", -1), contact.get("collider_shape_index", -1)]
			current[contact_key] = contact
			if not (_contacts.get(actor_key, {}) as Dictionary).has(contact_key):
				_emit(&"contact_begin", {"encounter": encounter, "role": role, "actor": actor, "contact": contact})
	for prior_key in (_contacts.get(actor_key, {}) as Dictionary):
		if not current.has(prior_key):
			_emit(&"contact_end", {"encounter": encounter, "role": role, "actor": actor, "contact": (_contacts.get(actor_key, {}) as Dictionary)[prior_key]})
	_contacts[actor_key] = current


func _observe_state(key: String, payload: Dictionary) -> void:
	var encoded := JSON.stringify(_json_value(payload.get("state", {})))
	if _states.get(key, "") != encoded:
		_states[key] = encoded
		_emit(&"state_change", payload)


func _observe_route(key: String, encounter: Dictionary, actor: Dictionary, path: Variant, navigation: Dictionary) -> void:
	var route := {"path": path, "index": navigation.get("index", -1), "end": navigation.get("end", Vector3.ZERO)}
	var encoded := JSON.stringify(_json_value(route))
	if _routes.get(key, "") != encoded:
		_routes[key] = encoded
		_emit(&"route_change", {"encounter": encounter, "actor": actor, "route": route})


func _emit_sample(encounter: Node) -> void:
	var player := _player(encounter)
	var enemy := encounter.get("enemy") as Node3D
	var ai := _ai_state(encounter)
	var ai_sample := ai.duplicate(true)
	var navigation := ai_sample.get("navigation", {}) as Dictionary
	navigation.erase("route")
	_strip_prediction_detail(navigation.get("selected", {}) as Dictionary)
	ai_sample["navigation"] = navigation
	var relative := {}
	if is_instance_valid(player) and is_instance_valid(enemy):
		var offset := enemy.global_position - player.global_position
		relative = {"player_to_enemy": offset, "distance": offset.length(), "xz_distance": Vector2(offset.x, offset.z).length()}
	var player_state := _controller_state(player)
	var enemy_state := _controller_state(enemy)
	player_state["contacts"] = _contacts_with_age(player_state)
	enemy_state["contacts"] = _contacts_with_age(enemy_state)
	_emit(&"sample", {"encounter": _identity(encounter), "player": player_state, "enemy": enemy_state, "ai": ai_sample, "relative": relative})


func _controller_frame(actor: Node3D) -> Dictionary:
	if is_instance_valid(actor) and actor.has_method(&"get_driving_trace_frame"):
		return actor.call(&"get_driving_trace_frame") as Dictionary
	return _identity(actor)


func _observe_prediction(key: String, encounter: Dictionary, actor: Node3D, navigation: Dictionary) -> void:
	var request_frame := int(navigation.get("request_frame", -1))
	var actor_id := actor.get_instance_id() if is_instance_valid(actor) else 0
	var stamp := "%d:%d" % [actor_id, request_frame]
	if request_frame < 0 or _prediction_frames.get(key, "") == stamp:
		return
	_prediction_frames[key] = stamp
	var selected := (navigation.get("selected", {}) as Dictionary).duplicate(true)
	var descriptor := _descriptors.get(actor_id, {}) as Dictionary
	_enrich_evidence(selected, descriptor.get("shape_map", []) as Array)
	_emit(&"prediction", {"encounter": encounter, "actor": _identity(actor),
		"request_frame": request_frame, "generation": navigation.get("generation", -1),
		"observed_frame": Engine.get_physics_frames(), "cached": request_frame != Engine.get_physics_frames(),
		"requested": navigation.get("requested", {}), "selected": selected,
		"output": navigation.get("output", {}), "goal": navigation.get("goal", null),
		"terminal": navigation.get("terminal", false)})


func _strip_prediction_detail(selected: Dictionary) -> void:
	var stats := selected.get("stats", {}) as Dictionary
	stats.erase("trace")


## 僅在 logger 階段解析身分；不在 predictor watchdog 內走場景樹。
func _enrich_evidence(value: Variant, shape_map: Array) -> void:
	if value is Dictionary:
		var record := value as Dictionary
		if record.has("collider_id"):
			var collider_id := int(record.collider_id) if record.collider_id != null else 0
			var collider: Object = instance_from_id(collider_id) if collider_id > 0 else null
			record["collider_path"] = str((collider as Node).get_path()) if collider is Node and (collider as Node).is_inside_tree() else ""
		if record.has("shape_index"):
			var shape_index := int(record.shape_index)
			for item in shape_map:
				if int((item as Dictionary).get("shape_index", -2)) == shape_index:
					record["part_id"] = (item as Dictionary).get("part_id", "unknown")
					record["anchor"] = (item as Dictionary).get("anchor", "unknown")
					break
		for item in record.values():
			_enrich_evidence(item, shape_map)
	elif value is Array:
		for item in value as Array:
			_enrich_evidence(item, shape_map)


func _index_colliders(node: Node) -> void:
	if node is CollisionObject3D:
		_collision_objects[(node as CollisionObject3D).get_rid().get_id()] = weakref(node)
	for child in node.get_children():
		_index_colliders(child)


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in ["res://src/actors/tank/tank_controller.gd", "res://src/ai/tank_combat_ai.gd",
		"res://src/ai/tank_navigation.gd", "res://src/ai/tank_recovery.gd",
		"res://src/ai/tank_driving_predictor.gd", "res://src/debug/driving_trace_recorder.gd",
		"res://src/actors/tank/geometry/tank_motion_guard.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _disable_actor_traces() -> void:
	for actor_id in _descriptors:
		var actor: Object = instance_from_id(int(actor_id))
		if is_instance_valid(actor) and actor.has_method(&"set_driving_trace_enabled"):
			actor.call(&"set_driving_trace_enabled", false)


func _controller_state(actor: Node3D) -> Dictionary:
	if not is_instance_valid(actor) or not actor.has_method(&"get_driving_trace_state"):
		return _identity(actor)
	var state: Variant = actor.call(&"get_driving_trace_state")
	return state as Dictionary if state is Dictionary else _identity(actor)


func _contacts_with_age(state: Dictionary) -> Array:
	var contacts: Array = []
	var age: Variant = state.get("contact_age", -1)
	for item in state.get("contacts", []) as Array:
		if item is Dictionary:
			var contact := (item as Dictionary).duplicate(true)
			contact["age"] = age
			contacts.append(contact)
	return contacts


func _ai_state(encounter: Node) -> Dictionary:
	var ai := encounter.get("combat_ai") as Node
	if ai == null or not is_instance_valid(ai) or not ai.has_method(&"get_driving_trace_state"):
		return {}
	var state: Variant = ai.call(&"get_driving_trace_state")
	return state as Dictionary if state is Dictionary else {}


func _ai_transition(ai: Dictionary) -> Dictionary:
	var navigation := ai.get("navigation", {}) as Dictionary
	var selected := navigation.get("selected", {}) as Dictionary
	return {
		"status": ai.get("status", ""),
		"combat_enabled": ai.get("combat_enabled", false),
		"visible": ai.get("visible", false),
		"pursuing": ai.get("pursuing", false),
		"last_seen_valid": ai.get("last_seen_valid", false),
		"generation": ai.get("generation", -1),
		"navigation": {
			"status": navigation.get("status", ""),
			"terminal": navigation.get("terminal", false),
			"recovery_phase": navigation.get("recovery_phase", ""),
			"attempts": navigation.get("attempts", 0),
			"selected_reason": selected.get("reason", ""),
		},
	}


func _discrete_state(source: Dictionary) -> Dictionary:
	var output := {}
	for key in ["reason", "blocked_reason", "status", "active", "blocked"]:
		if source.has(key):
			output[key] = source[key]
	for key in ["root", "turret", "gun"]:
		if source.get(key) is Dictionary:
			output[key] = _discrete_state(source[key] as Dictionary)
	var reason := str(source.get("blocked_reason", ""))
	if reason.begins_with("new-collider:") or reason.begins_with("old-contact-inward:"):
		var rid_id := int(reason.get_slice(":", 1))
		var reference: WeakRef = _collision_objects.get(rid_id) as WeakRef
		var collider: Node = reference.get_ref() as Node if reference != null else null
		output["blocking_object"] = _identity(collider)
		output["blocking_rid"] = rid_id
		output["blocking_part"] = "unknown"
	return output


func _player(encounter: Node) -> Node3D:
	var runtime := encounter.get("player_runtime") as Node
	return runtime.get("controlled_tank") as Node3D if is_instance_valid(runtime) else null


func _identity(node: Node) -> Dictionary:
	if not is_instance_valid(node):
		return {"id": 0, "path": "", "scene": ""}
	return {"id": node.get_instance_id(), "path": str(node.get_path()), "scene": node.scene_file_path}


func _encounter_key(encounter: Node) -> String:
	return str(encounter.get_instance_id())


func _scene_path(encounter: Node) -> String:
	var scene := encounter.get_tree().current_scene
	return scene.scene_file_path if is_instance_valid(scene) else ""


func _emit(type: StringName, payload: Dictionary) -> bool:
	if _stopped or _file == null:
		return false
	var encoded := _encode_event(type, payload)
	var text := str(encoded.text)
	var bytes := int(encoded.bytes)
	if _written_bytes + bytes > _limit_bytes:
		if bytes > _limit_bytes:
			_stop_logging("DrivingTraceRecorder event exceeds the trace segment byte limit; logging stopped.")
			return false
		if not _rotate_segment():
			return false
		encoded = _encode_event(type, payload)
		text = str(encoded.text)
		bytes = int(encoded.bytes)
		if _written_bytes + bytes > _limit_bytes:
			_stop_logging("DrivingTraceRecorder event did not fit after segment bootstrap; logging stopped.")
			return false
	_file.store_line(text)
	if _file.get_error() != OK:
		_stop_logging("DrivingTraceRecorder write failed and logging stopped.")
		return false
	_written_bytes += bytes
	_sequence += 1
	return true


func _encode_event(type: StringName, payload: Dictionary) -> Dictionary:
	var line := {"type": type, "seq": _sequence, "t_ms": (Time.get_ticks_usec() - _started_usec) / 1000, "frame": Engine.get_physics_frames()}
	for key in payload:
		line[key] = payload[key]
	var text := JSON.stringify(_json_value(line))
	return {"text": text, "bytes": text.to_utf8_buffer().size() + 1}


func _write_bootstrap_line(target: FileAccess, type: StringName, payload: Dictionary, written: int) -> Dictionary:
	var line := {"type": type, "seq": _sequence, "t_ms": (Time.get_ticks_usec() - _started_usec) / 1000, "frame": Engine.get_physics_frames()}
	for key in payload:
		line[key] = payload[key]
	var text := JSON.stringify(_json_value(line))
	var bytes := text.to_utf8_buffer().size() + 1
	if written + bytes > _limit_bytes:
		push_warning("DrivingTraceRecorder segment bootstrap exceeds the trace segment byte limit.")
		return {"ok": false}
	target.store_line(text)
	if target.get_error() != OK:
		push_warning("DrivingTraceRecorder could not write a trace segment bootstrap.")
		return {"ok": false}
	_sequence += 1
	return {"ok": true, "written_bytes": written + bytes}


func _rotate_segment() -> bool:
	var encounters := _live_encounters()
	var encounter: Node = encounters.front() as Node if not encounters.is_empty() else null
	var pending := _prepare_segment(encounter, _segment_index + 1, _log_path)
	if pending.is_empty():
		_stop_logging("DrivingTraceRecorder could not prepare a replacement trace segment; logging stopped.")
		return false
	var previous_file := _file
	var previous_path := _log_path
	_file = pending.file as FileAccess
	_log_path = str(pending.path)
	_written_bytes = int(pending.written_bytes)
	_segment_index += 1
	_segments.append({"path": _log_path, "index": _segment_index, "closed": false})
	for segment in _segments:
		if str(segment.path) == previous_path:
			segment["closed"] = true
			break
	previous_file.flush()
	if previous_file.get_error() != OK:
		_stop_logging("DrivingTraceRecorder could not close the previous trace segment; logging stopped.")
		return false
	previous_file.close()
	if not _cleanup_segments():
		return false
	return true


func _previous_segment_path() -> String:
	for offset in range(_segments.size() - 1, -1, -1):
		var segment := _segments[offset]
		if str(segment.path) != _log_path:
			return str(segment.path)
	return ""


func _retained_segment_paths() -> Dictionary:
	var retained := {}
	var first := maxi(0, _segments.size() - RETAIN_SEGMENT_COUNT)
	for offset in range(first, _segments.size()):
		retained[str(_segments[offset].path)] = true
	if not _pinned_marker_path.is_empty():
		retained[_pinned_marker_path] = true
	if not _pinned_previous_path.is_empty():
		retained[_pinned_previous_path] = true
	return retained


func _cleanup_segments() -> bool:
	var retained := _retained_segment_paths()
	var planned: Array[String] = []
	for segment in _segments:
		var path := str(segment.path)
		if bool(segment.get("closed", false)) and not retained.has(path):
			planned.append(path)
	for path in planned:
		if not _is_owned_closed_unretained_path(path, retained, planned):
			_stop_logging("DrivingTraceRecorder retention inventory mismatch; logging stopped.")
			return false
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			_stop_logging("DrivingTraceRecorder could not clean a retired trace segment; logging stopped.")
			return false
		for offset in range(_segments.size() - 1, -1, -1):
			if str(_segments[offset].path) == path:
				_segments.remove_at(offset)
				break
	return true



func _is_owned_closed_unretained_path(path: String, retained: Dictionary, planned: Array[String]) -> bool:
	if not planned.has(path) or retained.has(path):
		return false
	for segment in _segments:
		if str(segment.path) == path:
			return bool(segment.get("closed", false))
	return false


func _flush() -> bool:
	if _file == null or _stopped:
		return false
	_file.flush()
	if _file.get_error() != OK:
		_stop_logging("DrivingTraceRecorder flush failed and logging stopped.")
		return false
	return true


func _stop_logging(message: String) -> void:
	push_warning(message)
	_stopped = true
	_disable_actor_traces()
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


func _json_value(value: Variant) -> Variant:
	if value is Transform3D:
		var transform := value as Transform3D
		return {"origin": _json_value(transform.origin), "basis": _json_value(transform.basis)}
	if value is Basis:
		var basis := value as Basis
		return {"x": _json_value(basis.x), "y": _json_value(basis.y), "z": _json_value(basis.z)}
	if value is Vector3:
		var vector := value as Vector3
		return [_finite_or_null(vector.x), _finite_or_null(vector.y), _finite_or_null(vector.z)]
	if value is Vector2:
		var vector2 := value as Vector2
		return [_finite_or_null(vector2.x), _finite_or_null(vector2.y)]
	if value is RID:
		return (value as RID).get_id()
	if value is float:
		return _finite_or_null(value as float)
	if value is Dictionary:
		var output := {}
		for key in (value as Dictionary):
			output[str(key)] = _json_value((value as Dictionary)[key])
		return output
	if value is Array:
		var output: Array = []
		for item in value as Array:
			output.append(_json_value(item))
		return output
	return value


func _finite_or_null(value: float) -> Variant:
	return value if is_finite(value) else null
