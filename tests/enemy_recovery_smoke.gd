## 有限次卡住脫困的 deterministic unit smoke；不需要導航地圖或載具物理。
extends SceneTree

const Recovery := preload("res://src/ai/tank_recovery.gd")
const PLAYTEST := preload("res://src/world/training_ground/training_ground_playtest.tscn")
const TANK1 := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const DT := 1.0 / 60.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_progress_and_trigger()
	_validate_two_bounded_reverse_attempts()
	_validate_reset_lifecycle()
	await _validate_near_terminal_stall_counts()
	await _validate_combat_ai_intent_and_lifecycle()
	await _validate_rear_wall_collision()
	if _failures.is_empty():
		print("ENEMY_RECOVERY PASS: progress gate, two bounded reverse attempts, blocked terminal, reset.")
		quit(0)
		return
	for failure in _failures:
		push_error("ENEMY_RECOVERY FAIL: %s" % failure)
	quit(1)


func _validate_progress_and_trigger() -> void:
	var recovery := Recovery.new()
	var origin := Vector3.ZERO
	var forward := Vector3.LEFT
	recovery.reset(origin, forward)
	## Three seconds of demanded rotation with >=3 degrees of heading progress is not a stall.
	recovery.observe(origin, Vector3.LEFT.rotated(Vector3.UP, deg_to_rad(4.0)), 0.0, 1.0, 3.1)
	if recovery.phase != &"normal" or recovery.attempts != 0:
		_fail("Heading progress of >=3 degrees must reset stall observation; phase=%s attempts=%d." % [recovery.phase, recovery.attempts])
	## Either requested forward drive with <0.5m travel or requested turn with <3 degrees must trigger.
	recovery.reset(origin, forward)
	recovery.observe(origin + Vector3(0.49, 0.0, 0.0), forward, 1.0, 0.0, 3.01)
	if recovery.phase != &"braking" or recovery.attempts != 1:
		_fail("Forward demand with <0.5m progress for 3s must enter first braking attempt.")
	recovery.reset(origin, forward)
	recovery.observe(origin, Vector3.LEFT.rotated(Vector3.UP, deg_to_rad(2.9)), 0.0, 1.0, 3.01)
	if recovery.phase != &"braking" or recovery.attempts != 1:
		_fail("Turn demand with <3 degrees progress for 3s must enter first braking attempt.")


func _validate_two_bounded_reverse_attempts() -> void:
	var recovery := Recovery.new()
	var position := Vector3.ZERO
	var forward := Vector3.LEFT
	recovery.reset(position, forward)
	for expected_attempt in [1, 2]:
		recovery.observe(position, forward, 1.0, 0.0, 3.01)
		if recovery.phase != &"braking" or recovery.attempts != expected_attempt:
			_fail("Attempt %d must first enter braking exactly once; phase=%s attempts=%d." % [expected_attempt, recovery.phase, recovery.attempts])
			return
		var braking := recovery.drive(position, forward, 0.2, 2.0, 1.0, 0.1)
		if float(braking.movement) != 0.0 or float(braking.turn) != 0.0 or braking.status != &"recovering":
			_fail("Recovery must brake to <=0.1 before reversing; got %s." % braking)
		var reverse_start := recovery.drive(position, forward, 0.1, 2.0, 1.0, 0.1)
		if float(reverse_start.movement) != 0.0 or recovery.phase != &"reversing":
			_fail("Recovery must only arm reversing after the speed threshold; got %s phase=%s." % [reverse_start, recovery.phase])
		var reversing := recovery.drive(position, forward, 0.0, 2.0, 1.0, 0.1)
		if float(reversing.movement) >= 0.0 or float(reversing.turn) != 0.0 or reversing.status != &"recovering":
			_fail("Negative movement is allowed only while recovering/reversing; got %s." % reversing)
		position += Vector3.RIGHT * Recovery.REVERSE_METRES
		var bounded := recovery.drive(position, forward, 0.0, 2.0, 1.0, 0.1)
		if float(bounded.movement) != 0.0 or recovery.phase != &"settling":
			_fail("Reverse must stop at 2m (before any extra reverse); got %s phase=%s." % [bounded, recovery.phase])
		var settled := recovery.drive(position, forward, 0.1, 2.0, 1.0, 0.1)
		if settled.get("replan", false) != true or recovery.phase != &"normal":
			_fail("Stopped recovery must issue exactly one replan then return to normal; got %s phase=%s." % [settled, recovery.phase])
	## A third no-progress interval is terminal; there is no unbounded retry.
	recovery.observe(position, forward, 1.0, 0.0, 3.01)
	if recovery.phase != &"blocked" or recovery.attempts != Recovery.MAX_ATTEMPTS:
		_fail("After two attempts the same blocked goal must become terminal stuck, not retry; phase=%s attempts=%d." % [recovery.phase, recovery.attempts])
	var stuck := recovery.drive(position, forward, 0.0, 2.0, 1.0, 0.1)
	if stuck.status != &"stuck" or float(stuck.movement) != 0.0 or float(stuck.turn) != 0.0:
		_fail("Terminal stuck must hold movement/turn at zero; got %s." % stuck)


