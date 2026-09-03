extends SceneTree

const Verifier := preload("res://scripts/measure-converted-assets.gd")
const TANK_IDS := ["tank1", "tank2", "tank3", "tank4"]
const IDS := ["tank1", "tank2", "tank3", "tank4", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"]


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var checks := [
		check_cli, check_good_mesh, check_multiple_and_nested_transforms, check_local_hidden, check_ancestor_hidden,
		check_no_mesh, check_non_finite, check_join_cases, check_composite_cases,
	]
	for check in checks:
		var result: Dictionary = await check.call()
		if not result.ok:
			printerr("MEASURE_CONVERTED_ASSETS_TEST_FAIL")
			quit(1)
			return
	print("MEASURE_CONVERTED_ASSETS_TEST_PASS")
	quit(0)


func check_cli() -> Dictionary:
	var good := Verifier.parse_cli_args(["--emit", "--input-root", "/tmp/in", "--static-report", "/tmp/static", "--output-report", "/tmp/out"])
	if not good.ok or good.value.mode != "--emit":
		return failure()
	var good_check := Verifier.parse_cli_args(["--check", "--input-root", "/tmp/in", "--manifest", "/tmp/report", "--lock", "/tmp/lock"])
	if not good_check.ok or good_check.value.mode != "--check" or good_check.value.manifest != "/tmp/report" or good_check.value.lock != "/tmp/lock":
		return failure()
	for args in [[], ["--emit", "--input-root", "/tmp/in", "--input-root", "/tmp/other", "--static-report", "/tmp/static", "--output-report", "/tmp/out"], ["--check", "--input-root", "/tmp/in", "--manifest", "/tmp/report", "--lock", "/tmp/lock", "--unknown"], ["--check", "--input-root", "relative", "--manifest", "/tmp/report", "--lock", "/tmp/lock"], ["--emit", "--input-root", "/tmp/../tmp/in", "--static-report", "/tmp/static", "--output-report", "/tmp/out"]]:
		if Verifier.parse_cli_args(args).ok:
			return failure()
	return success()


func check_good_mesh() -> Dictionary:
	var model := Node3D.new()
	model.add_child(box(Vector3(2.0, 4.0, 6.0), Vector3.ZERO))
	root.add_child(model)
	await process_frame
	var measured := Verifier.measure_visible_mesh_aabb(model)
	model.queue_free()
	await process_frame
	if not measured.ok or measured.value != [2.0, 4.0, 6.0]:
		return failure()
	return success()


func check_multiple_and_nested_transforms() -> Dictionary:
	var model := Node3D.new()
	model.add_child(box(Vector3(2.0, 2.0, 2.0), Vector3(-3.0, 0.0, 0.0)))
	var parent := Node3D.new()
	parent.position = Vector3(3.0, 1.0, 0.0)
	parent.add_child(box(Vector3(2.0, 4.0, 2.0), Vector3.ZERO))
	model.add_child(parent)
	root.add_child(model)
	await process_frame
	var measured := Verifier.measure_visible_mesh_aabb(model)
	model.queue_free()
	await process_frame
	if not measured.ok or measured.value != [8.0, 4.0, 2.0]:
		return failure()
	return success()


func check_local_hidden() -> Dictionary:
	var model := Node3D.new()
	var hidden := box(Vector3(4.0, 4.0, 4.0), Vector3.ZERO)
	hidden.visible = false
	model.add_child(hidden)
	root.add_child(model)
	await process_frame
	var measured := Verifier.measure_visible_mesh_aabb(model)
	model.queue_free()
	await process_frame
	return success() if not measured.ok and measured.code == "NO_VISIBLE_MESH" else failure()


func check_ancestor_hidden() -> Dictionary:
	var model := Node3D.new()
	var parent := Node3D.new()
	parent.visible = false
	parent.add_child(box(Vector3(4.0, 4.0, 4.0), Vector3.ZERO))
	model.add_child(parent)
	root.add_child(model)
	await process_frame
	var measured := Verifier.measure_visible_mesh_aabb(model)
	model.queue_free()
	await process_frame
	return success() if not measured.ok and measured.code == "NO_VISIBLE_MESH" else failure()


func check_no_mesh() -> Dictionary:
	var model := Node3D.new()
	root.add_child(model)
	await process_frame
	var measured := Verifier.measure_visible_mesh_aabb(model)
	model.queue_free()
	await process_frame
	return success() if not measured.ok and measured.code == "NO_VISIBLE_MESH" else failure()


func check_non_finite() -> Dictionary:
	var invalid := AABB(Vector3(INF, 0.0, 0.0), Vector3.ONE)
	return success() if not Verifier.valid_local_aabb(invalid) else failure()


func check_join_cases() -> Dictionary:
	var actual := join_models()
	var manifest := join_models()
	var lock := join_models(true)
	if not Verifier.verify_measurement_join(actual, manifest, lock).ok:
		return failure()
	var digest := actual.duplicate(true)
	digest[1].outputDigest = digest[0].outputDigest
	var duplicate_manifest := manifest.duplicate(true)
	duplicate_manifest[1].outputDigest = duplicate_manifest[0].outputDigest
	var duplicate_lock := lock.duplicate(true)
	duplicate_lock[1].outputDigest = duplicate_lock[0].outputDigest
	if Verifier.verify_measurement_join(digest, duplicate_manifest, duplicate_lock).ok:
		return failure()
	var wrong_expected := lock.duplicate(true)
	wrong_expected[0].expectedGodotXyz[0] = 2.0
	if Verifier.verify_measurement_join(actual, manifest, wrong_expected).ok:
		return failure()
	var floor_boundary := join_case(1.01, 1.0)
	if not Verifier.verify_measurement_join(floor_boundary.actual, floor_boundary.manifest, floor_boundary.lock).ok:
		return failure()
	var past_floor_boundary := join_case(1.01001, 1.0)
	if Verifier.verify_measurement_join(past_floor_boundary.actual, past_floor_boundary.manifest, past_floor_boundary.lock).code != "TOLERANCE_MISMATCH":
		return failure()
	var relative_boundary := join_case(10.1, 10.0)
	if not Verifier.verify_measurement_join(relative_boundary.actual, relative_boundary.manifest, relative_boundary.lock).ok:
		return failure()
	var past_relative_boundary := join_case(10.10001, 10.0)
	if Verifier.verify_measurement_join(past_relative_boundary.actual, past_relative_boundary.manifest, past_relative_boundary.lock).code != "TOLERANCE_MISMATCH":
		return failure()
	var manifest_digest_mismatch := manifest.duplicate(true)
	manifest_digest_mismatch[0].outputDigest = "%064x" % 99
	if Verifier.verify_measurement_join(actual, manifest_digest_mismatch, lock).code != "JOIN_MISMATCH":
		return failure()
	var manifest_measurement_mismatch := manifest.duplicate(true)
	manifest_measurement_mismatch[0].measuredGodotXyz[0] = 1.1
	if Verifier.verify_measurement_join(actual, manifest_measurement_mismatch, lock).code != "MEASUREMENT_MISMATCH":
		return failure()
	var wrong_join := manifest.duplicate(true)
	wrong_join[1].id = "tank1"
	if Verifier.verify_measurement_join(actual, wrong_join, lock).ok:
		return failure()
	return success()


func check_composite_cases() -> Dictionary:
	var actual := join_models()
	var manifest := composite_models()
	var lock := composite_lock_models()
	if not Verifier.validate_composite_manifest(composite_manifest(manifest)).ok:
		return failure()
	if not Verifier.verify_composite_join(actual, manifest, lock).ok:
		return failure()
	var wrong_output := manifest.duplicate(true)
	wrong_output[0].outputDigest = "%064x" % 99
	if Verifier.verify_composite_join(actual, wrong_output, lock).code != "JOIN_MISMATCH":
		return failure()
	var wrong_measurement := manifest.duplicate(true)
	wrong_measurement[0].measuredGodotXyz[0] = 1.1
	if Verifier.verify_composite_join(actual, wrong_measurement, lock).code != "MEASUREMENT_MISMATCH":
		return failure()
	var unknown := composite_manifest(manifest)
	unknown.unexpected = true
	if Verifier.validate_composite_manifest(unknown).ok:
		return failure()
	var old_measurement_only := {"schemaVersion": 1, "staticReportDigest": "%064x" % 1, "models": join_models()}
	if Verifier.validate_composite_manifest(old_measurement_only).ok:
		return failure()
	return success()


func box(size: Vector3, position: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	return instance


func join_models(include_expected := false) -> Array:
	var models: Array = []
	for index in range(IDS.size()):
		var item := {"id": IDS[index], "outputDigest": "%064x" % (index + 1), "measuredGodotXyz": [1.0, 1.0, 1.0]}
		if include_expected:
			item.expectedGodotXyz = [1.0, 1.0, 1.0]
		models.append(item)
	return models


func join_case(actual_axis: float, expected_axis: float) -> Dictionary:
	var actual := join_models()
	var manifest := join_models()
	var lock := join_models(true)
	for models in [actual, manifest, lock]:
		models[0].measuredGodotXyz[0] = actual_axis
	lock[0].expectedGodotXyz[0] = expected_axis
	return {"actual": actual, "manifest": manifest, "lock": lock}


func composite_manifest(models: Array) -> Dictionary:
	return {"schemaVersion": 1, "runnerManifestDigest": "%064x" % 1, "runnerRunIdentity": "%064x" % 2, "toolchain": {"executableChecksum": "%064x" % 3, "id": "blender", "version": "4.3.0", "versionContract": {}}, "exporterDigest": "%064x" % 4, "models": models}


func composite_models() -> Array:
	var models: Array = []
	for index in range(IDS.size()):
		var id: String = IDS[index]
		var is_tank := TANK_IDS.has(id)
		models.append({"id": id, "category": "tank" if is_tank else "building", "sourceFileId": "file-%s" % id, "sourceDigest": "%064x" % (index + 10), "scale": 1.0, "sourceActionNames": ["Drive"] if is_tank else [], "outputRelativePath": "assets/models/tank/%s.glb" % id if is_tank else "assets/models/buildings/%s.glb" % id, "outputDigest": "%064x" % (index + 1), "animationNames": ["Drive"] if is_tank else [], "imageCount": 0 if is_tank else 1, "embeddedImageDigest": null if is_tank else "%064x" % (index + 30), "measuredGodotXyz": [1.0, 1.0, 1.0]})
	return models


func composite_lock_models() -> Array:
	var models: Array = []
	for model in composite_models():
		models.append({"id": model.id, "category": model.category, "source": {"fileId": model.sourceFileId, "sha256": model.sourceDigest}, "scale": model.scale, "expectedGodotXyz": [1.0, 1.0, 1.0], "outputDigest": model.outputDigest, "measuredGodotXyz": model.measuredGodotXyz, "embeddedImageDigest": model.embeddedImageDigest})
	return models


func success() -> Dictionary:
	return {"ok": true}


func failure() -> Dictionary:
	return {"ok": false}
