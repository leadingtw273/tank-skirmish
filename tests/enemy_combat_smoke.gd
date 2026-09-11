extends SceneTree

const PLAYTEST_SCENE := "res://src/world/training_ground/training_ground_playtest.tscn"
const TANK1_SCENE := "res://src/actors/tank/variants/tank1/tank1.tscn"
const TANK2_SCENE := "res://src/actors/tank/variants/tank2/tank2.tscn"
const TANK3_SCENE := "res://src/actors/tank/variants/tank3/tank3.tscn"
const TANK4_SCENE := "res://src/actors/tank/variants/tank4/tank4.tscn"
const HealthComponent := preload("res://src/combat/damage/health_component.gd")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")


func _init() -> void:
	var packed := load(PLAYTEST_SCENE) as PackedScene
	var playtest := packed.instantiate() as Node3D if packed != null else null
	if playtest == null:
		_fail("Enemy combat smoke must load the training-ground playtest.")
		return
	root.add_child(playtest)
	call_deferred("_validate", playtest)


func _validate(playtest: Node3D) -> void:
	var main := playtest.get_node_or_null("Main") as Node3D
	var encounter := playtest.get_node_or_null("Encounter") as Node3D
	var enemy := encounter.get_node_or_null("Enemy") as Node3D if encounter != null else null
	var vision := encounter.get_node_or_null("Vision") as Node if encounter != null else null
	var ai := encounter.get_node_or_null("CombatAI") as Node if encounter != null else null
	var player_runtime := main.get_node_or_null("PlayerRuntime") as Node if main != null else null
	var combat := main.get_node_or_null("CombatRuntime") as CombatRuntime if main != null else null
	var player := main.get_node_or_null("Tank") as Node3D if main != null else null
	if main == null or encounter == null or enemy == null or vision == null or ai == null \
			or player_runtime == null or combat == null or player == null:
		_finish(playtest, "Enemy combat smoke requires Main, Encounter, Enemy, Vision, CombatAI, and player runtime.")
		return
	if not combat.has_method(&"get_registered_shot_sources"):
		_finish(playtest, "CombatRuntime must expose get_registered_shot_sources() for enemy/player runtime registration inspection.")
		return
	## 先鎖住 LEA-172 的中央重生公開入口，避免後續行為案例把缺 API 淹沒。
	if not main.has_method(&"respawn_player_tank"):
		_finish(playtest, "LEA-172 requires Main.respawn_player_tank(PackedScene, Transform3D) before player-respawn behavior can be verified.")
		return
	var initial_camera_rig := player_runtime.get("camera_controller") as Node3D
	var initial_camera := initial_camera_rig.get("camera") as Camera3D if initial_camera_rig != null else null
	if initial_camera_rig == null or initial_camera == null:
		_finish(playtest, "Enemy combat smoke requires PlayerRuntime to expose its initial CameraRig.")
		return
	## 這份快照必須在既有幾何 fixture 瞬移玩家前取得，避免拿到測試暫時姿態當成開場構圖。
	var initial_camera_snapshot := {
		"rig_basis": initial_camera_rig.global_basis,
		"camera_transform": initial_camera.transform,
		"camera_size": initial_camera.size,
		"follow_offset": initial_camera_rig.global_position - player.global_position,
	}
	## R4 驗的是 reset 當下；暫停後續正常游標前視，避免它覆寫此一瞬間的觀察值。
	initial_camera_rig.set_process(false)
	## 換車必須回到 Encounter ready 時記錄的世界姿態，不是幾何案例後的暫時位置。
	var initial_enemy_transform := enemy.global_transform
	if not await _validate_near_hit_encounter_wiring(playtest, main, encounter, player_runtime, combat):
		return
	enemy = encounter.get_node_or_null("Enemy") as Node3D
	vision = encounter.get_node_or_null("Vision") as Node
	ai = encounter.get_node_or_null("CombatAI") as Node
	if enemy == null or vision == null or ai == null:
		_finish(playtest, "Near-hit regression must restore the live Tank2 encounter fixture.")
		return
	if not _configure_vision_geometry_fixture(playtest, enemy, vision):
		return
	ai.call("set_combat_enabled", false)
	## 幾何用例使用固定測試姿態，不要求使用者的實際場景保持原始擺放。
	enemy.global_transform = Transform3D(Basis.IDENTITY, Vector3(60, 0, 8))
	player.global_position = Vector3(0, 0, 8)
	## 玩家瞄準器會依滑鼠重寫砲塔；本測試只觀察敵方戰鬥，不讓它干擾定位。
	## 幾何測試會瞬移車體，停用它的運動積分，避免 get_real_velocity 將瞬移解讀成行駛速度。
	## 碰撞體仍在物理世界；生命、受傷、PlayerRuntime 與 AI 仍正常執行。
	player.set_physics_process(false)
	var player_aim := player_runtime.get_node_or_null("PlayerAimController") as Node
	if player_aim != null:
		player_aim.set_process(false)
	if not await _validate_playtest_sight_blockers(playtest, enemy, player, vision):
		return
	if not await _validate_vision_geometry(playtest, enemy, player, vision):
		return
	if not await _validate_ai_hull_aim(playtest):
		return
	if not await _validate_hit_inspection_contract(playtest, ai):
		return
	if not await _validate_hit_inspection_behavior(playtest):
		return
	if not await _validate_combat_and_recovery(playtest, main, encounter, enemy, player, vision, ai, player_runtime, combat, initial_enemy_transform, initial_camera_snapshot):
		return
	playtest.queue_free()
	print("Enemy combat smoke validation passed.")
	quit(0)


func _configure_vision_geometry_fixture(playtest: Node3D, enemy: Node3D, vision: Node) -> bool:
	## 維持既有幾何案例（25m 近圈、100m 遠距、90 度扇形），但設定歸屬改為觀察坦克。
	enemy.set("vision_near_radius", 25.0)
	enemy.set("vision_far_radius", 100.0)
	enemy.set("vision_field_of_view_degrees", 90.0)
	if not is_equal_approx(float(enemy.get("vision_near_radius")), 25.0) \
			or not is_equal_approx(float(enemy.get("vision_far_radius")), 100.0) \
			or not is_equal_approx(float(enemy.get("vision_field_of_view_degrees")), 90.0) \
			or not is_equal_approx(float(vision.get("near_radius")), 25.0) \
			or not is_equal_approx(float(vision.get("far_radius")), 100.0) \
			or not is_equal_approx(float(vision.get("far_field_of_view_degrees")), 90.0):
		_finish(playtest, "Vision geometry fixture must read 25/100/90 from the observer tank.")
		return false
	return true


func _validate_playtest_sight_blockers(playtest: Node3D, enemy: Node3D, player: Node3D, vision: Node) -> bool:
	var sight_blockers := playtest.get_node_or_null("SightBlockers") as Node3D
	if sight_blockers == null:
		_finish(playtest, "Enemy combat fixture requires SightBlockers.")
		return false
	var row_count := 0
	for row_node in sight_blockers.get_children():
		var row := row_node as Node3D
		if row == null or row is PhysicsBody3D or row.get_child_count() != 3:
			_finish(playtest, "Each row must be a plain Node3D with three buildings.")
			return false
		row_count += 1
		for blocker_name in ["CentralOneStory", "NorthGable", "SouthTwoStory"]:
			var blocker := row.get_node_or_null(blocker_name) as StaticBody3D
			var model := blocker.get_node_or_null("Model") as Node3D if blocker != null else null
			var collision := blocker.get_node_or_null("CollisionShape3D") as CollisionShape3D if blocker != null else null
			if blocker == null or blocker.collision_layer != 1 or blocker.collision_mask != 0 \
					or model == null or collision == null or not collision.shape is BoxShape3D \
					or blocker.get_child_count() != 2:
				_finish(playtest, "Each building requires only its model and layer-1 collision.")
				return false
			var half_height := (collision.shape as BoxShape3D).size.y * 0.5
			if not model.transform.is_equal_approx(Transform3D.IDENTITY) \
					or not collision.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0, half_height, 0))):
				_finish(playtest, "Building placement belongs to the body; model and collision must share its local frame.")
				return false
	if row_count == 0:
		_finish(playtest, "SightBlockers must contain at least one independent building row container.")
		return false
	## 建築的美術排列可調整；幾何回歸改用這組明確的短暫碰撞 fixture，避免綁死場景座標。
	sight_blockers.queue_free()
	await physics_frame
	var fixture_blockers: Array[StaticBody3D] = [
		_make_blocker(Vector3(35, 1.5, 0), Vector3(8, 4, 8)),
		_make_blocker(Vector3(35, 1.5, 8), Vector3(8, 4, 8)),
		_make_blocker(Vector3(35, 1.5, 16), Vector3(8, 4, 8)),
	]
	for fixture_blocker in fixture_blockers:
		playtest.add_child(fixture_blocker)
	var original_position := player.global_position
	await physics_frame
	await physics_frame
	if bool(vision.call("can_see", player)):
		_finish(playtest, "The explicit central sight fixture must hide the initial player position.")
		return false
	player.global_position = Vector3(0, 0, 28)
	await physics_frame
	await physics_frame
	if bool(vision.call("can_see", player)):
		_finish(playtest, "The explicit sight fixture must block the intermediate target position.")
		return false
	player.global_position = Vector3(0, 0, 53)
	await physics_frame
	await physics_frame
	if not bool(vision.call("can_see", player)):
		_finish(playtest, "Moving beyond the explicit sight fixture must restore visibility inside the vision sector.")
		return false
	player.global_position = original_position
	await physics_frame
	await physics_frame
	for fixture_blocker in fixture_blockers:
		fixture_blocker.queue_free()
	await physics_frame
	await physics_frame
	return true


