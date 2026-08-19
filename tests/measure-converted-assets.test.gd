extends SceneTree

const Verifier := preload("res://scripts/measure-converted-assets.gd")
const IDS := ["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"]


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var checks := [
		check_cli, check_good_mesh, check_multiple_and_nested_transforms, check_local_hidden, check_ancestor_hidden,
		check_no_mesh, check_non_finite, check_join_cases,
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
	var tolerance_boundary := lock.duplicate(true)
	tolerance_boundary[0].expectedGodotXyz[0] = 1.005
	if not Verifier.verify_measurement_join(actual, manifest, tolerance_boundary).ok:
		return failure()
	var wrong_join := manifest.duplicate(true)
	wrong_join[1].id = "tank2"
	if Verifier.verify_measurement_join(actual, wrong_join, lock).ok:
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


func success() -> Dictionary:
	return {"ok": true}


func failure() -> Dictionary:
	return {"ok": false}