func _validate_reset_lifecycle() -> void:
	var recovery := Recovery.new()
	recovery.reset(Vector3.ZERO, Vector3.LEFT)
	recovery.observe(Vector3.ZERO, Vector3.LEFT, 1.0, 0.0, 3.01)
	recovery.reset(Vector3(3.0, 0.0, 0.0), Vector3.LEFT)
	if recovery.phase != &"normal" or recovery.attempts != 0:
		_fail("New goal / clear lifecycle reset must cancel reverse state and restore retry budget.")


## A near-stop positive drive demand is still a stall candidate.  Keep the tank frozen on
## purpose: this isolates the old braking predicate regression from wall/physics behavior.
func _validate_near_terminal_stall_counts() -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	(scene.get_node("Main/World/Ground") as StaticBody3D).process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(scene)
	if not await _await_navigation(scene):
		scene.queue_free()
		return
	var tank := TANK1.instantiate() as CharacterBody3D
	tank.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(tank)
	tank.global_position = Vector3(-120.0, 0.0, 80.0)
	tank.rotation.y = 0.0
	tank.set("forward_speed", 0.0)
	await physics_frame
	var driver := TankNavigation.new()
	driver.setup(tank)
	var agent := tank.get_node_or_null("TankNavigationAgent") as NavigationAgent3D
	if agent != null:
		agent.process_mode = Node.PROCESS_MODE_ALWAYS
	var forward := tank.global_basis * Vector3.LEFT
	var goal: Vector3 = tank.stable_world_center() + forward.normalized() * 3.1
	var saw_positive_moving := false
	var saw_recovering := false
	var invalid_terminal := false
	for unused in 210: ## 3.5 seconds at 60Hz, with no command applied to the frozen tank.
		var command: Dictionary = driver.drive(goal, 7, 3.0, DT)
		saw_positive_moving = saw_positive_moving or (command.status == &"moving" and float(command.movement) > 0.05)
		saw_recovering = saw_recovering or command.status == &"recovering"
		invalid_terminal = invalid_terminal or command.status in [&"arrived", &"no_path"]
		await physics_frame
	if not saw_positive_moving or not saw_recovering or invalid_terminal:
		_fail("Near-terminal frozen forward demand must move then recover, never arrive/no_path; positive=%s recovering=%s terminal=%s." % [saw_positive_moving, saw_recovering, invalid_terminal])
	driver.dispose()
	tank.queue_free()
	scene.queue_free()
	await physics_frame


