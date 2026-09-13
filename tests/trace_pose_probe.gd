## One-shot read-only diagnostic.  It reconstructs two observed trace poses inside
## the authored training scene; it never loads the Windows editor trace project.
extends SceneTree

const Predictor := preload("res://src/ai/tank_driving_predictor.gd")
const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const DT := 1.0 / 60.0

const CASES := [
	{
		"label": "reverse_f4604", "frame": 4604, "seq": 9678,
		"requested": Vector2(-0.52399998, 0.0),
		"enemy_root": Transform3D(Basis(Vector3.UP, 3.02348136901855), Vector3(72.9678955078125, 0.0, -81.4386367797852)),
		"enemy_turret": -1.83570396900177, "enemy_pitch": -0.0412773303687572,
		"enemy_speed": 0.0333333333333331, "enemy_angular": 0.0,
		"player_root": Transform3D(Basis(Vector3.UP, 1.5098522901535), Vector3(53.402587890625, 0.0, -51.5303077697754)),
		"player_turret": 2.54795503616333, "player_pitch": -0.0237586926668882,
		"goal": Vector3(65.7923431396484, 0.0, -64.0484619140625),
	},
	{
		"label": "terminal_f4906", "frame": 4906, "seq": 10516,
		"requested": Vector2(0.0, -1.0),
		"enemy_root": Transform3D(Basis(Vector3.UP, 2.98051881790161), Vector3(73.166618347168, 0.0, -81.4106140136719)),
		"enemy_turret": -1.80296683311462, "enemy_pitch": -0.0411513410508633,
		"enemy_speed": 0.1, "enemy_angular": -0.016,
		"player_root": Transform3D(Basis(Vector3.UP, 1.5098522901535), Vector3(53.402587890625, 0.0, -51.5303077697754)),
		"player_turret": 2.54370093345642, "player_pitch": -0.0208977330476046,
		"goal": Vector3(65.7923431396484, 0.0, -64.0484619140625),
	},
]

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for data in CASES:
		await _probe_case(data)
	if _failures.is_empty():
		print("TRACE_POSE_PROBE PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("TRACE_POSE_PROBE FAIL: %s" % failure)
		quit(1)

func _probe_case(data: Dictionary) -> void:
	var scene := PLAYTEST.instantiate()
	root.add_child(scene)
	await physics_frame
	var enemy := scene.get_node_or_null("Encounter/Enemy") as CharacterBody3D
	var player := scene.get_node_or_null("Main/Tank") as CharacterBody3D
	if enemy == null or player == null:
		_fail("%s: expected Encounter/Enemy and Main/Tank." % data.label)
		scene.queue_free()
		await physics_frame
		return
	_freeze_tree(scene)
	_apply_pose(enemy, data.enemy_root, float(data.enemy_turret), float(data.enemy_pitch), float(data.enemy_speed), float(data.enemy_angular))
	_apply_pose(player, data.player_root, float(data.player_turret), float(data.player_pitch), 0.0, 0.0)
	# keep collision objects registered while all behaviour updates are stopped.
	await physics_frame
	await physics_frame
	enemy.call("set_driving_trace_enabled", true)
	var predictor := Predictor.new()
	predictor.setup(enemy)
	var requested: Vector2 = data.requested
	var baseline: Dictionary = predictor.choose(requested.x, requested.y, data.goal, DT, false, false)
	var baseline_stats: Dictionary = predictor.get_stats()
	var baseline_trace: Dictionary = baseline_stats.get("trace", {}) as Dictionary
	var trace_candidates: Array = baseline_trace.get("candidates", []) as Array
	var blocker: Dictionary = trace_candidates[0].get("first_blocker", {}) as Dictionary if not trace_candidates.is_empty() else {}
	print("TRACE_POSE_BASELINE label=%s frame=%d seq=%d requested=(%.6f,%.6f) result=%s blocker=%s stats=%s" % [data.label, data.frame, data.seq, requested.x, requested.y, baseline, blocker, baseline_stats])
	if StringName(baseline.get("reason", &"")) != &"blocked" or blocker.get("part_id", "") != "gun" or int(blocker.get("shape_index", -1)) != 14:
		_fail("%s: original trace request did not reproduce as blocked; result=%s" % [data.label, baseline])
		scene.queue_free()
		await physics_frame
		return
	# Nominal-only calls deliberately avoid the production adjustment/scoring path.
	for movement in [-0.10, 0.0, 0.10]:
		for turn in [-0.4, -0.2, 0.0, 0.2, 0.4]:
			if is_zero_approx(movement) and is_zero_approx(turn):
				continue
			var choice: Dictionary = predictor.choose(movement, turn, data.goal, DT, false, false)
			var safe := StringName(choice.get("reason", &"")) == &"clear"
			print("TRACE_POSE_CANDIDATE label=%s movement=%.2f turn=%.2f safe=%s result=%s stats=%s" % [data.label, movement, turn, safe, choice, predictor.get_stats()])
	scene.queue_free()
	await physics_frame

func _freeze_tree(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze_tree(child)

func _apply_pose(tank: CharacterBody3D, root_transform: Transform3D, turret_yaw: float, gun_pitch: float, forward_speed: float, angular_speed: float) -> void:
	tank.global_transform = root_transform
	tank.velocity = Vector3.ZERO
	tank.forward_speed = forward_speed
	tank.angular_speed = angular_speed
	tank.actual_angular_speed = angular_speed
	tank.movement_command = 0.0
	tank.turn_command = 0.0
	var turret := tank.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	var gun := tank.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	if turret == null or gun == null:
		_fail("%s: missing turret or gun pivot." % tank.name)
		return
	turret.rotation.y = turret_yaw
	gun.rotation.z = -gun_pitch
	tank.call("_sync_part_collision_shapes")

func _fail(message: String) -> void:
	_failures.append(message)
