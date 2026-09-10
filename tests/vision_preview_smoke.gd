extends SceneTree

## 水平視野預覽的有限黑箱 smoke。所有真值都由獨立的 PhysicsRayQuery
## 取得；測試絕不呼叫 Preview 的私有或可見性判斷邏輯。

const VisionPreview := preload("res://src/world/training_ground/vision_range_preview.gd")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const TANK2_SCENE := preload("res://src/actors/tank/variants/tank2/tank2.tscn")
const TANK1_SCENE := preload("res://src/actors/tank/variants/tank1/tank1.tscn")
const GROUND_MASK := 128
const OUTLINE_EPSILON := 0.35

var _fixture: Dictionary = {}
var _saved_max_physics_steps_per_frame := -1


func _init() -> void:
	if not await _run():
		quit(1)
		return
	print("Vision preview smoke validation passed.")
	quit(0)


func _run() -> bool:
	_saved_max_physics_steps_per_frame = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 1
	_fixture = await _make_fixture()
	if _fixture.is_empty():
		return false
	var ok := await _validate_s1_open_outline()
	if ok:
		ok = await _validate_s2_height_blockers()
	if ok:
		ok = await _validate_s3_live_updates_and_lifecycle()
	await _dispose()
	return ok


func _make_fixture() -> Dictionary:
	var holder := Node3D.new()
	holder.name = "HorizontalVisionPreviewFixture"
	root.add_child(holder)
	var ground := StaticBody3D.new()
	ground.collision_layer = GROUND_MASK
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(256.0, 0.2, 256.0)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	ground.position.y = -0.1
	holder.add_child(ground)
	var observer := TANK2_SCENE.instantiate() as CharacterBody3D
	if observer == null:
		return await _fixture_fail("Horizontal preview observer must instantiate.")
	observer.name = "Observer"
	observer.set("vision_near_radius", 12.0)
	observer.set("vision_far_radius", 40.0)
	observer.set("vision_field_of_view_degrees", 90.0)
	holder.add_child(observer)
	var vision := TankVision.new()
	vision.observer = observer
	holder.add_child(vision)
	var preview := VisionPreview.new() as MeshInstance3D
	preview.name = "Preview"
	preview.vision = vision
	holder.add_child(preview)
	await physics_frame
	observer.set_physics_process(false)
	if not _aim_turret(observer, Vector3(48.0, 0.0, 0.0)):
		return await _fixture_fail("Fixture observer must expose aim_turret_at().")
	if not await _next_update(preview, "initial horizontal outline"):
		return await _fixture_fail("Preview must complete one physics-frame update.")
	return {"holder": holder, "observer": observer, "vision": vision, "preview": preview}


func _validate_s1_open_outline() -> bool:
	var preview := _fixture.preview as MeshInstance3D
	if preview == null or not _has_schema(preview):
		return _fail("S1 preview must expose only the horizontal-outline public contract.")
	var snapshot := preview.published_snapshot as Dictionary
	var state := snapshot.get("observer_state", {}) as Dictionary
	if not _snapshot_is_valid(preview, snapshot):
		return _fail("S1 snapshot/outline/angle/distance arrays must be complete and finite.")
	var forward := state.get("forward", Vector3.ZERO) as Vector3
	var forward_angle := _angle_of(forward)
	## 固定四類：開放近圈、遠扇、扇外近圈、扇外遠距（至少離邊界 0.1 度）。
	for sample: Dictionary in [
		{"name": "open_near", "angle": _wrap_angle(forward_angle + PI), "expected": 12.0},
		{"name": "far_cone", "angle": forward_angle, "expected": 40.0},
		{"name": "outside_cone_near", "angle": _wrap_angle(forward_angle + PI * 0.5), "expected": 12.0},
		{"name": "outside_cone_far", "angle": _wrap_angle(forward_angle - PI * 0.5), "expected": 12.0},
	]:
		if not _assert_outline_matches_oracle(preview, String(sample.name), float(sample.angle), float(sample.expected)):
			return false
	var material := preview.material_override as ShaderMaterial
	if material == null or not is_equal_approx((material.get_shader_parameter("tint") as Color).a, 0.15):
		return _fail("S1 preview must keep exactly one alpha .15 tint layer.")
	return true


