extends SceneTree

const IDS := ["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"]
const SHA256_LENGTH := 64
const ROUNDING_FACTOR := 100000.0


func _init() -> void:
	call_deferred("_run_cli")


func _run_cli() -> void:
	var parsed := parse_cli_args(OS.get_cmdline_user_args())
	if not parsed.ok:
		printerr(parsed.code)
		quit(2)
		return

	var result := await run_command(parsed.value)
	if not result.ok:
		printerr(result.code)
		quit(1)
		return
	quit(0)


static func parse_cli_args(args: Array) -> Dictionary:
	if args.size() != 7:
		return failure("USAGE")
	var mode: String = args[0]
	if mode != "--emit" and mode != "--check":
		return failure("USAGE")
	var required := ["--input-root", "--static-report", "--output-report"] if mode == "--emit" else ["--input-root", "--manifest", "--lock"]
	var values := {"mode": mode}
	for flag in required:
		var index := args.find(flag)
		if index == -1 or args.find(flag, index + 1) != -1 or index + 1 >= args.size():
			return failure("USAGE")
		if typeof(args[index + 1]) != TYPE_STRING:
			return failure("USAGE")
		var value: String = args[index + 1]
		if not value.is_absolute_path() or value.simplify_path() != value:
			return failure("USAGE")
		values[flag.trim_prefix("--").replace("-", "_")] = value
	for index in range(args.size()):
		if index == 0:
			continue
		if args[index] in required:
			continue
		if index > 0 and args[index - 1] in required:
			continue
		return failure("USAGE")
	return success(values)


func run_command(parsed: Dictionary) -> Dictionary:
	if parsed.mode == "--emit":
		return await emit_report(parsed.input_root, parsed.static_report, parsed.output_report)
	return await check_report(parsed.input_root, parsed.manifest, parsed.lock)


func emit_report(input_root: String, static_report_path: String, output_report: String) -> Dictionary:
	var static_read := read_canonical_json(static_report_path, "STATIC_REPORT_INVALID")
	if not static_read.ok:
		return static_read
	var static_report: Dictionary = static_read.value
	var static_validation := validate_static_report(static_report)
	if not static_validation.ok:
		return static_validation
	if FileAccess.file_exists(output_report):
		return failure("OUTPUT_REPORT_EXISTS")
	if not DirAccess.dir_exists_absolute(input_root):
		return failure("INPUT_ROOT_INVALID")

	var static_by_id := closed_model_map(static_report.models, ["id", "category", "outputRelativePath", "outputDigest", "sourceActionNames", "animationNames", "imageCount", "embeddedImageDigest"], true, "STATIC_REPORT_INVALID")
	if not static_by_id.ok:
		return static_by_id
	var models: Array = []
	for id in IDS:
		var item: Dictionary = static_by_id.value[id]
		var output_path: String = input_root.path_join(item.outputRelativePath)
		if not FileAccess.file_exists(output_path) or sha256_bytes(FileAccess.get_file_as_bytes(output_path)) != item.outputDigest:
			return failure("DIGEST_MISMATCH")
		var loaded := await measure_packed_scene(output_path)
		if not loaded.ok:
			return loaded
		models.append({"id": id, "outputDigest": item.outputDigest, "measuredGodotXyz": loaded.value})

	var report := {"schemaVersion": 1, "staticReportDigest": sha256_bytes(static_read.bytes), "models": models}
	var bytes := canonical_bytes(report)
	if bytes.is_empty():
		return failure("REPORT_INVALID")
	var file := FileAccess.open(output_report, FileAccess.WRITE)
	if file == null:
		return failure("OUTPUT_WRITE_FAILED")
	file.store_buffer(bytes)
	file.close()
	return success()