func _validate_vision_geometry(playtest: Node3D, enemy: Node3D, player: Node3D, vision: Node) -> bool:
	## 以實際 Tank 碰撞與物理射線驗近圈、扇形與兩種 LOS 遮擋，不使用字串替身。
	var original_position := player.global_position
	player.global_position = enemy.global_position + Vector3(10, 0, 0)
	await physics_frame
	if not bool(vision.call("can_see", player)):
		_finish(playtest, "Near-radius targets behind the turret must remain visible.")
		return false
	player.global_position = enemy.global_position + Vector3(-50, 0, 0)
	await physics_frame
	if not bool(vision.call("can_see", player)):
		_finish(playtest, "A distant target inside the turret sector must be visible.")
		return false
	player.global_position = enemy.global_position + Vector3(0, 0, 50)
	await physics_frame
	if bool(vision.call("can_see", player)):
		_finish(playtest, "A distant target outside the turret sector must not be visible.")
		return false
	player.global_position = enemy.global_position + Vector3(10, 0, 0)
	await physics_frame
	var blocker := _make_blocker(Vector3.ZERO, Vector3.ONE)
	playtest.add_child(blocker)
	_configure_full_visibility_blocker(blocker, enemy, player)
	await physics_frame
	if bool(vision.call("can_see", player)):
		_finish(playtest, "A near-radius target behind a physical blocker must not be visible.")
		return false
	player.global_position = enemy.global_position + Vector3(-50, 0, 0)
	await physics_frame
	_configure_full_visibility_blocker(blocker, enemy, player)
	await physics_frame
	if bool(vision.call("can_see", player)):
		_finish(playtest, "A distant sector target behind a physical blocker must not be visible.")
		return false
	blocker.queue_free()
	player.global_position = original_position
	await physics_frame
	return true


func _validate_ai_hull_aim(playtest: Node3D) -> bool:
	## 此 fixture 只使用完整 Tank、原 Vision 與原 AI；置於空中避免地圖房屋座標變動影響物理 LOS。
	if not await _validate_fixed_turret_ai_hull_aim(playtest, TANK1_SCENE, "Tank1", [&"lost_sight", &"target_dead"]):
		return false
	if not await _validate_fixed_turret_ai_hull_aim(playtest, TANK4_SCENE, "Tank4", [&"ai_disabled", &"observer_dead"]):
		return false
	if not await _validate_rotating_turret_ai_hull_aim(playtest, TANK2_SCENE, "Tank2"):
		return false
	if not await _validate_rotating_turret_ai_hull_aim(playtest, TANK3_SCENE, "Tank3"):
		return false
	return true


func _validate_hit_inspection_contract(playtest: Node3D, ai: Node) -> bool:
	## LEA-172 的接線契約：受擊側查看只能經公開世界座標 API 請求。
	if not ai.has_method(&"inspect_hit_position"):
		_finish(playtest, "LEA-172 requires CombatAI.inspect_hit_position(world_hit: Vector3) before hit-inspection behavior can be verified.")
		return false
	return true


func _validate_near_hit_encounter_wiring(playtest: Node3D, main: Node3D, encounter: Node3D, player_runtime: Node, combat: CombatRuntime) -> bool:
	## 從場景原始 Tank2 經真實粉色靶命中切到 Tank1，不能以改寫近圈 export 偽造 80m 規格。
	var switch_target := playtest.get_node_or_null("TrainingControls/EnemyTypeSwitch") as StaticBody3D
	var player := player_runtime.get("controlled_tank") as CharacterBody3D
	if switch_target == null or player == null:
		_finish(playtest, "Near-hit regression requires the live player and enemy-switch target.")
		return false
	for expected_scene in [TANK3_SCENE, TANK4_SCENE, TANK1_SCENE]:
		if not await _fire_projectile_at(combat, player, switch_target) or not await _wait_for_enemy_scene(encounter, expected_scene):
			_finish(playtest, "Near-hit regression requires real CombatRuntime switch impacts through Tank1.")
			return false
	var enemy := encounter.get_node_or_null("Enemy") as CharacterBody3D
	var vision := encounter.get_node_or_null("Vision") as Node
	var ai := encounter.get_node_or_null("CombatAI") as Node
	var health := enemy.get_node_or_null("HealthComponent") as HealthComponent if enemy != null else null
	if enemy == null or vision == null or ai == null or health == null \
			or enemy.scene_file_path != TANK1_SCENE or not is_equal_approx(float(enemy.get("vision_near_radius")), 80.0):
		_finish(playtest, "Near-hit regression must use the authored Tank1 80m near radius.")
		return false
	## 50m 側向命中仍在 Tank1 近圈內；物理遮擋保證玩家未被看見，命中位置本身也不在初始 FOV。
	ai.call("set_combat_enabled", false)
	## 這個幾何 fixture 要在固定姿態取樣；保留碰撞、生命與受傷處理。
	## PlayerAimController 會每 frame 改玩家砲塔，砲塔／砲管 surface samples 會離開方才建立的小屏幕。
	var player_aim := player_runtime.get_node_or_null("PlayerAimController") as Node
	var player_was_physics_processing := player.is_physics_processing()
	var player_aim_was_processing := player_aim.is_processing() if player_aim != null else false
	player.set_physics_process(false)
	if player_aim != null:
		player_aim.set_process(false)
	enemy.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 30, 0))
	player.global_position = enemy.global_position + Vector3(0, 0, 50)
	await physics_frame
	await physics_frame
	## 先鎖定原右側合法彈道，再遮住敵方眼睛到玩家的部位射線；遮擋不能順便擋掉來襲砲彈。
	var hit_position := _find_side_hit_surface_point(player, enemy, vision.call("target_world_position", enemy) as Vector3)
	if not hit_position.is_finite():
		_finish(playtest, "Near-hit regression requires a finite right-side hit before installing the visibility screen.")
		return false
	var shot_origin := player.global_position + Vector3.UP * 1.5
	var blockers := _make_near_hit_visibility_screen(enemy, player, shot_origin, hit_position)
	if blockers.is_empty():
		_finish(playtest, "Near-hit screen requires separated observation and incoming-shot rays.")
		return false
	for blocker in blockers:
		playtest.add_child(blocker)
	await physics_frame
	await physics_frame
	if bool(vision.call("can_see", player)):
		_finish(playtest, "Near-hit regression setup must physically hide the side player.")
		return false
	var health_before := health.current_health
	var initial_hull_yaw := enemy.global_rotation.y
	ai.call("set_combat_enabled", true)
	var shot_query := PhysicsRayQueryParameters3D.create(shot_origin, hit_position, 129, [player.get_rid()])
	if enemy.get_world_3d().direct_space_state.intersect_ray(shot_query).get("collider") != enemy:
		_finish(playtest, "Near-hit screen must preserve the real incoming projectile ray to the enemy side.")
		return false
	if not await _fire_projectile_at_node(combat, player, enemy, hit_position) \
			or not await _wait_for_health_loss(health, health_before, 120) \
			or (ai.get("_inspection_direction") as Vector3).is_zero_approx() \
			or not await _wait_for_hull_rotation(enemy, initial_hull_yaw, 180):
		_finish(playtest, "A hidden side hit inside Tank1's authored 80m near radius must damage it and start hull inspection.")
		return false
	for blocker in blockers:
		blocker.queue_free()
	await physics_frame
	await physics_frame
	## 已可見時仍必須走正常交戰而非保留查看方向；既有 LOS priority fixture 繼續驗證實際開火。
	if not bool(vision.call("can_see", player)) or not (ai.get("_inspection_direction") as Vector3).is_zero_approx():
		_finish(playtest, "A newly visible target must clear Tank1's near-hit inspection before ordinary combat.")
		return false
	ai.call("set_combat_enabled", false)
	if not await _fire_projectile_at(combat, player, switch_target) or not await _wait_for_enemy_scene(encounter, TANK2_SCENE):
		_finish(playtest, "Near-hit regression must restore Tank2 for the remaining smoke cases.")
		return false
	player.set_physics_process(player_was_physics_processing)
	if player_aim != null:
		player_aim.set_process(player_aim_was_processing)
	return true

func _fire_projectile_at_node(combat: CombatRuntime, shooter: Node3D, target: Node3D, target_position: Vector3) -> bool:
	var impacts: Array[ImpactEvent] = []
	var impact_callback := func(event: ImpactEvent) -> void: impacts.append(event)
	combat.impact_resolved.connect(impact_callback)
	var origin := shooter.global_position + Vector3.UP * 1.5
	combat._on_shot_fired(ShotEvent.new(Transform3D(Basis.IDENTITY, origin), target_position - origin, shooter.get_rid(), 10.0))
	for _frame in 60:
		await physics_frame
		for impact in impacts:
			if impact.collider == target:
				combat.impact_resolved.disconnect(impact_callback)
				return true
	if combat.impact_resolved.is_connected(impact_callback):
		combat.impact_resolved.disconnect(impact_callback)
	return false