func _validate_s2_height_blockers() -> bool:
	var holder := _fixture.holder as Node3D
	var preview := _fixture.preview as MeshInstance3D
	var state := _state(preview)
	var origin := state.get("view_origin", Vector3.ZERO) as Vector3
	## 同一面牆：低牆明確低於 ray Y，高牆跨過 ray Y；先從近圈方向驗，
	## 再原地轉砲塔 180 度，讓同一面高牆落入遠扇。
	var near_angle := _wrap_angle(_angle_of(state.get("forward", Vector3.ZERO) as Vector3) + PI)
	var wall_direction := Vector3(cos(near_angle), 0.0, sin(near_angle))
	var wall_position := wall_direction * 8.0
	var low_wall := _wall(Vector3(wall_position.x, 0.75, wall_position.z), Vector3(8.0, 1.5, 8.0), "LowWall")
	holder.add_child(low_wall)
	if not await _next_update(preview, "low wall"):
		return false
	if not _assert_outline_matches_oracle(preview, "low_wall_passes", near_angle, _range_for_angle(_state(preview), near_angle)):
		return false
	low_wall.queue_free()
	await physics_frame
	var high_wall := _wall(Vector3(wall_position.x, origin.y, wall_position.z), Vector3(8.0, 6.0, 8.0), "HighWall")
	holder.add_child(high_wall)
	if not await _next_update(preview, "high wall"):
		return false
	if not _assert_ray_has_blocking_hit("S2 high wall near", origin, near_angle, _state(preview)):
		return false
	if not _assert_outline_matches_oracle(preview, "high_wall_cuts_near", near_angle, 0.0):
		return false
	## 遠扇也須由同一個高牆截斷。
	var turret := (_fixture.observer as CharacterBody3D).get_node_or_null("VisualRecoilPivot/TurretPivot") as Node3D
	if turret == null:
		return _fail("S2 fixture must retain the observer turret.")
	turret.rotate_y(PI)
	if not await _next_update(preview, "high wall far cone"):
		return false
	var far_state := _state(preview)
	if _range_for_angle(far_state, near_angle) <= float(far_state.get("near_radius", 0.0)):
		return _fail("S2 rotated fixture must place the same wall in the far cone.")
	if not _assert_ray_has_blocking_hit("S2 high wall far", origin, near_angle, far_state):
		return false
	if not _assert_outline_matches_oracle(preview, "high_wall_cuts_far", near_angle, 0.0):
		return false
	high_wall.queue_free()
	await physics_frame
	## 真車經既有死亡入口成為 wreck：同高度時仍遮擋；下移至低於視線則可越過。
	var wreck := TANK1_SCENE.instantiate() as CharacterBody3D
	if wreck == null:
		return _fail("S2 wreck fixture must instantiate a real tank.")
	wreck.name = "DeadTankWreck"
	wreck.position = Vector3(wall_position.x, 0.0, wall_position.z)
	holder.add_child(wreck)
	wreck.set_physics_process(false)
	await physics_frame
	var health := wreck.get_node_or_null("HealthComponent") as HealthComponent
	var receiver := wreck.get_node_or_null("DamageReceiver") as DamageReceiver
	if health == null or receiver == null or not receiver.receive_damage(health.current_health):
		return _fail("S2 wreck must pass through the real health/death entry point.")
	if not await _next_update(preview, "wreck at view height"):
		return false
	if not _assert_ray_has_blocking_hit("S2 wreck", origin, near_angle, _state(preview)):
		return false
	if not _assert_outline_matches_oracle(preview, "wreck_blocks_at_view_height", near_angle, 0.0):
		return false
	wreck.position.y = -10.0
	if not await _next_update(preview, "lowered wreck"):
		return false
	if not _assert_outline_matches_oracle(preview, "lowered_wreck_passes", near_angle, _range_for_angle(_state(preview), near_angle)):
		return false
	wreck.queue_free()
	await physics_frame
	return true