func check_report(input_root: String, manifest_path: String, lock_path: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(input_root):
		return failure("INPUT_ROOT_INVALID")
	var manifest_read := read_canonical_json(manifest_path, "MEASUREMENT_REPORT_INVALID")
	if not manifest_read.ok:
		return manifest_read
	var manifest_validation := validate_measurement_report(manifest_read.value)
	if not manifest_validation.ok:
		return manifest_validation
	var lock_read := read_json(lock_path, "LOCK_INVALID")
	if not lock_read.ok:
		return lock_read
	var lock_validation := validate_lock(lock_read.value)
	if not lock_validation.ok:
		return lock_validation

	var actual: Array = []
	for id in IDS:
		var path := input_root.path_join(logical_path(id))
		if not FileAccess.file_exists(path):
			return failure("LOAD_FAILED")
		var bytes := FileAccess.get_file_as_bytes(path)
		var measured := await measure_packed_scene(path)
		if not measured.ok:
			return measured
		actual.append({"id": id, "outputDigest": sha256_bytes(bytes), "measuredGodotXyz": measured.value})
	return verify_measurement_join(actual, manifest_read.value.models, lock_read.value.models)


func measure_packed_scene(path: String) -> Dictionary:
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		return failure("LOAD_FAILED")
	var instance := packed.instantiate()
	if not (instance is Node3D):
		return failure("LOAD_FAILED")
	root.add_child(instance)
	await process_frame
	var result := measure_visible_mesh_aabb(instance)
	instance.queue_free()
	await process_frame
	return result


static func measure_visible_mesh_aabb(model_root: Node3D) -> Dictionary:
	if model_root == null or not model_root.is_inside_tree():
		return failure("MODEL_NOT_IN_TREE")
	var extrema := {"has_mesh": false, "minimum": Vector3.ZERO, "maximum": Vector3.ZERO}
	var visit := collect_mesh_bounds(model_root, model_root, extrema)
	if not visit.ok:
		return visit
	if not extrema.has_mesh:
		return failure("NO_VISIBLE_MESH")
	var size: Vector3 = extrema.maximum - extrema.minimum
	if not valid_vector(size) or size.x < 0.0 or size.y < 0.0 or size.z < 0.0:
		return failure("AABB_INVALID")
	return success(round_vector(size))


static func collect_mesh_bounds(model_root: Node3D, node: Node, extrema: Dictionary) -> Dictionary:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.is_visible_in_tree() and mesh_instance.mesh != null:
			var local := mesh_instance.mesh.get_aabb()
			if not valid_local_aabb(local):
				return failure("AABB_INVALID")
			var relative := model_root.global_transform.affine_inverse() * mesh_instance.global_transform
			for corner in aabb_corners(local):
				var point: Vector3 = relative * corner
				if not valid_vector(point):
					return failure("AABB_INVALID")
				if not extrema.has_mesh:
					extrema.minimum = point
					extrema.maximum = point
					extrema.has_mesh = true
				else:
					extrema.minimum = extrema.minimum.min(point)
					extrema.maximum = extrema.maximum.max(point)
	for child in node.get_children():
		var result := collect_mesh_bounds(model_root, child, extrema)
		if not result.ok:
			return result
	return success()


static func aabb_corners(aabb: AABB) -> Array:
	var from := aabb.position
	var to := aabb.position + aabb.size
	return [
		Vector3(from.x, from.y, from.z), Vector3(from.x, from.y, to.z), Vector3(from.x, to.y, from.z), Vector3(from.x, to.y, to.z),
		Vector3(to.x, from.y, from.z), Vector3(to.x, from.y, to.z), Vector3(to.x, to.y, from.z), Vector3(to.x, to.y, to.z),
	]


static func valid_local_aabb(aabb: AABB) -> bool:
	return valid_vector(aabb.position) and valid_vector(aabb.size) and aabb.size.x >= 0.0 and aabb.size.y >= 0.0 and aabb.size.z >= 0.0


static func verify_measurement_join(actual_models: Array, manifest_models: Array, lock_models: Array) -> Dictionary:
	var actual := closed_model_map(actual_models, ["id", "outputDigest", "measuredGodotXyz"], true, "JOIN_MISMATCH")
	var manifest := closed_model_map(manifest_models, ["id", "outputDigest", "measuredGodotXyz"], true, "JOIN_MISMATCH")
	var lock := closed_model_map(lock_models, ["id", "outputDigest", "expectedGodotXyz", "measuredGodotXyz"], false, "JOIN_MISMATCH")
	if not actual.ok:
		return actual
	if not manifest.ok:
		return manifest
	if not lock.ok:
		return lock
	var digest_seen := {}
	for id in IDS:
		var current: Dictionary = actual.value[id]
		var recorded: Dictionary = manifest.value[id]
		var locked: Dictionary = lock.value[id]
		if not valid_sha256(current.outputDigest) or current.outputDigest != recorded.outputDigest or current.outputDigest != locked.outputDigest:
			return failure("JOIN_MISMATCH")
		if digest_seen.has(current.outputDigest):
			return failure("DUPLICATE_DIGEST")
		digest_seen[current.outputDigest] = true
		if not valid_vector_array(current.measuredGodotXyz, false) or not valid_vector_array(recorded.measuredGodotXyz, false) or not valid_vector_array(locked.measuredGodotXyz, false) or not valid_vector_array(locked.expectedGodotXyz, true):
			return failure("JOIN_MISMATCH")
		for axis in range(3):
			var actual_axis: float = canonical_round(float(current.measuredGodotXyz[axis]))
			var expected_axis: float = float(locked.expectedGodotXyz[axis])
			if not within_measurement_tolerance(actual_axis, expected_axis):
				return failure("TOLERANCE_MISMATCH")
			if actual_axis != float(recorded.measuredGodotXyz[axis]) or actual_axis != float(locked.measuredGodotXyz[axis]):
				return failure("MEASUREMENT_MISMATCH")
	return success()


static func validate_static_report(value: Variant) -> Dictionary:
	if not exact_dictionary(value, ["schemaVersion", "runIdentity", "runnerManifestDigest", "toolchain", "exporter", "models"]) or value.schemaVersion != 1 or not valid_sha256(value.runIdentity) or not valid_sha256(value.runnerManifestDigest):
		return failure("STATIC_REPORT_INVALID")
	if not exact_dictionary(value.toolchain, ["executableChecksum", "id", "version", "versionContract"]) or not valid_sha256(value.toolchain.executableChecksum) or typeof(value.toolchain.id) != TYPE_STRING or typeof(value.toolchain.version) != TYPE_STRING or typeof(value.toolchain.versionContract) != TYPE_DICTIONARY:
		return failure("STATIC_REPORT_INVALID")
	if not exact_dictionary(value.exporter, ["sourceDigest"]) or not valid_sha256(value.exporter.sourceDigest):
		return failure("STATIC_REPORT_INVALID")
	var models := closed_model_map(value.models, ["id", "category", "outputRelativePath", "outputDigest", "sourceActionNames", "animationNames", "imageCount", "embeddedImageDigest"], true, "STATIC_REPORT_INVALID")
	if not models.ok:
		return models
	var digest_seen := {}
	for id in IDS:
		var model: Dictionary = models.value[id]
		if model.category != ("tank" if id == "tank2" else "building") or model.outputRelativePath != logical_path(id) or not valid_sha256(model.outputDigest) or typeof(model.sourceActionNames) != TYPE_ARRAY or typeof(model.animationNames) != TYPE_ARRAY or (typeof(model.imageCount) != TYPE_INT and typeof(model.imageCount) != TYPE_FLOAT):
			return failure("STATIC_REPORT_INVALID")
		var image_count := float(model.imageCount)
		if not is_finite(image_count) or image_count < 0.0 or image_count != floor(image_count):
			return failure("STATIC_REPORT_INVALID")
		if digest_seen.has(model.outputDigest):
			return failure("DUPLICATE_DIGEST")
		digest_seen[model.outputDigest] = true
	return success()


static func validate_measurement_report(value: Variant) -> Dictionary:
	if not exact_dictionary(value, ["schemaVersion", "staticReportDigest", "models"]) or value.schemaVersion != 1 or not valid_sha256(value.staticReportDigest):
		return failure("MEASUREMENT_REPORT_INVALID")
	return closed_model_map(value.models, ["id", "outputDigest", "measuredGodotXyz"], true, "MEASUREMENT_REPORT_INVALID")


static func validate_lock(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or not value.has("conversionManifest") or not value.has("models") or typeof(value.conversionManifest) != TYPE_DICTIONARY or value.conversionManifest.get("state") != "present":
		return failure("LOCK_INVALID")
	return closed_model_map(value.models, ["id", "outputDigest", "expectedGodotXyz", "measuredGodotXyz"], false, "LOCK_INVALID")


static func closed_model_map(models: Variant, required_fields: Array, require_exact: bool, code: String) -> Dictionary:
	if typeof(models) != TYPE_ARRAY or models.size() != IDS.size():
		return failure(code)
	var by_id := {}
	for model in models:
		if typeof(model) != TYPE_DICTIONARY or not model.has("id") or typeof(model.id) != TYPE_STRING or not IDS.has(model.id) or by_id.has(model.id):
			return failure(code)
		for field in required_fields:
			if not model.has(field):
				return failure(code)
		if require_exact and model.size() != required_fields.size():
			return failure(code)
		by_id[model.id] = model
	for id in IDS:
		if not by_id.has(id):
			return failure(code)
	return success(by_id)


static func read_json(path: String, code: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return failure(code)
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return failure(code)
	return success(parsed)


static func read_canonical_json(path: String, code: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return failure(code)
	var bytes := FileAccess.get_file_as_bytes(path)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY or bytes != canonical_bytes(parsed):
		return failure(code)
	return {"ok": true, "value": parsed, "bytes": bytes}


static func canonical_bytes(value: Variant) -> PackedByteArray:
	var encoded := canonical_json(value)
	if encoded.is_empty():
		return PackedByteArray()
	return (encoded + "\n").to_utf8_buffer()


static func canonical_json(value: Variant) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		var keys: Array = dictionary.keys()
		keys.sort()
		var fields: Array[String] = []
		for key in keys:
			if typeof(key) != TYPE_STRING:
				return ""
			var encoded := canonical_json(dictionary[key])
			if encoded.is_empty():
				return ""
			fields.append(JSON.stringify(key) + ":" + encoded)
		return "{" + ",".join(fields) + "}"
	if typeof(value) == TYPE_ARRAY:
		var values: Array[String] = []
		for item in value:
			var encoded := canonical_json(item)
			if encoded.is_empty():
				return ""
			values.append(encoded)
		return "[" + ",".join(values) + "]"
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value):
			return ""
		if value == floor(value):
			return str(int(value))
	if typeof(value) != TYPE_NIL and typeof(value) != TYPE_BOOL and typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_STRING:
		return ""
	return JSON.stringify(value)


static func logical_path(id: String) -> String:
	return "assets/models/tank/tank2.glb" if id == "tank2" else "assets/models/buildings/%s.glb" % id


static func exact_dictionary(value: Variant, fields: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	return true


static func valid_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != SHA256_LENGTH:
		return false
	for character in value:
		if not (character >= "0" and character <= "9") and not (character >= "a" and character <= "f"):
			return false
	return true


static func valid_vector(value: Vector3) -> bool:
	return value.is_finite()


static func valid_vector_array(value: Variant, positive: bool) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for coordinate in value:
		if (typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT) or not is_finite(float(coordinate)) or (positive and float(coordinate) <= 0.0):
			return false
	return true


static func round_vector(value: Vector3) -> Array:
	return [canonical_round(value.x), canonical_round(value.y), canonical_round(value.z)]


static func canonical_round(value: float) -> float:
	var rounded := roundf(value * ROUNDING_FACTOR) / ROUNDING_FACTOR
	return 0.0 if rounded == 0.0 else rounded


static func within_measurement_tolerance(actual_axis: float, expected_axis: float) -> bool:
	var actual_units := roundf(actual_axis * ROUNDING_FACTOR)
	var expected_units := expected_axis * ROUNDING_FACTOR
	var tolerance_units := maxf(0.01 * ROUNDING_FACTOR, absf(expected_units) * 0.005)
	return absf(actual_units - expected_units) <= tolerance_units + 0.000001


static func sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


static func success(value: Variant = null) -> Dictionary:
	return {"ok": true, "value": value}


static func failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}