## 本 fixture 的眼睛→玩家射線與玩家→受擊部位彈道不同；以兩條線的實際距離構造遮光尺寸。
## 屏幕位於 50m 側向玩家前方 10% 距離，不進入玩家幾何；不移動任何正式場景障礙。
func _make_near_hit_visibility_screen(observer: CharacterBody3D, subject: CharacterBody3D, shot_origin: Vector3, shot_target: Vector3) -> Array[StaticBody3D]:
	var origin := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_position
	var points: PackedVector3Array = subject.call("part_world_surface_points") as PackedVector3Array
	points.append(subject.call("stable_world_center") as Vector3)
	var placements: Array[Vector4] = []
	var blockers: Array[StaticBody3D] = []
	for point_index in points.size():
		var point := points[point_index]
		var position := origin.lerp(point, 0.9)
		var closest := Geometry3D.get_closest_point_to_segment(position, shot_origin, shot_target)
		var clearance := position.distance_to(closest)
		if clearance <= 0.002:
			return blockers
		## 盒的半對角線 < clearance，保證新 blocker 與已選來襲彈道不相交。
		var half_size := minf(0.05, clearance * 0.25)
		placements.append(Vector4(position.x, position.y, position.z, half_size * 2.0))
	for placement in placements:
		blockers.append(_make_blocker(Vector3(placement.x, placement.y, placement.z), Vector3.ONE * placement.w))
	return blockers
func _find_side_hit_surface_point(shooter: Node3D, target: CharacterBody3D, stable_center: Vector3) -> Vector3:
	## 舊 Box 的 center + X 3 可能落在真實凸形外；只從離線烘焙且固定排序的表面 sample 選擇。
	if shooter == null or target == null or target.get_world_3d() == null or not target.has_method(&"part_world_surface_points"):
		return Vector3.INF
	var origin := shooter.global_position + Vector3.UP * 1.5
	var preferred_side := stable_center + Vector3.RIGHT * 3.0
	var selected := Vector3.INF
	var selected_score := INF
	var samples: PackedVector3Array = target.call("part_world_surface_points") as PackedVector3Array
	for sample in samples:
		var local_offset := sample - stable_center
		## 保留原 fixture 的右側命中意圖，避免退化為正面或後方中心射擊。
		if local_offset.x <= 0.1 or absf(local_offset.x) < absf(local_offset.z):
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, sample, 129, [shooter.get_rid()])
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var hit := target.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.get("collider") != target:
			continue
		var score := sample.distance_squared_to(preferred_side)
		if score < selected_score:
			selected = sample
			selected_score = score
	return selected


func _validate_hit_inspection_behavior(playtest: Node3D) -> bool:
	## 四車只各跑一次：Tank2/3 砲塔查看，Tank1/4 由既有 hull assist 原地補轉。
	for specimen in [
		[TANK1_SCENE, "Tank1", true], [TANK2_SCENE, "Tank2", false],
		[TANK3_SCENE, "Tank3", false], [TANK4_SCENE, "Tank4", true],
	]:
		if not await _validate_hit_inspection_variant(playtest, specimen[0], specimen[1], specimen[2]):
			return false
	if not await _validate_hit_inspection_los_priority(playtest):
		return false
	if not await _validate_hit_inspection_rejections_and_cancellation(playtest):
		return false
	return true


func _validate_hit_inspection_variant(playtest: Node3D, scene_path: String, label: String, expects_hull_turn: bool) -> bool:
	var fixture := await _make_ai_hull_aim_fixture(playtest, scene_path)
	var observer := fixture.get("observer") as CharacterBody3D
	var target := fixture.get("target") as CharacterBody3D
	var vision := fixture.get("vision") as Node
	var ai := fixture.get("ai") as Node
	if observer == null or target == null or vision == null or ai == null:
		_finish(playtest, "%s hit-inspection fixture requires complete tanks, Vision, and CombatAI." % label)
		return false
	_configure_hit_inspection_vision(observer)
	var body_center := vision.call("target_world_position", observer) as Vector3
	var hit_position := body_center + Vector3(0, 0, 40)
	target.global_position = body_center + Vector3(0, 0, 50)
	var blocker := _make_blocker(body_center + Vector3(0, 1.5, 25), Vector3(8, 5, 8))
	fixture["root"].add_child(blocker)
	var shots: Array[ShotEvent] = []
	observer.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
	var initial_position := observer.global_position
	var initial_hull_yaw := observer.global_rotation.y
	ai.call("set_combat_enabled", true)
	await physics_frame
	if bool(vision.call("can_see", target)):
		_finish(playtest, "%s hit-inspection setup must keep the distant target physically hidden." % label)
		return false
	ai.call("inspect_hit_position", hit_position)
	if not await _wait_for_inspection_alignment(observer, hit_position, 360):
		_finish(playtest, "%s must turn toward body-center-to-hit XZ direction within the 3 degree tolerance." % label)
		return false
	var hull_turn_degrees := rad_to_deg(absf(angle_difference(initial_hull_yaw, observer.global_rotation.y)))
	if observer.global_position.distance_to(initial_position) > 0.02 or not is_zero_approx(observer.movement_command) \
			or not shots.is_empty() or (expects_hull_turn and hull_turn_degrees <= 5.0) \
			or (not expects_hull_turn and hull_turn_degrees > 0.5):
		_finish(playtest, "%s hit inspection must rotate in place without firing; only fixed-turret variants may turn their hull." % label)
		return false
	if not await _wait_for_hull_stop(observer, 30) or _horizontal_angle_to(observer, hit_position) > deg_to_rad(3.05):
		_finish(playtest, "%s must remain stopped at the inspected hit side after reaching alignment." % label)
		return false
	fixture["root"].queue_free()
	await physics_frame
	return true


