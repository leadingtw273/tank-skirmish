extends SceneTree

const TANK3 := preload("res://src/actors/tank/variants/tank3/tank3.tscn")
const TANK2 := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var main := load("res://src/main.tscn").instantiate() as Node3D
	main.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(main)
	var group := main.get_node("PlayerSpawnGroup") as Node3D
	var tank := group.get_node("Tank") as Node3D
	var camera := group.get_node("CameraRig") as Node3D
	var player := main.get_node("PlayerRuntime")
	var combat := main.get_node("CombatRuntime")
	expect(group.get_child_count() == 2, "spawn group starts with camera and tank only")
	expect(tank.global_position.distance_to(Vector3(-108, 0, -106)) < 0.001, "main retains upper-left spawn")
	expect(camera.global_position.distance_to(Vector3(-108, 0, -114)) < 0.001, "camera translates with spawn")
	expect(camera.get("follow_target") == tank, "camera is bound to grouped tank")
	expect(player.get("controlled_tank") == tank, "player is bound to grouped tank")
	expect(combat.call("get_registered_shot_sources").has(tank), "combat registers grouped tank")
	expect(camera.get("follow_target_offset").distance_to(Vector3(0, 0, -8)) < 0.001, "original framing offset retained")
	# Suppress mouse look-ahead only in this deterministic test.
	camera.set("look_ahead_dead_zone", 2.0)
	var framing_basis: Basis = camera.global_basis
	var before_tank := tank.global_position
	var before_camera := camera.global_position
	var shift := Vector3(17, 0, -9)
	group.position += shift
	expect(tank.global_position.distance_to(before_tank + shift) < 0.001, "group translation moves tank")
	expect(camera.global_position.distance_to(before_camera + shift) < 0.001, "group translation moves camera equally")
	tank.global_position += Vector3(4, 0, 3)
	tank.rotate_y(0.4)
	camera.call("_process", 0.0)
	expect(camera.global_position.distance_to(tank.global_position + Vector3(0, 0, -8)) < 0.001, "camera follows tank motion")
	expect(camera.global_basis.is_equal_approx(framing_basis), "hull rotation does not rotate camera")
	var replace_pose := tank.global_transform
	var replacement := main.call("replace_player_tank", TANK3) as Node3D
	expect(replacement != null, "replacement succeeds")
	if replacement != null:
		expect(replacement.get_parent() == group, "replacement stays inside group")
		expect(replacement.global_transform.is_equal_approx(replace_pose), "replacement preserves world pose under translated group")
		expect(player.get("controlled_tank") == replacement, "replacement controls rebound")
		expect(camera.get("follow_target") == replacement, "replacement camera rebound")
		expect(combat.call("get_registered_shot_sources").has(replacement), "replacement combat rebound")
		expect(not combat.call("get_registered_shot_sources").has(tank), "old shot source removed")
		# Exercise the real wreck-retention path as well as an ordinary replacement.
		replacement.get_node("HealthComponent").call("apply_damage", 100000.0)
		var spawn_pose := Transform3D(Basis(Vector3.UP, 0.2), Vector3(-108, 0, -106))
		var respawned := main.call("respawn_player_tank", TANK2, spawn_pose) as Node3D
		expect(respawned != null, "respawn succeeds")
		if respawned != null:
			expect(respawned.get_parent() == group, "respawn stays inside group")
			expect(respawned.global_transform.is_equal_approx(spawn_pose), "respawn uses world-to-group conversion")
			expect(camera.global_position.distance_to(spawn_pose.origin + Vector3(0, 0, -8)) < 0.001, "respawn resets camera around new tank")
			expect(player.get("controlled_tank") == respawned, "respawn controls rebound")
			expect(combat.call("get_registered_shot_sources").has(respawned), "respawn combat rebound")
			expect(replacement.is_in_group("player_wreck"), "wreck behavior retained")
	main.queue_free()
	await process_frame
	var training := load("res://src/maps/training_ground/training_ground_playtest.tscn").instantiate() as Node3D
	training.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(training)
	var training_tank := training.get_node("Main/PlayerSpawnGroup/Tank") as Node3D
	var training_camera := training.get_node("Main/PlayerSpawnGroup/CameraRig") as Node3D
	expect(training_tank.global_position.distance_to(Vector3(0, 0, 8)) < 0.001, "training spawn unchanged")
	expect(training_camera.global_position.distance_to(Vector3.ZERO) < 0.001, "training camera pose unchanged")
	expect(training_camera.get("follow_target") == training_tank, "training follow binding valid")
	training.queue_free()
	await process_frame
	print("PLAYER_SPAWN_GROUP %s failures=%d" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