func _validate_combat_ai_intent_and_lifecycle() -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	root.add_child(scene)
	await physics_frame
	var ai := scene.get_node_or_null("Encounter/CombatAI") as Node
	var tank := scene.get_node_or_null("Encounter/Enemy") as CharacterBody3D
	var player := scene.get_node_or_null("Main/Tank") as CharacterBody3D
	if ai == null or tank == null or player == null:
		_fail("CombatAI recovery integration fixture requires Encounter/CombatAI, Enemy, and Main/Tank.")
	else:
		ai.set_physics_process(false)
		## Recovering commands own both body axes; stationary target-facing must not replace a side-turn.
		ai.call("_submit_navigation_intent", {"movement": -0.5, "turn": 0.4, "status": &"recovering"}, player.stable_world_center())
		if float(tank.get("movement_command")) >= 0.0 or not is_equal_approx(float(tank.get("turn_command")), 0.4):
			_fail("CombatAI must pass recovering negative movement and non-zero turn without target-facing overwrite.")
		## A stuck intent has precedence over stationary-facing correction even when target is off-heading.
		ai.call("_submit_navigation_intent", {"movement": 0.0, "turn": 0.0, "status": &"stuck"}, tank.stable_world_center() + Vector3.FORWARD * 30.0)
		if not is_zero_approx(float(tank.get("movement_command"))) or not is_zero_approx(float(tank.get("turn_command"))):
			_fail("CombatAI stuck intent must hold body movement/turn at zero, without stationary-facing overwrite.")
		ai.call("_ensure_navigation")
		var navigation := ai.get("_navigation") as RefCounted
		var recovery := navigation.get("_recovery") as RefCounted if navigation != null else null
		if recovery == null:
			_fail("CombatAI must own a TankNavigation recovery instance.")
		else:
			recovery.set("phase", &"reversing")
			recovery.set("_escape_forward", Vector3.FORWARD)
			ai.call("_submit_navigation_intent", {"movement": -0.5, "turn": 0.0, "status": &"recovering"}, player.stable_world_center())
			if float(tank.get("movement_command")) >= 0.0:
				_fail("set_combat_enabled lifecycle setup must begin from an actual recovering negative command.")
			ai.call("set_combat_enabled", false)
			if recovery.get("phase") != &"normal" or not (recovery.get("_escape_forward") as Vector3).is_zero_approx() or not is_zero_approx(float(tank.get("movement_command"))):
				_fail("set_combat_enabled(false) must cancel an in-flight reverse, side direction, and stop the tank.")
			ai.call("set_combat_enabled", true)
			recovery.set("phase", &"reversing")
			recovery.set("_escape_forward", Vector3.FORWARD)
			ai.call("_submit_navigation_intent", {"movement": -0.5, "turn": 0.0, "status": &"recovering"}, player.stable_world_center())
			if float(tank.get("movement_command")) >= 0.0:
				_fail("set_target lifecycle setup must begin from an actual recovering negative command.")
			ai.call("set_target", null)
			if recovery.get("phase") != &"normal" or not (recovery.get("_escape_forward") as Vector3).is_zero_approx() or not is_zero_approx(float(tank.get("movement_command"))):
				_fail("set_target replacement must cancel an in-flight reverse, side direction, and stop the tank.")
	scene.queue_free()
	await physics_frame