func _validate_hit_inspection_los_priority(playtest: Node3D) -> bool:
	var fixture := await _make_ai_hull_aim_fixture(playtest, TANK2_SCENE)
	var observer := fixture.get("observer") as CharacterBody3D
	var target := fixture.get("target") as CharacterBody3D
	var vision := fixture.get("vision") as Node
	var ai := fixture.get("ai") as Node
	if observer == null or target == null or vision == null or ai == null:
		_finish(playtest, "Hit-inspection LOS-priority fixture requires Tank2, target, Vision, and CombatAI.")
		return false
	_configure_hit_inspection_vision(observer)
	var center := vision.call("target_world_position", observer) as Vector3
	## 玩家原本在遠扇形內但被遮蔽；查看另一側途中解除遮蔽，必須立刻回交戰。
	var initial_forward := -(observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_basis.x
	initial_forward.y = 0.0
	target.global_position = center + initial_forward.normalized() * 50.0
	var blocker := _make_blocker(center + Vector3(-25, 1.5, 0), Vector3(8, 5, 8))
	fixture["root"].add_child(blocker)
	var shots: Array[ShotEvent] = []
	observer.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
	ai.call("set_combat_enabled", true)
	ai.call("inspect_hit_position", center + Vector3(0, 0, 40))
	if not await _wait_for_frames(20) or bool(vision.call("can_see", target)):
		_finish(playtest, "Hit inspection must begin while the target has no line of sight.")
		return false
	blocker.queue_free()
	await physics_frame
	await physics_frame
	if not bool(vision.call("can_see", target)) or not await _wait_for_shots(shots, 1, 360):
		_finish(playtest, "A target becoming visible during inspection must resume ordinary aiming and firing.")
		return false
	fixture["root"].queue_free()
	await physics_frame
	return true


func _validate_hit_inspection_rejections_and_cancellation(playtest: Node3D) -> bool:
	var fixture := await _make_ai_hull_aim_fixture(playtest, TANK2_SCENE)
	var observer := fixture.get("observer") as CharacterBody3D
	var target := fixture.get("target") as CharacterBody3D
	var vision := fixture.get("vision") as Node
	var ai := fixture.get("ai") as Node
	if observer == null or target == null or vision == null or ai == null:
		_finish(playtest, "Hit-inspection guard fixture requires Tank2, target, Vision, and CombatAI.")
		return false
	_configure_hit_inspection_vision(observer)
	var center := vision.call("target_world_position", observer) as Vector3
	ai.call("set_combat_enabled", true)
	## 已可見遠目標不能建立查看意圖；近圈遮擋命中則由 live Encounter regression 驗證可查看。
	var guard_forward := -(observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_basis.x
	guard_forward.y = 0.0
	target.global_position = center + guard_forward.normalized() * 50.0
	await physics_frame
	if not bool(vision.call("can_see", target)):
		_finish(playtest, "The visible-target rejection fixture must expose its distant target before inspecting a hit.")
		return false
	ai.call("inspect_hit_position", center + Vector3(0, 0, 40))
	if not (ai.get("_inspection_direction") as Vector3).is_zero_approx():
		_finish(playtest, "An already visible target must keep normal combat priority over hit inspection.")
		return false
	## 受擊側本身在初始遠扇形內，即使玩家被遮住也不能查看。
	target.global_position = center + Vector3(0, 0, 50)
	var blocker := _make_blocker(center + Vector3(0, 1.5, 25), Vector3(8, 5, 8))
	fixture["root"].add_child(blocker)
	var fov_forward := -(observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_basis.x
	fov_forward.y = 0.0
	ai.call("inspect_hit_position", center + fov_forward.normalized() * 40.0)
	if not (ai.get("_inspection_direction") as Vector3).is_zero_approx():
		_finish(playtest, "A hit side already inside the initial far FOV must not trigger inspection.")
		return false
	ai.call("inspect_hit_position", center + Vector3(0, 0, 40))
	if not await _wait_for_inspection_motion(observer, 90):
		_finish(playtest, "The cancellation fixture must first create a pending inspection turn.")
		return false
	ai.call("set_combat_enabled", false)
	if not await _wait_for_hull_stop(observer, 20):
		_finish(playtest, "Disabling CombatAI must clear hit-inspection rotation and inertia.")
		return false
	fixture["root"].queue_free()
	await physics_frame
	return true


func _horizontal_angle_to(observer: CharacterBody3D, world_position: Vector3) -> float:
	var turret := observer.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret == null:
		return PI
	var forward := -turret.global_basis.x
	forward.y = 0.0
	var offset := world_position - observer.global_position
	offset.y = 0.0
	return PI if forward.is_zero_approx() or offset.is_zero_approx() else forward.normalized().angle_to(offset.normalized())


func _configure_hit_inspection_vision(observer: CharacterBody3D) -> void:
	## 車型原始近圈不同；回歸固定使用規格的 25m / 100m / 90° 幾何條件。
	observer.set("vision_near_radius", 25.0)
	observer.set("vision_far_radius", 100.0)
	observer.set("vision_field_of_view_degrees", 90.0)


func _wait_for_inspection_alignment(observer: CharacterBody3D, hit_position: Vector3, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if _horizontal_angle_to(observer, hit_position) <= deg_to_rad(3.05):
			return true
	return false


func _wait_for_inspection_motion(observer: CharacterBody3D, maximum_frames: int) -> bool:
	var initial_yaw := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_rotation.y
	for _frame in maximum_frames:
		await physics_frame
		var turret := observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D
		if absf(angle_difference(initial_yaw, turret.global_rotation.y)) > deg_to_rad(3.0):
			return true
	return false


func _validate_fixed_turret_ai_hull_aim(playtest: Node3D, scene_path: String, label: String, cancellation_cases: Array[StringName]) -> bool:
	var fixture := await _make_ai_hull_aim_fixture(playtest, scene_path)
	var observer := fixture["observer"] as CharacterBody3D
	var target := fixture["target"] as CharacterBody3D
	var vision := fixture["vision"] as Node
	var ai := fixture["ai"] as Node
	if observer == null or target == null or vision == null or ai == null:
		_finish(playtest, "%s hull-aim fixture must create complete tanks with the original Vision and CombatAI." % label)
		return false
	var shots: Array[ShotEvent] = []
	observer.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
	var initial_position := observer.global_position
	var initial_yaw := observer.global_rotation.y
	ai.call("set_combat_enabled", true)
	if not await _wait_for_hull_rotation(observer, initial_yaw, 300):
		print("hull aim start: label=", label, " visible=", vision.call("can_see", target), " requested=", observer.call("get_hull_aim_turn_input"), " turn=", observer.turn_command, " angular=", observer.angular_speed, " position=", observer.global_position)
		_finish(playtest, "%s must physically rotate its hull for a near, visible target outside the gun yaw range." % label)
		return false
	if observer.global_position.distance_to(initial_position) > 0.02 or not is_zero_approx(observer.movement_command):
		print("hull aim translation: label=", label, " start=", initial_position, " current=", observer.global_position, " movement=", observer.movement_command)
		_finish(playtest, "%s hull aim must rotate in place without translating." % label)
		return false
	if not await _wait_for_shots(shots, 1, 420) or not await _wait_for_hull_stop(observer, 90):
		print("hull aim settle: label=", label, " shots=", shots.size(), " requested=", observer.call("get_hull_aim_turn_input"), " turn=", observer.turn_command, " angular=", observer.angular_speed, " visible=", vision.call("can_see", target))
		_finish(playtest, "%s must stop hull rotation after alignment and emit a real firing event." % label)
		return false
	for cancellation_case in cancellation_cases:
		if not await _start_side_hull_turn(observer, target, ai, label):
			_finish(playtest, "%s must resume hull turning before the cancellation check." % label)
			return false
		if cancellation_case == &"lost_sight":
			var view_origin := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_position
			var blocker := _make_blocker(Vector3.ZERO, Vector3.ONE)
			fixture["root"].add_child(blocker)
			_configure_full_visibility_blocker(blocker, observer, target)
			await physics_frame
			await physics_frame
			if bool(vision.call("can_see", target)):
				print("hull aim lost sight: label=", label, " origin=", view_origin, " target=", vision.call("target_world_position", target), " blocker=", blocker.global_position)
				_finish(playtest, "%s hull-aim lost-sight fixture must block the original Vision ray." % label)
				return false
			var hidden_yaw := observer.global_rotation.y
			var shots_before_hidden := shots.size()
			if not await _wait_for_frames(10) or absf(angle_difference(hidden_yaw, observer.global_rotation.y)) <= deg_to_rad(1.0) \
					or shots.size() != shots_before_hidden or not is_zero_approx(observer.movement_command):
				print("hull aim last-seen: label=", label, " turn=", observer.turn_command, " angular=", observer.angular_speed, " movement=", observer.movement_command, " shots=", shots.size())
				_finish(playtest, "Losing sight with a last-seen position must keep %s turning in place without firing." % label)
				return false
			blocker.queue_free()
			await physics_frame
		elif cancellation_case == &"ai_disabled":
			ai.call("set_combat_enabled", false)
			if not await _wait_for_hull_stop(observer, 10):
				print("hull aim disabled stop: label=", label, " turn=", observer.turn_command, " angular=", observer.angular_speed, " movement=", observer.movement_command)
				_finish(playtest, "Disabling CombatAI must immediately clear %s hull-turn command and inertia." % label)
				return false
			ai.call("set_combat_enabled", true)
		elif cancellation_case == &"target_dead":
			var target_health := target.get_node_or_null("HealthComponent") as HealthComponent
			if target_health == null or not target_health.apply_damage(target_health.current_health) or not await _wait_for_hull_stop(observer, 10):
				print("hull aim target death: label=", label, " health=", target_health.current_health if target_health != null else -1.0, " turn=", observer.turn_command, " angular=", observer.angular_speed)
				_finish(playtest, "Target death must immediately clear %s hull-turn command and inertia." % label)
				return false
		elif cancellation_case == &"observer_dead":
			var observer_health := observer.get_node_or_null("HealthComponent") as HealthComponent
			if observer_health == null or not observer_health.apply_damage(observer_health.current_health) or not await _wait_for_hull_stop(observer, 10):
				print("hull aim observer death: label=", label, " health=", observer_health.current_health if observer_health != null else -1.0, " turn=", observer.turn_command, " angular=", observer.angular_speed)
				_finish(playtest, "Observer death must immediately clear %s hull-turn command and inertia." % label)
				return false
	fixture["root"].queue_free()
	await physics_frame
	return true


func _validate_rotating_turret_ai_hull_aim(playtest: Node3D, scene_path: String, label: String) -> bool:
	var fixture := await _make_ai_hull_aim_fixture(playtest, scene_path)
	var observer := fixture["observer"] as CharacterBody3D
	var target := fixture["target"] as CharacterBody3D
	var ai := fixture["ai"] as Node
	var initial_position := observer.global_position
	var initial_yaw := observer.global_rotation.y
	ai.call("set_combat_enabled", true)
	if not await _wait_for_frames(45) or not is_zero_approx(float(observer.call("get_hull_aim_turn_input"))) \
			or not is_zero_approx(observer.turn_command) or not is_zero_approx(observer.angular_speed) \
			or observer.global_position.distance_to(initial_position) > 0.02 \
			or absf(angle_difference(initial_yaw, observer.global_rotation.y)) > 0.001:
		print("rotating turret hull aim: label=", label, " requested=", observer.call("get_hull_aim_turn_input"), " turn=", observer.turn_command, " angular=", observer.angular_speed, " start=", initial_position, " current=", observer.global_position, " yaw=", initial_yaw, "/", observer.global_rotation.y, " target=", target.global_position)
		_finish(playtest, "%s must keep hull aim disabled while its rotating turret tracks the same near target." % label)
		return false
	fixture["root"].queue_free()
	await physics_frame
	return true


func _make_ai_hull_aim_fixture(playtest: Node3D, observer_scene_path: String) -> Dictionary:
	var fixture := Node3D.new()
	fixture.name = "AIHullAimFixture"
	var observer_packed := load(observer_scene_path) as PackedScene
	var observer := observer_packed.instantiate() as CharacterBody3D if observer_packed != null else null
	var target_packed := load(TANK3_SCENE) as PackedScene
	var target := target_packed.instantiate() as CharacterBody3D if target_packed != null else null
	var vision := TankVision.new() as Node
	var ai := TankCombatAI.new() as Node
	if observer == null or target == null or vision == null or ai == null:
		return {}
	observer.name = "Observer"
	target.name = "Target"
	## Tank 使用平面移動且沒有重力；浮空 fixture 可避開訓練場的視線房屋與靶子碰撞。
	observer.position = Vector3(0, 30, 0)
	target.position = observer.position + Vector3.FORWARD * 12.0
	target.set_physics_process(false)
	vision.name = "Vision"
	vision.set("observer", observer)
	ai.name = "CombatAI"
	ai.set("controlled_tank", observer)
	ai.set("vision", vision)
	ai.call("set_target", target)
	ai.call("set_combat_enabled", false)
	fixture.add_child(observer)
	fixture.add_child(target)
	fixture.add_child(vision)
	fixture.add_child(ai)
	playtest.add_child(fixture)
	await physics_frame
	await physics_frame
	return {"root": fixture, "observer": observer, "target": target, "vision": vision, "ai": ai}


func _wait_for_hull_rotation(observer: CharacterBody3D, initial_yaw: float, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if absf(angle_difference(initial_yaw, observer.global_rotation.y)) > deg_to_rad(5.0):
			return true
	return false


func _wait_for_hull_stop(observer: CharacterBody3D, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if is_zero_approx(observer.turn_command) and is_zero_approx(observer.angular_speed) \
				and is_zero_approx(observer.actual_angular_speed) and is_zero_approx(observer.movement_command):
			return true
	return false


func _start_side_hull_turn(observer: CharacterBody3D, target: CharacterBody3D, ai: Node, label: String) -> bool:
	var forward := -observer.global_basis.x
	forward.y = 0.0
	if forward.is_zero_approx():
		return false
	var side := Vector3(-forward.z, 0.0, forward.x).normalized()
	target.global_position = observer.global_position + side * 12.0
	ai.call("set_combat_enabled", true)
	for _frame in 90:
		await physics_frame
		if not is_zero_approx(observer.turn_command) and not is_zero_approx(observer.angular_speed):
			return true
	print("hull aim restart: label=", label, " requested=", observer.call("get_hull_aim_turn_input"), " turn=", observer.turn_command, " angular=", observer.angular_speed, " observer=", observer.global_position, " target=", target.global_position)
	return false


func _validate_combat_and_recovery(playtest: Node3D, main: Node3D, encounter: Node3D, enemy: Node3D, player: Node3D, vision: Node, ai: Node, player_runtime: Node, combat: CombatRuntime, initial_enemy_transform: Transform3D, initial_camera_snapshot: Dictionary) -> bool:
	## 真實 ShotEvent 證明對準後才開火；遮擋、失聯、死亡與換車皆在同一組裝場景驗證。
	var shots: Array[ShotEvent] = []
	enemy.shot_event_fired.connect(func(event: ShotEvent) -> void: shots.append(event))
	var turret := enemy.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret == null:
		_finish(playtest, "Enemy combat fixture requires the live turret pivot.")
		return false
	## 仍留在 90 度視野內，但先製造可見的偏航誤差，確認 AI 不會未對準就射擊。
	turret.global_rotation.y = 0.6
	## 固定此 smoke 的彈道，讓真實 ShotEvent 後能穩定驗證投射物確實傷害玩家。
	enemy.set("aim_spread_base_degrees", 0.0)
	enemy.set("aim_spread_cap_degrees", 0.0)
	enemy.set("current_spread_degrees", 0.0)
	var player_health := player.get_node_or_null("HealthComponent") as HealthComponent
	if player_health == null:
		_finish(playtest, "Enemy combat fixture requires the live player health component.")
		return false
	var health_before_first_shot := player_health.current_health
	ai.call("set_combat_enabled", true)
	await physics_frame
	if not shots.is_empty():
		_finish(playtest, "Enemy must not fire before its turret and muzzle are aligned.")
		return false
	if not await _wait_for_shots(shots, 1, 360):
		_finish(playtest, "A visible, aligned enemy must publish a real ShotEvent.")
		return false
	if not await _wait_for_health_loss(player_health, health_before_first_shot, 180):
		_finish(playtest, "The aligned enemy ShotEvent must create a projectile that damages the player.")
		return false
	## 單獨驗炮口阻擋時固定姿態，先等上一發的視覺後座回正，避免障礙物離開射線。
	ai.call("set_combat_enabled", false)
	await _wait_for_frames(60)
	var settled_target := vision.call("target_world_position", player) as Vector3
	enemy.call("aim_turret_at", settled_target, 10.0)
	enemy.call("aim_gun_pitch_at_target", settled_target, 10.0)
	await physics_frame
	if not bool(ai.call("_is_muzzle_aligned_and_clear", settled_target)):
		_finish(playtest, "The isolated muzzle fixture must start aligned with an unobstructed player.")
		return false
	var original_turn_speed := float(enemy.get("turret_turn_speed"))
	var original_pitch_speed := float(enemy.get("gun_pitch_speed"))
	enemy.set("turret_turn_speed", 0.0)
	enemy.set("gun_pitch_speed", 0.0)
	var muzzle := enemy.call("muzzle_global_position") as Vector3
	var target_position := vision.call("target_world_position", player) as Vector3
	var muzzle_direction := enemy.call("muzzle_global_direction") as Vector3
	var muzzle_block_position := muzzle + muzzle_direction * 0.5
	var view_origin := turret.global_position
	var view_offset := target_position - view_origin
	var view_direction := view_offset.normalized()
	var view_closest := view_origin + view_direction * clampf(
		(muzzle_block_position - view_origin).dot(view_direction), 0.0, view_offset.length())
	var ray_separation := muzzle_block_position.distance_to(view_closest)
	if ray_separation <= 0.04:
		_finish(playtest, "Muzzle and vision rays need measurable separation for the isolated blocker fixture.")
		return false
	## 用同一個 0.5m 砲口前方取樣計算兩條真實射線距離；盒子小於間距，只攔炮口射線。
	## 盒子半徑也必須小於距砲口的 0.5m，不能把射線起點包進盒內。
	var muzzle_blocker := _make_blocker(muzzle_block_position, Vector3.ONE * clampf(ray_separation * 0.5, 0.02, 0.4))
	playtest.add_child(muzzle_blocker)
	await physics_frame
	await physics_frame
	var shots_before_block := shots.size()
	var muzzle_query := PhysicsRayQueryParameters3D.create(
		muzzle, muzzle + muzzle_direction * muzzle.distance_to(target_position), 0xFFFFFFFF, [enemy.get_rid()])
	var muzzle_hit := enemy.get_world_3d().direct_space_state.intersect_ray(muzzle_query)
	if muzzle_hit.get("collider") != muzzle_blocker:
		print("muzzle fixture: origin=", muzzle, " direction=", muzzle_direction, " blocker=", muzzle_blocker.global_position, " size=", ray_separation, " hit=", muzzle_hit)
		_finish(playtest, "Muzzle-block fixture must be the first physical hit on the actual firing ray.")
		return false
	if not bool(vision.call("can_see", player)):
		_finish(playtest, "Muzzle-block fixture must preserve turret visibility while denying the firing ray.")
		return false
	ai.call("set_combat_enabled", true)
	if not await _wait_for_frames(90) or shots.size() != shots_before_block:
		_finish(playtest, "A clear vision result with a blocked muzzle ray must not fire.")
		return false
	muzzle_blocker.queue_free()
	enemy.set("turret_turn_speed", original_turn_speed)
	enemy.set("gun_pitch_speed", original_pitch_speed)
	await physics_frame
	var sight_blocker := _make_blocker(Vector3.ZERO, Vector3.ONE)
	playtest.add_child(sight_blocker)
	_configure_full_visibility_blocker(sight_blocker, enemy, player, Vector3(0, 0, 1))
	await physics_frame
	shots_before_block = shots.size()
	var lost_yaw := turret.global_rotation.y
	player.global_position.z += 1.0
	if bool(vision.call("can_see", player)) or not await _wait_for_frames(90) or shots.size() != shots_before_block:
		_finish(playtest, "Losing sight must stop tracking and firing on the next physics updates.")
		return false
	sight_blocker.queue_free()
	if absf(angle_difference(lost_yaw, turret.global_rotation.y)) > 0.0001:
		_finish(playtest, "A hidden moving target must not update the enemy turret yaw.")
		return false
	await physics_frame
	if not await _wait_for_shots(shots, shots_before_block + 1, 360):
		print("reacquire: enabled=", ai.get("combat_enabled"), " visible=", vision.call("can_see", player), " health=", player_health.current_health, " player=", player.global_position, " enemy=", enemy.global_position, " direction=", enemy.call("muzzle_global_direction"), " target=", vision.call("target_world_position", player), " speeds=", enemy.get("turret_turn_speed"), "/", enemy.get("gun_pitch_speed"), " shots=", shots.size(), "/", shots_before_block)
		_finish(playtest, "Reacquiring an unobstructed target must resume enemy fire.")
		return false
	ai.call("set_combat_enabled", false)
	## R1-R5：死亡車留下，新實例於可編輯出生標記重生；鏡頭、無敵和操作都恢復。
	## 移出視野，避免重生時被下一發擊中而誤判；瞬移後至少讓物理世界同步一次。
	player.global_position = enemy.global_position + Vector3(150, 0, 0)
	var cleanup_zone := playtest.get_node_or_null("PlayerSpawnPoint/WreckCleanupZone") as Node3D
	var cleanup_area := cleanup_zone.get_node_or_null("RegionVolume") as Area3D if cleanup_zone != null else null
	var left_cleanup_area := false
	for _physics_step in 4:
		await physics_frame
		await process_frame
		if cleanup_area != null and not cleanup_area.get_overlapping_bodies().has(player):
			left_cleanup_area = true
			break
	if cleanup_area == null or not left_cleanup_area:
		_finish(playtest, "Player respawn fixture must synchronize its moved live tank outside WreckCleanupZone within four physics updates.")
		return false
	var spawn_point := playtest.get_node_or_null("PlayerSpawnPoint") as Node3D
	var camera_rig := player_runtime.get("camera_controller") as Node3D
	var camera := camera_rig.get("camera") as Camera3D if camera_rig != null else null
	if spawn_point == null or camera_rig == null or camera == null:
		_finish(playtest, "Player respawn requires the playtest PlayerSpawnPoint and PlayerRuntime CameraRig.")
		return false
	var initial_camera_basis := initial_camera_snapshot["rig_basis"] as Basis
	var initial_camera_transform := initial_camera_snapshot["camera_transform"] as Transform3D
	var initial_camera_size := float(initial_camera_snapshot["camera_size"])
	var initial_camera_offset := initial_camera_snapshot["follow_offset"] as Vector3
	var original_spawn_transform := spawn_point.global_transform
	## R3：不是寫死中央座標；改動作者標記就必須決定新車世界姿態。
	spawn_point.global_transform = Transform3D(original_spawn_transform.basis, original_spawn_transform.origin + Vector3(0, 0, 4))
	if not is_equal_approx(float(encounter.get("player_respawn_seconds")), 3.0):
		_finish(playtest, "Player recovery must default to three seconds.")
		return false
	if not is_equal_approx(float(encounter.get("player_invulnerability_seconds")), 2.0):
		_finish(playtest, "Player respawn invulnerability must default to two seconds.")
		return false
	var player_controller := player_runtime.get_node_or_null("PlayerController") as Node
	if player_health == null or player_controller == null or not player_health.apply_damage(player_health.current_health):
		_finish(playtest, "Player death fixture requires the live health and controller components.")
		return false
	await physics_frame
	player_controller.call("apply_commands", 1.0, 1.0, true)
	if bool(player_runtime.get("controls_enabled")) or bool(ai.get("combat_enabled")):
		_finish(playtest, "Player depletion must disable controls and enemy combat immediately.")
		return false
	if not await _wait_for_frames(120) or main.get_node_or_null("Tank") != player \
			or bool(player_runtime.get("controls_enabled")) or bool(ai.get("combat_enabled")):
		_finish(playtest, "Before three seconds the depleted original tank must remain the disabled controlled instance.")
		return false
	var respawned := await _wait_for_player_replacement(main, player, 100)
	var respawned_health := respawned.get_node_or_null("HealthComponent") as HealthComponent if respawned != null else null
	if respawned == null or respawned.scene_file_path != player.scene_file_path \
			or not respawned.global_transform.is_equal_approx(spawn_point.global_transform) \
			or respawned_health == null or not is_equal_approx(respawned_health.current_health, respawned_health.maximum_health) \
			or not respawned.velocity.is_zero_approx() or not bool(player_runtime.get("controls_enabled")) \
			or not bool(ai.get("combat_enabled")):
		_finish(playtest, "After three seconds respawn must create a full-health, stationary same-variant tank at PlayerSpawnPoint.")
		return false
	if not player.is_in_group("player_wreck") or player_health.current_health != 0.0 \
			or player_runtime.get("controlled_tank") == player or ai.get("target") == player \
			or combat.get_registered_shot_sources().has(player) or main.get("track_contact_effects") == player.get_node_or_null("TrackContactEffects"):
		_finish(playtest, "The old depleted tank must remain a disconnected player_wreck, never an input, AI, shot, or track-contact source.")
		return false
	var wreck_visuals := player.find_child("*DamageVisuals", true, false) as Node
	var wreck_gun := player.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	if wreck_visuals == null or int(wreck_visuals.get("active_damage_stage")) != 0 or wreck_gun == null \
			or is_zero_approx(wreck_gun.rotation.z):
		_finish(playtest, "The retained player wreck must preserve its depleted grey-black damage state and lowered gun.")
		return false
	if not camera_rig.global_basis.is_equal_approx(initial_camera_basis) \
			or not camera.transform.is_equal_approx(initial_camera_transform) \
			or not is_equal_approx(camera.size, initial_camera_size) \
			or not (camera_rig.global_position - respawned.global_position).is_equal_approx(initial_camera_offset) \
			or not (camera_rig.get("look_ahead_offset") as Vector3).is_zero_approx():
		_finish(playtest, "Respawn must reset the camera to its initial relative view, size, and clear look-ahead.")
		return false
	camera_rig.set_process(true)
	var receiver := respawned.get_node_or_null("DamageReceiver") as Node
	var body_visibility := _body_mesh_visibility(respawned)
	if receiver == null or bool(receiver.get("enabled")) or body_visibility.is_empty():
		_finish(playtest, "A newly respawned tank must start with DamageReceiver disabled and visible non-effect body meshes.")
		return false
	var blink_transitions := 0
	var previous_visibility := body_visibility
	for _sample in 9:
		await _wait_for_frames(10)
		var sampled_visibility := _body_mesh_visibility(respawned)
		if sampled_visibility != previous_visibility:
			blink_transitions += 1
		previous_visibility = sampled_visibility
	if blink_transitions < 2 or bool(receiver.call("receive_damage", 1.0)) \
		or not is_equal_approx(respawned_health.current_health, respawned_health.maximum_health):
		_finish(playtest, "The two-second protection must reject real receiver damage while non-effect body meshes blink repeatedly.")
		return false
	## R6 前半：一般換車不重置保護；操作仍通過既有 PlayerRuntime。
	var protected_replacement := main.call("replace_player_tank", load(TANK1_SCENE)) as Node3D
	var protected_receiver := protected_replacement.get_node_or_null("DamageReceiver") as Node if protected_replacement != null else null
	if protected_replacement == null or protected_receiver == null or bool(protected_receiver.get("enabled")) \
			or player_runtime.get("controlled_tank") != protected_replacement:
		_finish(playtest, "Changing tank during invulnerability must carry the remaining protection to the newly controlled tank.")
		return false
	player_controller.call("apply_commands", 1.0, 0.0, true)
	if is_zero_approx(float(protected_replacement.get("movement_command"))):
		_finish(playtest, "Respawn protection must not lock normal player movement input.")
		return false
	if not await _wait_for_frames(60) or not bool(protected_receiver.get("enabled")) \
			or not bool(protected_receiver.call("receive_damage", 1.0)):
		_finish(playtest, "When protection expires, the currently controlled replacement must restore visibility and receive damage again.")
		return false
	var target := main.get_node_or_null("World/Targets/Tank1TrainingTarget/SubjectSlot/Tank") as Node3D
	var target_health := target.get_node_or_null("HealthComponent") as HealthComponent if target != null else null
	if target_health == null or not target_health.apply_damage(target_health.current_health):
		_finish(playtest, "Tank replacement fixture requires the existing first training target.")
		return false
	await process_frame
	await physics_frame
	var replacement := main.get_node_or_null("Tank") as Node3D
	if replacement == null or replacement == player or replacement.scene_file_path != TANK1_SCENE \
			or ai.get("target") != replacement or not _has_exact_registered_sources(combat, [replacement, enemy]) \
			or enemy.is_connected("shot_event_fired", Callable(player_runtime, "_on_controlled_tank_shot_event_fired")):
		_finish(playtest, "Replacement must retarget AI, retain one player/enemy source each, and keep enemy out of camera recoil.")
		return false
	var enemy_health := enemy.get_node_or_null("HealthComponent") as HealthComponent
	## 死亡倒數期間仍可能被在途砲彈觸發換車，不能藉換車提前恢復輸入與敵方開火。
	var replacement_health := replacement.get_node("HealthComponent") as HealthComponent
	replacement_health.apply_damage(replacement_health.current_health)
	var remaining_before_swap := float(encounter.get("_respawn_remaining"))
	main.call("replace_player_tank", load(TANK1_SCENE))
	if bool(player_runtime.get("controls_enabled")) or bool(ai.get("combat_enabled")) \
			or not is_equal_approx(float(encounter.get("_respawn_remaining")), remaining_before_swap):
		_finish(playtest, "Changing tank during recovery must preserve the remaining delay and disabled controls.")
		return false
	var shots_before_death := shots.size()
	## 倒數中的正常換車不取消倒數；210 幀後必須又由重生入口產生新實例，不能保留舊指標。
	var countdown_tank := main.get_node("Tank") as Node3D
	var encounter_child_count := encounter.get_child_count()
	if enemy_health == null or not enemy_health.apply_damage(enemy_health.current_health):
		_finish(playtest, "Enemy death fixture requires the complete Tank2 health component.")
		return false
	ai.call("set_combat_enabled", true)
	if not await _wait_for_frames(210) or shots.size() != shots_before_death \
			or not is_instance_valid(enemy) or encounter.get_node_or_null("Enemy") != enemy \
			or enemy_health.current_health != 0.0 or encounter.get_child_count() != encounter_child_count \
			or main.get_node("Tank") == countdown_tank or not bool(player_runtime.get("controls_enabled")) \
			or not bool(ai.get("combat_enabled")):
		_finish(playtest, "A depleted enemy must permanently stop firing; player recovery must still replace the countdown tank normally.")
		return false
	var active_player := main.get_node_or_null("Tank") as Node3D
	if not await _validate_enemy_type_switch(playtest, main, encounter, enemy, active_player, vision, ai, player_runtime, combat, initial_enemy_transform):
		return false
	if not await _validate_respawn_wreck_clearance(playtest, main, encounter, player_runtime, combat):
		return false
	return true


func _validate_enemy_type_switch(playtest: Node3D, main: Node3D, encounter: Node3D, initial_enemy: Node3D, player: Node3D, vision: Node, ai: Node, player_runtime: Node, combat: CombatRuntime, initial_enemy_transform: Transform3D) -> bool:
	## 故意從死亡的 Tank2 開始：沒有粉色靶命中時它絕不能自行重生；只有真實命中才可換車。
	var switch_target := playtest.get_node_or_null("TrainingControls/EnemyTypeSwitch") as StaticBody3D
	var non_switch_target := main.get_node_or_null("World/Range/ClearTarget") as StaticBody3D
	var switch_collision := switch_target.get_node_or_null("CollisionShape3D") as CollisionShape3D if switch_target != null else null
	var switch_shape := switch_collision.shape as BoxShape3D if switch_collision != null else null
	var switch_visual := switch_target.get_node_or_null("Visual") as MeshInstance3D if switch_target != null else null
	var switch_mesh := switch_visual.mesh as BoxMesh if switch_visual != null else null
	var switch_material := switch_mesh.material as StandardMaterial3D if switch_mesh != null else null
	var switch_label := switch_target.get_node_or_null("Label") as Label3D if switch_target != null else null
	if player == null or switch_target == null or non_switch_target == null or switch_shape == null \
			or not switch_shape.size.is_equal_approx(Vector3(4, 4, 0.2)) or switch_mesh == null \
			or not switch_mesh.size.is_equal_approx(Vector3(4, 4, 0.2)) or switch_material == null \
			or not switch_material.albedo_color.is_equal_approx(Color(1, 0.35, 0.65, 1)) \
			or switch_label == null or switch_label.text != "切換敵方車型" or switch_label.font_size != 320 \
			or main.get_node_or_null("World/TrainingControls/EnemyTypeSwitch") != null:
		_finish(playtest, "Enemy switch requires the authored 4m pink switch target and an independent non-switch target.")
		return false
	var recovering_player := player_runtime.get("controlled_tank") as Node3D
	var player_health := recovering_player.get_node_or_null("HealthComponent") as HealthComponent if recovering_player != null else null
	var switch_cleanup_zone := playtest.get_node_or_null("PlayerSpawnPoint/WreckCleanupZone") as Node3D
	var switch_cleanup_area := switch_cleanup_zone.get_node_or_null("RegionVolume") as Area3D if switch_cleanup_zone != null else null
	if recovering_player != null:
		recovering_player.global_position += Vector3(150, 0, 0)
	var switch_player_left_cleanup_area := false
	for _physics_step in 4:
		await physics_frame
		await process_frame
		if switch_cleanup_area != null and recovering_player != null and not switch_cleanup_area.get_overlapping_bodies().has(recovering_player):
			switch_player_left_cleanup_area = true
			break
	if switch_cleanup_area == null or not switch_player_left_cleanup_area:
		_finish(playtest, "Enemy-switch recovery fixture must synchronize its live player outside WreckCleanupZone within four physics updates.")
		return false
	if recovering_player == null or player_health == null or not player_health.apply_damage(player_health.current_health):
		_finish(playtest, "Enemy switch recovery fixture requires a live player health component.")
		return false
	var remaining_before_switch := float(encounter.get("_respawn_remaining"))
	if bool(player_runtime.get("controls_enabled")) or bool(ai.get("combat_enabled")) or remaining_before_switch <= 0.0:
		_finish(playtest, "Player death must begin the original recovery countdown before an enemy switch.")
		return false
	if not await _fire_projectile_at(combat, recovering_player, non_switch_target):
		_finish(playtest, "The non-switch regression fixture must resolve a real projectile impact.")
		return false
	await process_frame
	if encounter.get_node_or_null("Enemy") != initial_enemy:
		_finish(playtest, "A non-switch projectile impact must not replace the dead enemy.")
		return false
	## 實例化前先留下錯誤狀態；每一種新車都必須回復最初世界姿態、滿血、零速度和原廠砲塔姿態。
	initial_enemy.global_transform = Transform3D(Basis.from_euler(Vector3(0.3, -0.7, 0.2)), initial_enemy_transform.origin + Vector3(8, 0, -5))
	initial_enemy.velocity = Vector3(6, 0, -4)
	var expected_scenes := [TANK3_SCENE, TANK4_SCENE, TANK1_SCENE, TANK2_SCENE]
	var current_enemy := initial_enemy
	for index in expected_scenes.size():
		var expected_scene: String = expected_scenes[index]
		var current_player := player_runtime.get("controlled_tank") as Node3D
		if current_player == null or not await _fire_projectile_at(combat, current_player, switch_target):
			_finish(playtest, "The pink switch must react to a real CombatRuntime projectile impact.")
			return false
		if not await _wait_for_enemy_scene(encounter, expected_scene):
			_finish(playtest, "Each pink-switch hit must cycle Tank2 → Tank3 → Tank4 → Tank1 → Tank2 exactly once.")
			return false
		var replacement := encounter.get_node_or_null("Enemy") as CharacterBody3D
		var health := replacement.get_node_or_null("HealthComponent") as HealthComponent if replacement != null else null
		if replacement == null or not replacement.global_transform.is_equal_approx(initial_enemy_transform) \
				or not replacement.velocity.is_zero_approx() or health == null \
				or not is_equal_approx(health.current_health, health.maximum_health) \
				or not _has_default_turret_and_gun_pose(replacement, expected_scene) \
			or ai.get("controlled_tank") != replacement or vision.get("observer") != replacement \
			or not _has_exact_registered_sources(combat, [current_player, replacement]):
			_finish(playtest, "Enemy replacement must restore its bare variant state and rebind AI, Vision, and CombatRuntime exactly once.")
			return false
		if index == 0 and (bool(player_runtime.get("controls_enabled")) or bool(ai.get("combat_enabled")) \
				or float(encounter.get("_respawn_remaining")) <= 0.0 \
				or float(encounter.get("_respawn_remaining")) >= remaining_before_switch):
			_finish(playtest, "Switching during player recovery must preserve its in-progress countdown and disabled AI/controls.")
			return false
		current_enemy = replacement
	if not await _wait_for_frames(190):
		_finish(playtest, "The original player recovery countdown must complete normally after an enemy switch.")
		return false
	var recovered_player := player_runtime.get("controlled_tank") as Node3D
	var recovered_health := recovered_player.get_node_or_null("HealthComponent") as HealthComponent if recovered_player != null else null
	if recovered_player == null or not bool(player_runtime.get("controls_enabled")) \
			or not bool(ai.get("combat_enabled")) or recovered_health == null \
			or not is_equal_approx(recovered_health.current_health, recovered_health.maximum_health):
		_finish(playtest, "The original player recovery countdown must complete normally after an enemy switch.")
		return false
	## 對準可見玩家後，新敵人也必須以新註冊的 source 發出真實射擊事件；固定砲塔不要求新增車身轉向。
	var replacement_shots: Array[ShotEvent] = []
	current_enemy.shot_event_fired.connect(func(event: ShotEvent) -> void: replacement_shots.append(event))
	recovered_player.global_position = current_enemy.global_position + Vector3(10, 0, 0)
	ai.call("set_combat_enabled", true)
	if not await _wait_for_shots(replacement_shots, 1, 360):
		_finish(playtest, "The currently switched enemy must remain an effective CombatRuntime firing source in its existing firing arc.")
		return false
	return true


func _has_exact_registered_sources(combat: CombatRuntime, expected_sources: Array[Node]) -> bool:
	var registered_sources: Array[Node] = combat.get_registered_shot_sources()
	if registered_sources.size() != expected_sources.size():
		return false
	for source in expected_sources:
		if registered_sources.count(source) != 1:
			return false
	return true


func _validate_respawn_wreck_clearance(playtest: Node3D, main: Node3D, encounter: Node3D, player_runtime: Node, combat: CombatRuntime) -> bool:
	## R8 改由固定區域：區內死亡車可早於三秒移除，重生流程不得依賴舊節點。
	var spawn_point := playtest.get_node_or_null("PlayerSpawnPoint") as Node3D
	var zone := playtest.get_node_or_null("PlayerSpawnPoint/WreckCleanupZone") as Node3D
	var area := zone.get_node_or_null("RegionVolume") as Area3D if zone != null else null
	var player := main.get_node_or_null("Tank") as Node3D
	var player_health := player.get_node_or_null("HealthComponent") as HealthComponent if player != null else null
	var player_controller := player_runtime.get_node_or_null("PlayerController") as Node
	var ai := encounter.get_node_or_null("CombatAI") as Node
	var camera_rig := player_runtime.get("camera_controller") as Node
	var player_scene_path := player.scene_file_path if player != null else ""
	if spawn_point == null or zone == null or area == null or player == null or player_health == null or player_controller == null \
			or ai == null or camera_rig == null:
		_finish(playtest, "R8 requires the authored PlayerSpawnPoint, WreckCleanupZone, and a currently controlled complete player tank.")
		return false
	var outside_wreck := _make_player_wreck_fixture(main, load(TANK1_SCENE), spawn_point.global_position + Vector3(35, 0, 0))
	var outside_health := outside_wreck.get_node_or_null("HealthComponent") as HealthComponent if outside_wreck != null else null
	if outside_wreck == null or outside_health == null or not outside_health.apply_damage(outside_health.current_health):
		_finish(playtest, "R8 requires a real dead corpse outside the authored cleanup area.")
		return false
	await physics_frame
	## 實際死亡車在區內；不假定 render frame 等於 physics frame，逐步等待安全 queue_free。
	player.global_transform = spawn_point.global_transform
	await physics_frame
	if not player_health.apply_damage(player_health.current_health):
		_finish(playtest, "R8 requires the controlled tank to become a real depleted wreck inside WreckCleanupZone.")
		return false
	var freed_early := false
	for _frame in 12:
		await physics_frame
		await process_frame
		if not is_instance_valid(player):
			freed_early = true
			break
	if not freed_early or main.get_node_or_null("Tank") != null or player_runtime.get("controlled_tank") != null \
			or bool(player_runtime.get("controls_enabled")) or bool(ai.get("combat_enabled")):
		_finish(playtest, "R8 zone cleanup must early-free the dead player while leaving recovery safely unbound and disabled.")
		return false
	var respawned := await _wait_for_player_replacement(main, null, 220)
	var respawned_health := respawned.get_node_or_null("HealthComponent") as HealthComponent if respawned != null else null
	var respawned_receiver := respawned.get_node_or_null("DamageReceiver") as Node if respawned != null else null
	if respawned == null or respawned.scene_file_path != player_scene_path or respawned_health == null or respawned_receiver == null \
			or not is_equal_approx(respawned_health.current_health, respawned_health.maximum_health) \
			or not bool(player_runtime.get("controls_enabled")) or player_runtime.get("controlled_tank") != respawned \
			or ai.get("target") != respawned or camera_rig.get("follow_target") != respawned \
			or bool(respawned_receiver.get("enabled")) or not combat.get_registered_shot_sources().has(respawned):
		_finish(playtest, "R8 early zone cleanup must still produce the same full-health controlled respawn with AI and shot-source rebindings.")
		return false
	player_controller.call("apply_commands", 1.0, 0.0, true)
	if is_zero_approx(float(respawned.get("movement_command"))):
		_finish(playtest, "The R8 replacement tank must be controllable after early cleanup.")
		return false
	if not is_instance_valid(outside_wreck):
		_finish(playtest, "R8 must preserve a corpse outside the cleanup area; respawn is not a global cleanup event.")
		return false
	## physics_frame 早於計時 callback；兩秒邊界留兩步同步，不改產品保護時間。
	if not await _wait_for_frames(122) or not bool(respawned_receiver.get("enabled")) \
			or not bool(respawned_receiver.call("receive_damage", 1.0)):
		_finish(playtest, "R8 early cleanup respawn must retain its two-second protection, then restore real damage reception.")
		return false
	## 獨立流程：區外死車被外部手動 queue_free，仍必須正常走既有三秒重生。
	respawned.global_position = spawn_point.global_position + Vector3(100, 0, 0)
	await physics_frame
	if not respawned_health.apply_damage(respawned_health.current_health):
		_finish(playtest, "R8 independent-flow fixture requires a real outside-zone player death.")
		return false
	respawned.queue_free()
	await process_frame
	var manual_replacement := await _wait_for_player_replacement(main, null, 220)
	var manual_health := manual_replacement.get_node_or_null("HealthComponent") as HealthComponent if manual_replacement != null else null
	if manual_replacement == null or manual_health == null or not is_equal_approx(manual_health.current_health, manual_health.maximum_health):
		_finish(playtest, "R8 manual removal outside WreckCleanupZone must not break the independent three-second respawn flow.")
		return false
	return true


func _make_player_wreck_fixture(parent: Node3D, tank_scene: PackedScene, position: Vector3) -> Node3D:
	var wreck := tank_scene.instantiate() as Node3D if tank_scene != null else null
	if parent == null or wreck == null:
		return null
	wreck.name = "FixturePlayerWreck"
	wreck.position = parent.to_local(position)
	parent.add_child(wreck)
	wreck.add_to_group("player_wreck")
	return wreck


func _fire_projectile_at(combat: CombatRuntime, shooter: Node3D, target: StaticBody3D) -> bool:
	var impacts: Array[ImpactEvent] = []
	var impact_callback := func(event: ImpactEvent) -> void: impacts.append(event)
	combat.impact_resolved.connect(impact_callback)
	var origin := target.global_position + Vector3.UP * 5.0
	combat._on_shot_fired(ShotEvent.new(Transform3D(Basis.IDENTITY, origin), Vector3.DOWN, shooter.get_rid()))
	for _frame in 30:
		await physics_frame
		for impact in impacts:
			if impact.collider == target:
				combat.impact_resolved.disconnect(impact_callback)
				return true
	if combat.impact_resolved.is_connected(impact_callback):
		combat.impact_resolved.disconnect(impact_callback)
	return false


func _wait_for_enemy_scene(encounter: Node3D, expected_scene: String) -> bool:
	for _frame in 60:
		await process_frame
		var current_enemy := encounter.get_node_or_null("Enemy") as Node3D
		if current_enemy != null and current_enemy.scene_file_path == expected_scene:
			return true
	return false


func _wait_for_player_replacement(main: Node3D, previous: Node3D, maximum_frames: int) -> Node3D:
	for _frame in maximum_frames:
		await physics_frame
		var current := main.get_node_or_null("Tank") as Node3D
		if current != null and current != previous:
			return current
	return null


func _body_mesh_visibility(tank: Node3D) -> Array[bool]:
	var visibility: Array[bool] = []
	if tank == null:
		return visibility
	for node in tank.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null and not mesh.is_in_group("effect_mesh"):
			visibility.append(mesh.visible)
	return visibility


func _has_default_turret_and_gun_pose(enemy: Node3D, scene_path: String) -> bool:
	var packed := load(scene_path) as PackedScene
	var bare_variant := packed.instantiate() as Node3D if packed != null else null
	var parent := enemy.get_parent()
	if bare_variant == null or parent == null:
		return false
	## TankController 在 ready 時依模型 pivot 校正砲塔與砲管；裸實例也必須進樹完成同一初始化再比對。
	parent.add_child(bare_variant)
	var turret := enemy.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	var gun := enemy.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	var bare_turret := bare_variant.get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	var bare_gun := bare_variant.get_node_or_null("VisualRecoilPivot/TurretPivot/GunPitchPivot") as Node3D
	var matches := turret != null and gun != null and bare_turret != null and bare_gun != null \
			and turret.transform.is_equal_approx(bare_turret.transform) and gun.transform.is_equal_approx(bare_gun.transform)
	parent.remove_child(bare_variant)
	bare_variant.free()
	return matches


func _configure_full_visibility_blocker(blocker: StaticBody3D, observer: Node3D, subject: Node3D, additional_subject_offset := Vector3.ZERO) -> void:
	## 舊案例的單中心盒不足以遮住新 Vision 的所有表面射線；以視線中段平面與各射線交點包圍建屏。
	var origin := (observer.get_node("VisualRecoilPivot/TurretPivot") as Node3D).global_position
	var points: PackedVector3Array = subject.call("part_world_surface_points") as PackedVector3Array
	var stable_center := subject.call("stable_world_center") as Vector3
	points.append(stable_center)
	var normal := (stable_center - origin).normalized()
	var tangent_x := normal.cross(Vector3.UP).normalized()
	if tangent_x.is_zero_approx():
		tangent_x = normal.cross(Vector3.RIGHT).normalized()
	var tangent_y := normal.cross(tangent_x).normalized()
	var screen_center := origin.lerp(stable_center, 0.5)
	var screen_depth := normal.dot(screen_center - origin)
	var half_width := 0.0
	var half_height := 0.0
	for point in points:
		var candidate_points := PackedVector3Array([point, point + additional_subject_offset])
		for candidate in candidate_points:
			var ray := candidate - origin
			var denominator := normal.dot(ray)
			assert(denominator > 0.0001, "Full visibility blocker requires every target point beyond its screen plane.")
			var intersection := origin + ray * (screen_depth / denominator)
			var offset := intersection - screen_center
			half_width = maxf(half_width, absf(offset.dot(tangent_x)))
			half_height = maxf(half_height, absf(offset.dot(tangent_y)))
	blocker.global_transform = Transform3D(Basis(tangent_x, tangent_y, normal), screen_center)
	var collision := blocker.get_node("CollisionShape3D") as CollisionShape3D
	## 只在射線法線方向保留 0.2m 厚度，避免世界軸 AABB 的長邊回頭接觸觀察車。
	(collision.shape as BoxShape3D).size = Vector3(half_width * 2.0 + 0.2, half_height * 2.0 + 0.2, 0.2)
	var overlap_query := PhysicsShapeQueryParameters3D.new()
	overlap_query.shape = collision.shape
	overlap_query.transform = blocker.global_transform
	overlap_query.collision_mask = 129
	overlap_query.exclude = [blocker.get_rid()]
	for overlap in observer.get_world_3d().direct_space_state.intersect_shape(overlap_query, 64):
		assert(overlap.get("collider") != observer, "Full visibility blocker must not overlap or push its observer fixture.")


func _make_blocker(position: Vector3, size: Vector3) -> StaticBody3D:
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	blocker.add_child(collision)
	blocker.position = position
	return blocker


func _wait_for_shots(shots: Array[ShotEvent], expected_shots: int, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if shots.size() >= expected_shots:
			return true
	return false


func _wait_for_frames(frame_count: int) -> bool:
	for _frame in frame_count:
		await physics_frame
	return true


func _wait_for_health_loss(health: HealthComponent, previous_health: float, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if health.current_health < previous_health:
			return true
	return false


func _finish(playtest: Node3D, message: String) -> void:
	Input.set_custom_mouse_cursor(null)
	playtest.queue_free()
	_fail(message)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