func _validate_s3_live_updates_and_lifecycle() -> bool:
	var holder := _fixture.holder as Node3D
	var preview := _fixture.preview as MeshInstance3D
	var observer := _fixture.observer as CharacterBody3D
	var initial := int(preview.completed_updates)
	## observer 本身只能排除自身：從 view origin 向近圈反向射線不得被 tank 自體截斷。
	var state := _state(preview)
	if not _assert_outline_matches_oracle(preview, "observer_self_exclusion", _wrap_angle(_angle_of(state.forward as Vector3) + PI), 12.0):
		return false
	var player := TANK1_SCENE.instantiate() as CharacterBody3D
	if player == null:
		return _fail("S3 player blocker must instantiate.")
	player.name = "PlayerBlocker"
	player.position = Vector3(10.0, 0.0, 0.0)
	holder.add_child(player)
	player.set_physics_process(false)
	if not await _next_update(preview, "other player blocker"):
		return false
	if int(preview.completed_updates) != initial + 2:
		return _fail("S3 player blocker must produce exactly the next complete physics update.")
	if not _assert_outline_matches_oracle(preview, "other_player_is_not_excluded", 0.0, 0.0):
		return false
	var before_move := int(preview.completed_updates)
	player.position = Vector3(10.0, 0.0, 16.0)
	if not await _next_update(preview, "moved blocker"):
		return false
	if int(preview.completed_updates) != before_move + 2:
		return _fail("S3 moving a blocker must publish on the next complete physics update.")
	if not _assert_outline_matches_oracle(preview, "moved_blocker_reopens", 0.0, _range_for_angle(_state(preview), 0.0)):
		return false
	var before_turn := int(preview.completed_updates)
	if not _aim_turret(observer, Vector3(0.0, 0.0, 48.0)) or not await _next_update(preview, "turret turn"):
		return _fail("S3 turret turn must publish one next complete update.")
	var turned := preview.published_snapshot as Dictionary
	var turned_forward := ((turned.get("observer_state", {}) as Dictionary).get("forward", Vector3.ZERO) as Vector3)
	if int(preview.completed_updates) != before_turn + 2 \
			or turned_forward.is_equal_approx(state.get("forward", Vector3.ZERO) as Vector3):
		return _fail("S3 turret turn must publish its new observer pose.")
	var before_move_observer := int(preview.completed_updates)
	var before_origin := ((preview.published_snapshot as Dictionary).get("observer_state", {}) as Dictionary).get("view_origin", Vector3.ZERO) as Vector3
	observer.position = Vector3(2.0, 0.0, 0.0)
	if not await _next_update(preview, "observer move"):
		return false
	var moved_origin := (((preview.published_snapshot as Dictionary).get("observer_state", {}) as Dictionary).get("view_origin", Vector3.ZERO) as Vector3)
	if int(preview.completed_updates) != before_move_observer + 2 \
			or moved_origin.is_equal_approx(before_origin):
		return _fail("S3 observer move must publish its new capture pose.")
	preview.vision = null
	await physics_frame
	if preview.visible or preview.mesh != null or not preview.published_snapshot.is_empty() \
			or not preview.published_outline.is_empty() or not preview.published_angles.is_empty() \
			or not preview.published_distances.is_empty() or preview.last_update_ray_count != 0:
		return _fail("S3 invalid observer must hide and clear all public preview state.")
	preview.vision = _fixture.vision as Node
	if not await _next_update(preview, "restored observer"):
		return false
	var before_disabled := int(preview.completed_updates)
	var saved_snapshot := (preview.published_snapshot as Dictionary).duplicate(true)
	var saved_vision_observer: Node3D = (_fixture.vision as Node).get("observer") as Node3D
	preview.display_enabled = false
	await physics_frame
	if preview.visible or int(preview.completed_updates) != before_disabled \
			or preview.published_snapshot != saved_snapshot \
			or (_fixture.vision as Node).get("observer") != saved_vision_observer:
		return _fail("S3 disabled display must stop queries/hide without changing the AI/Vision observer binding.")
	preview.display_enabled = true
	player.queue_free()
	return true


func _assert_outline_matches_oracle(preview: MeshInstance3D, label: String, angle: float, expected_open_distance: float) -> bool:
	var state := _state(preview)
	var origin := state.get("view_origin", Vector3.ZERO) as Vector3
	var expected := _horizontal_oracle(origin, angle, _range_for_angle(state, angle), state)
	var actual := _distance_at_angle(preview, angle)
	if absf(actual - expected) > OUTLINE_EPSILON:
		return _fail("%s endpoint %.3f must match independent horizontal ray %.3f." % [label, actual, expected])
	if expected_open_distance > 0.0 and absf(expected - expected_open_distance) > OUTLINE_EPSILON:
		return _fail("%s fixture must be open to %.1fm, got %.3fm." % [label, expected_open_distance, expected])
	return true


func _horizontal_oracle(origin: Vector3, angle: float, limit: float, state: Dictionary) -> float:
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	var excludes: Array[RID] = []
	for item: Variant in state.get("exclude", []):
		if item is RID:
			excludes.append(item)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * limit,
		int(state.get("collision_mask", 129)), excludes)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	return origin.distance_to(hit.get("position", origin) as Vector3) if not hit.is_empty() else limit


func _assert_ray_has_blocking_hit(label: String, origin: Vector3, angle: float, state: Dictionary) -> bool:
	var limit := _range_for_angle(state, angle)
	var distance := _horizontal_oracle(origin, angle, limit, state)
	if distance >= limit - OUTLINE_EPSILON:
		return _fail("%s must have an actual horizontal physics-ray hit before its range limit." % label)
	return true