func _validate_rear_wall_collision() -> void:
	var scene := PLAYTEST.instantiate() as Node3D
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	(scene.get_node("Main/World/Ground") as StaticBody3D).process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(scene)
	if not await _await_navigation(scene):
		scene.queue_free()
		return
	var tank := TANK1.instantiate() as CharacterBody3D
	tank.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(tank)
	tank.global_position = Vector3(-120.0, 0.0, 80.0)
	tank.rotation.y = 0.0
	await physics_frame
	var rear_edge := _max_part_x(tank)
	var wall := _wall_at(Vector3(rear_edge + 0.75, 3.0, tank.global_position.z), Vector3(1.0, 8.0, 12.0))
	wall.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(wall)
	await physics_frame
	if _part_hits_wall(tank, wall):
		_fail("Rear-wall fixture must begin clear of the real tank collision geometry.")
		wall.queue_free()
		tank.queue_free()
		scene.queue_free()
		return
	var driver := TankNavigation.new()
	driver.setup(tank)
	var goal: Vector3 = tank.stable_world_center() + Vector3.LEFT * 30.0
	## First drive establishes the generation; setting recovery before it would be reset by that lifecycle edge.
	driver.drive(goal, 1, 3.0, DT)
	var recovery := driver.get("_recovery") as RefCounted
	recovery.set("phase", &"reversing")
	recovery.call("reset_progress", tank.stable_world_center(), tank.global_basis * Vector3.LEFT)
	var wall_min_x := wall.global_position.x - 0.5
	var reverse_start: Vector3 = tank.stable_world_center()
	var reversed := false
	var moved_backward := false
	var reached_wall_side := false
	var saw_settling := false
	var crossed_wall := false
	for unused in 140: ## >2 seconds: reverse timer must settle even when a real wall is behind it.
		var command: Dictionary = driver.drive(goal, 1, 3.0, DT)
		reversed = reversed or float(command.get("movement", 0.0)) < -0.05
		saw_settling = saw_settling or recovery.get("phase") == &"settling"
		tank.set_movement_input(float(command.get("movement", 0.0)))
		tank.set_turn_input(float(command.get("turn", 0.0)))
		await physics_frame
		moved_backward = moved_backward or tank.stable_world_center().x > reverse_start.x + 0.1
		reached_wall_side = reached_wall_side or _max_part_x(tank) >= wall_min_x - 0.05
		crossed_wall = crossed_wall or _max_part_x(tank) > wall_min_x + 0.03
	if not reversed:
		_fail("Rear-wall fixture must receive a real negative recovering command.")
	if not moved_backward:
		_fail("Rear-wall fixture must produce actual backward tank displacement, not only a negative command.")
	if not reached_wall_side:
		_fail("Rear-wall fixture must drive into the wall side; a no-wall reverse would be a false green.")
	if not saw_settling:
		_fail("Recovery reverse must reach settling after its 2-second cap even while pressed against the wall.")
	if crossed_wall or _part_hits_wall(tank, wall):
		_fail("A real rear wall must prevent recovery reverse from penetrating its collision shape.")
	## Driver terminal gate: same generation/goal remains stopped; an exactly-3m target move resets budget.
	recovery.set("phase", &"blocked")
	recovery.set("attempts", Recovery.MAX_ATTEMPTS)
	var terminal := driver.drive(goal, 1, 3.0, DT)
	var same_goal := driver.drive(goal, 1, 3.0, DT)
	var moved_goal := goal + Vector3(3.0, 0.0, 0.0)
	var retried := driver.drive(moved_goal, 1, 3.0, DT)
	if terminal.status != &"stuck" or same_goal.status != &"stuck" or float(same_goal.movement) != 0.0:
		_fail("Same terminal target must stay stuck with zero movement until a generation/goal change.")
	if retried.status in [&"stuck", &"waiting_map"] or int(recovery.get("attempts")) != 0:
		_fail("A 3m target change must clear terminal recovery and reset retry budget; got %s attempts=%s." % [retried, recovery.get("attempts")])
	driver.dispose()
	wall.queue_free()
	tank.queue_free()
	scene.queue_free()
	await physics_frame


func _await_navigation(scene: Node3D) -> bool:
	var region := scene.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var map := scene.get_world_3d().navigation_map
	for unused in 180:
		if region != null and NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 \
				and NavigationServer3D.map_get_closest_point_owner(map, Vector3(43.0, 0.0, -20.0)).is_valid():
			return true
		await physics_frame
	_fail("Recovery rear-wall fixture navigation map did not become ready.")
	return false


func _wall_at(position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	return wall


func _max_part_x(tank: CharacterBody3D) -> float:
	var maximum := -INF
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			for point in shape.points:
				maximum = maxf(maximum, (transforms[index] * point).x)
			index += 1
	return maximum


func _part_hits_wall(tank: CharacterBody3D, wall: StaticBody3D) -> bool:
	var transforms: Array[Transform3D] = tank.part_shape_world_transforms()
	var index := 0
	for part in tank.part_geometry.parts:
		for shape in part.convex_shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = transforms[index]
			query.collision_mask = 1
			query.exclude = [tank.get_rid()]
			for hit in tank.get_world_3d().direct_space_state.intersect_shape(query, 16):
				if hit.get("collider") == wall:
					return true
			index += 1
	return false


func _fail(message: String) -> void:
	_failures.append(message)
