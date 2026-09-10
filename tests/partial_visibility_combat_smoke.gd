extends SceneTree

const PLAYTEST_SCENE := "res://src/world/training_ground/training_ground_playtest.tscn"
const HealthComponent := preload("res://src/combat/damage/health_component.gd")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")

class CountingVision extends TankVision:
	var visible_calls := 0
	var last_points := PackedVector3Array()
	func visible_target_points(target: Node3D) -> PackedVector3Array:
		visible_calls += 1
		last_points = super.visible_target_points(target)
		return last_points

func _init() -> void:
	var packed := load(PLAYTEST_SCENE) as PackedScene
	var scene := packed.instantiate() as Node3D if packed != null else null
	if scene == null:
		_fail("A1/A2 requires training-ground playtest")
		return
	root.add_child(scene)
	call_deferred("_run", scene)

func _run(scene: Node3D) -> void:
	var main := scene.get_node_or_null("Main") as Node3D
	var encounter := scene.get_node_or_null("Encounter") as Node3D
	var enemy := encounter.get_node_or_null("Enemy") as Node3D if encounter != null else null
	var original_vision := encounter.get_node_or_null("Vision") as Node if encounter != null else null
	var ai := encounter.get_node_or_null("CombatAI") as Node if encounter != null else null
	var player := main.get_node_or_null("Tank") as Node3D if main != null else null
	var player_runtime := main.get_node_or_null("PlayerRuntime") as Node if main != null else null
	var combat := main.get_node_or_null("CombatRuntime") as CombatRuntime if main != null else null
	if enemy == null or original_vision == null or ai == null or player == null or combat == null:
		_fail("A1/A2 requires live Enemy, Vision, CombatAI, player, and CombatRuntime")
		return
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or combat.projectiles == null:
		_fail("A2 requires real HealthComponent and projectile container")
		return

	## Manual scheduling prevents an automatic second AI tick; combat itself remains enabled.
	ai.set_physics_process(false)
	ai.call("set_combat_enabled", false)
	enemy.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 30, 0))
	player.global_position = enemy.global_position + Vector3.FORWARD * 12.0
	player.set_physics_process(false)
	var player_aim := player_runtime.get_node_or_null("PlayerAimController") as Node if player_runtime != null else null
	if player_aim != null:
		player_aim.set_process(false)
	enemy.set("aim_spread_base_degrees", 0.0)
	enemy.set("aim_spread_cap_degrees", 0.0)
	enemy.set("current_spread_degrees", 0.0)
	await physics_frame
	await physics_frame
	var vision := CountingVision.new()
	vision.observer = enemy
	vision.collision_mask = int(original_vision.get("collision_mask"))
	scene.add_child(vision)
	ai.set("vision", vision)
	ai.call("set_combat_enabled", true)
	var center := vision.target_world_position(player)
	var samples: PackedVector3Array = player.call("part_world_surface_points") as PackedVector3Array
	if samples.is_empty():
		_fail("A1/A2 requires real target surface samples")
		return

	## A1.1: open center is the first visible and fireable candidate.
	if not _one_tick(ai, vision):
		_fail("A1 open: enabled AI must consume exactly one true Vision result")
		return
	var points := vision.last_points
	var selection: Dictionary = ai.call("_select_aim_target", points) as Dictionary
	if points.is_empty() or not points[0].is_equal_approx(center) \
			or not (selection.get("position", Vector3.ZERO) as Vector3).is_equal_approx(center) \
			or not bool(selection.get("can_fire", false)):
		_fail("A1 open: stable center must be visible, first, and fireable")
		return

	## A1.2: center view ray is blocked while a real sample stays visible and fireable.
	var view_origin := (enemy.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_position
	var center_screen := _blocker(view_origin.lerp(center, 0.55), 0.12)
	scene.add_child(center_screen)
	await physics_frame
	if _first_hit(enemy, view_origin, center) != center_screen or not _one_tick(ai, vision):
		_fail("A1 center-screen: real blocker and single enabled Vision query are required")
		return
	points = vision.last_points
	selection = ai.call("_select_aim_target", points) as Dictionary
	var selected := selection.get("position", Vector3.ZERO) as Vector3
	if points.is_empty() or _has(points, center) or not _has(samples, selected) \
			or not bool(selection.get("can_fire", false)):
		_fail("A1 center-screen: an existing sample must remain visible and fireable")
		return
	center_screen.queue_free()
	await physics_frame

	## A1.3: center is visible again, but only its muzzle path is blocked.
	points = vision.visible_target_points(player)
	if not _has(points, center) or _first_hit(enemy, view_origin, center) != player:
		_fail("A1 muzzle-block: center must really be visible after screen teardown")
		return
	enemy.call("aim_turret_at", center, 10.0)
	enemy.call("aim_gun_pitch_at_target", center, 10.0)
	await physics_frame
	var muzzle := enemy.call("muzzle_global_position") as Vector3
	var blocker_position := muzzle.lerp(center, 0.35)
	var view_clearance := _distance_to_segment(blocker_position, view_origin, center)
	if view_clearance <= 0.0001:
		_fail("A1 muzzle-block: view and muzzle rays require measurable geometric separation")
		return
	## Keep the box's bounding sphere below half the measured view-ray clearance.
	var center_muzzle_block := _blocker(blocker_position, view_clearance * 0.5)
	scene.add_child(center_muzzle_block)
	await physics_frame
	var pre_tick_hit := _first_hit(enemy, muzzle, center)
	var pre_tick_points := vision.visible_target_points(player)
	var pre_tick_selection: Dictionary = ai.call("_select_aim_target", pre_tick_points) as Dictionary
	var pre_tick_selected := pre_tick_selection.get("position", Vector3.ZERO) as Vector3
	if pre_tick_hit != center_muzzle_block or not _has(pre_tick_points, center) \
			or pre_tick_selected.is_equal_approx(center) or not _has(samples, pre_tick_selected) \
			or not bool(pre_tick_selection.get("can_fire", false)):
		_fail("A1 muzzle-block: center-only muzzle blocker must leave center visible and an existing sample fireable")
		return
	if not _one_tick(ai, vision):
		_fail("A1 muzzle-block: enabled AI must consume exactly one true Vision result")
		return
	points = vision.last_points
	if not _same_points(points, pre_tick_points):
		_fail("A1 muzzle-block: AI tick must consume the pre-validated visible candidates")
		return
	print("PASS A1 muzzle-block center visible, center muzzle-blocked, selected sample=", pre_tick_selected)
	center_muzzle_block.queue_free()
	await physics_frame

	## A2: recreate and retain the center screen through the final impact.
	center_screen = _blocker(view_origin.lerp(center, 0.55), 0.12)
	scene.add_child(center_screen)
	await physics_frame
	points = vision.visible_target_points(player)
	selection = ai.call("_select_aim_target", points) as Dictionary
	var alternate := selection.get("position", Vector3.ZERO) as Vector3
	if _first_hit(enemy, view_origin, center) != center_screen or points.is_empty() or _has(points, center) \
			or not _has(samples, alternate) or not bool(selection.get("can_fire", false)):
		_fail("A2 setup: screened center and a fireable real alternate sample are required")
		return
	enemy.call("aim_turret_at", alternate, 10.0)
	enemy.call("aim_gun_pitch_at_target", alternate, 10.0)
	await physics_frame
	if not bool(ai.call("_is_muzzle_aligned_and_clear", alternate)):
		_fail("A2 setup: actual muzzle direction/alignment gate must accept alternate")
		return

	## With every path blocked the specified fallback is points[0]; settle on it before placing blockers.
	enemy.call("aim_turret_at", points[0], 10.0)
	enemy.call("aim_gun_pitch_at_target", points[0], 10.0)
	await physics_frame
	muzzle = enemy.call("muzzle_global_position") as Vector3
	var blockers: Array[StaticBody3D] = []
	for point in points:
		var body := _blocker(muzzle.lerp(point, 0.18), 0.055)
		scene.add_child(body)
		blockers.append(body)
	await physics_frame
	var blocked_points := vision.visible_target_points(player)
	if blocked_points.is_empty() or _has(blocked_points, center):
		_fail("A2 blocked setup must retain non-center visible candidates")
		return
	for point in blocked_points:
		if not blockers.has(_first_hit(enemy, muzzle, point)):
			_fail("A2 blocked setup must physically block every visible muzzle path")
			return

	var shots: Array[ShotEvent] = []
	var shot_gate_results: Array[bool] = []
	enemy.shot_event_fired.connect(func(event: ShotEvent) -> void:
		shots.append(event)
		shot_gate_results.append(bool(ai.call("_is_muzzle_aligned_and_clear", alternate)))
	)
	var blocked_query_start := vision.visible_calls
	for _frame in 90:
		var pre_tick_muzzle := enemy.call("muzzle_global_position") as Vector3
		if not _one_tick(ai, vision):
			_fail("A2 blocked: every AI tick must consume one true Vision result")
			return
		points = vision.last_points
		if points.is_empty() or _has(points, center) or not _has(samples, points[0]):
			_fail("A2 blocked: visible non-center aim must remain can_fire=false")
			return
		for point in points:
			if not blockers.has(_first_hit(enemy, pre_tick_muzzle, point)):
				_fail("A2 blocked: every candidate must be blocked at the AI decision-time muzzle")
				return
		await physics_frame
	if not shots.is_empty():
		_fail("A2 blocked: 90 enabled true AI ticks must emit no ShotEvent")
		return
	print("PASS A2 blocked ticks=90 queries=", vision.visible_calls - blocked_query_start, " shots=", shots.size())

	## Remove only muzzle blockers. The same alternate must fire; center never returns.
	for body in blockers:
		body.queue_free()
	await physics_frame
	points = vision.visible_target_points(player)
	selection = ai.call("_select_aim_target", points) as Dictionary
	selected = selection.get("position", Vector3.ZERO) as Vector3
	if _first_hit(enemy, view_origin, center) != center_screen or _has(points, center) \
			or not selected.is_equal_approx(alternate) or not bool(selection.get("can_fire", false)):
		_fail("A2 unblocked: same alternate must remain selectable with center screened")
		return

	var impacts: Array[ImpactEvent] = []
	combat.impact_resolved.connect(func(event: ImpactEvent) -> void: impacts.append(event))
	var health_before := health.current_health
	var saw_projectile := false
	for _frame in 360:
		if not _one_tick(ai, vision):
			_fail("A2 fire: every AI tick must consume one true Vision result")
			return
		if not shots.is_empty() and combat.projectiles.get_child_count() > 0:
			saw_projectile = true
		await physics_frame
		for impact in impacts:
			if impact.collider == player and saw_projectile and not shots.is_empty() \
					and not shot_gate_results.is_empty() and shot_gate_results[0] \
					and health.current_health < health_before:
				print("PASS A1/A2 true alternate pipeline shots=", shots.size(), " impact=", impact.position)
				quit(0)
				return
	_fail("A2 requires true AI -> ShotEvent -> Projectile -> target ImpactEvent -> Health loss")

func _one_tick(ai: Node, vision: CountingVision) -> bool:
	var before := vision.visible_calls
	ai.call("_physics_process", 1.0 / 60.0)
	return vision.visible_calls == before + 1

func _first_hit(observer: Node3D, from: Vector3, to: Vector3) -> Object:
	var query := PhysicsRayQueryParameters3D.create(from, to, 129, [observer.get_rid()])
	return observer.get_world_3d().direct_space_state.intersect_ray(query).get("collider") as Object

func _has(points: PackedVector3Array, expected: Vector3) -> bool:
	for point in points:
		if point.is_equal_approx(expected):
			return true
	return false

func _same_points(left: PackedVector3Array, right: PackedVector3Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]):
			return false
	return true

func _distance_to_segment(point: Vector3, from: Vector3, to: Vector3) -> float:
	var segment := to - from
	if segment.is_zero_approx():
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)

func _blocker(position: Vector3, extent: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * extent
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	return body

func _fail(message: String) -> void:
	push_error(message)
	print("FAIL: ", message)
	quit(1)