func _next_update(preview: MeshInstance3D, label: String) -> bool:
	## 允許一個 physics step 同步移動碰撞體；每一步本身仍必須完整發布一次。
	for step in 2:
		var before := int(preview.completed_updates)
		await physics_frame
		if int(preview.completed_updates) != before + 1:
			return _fail("%s step %d must publish exactly once; got %d -> %d." % [label, step, before, preview.completed_updates])
	return true


func _has_schema(preview: Object) -> bool:
	for wanted: StringName in [&"vision", &"display_enabled", &"tint", &"ground_height",
		&"published_snapshot", &"published_outline", &"published_angles", &"published_distances",
		&"completed_updates", &"last_update_elapsed_ms", &"last_update_ray_count", &"frame_work_times_ms"]:
		if not _has_property(preview, wanted):
			return false
	for removed: StringName in [&"reference_target", &"published_mask", &"completed_batches", &"last_batch_elapsed_ms", &"last_batch_ray_count"]:
		if _has_property(preview, removed):
			return false
	return true


func _snapshot_is_valid(preview: MeshInstance3D, snapshot: Dictionary) -> bool:
	var outline := preview.published_outline as PackedVector3Array
	var angles := preview.published_angles as PackedFloat64Array
	var distances := preview.published_distances as PackedFloat64Array
	if not snapshot.has("observer_instance_id") or not snapshot.has("observer_state") or not snapshot.has("origin") \
			or not (snapshot.get("origin") is Vector3) \
			or outline.size() < 3 or outline.size() != angles.size() or angles.size() != distances.size() \
			or preview.last_update_ray_count <= 0 or preview.last_update_ray_count > 2048 \
			or (preview.frame_work_times_ms as Array).size() > 240:
		return false
	var previous := -1.0
	for index in angles.size():
		if not is_finite(angles[index]) or angles[index] < 0.0 or angles[index] >= TAU \
				or angles[index] < previous or not is_finite(distances[index]) or distances[index] <= 0.0 \
				or not is_finite(outline[index].x) or not is_finite(outline[index].y) or not is_finite(outline[index].z):
			return false
		previous = angles[index]
	return true


func _state(preview: MeshInstance3D) -> Dictionary:
	return (preview.published_snapshot as Dictionary).get("observer_state", {}) as Dictionary


func _distance_at_angle(preview: MeshInstance3D, angle: float) -> float:
	var angles := preview.published_angles as PackedFloat64Array
	var distances := preview.published_distances as PackedFloat64Array
	var best_index := -1
	var best_delta := INF
	for index in angles.size():
		var delta := absf(_wrap_signed(float(angles[index]) - angle))
		if delta < best_delta:
			best_delta = delta
			best_index = index
	if best_index < 0 or best_delta > deg_to_rad(0.26):
		return NAN
	return float(distances[best_index])


func _max_radius(state: Dictionary) -> float:
	return maxf(float(state.get("near_radius", 0.0)), float(state.get("far_radius", 0.0)))


func _range_for_angle(state: Dictionary, angle: float) -> float:
	var near_radius := float(state.get("near_radius", 0.0))
	var far_radius := float(state.get("far_radius", 0.0))
	var forward := state.get("forward", Vector3.ZERO) as Vector3
	var half_fov := deg_to_rad(float(state.get("far_field_of_view_degrees", 0.0)) * 0.5)
	return far_radius if absf(_wrap_signed(angle - _angle_of(forward))) <= half_fov else near_radius


func _angle_of(direction: Vector3) -> float:
	return _wrap_angle(atan2(direction.z, direction.x))


func _wrap_angle(angle: float) -> float:
	return fposmod(angle, TAU)


func _wrap_signed(angle: float) -> float:
	return fposmod(angle + PI, TAU) - PI


func _aim_turret(tank: CharacterBody3D, target: Vector3) -> bool:
	if not tank.has_method(&"aim_turret_at"):
		return false
	tank.call("aim_turret_at", target, 1000.0)
	return true


func _wall(position: Vector3, size: Vector3, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	return body


func _has_property(object: Object, wanted: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if property.name == wanted:
			return true
	return false


func _fixture_fail(message: String) -> Dictionary:
	_fail(message)
	await _dispose()
	return {}


func _dispose() -> void:
	var holder := _fixture.get("holder") as Node3D
	if is_instance_valid(holder):
		holder.queue_free()
		await physics_frame
	_fixture.clear()
	if _saved_max_physics_steps_per_frame >= 0:
		Engine.max_physics_steps_per_frame = _saved_max_physics_steps_per_frame
		_saved_max_physics_steps_per_frame = -1


func _fail(message: String) -> bool:
	push_error(message)
	print("FAIL: ", message)
	return false
