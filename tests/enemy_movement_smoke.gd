## LEA-175：四車真實 physics 移動 smoke。
## 這份檔案的 open/search/blocked cases 都使用正式 Tank、TankVision、TankCombatAI
## 與 NavigationRegion3D；只有 A9 的 no_path/partial_end 狀態分支直接呼叫導航元件，
## 並在案例名稱明確標記為「命令注入」，不把它當成四車可駕駛的證據。
extends SceneTree

const TankCombatAI := preload("res://src/ai/tank_combat_ai.gd")
const TankVision := preload("res://src/actors/tank/perception/tank_vision.gd")
const TankNavigation := preload("res://src/ai/tank_navigation.gd")
const TANK_SCENES: Array[PackedScene] = [
	preload("res://src/actors/tank/variants/tank1/tank1.tscn"),
	preload("res://src/actors/tank/variants/tank2/tank2.tscn"),
	preload("res://src/actors/tank/variants/tank3/tank3.tscn"),
	preload("res://src/actors/tank/variants/tank4/tank4.tscn"),
]
const DT := 1.0 / 60.0
const STOP_DISTANCE := 40.0
const RESUME_DISTANCE := 55.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _a1_four_tanks_drive_to_stop_and_face():
		return
	if not await _a2_a3_hysteresis_and_no_reverse():
		return
	if not await _a4_moving_can_fire_hidden_cannot():
		return
	if not await _a5_a6_search_fixed_last_seen_and_wait():
		return
	if not await _a7_a11_interruptions_and_lifecycle_clear():
		return
	if not await _a11_controlled_tank_replacement_clears_old_state():
		return
	if not await _a9_terminal_navigation_and_stuck():
		return
	print("LEA-175 movement smoke passed: A1/A2/A3/A4/A5/A6/A7/A9/A11; A8 in navigation smoke, A12 in full regression.")
	quit(0)


## A1：四個正式車型皆從 80m 走到 40±1m，停止後車頭朝敵 <=5 度。
func _a1_four_tanks_drive_to_stop_and_face() -> bool:
	for index in TANK_SCENES.size():
		var fixture := await _make_fixture(index, Vector3(-80, 0, 0))
		if fixture.is_empty():
			return _fail("A1 Tank%d fixture failed." % (index + 1))
		var tank := fixture.tank as CharacterBody3D
		var target := fixture.target as CharacterBody3D
		var ai := fixture.ai as Node
		var saw_moving := false
		for frame in 1800:
			await _tick(ai)
			saw_moving = saw_moving or ai.get("movement_status") == &"moving"
			if ai.get("movement_status") in [&"holding", &"arrived"] \
					and absf(_horizontal_distance(tank.call("stable_world_center"), target.call("stable_world_center")) - STOP_DISTANCE) <= 1.0 \
					and absf(tank.actual_linear_speed) <= 0.1:
				break
		if not saw_moving:
			return await _dispose_fail(fixture, "A1 Tank%d must enter moving on its true NavigationRegion3D path." % (index + 1))
		var distance := _horizontal_distance(tank.call("stable_world_center"), target.call("stable_world_center"))
		if absf(distance - STOP_DISTANCE) > 1.0 or _facing_error(tank, target.call("stable_world_center")) > deg_to_rad(5.0):
			return await _dispose_fail(fixture, "A1 Tank%d stopped distance=%.2f / facing=%.2fdeg; expected 40±1m and <=5deg." % [index + 1, distance, rad_to_deg(_facing_error(tank, target.call("stable_world_center")))])
		var settled_position := tank.global_position
		for unused in 60:
			await _tick(ai)
			if absf(tank.actual_linear_speed) > 0.1 or tank.global_position.distance_to(settled_position) > 0.1:
				return await _dispose_fail(fixture, "A1 Tank%d must remain stopped for one second after reaching its stop distance." % (index + 1))
		await _dispose(fixture)
	return true


## A2/A3：首次 47/55m 停，56m 才追；已追近須到 40m 才停，近距不能倒車。
func _a2_a3_hysteresis_and_no_reverse() -> bool:
	var fixture := await _make_fixture(1, Vector3(-47, 0, 0))
	if fixture.is_empty():
		return _fail("A2 fixture failed.")
	var tank := fixture.tank as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var ai := fixture.ai as Node
	for label_distance in [47.0, 55.0]:
		target.global_position = Vector3(-label_distance, 0, 0)
		for unused in 90:
			await _tick(ai)
		if ai.get("movement_status") != &"holding" or not is_zero_approx(tank.movement_command):
			return await _dispose_fail(fixture, "A2 first visible %.0fm must hold, not pursue." % label_distance)
	target.global_position = Vector3(-56, 0, 0)
	var saw_moving := false
	for unused in 240:
		await _tick(ai)
		saw_moving = saw_moving or ai.get("movement_status") == &"moving"
	if not saw_moving:
		return await _dispose_fail(fixture, "A2 56m must resume pursuit.")
	target.global_position = tank.call("stable_world_center") + Vector3(-47, 0, 0)
	for unused in 3:
		await _tick(ai)
	if _horizontal_distance(tank.call("stable_world_center"), target.call("stable_world_center")) <= STOP_DISTANCE \
			or ai.get("movement_status") != &"moving":
		return await _dispose_fail(fixture, "A2 already-pursuing 47m target must keep pursuing until stop distance.")
	target.global_position = tank.call("stable_world_center") + Vector3(-30, 0, 0)
	for unused in 90:
		await _tick(ai)
		if tank.movement_command < -0.0001:
			return await _dispose_fail(fixture, "A3 target inside 40m must never submit reverse movement.")
	if not is_zero_approx(tank.movement_command):
		return await _dispose_fail(fixture, "A3 target inside 40m must stop rather than reverse.")
	await _dispose(fixture)
	return true


## A4：移動中仍可經既有真實射擊 gate 開火；遮擋／失視各自維持零 shots。
func _a4_moving_can_fire_hidden_cannot() -> bool:
	for model in [0, 1]:
		if not await _a4_moving_fire_variant(model):
			return false
	return true


func _a4_moving_fire_variant(model: int) -> bool:
	var fixture := await _make_fixture(model, Vector3(-80, 0, 0))
	if fixture.is_empty():
		return _fail("A4 fixture failed.")
	var tank := fixture.tank as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var ai := fixture.ai as Node
	tank.set("aim_spread_base_degrees", 0.0)
	tank.set("aim_spread_cap_degrees", 0.0)
	var shots: Array = []
	## Lambda 對純量是值捕捉；以陣列保存訊號當下證據，避免外層計數永遠為0。
	var moving_shots: Array = []
	tank.shot_event_fired.connect(func(event) -> void:
		shots.append(event)
		if ai.get("movement_status") == &"moving" and absf(tank.actual_linear_speed) > 0.1:
			moving_shots.append(event)
	)
	for unused in 720:
		await _tick(ai)
		if not moving_shots.is_empty():
			break
	if moving_shots.is_empty():
		return await _dispose_fail(fixture, "A4 visible moving tank must emit a real ShotEvent when existing gate aligns.")
	var blocker := _blocker_between(tank, target)
	fixture.root.add_child(blocker)
	await physics_frame
	var before_blocked := shots.size()
	for unused in 120:
		await _tick(ai)
	if shots.size() != before_blocked:
		return await _dispose_fail(fixture, "A4 physical muzzle blocker must emit zero additional shots.")
	blocker.queue_free()
	await physics_frame
	tank.set("vision_near_radius", 0.0)
	tank.set("vision_far_radius", 0.0)
	var before_hidden := shots.size()
	for unused in 120:
		await _tick(ai)
	if shots.size() != before_hidden:
		return await _dispose_fail(fixture, "A4 hidden target must emit zero additional shots.")
	await _dispose(fixture)
	return true


## A5/A6：失視後只走最後目擊點，不追隱藏玩家的新位置；3m 內抵達後至少等 5 秒。
func _a5_a6_search_fixed_last_seen_and_wait() -> bool:
	var fixture := await _make_fixture(1, Vector3(-60, 0, 0))
	if fixture.is_empty():
		return _fail("A5 fixture failed.")
	var tank := fixture.tank as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var ai := fixture.ai as Node
	for unused in 30:
		await _tick(ai)
	var remembered := target.call("stable_world_center") as Vector3
	tank.set("vision_near_radius", 0.0)
	tank.set("vision_far_radius", 0.0)
	target.global_position = Vector3(70, 0, 70)
	var nearest := INF
	for unused in 1200:
		await _tick(ai)
		nearest = minf(nearest, _horizontal_distance(tank.call("stable_world_center"), remembered))
		if ai.get("movement_status") == &"arrived":
			break
	if nearest > 3.0 or ai.get("movement_status") != &"arrived":
		return await _dispose_fail(fixture, "A5/A6 must reach remembered world point within 3m, not hidden target's moved position.")
	var arrived_position := tank.global_position
	for unused in 300: # 5 seconds at 60Hz
		await _tick(ai)
		if ai.get("movement_status") != &"arrived" or tank.global_position.distance_to(arrived_position) > 0.1:
			return await _dispose_fail(fixture, "A6 reached search point must wait at least 5 seconds without restarting.")
	await _dispose(fixture)
	return true


## A7/A11：受擊查看取消搜索；重見改回可見目標；停用、死亡、換目標清舊命令。
func _a7_a11_interruptions_and_lifecycle_clear() -> bool:
	var fixture := await _make_fixture(1, Vector3(-60, 0, 0))
	if fixture.is_empty():
		return _fail("A7 fixture failed.")
	var tank := fixture.tank as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var ai := fixture.ai as Node
	for unused in 30:
		await _tick(ai)
	tank.set("vision_near_radius", 0.0)
	tank.set("vision_far_radius", 0.0)
	for unused in 30:
		await _tick(ai)
	ai.call("inspect_hit_position", tank.global_position + Vector3(0, 0, 30))
	await _tick(ai)
	if ai.get("movement_status") != &"inspection" or not is_zero_approx(tank.movement_command):
		return await _dispose_fail(fixture, "A7 valid hit inspection must cancel search and stop movement.")
	tank.set("vision_near_radius", 50.0)
	tank.set("vision_far_radius", 150.0)
	target.global_position = tank.global_position + Vector3(-80, 0, 0)
	for unused in 120:
		await _tick(ai)
	if ai.get("movement_status") != &"moving":
		return await _dispose_fail(fixture, "A7 reacquiring a visible 80m target must replace inspection/search with pursuit.")
	for mode in [&"disabled", &"target_null", &"target_dead", &"replacement", &"observer_dead"]:
		if mode == &"disabled":
			ai.call("set_combat_enabled", false)
		elif mode == &"target_null":
			ai.call("set_target", null)
		elif mode == &"target_dead":
			(target.get_node("HealthComponent") as Node).call("apply_damage", 100000.0)
		elif mode == &"replacement":
			var replacement := TANK_SCENES[2].instantiate() as CharacterBody3D
			replacement.position = tank.global_position + Vector3(-80, 0, 0)
			fixture.root.add_child(replacement)
			await physics_frame
			ai.call("set_target", replacement)
			if not is_zero_approx(tank.movement_command) or not is_zero_approx(tank.turn_command) or ai.get("movement_status") != &"idle":
				return await _dispose_fail(fixture, "A11 replacement must synchronously clear the old movement and route state before new targeting.")
			continue
		else:
			(tank.get_node("HealthComponent") as Node).call("apply_damage", 100000.0)
		await _tick(ai)
		if not is_zero_approx(tank.movement_command) or not is_zero_approx(tank.turn_command) or ai.get("movement_status") != &"idle":
			return await _dispose_fail(fixture, "A11 %s must clear old movement and route state." % mode)
		if mode == &"disabled":
			ai.call("set_combat_enabled", true)
		elif mode == &"target_null":
			ai.call("set_target", target)
	await _dispose(fixture)
	return true


## A11：這不是 set_target；換掉 AI 實際控制的車時，舊車的命令與記憶不能殘留。
func _a11_controlled_tank_replacement_clears_old_state() -> bool:
	var fixture := await _make_fixture(1, Vector3(-80, 0, 0))
	if fixture.is_empty():
		return _fail("A11 controlled-tank replacement fixture failed.")
	var old_tank := fixture.tank as CharacterBody3D
	var target := fixture.target as CharacterBody3D
	var vision := fixture.vision as Node
	var ai := fixture.ai as Node
	var saw_old_navigation := false
	for unused in 180:
		await _tick(ai)
		saw_old_navigation = saw_old_navigation or ai.get("movement_status") == &"moving"
	if not saw_old_navigation:
		return await _dispose_fail(fixture, "A11 setup requires old controlled tank to have real visible-target navigation state.")
	var replacement := TANK_SCENES[2].instantiate() as CharacterBody3D
	if replacement == null:
		return await _dispose_fail(fixture, "A11 controlled-tank replacement must instantiate a formal tank variant.")
	## root identity makes this the same world origin; add first so the replacement runs its normal ready wiring.
	replacement.position = Vector3.ZERO
	fixture.root.add_child(replacement)
	await physics_frame
	## 明確留下舊車非零命令，驗 controlled_tank setter 是否同步清除，不靠下一物理步補救。
	old_tank.set_movement_input(1.0)
	old_tank.set_turn_input(1.0)
	if is_zero_approx(old_tank.movement_command) or is_zero_approx(old_tank.turn_command):
		return await _dispose_fail(fixture, "A11 setup requires non-zero old tank movement and turn commands.")
	ai.set("controlled_tank", replacement)
	vision.set("observer", replacement)
	if not is_zero_approx(old_tank.movement_command) or not is_zero_approx(old_tank.turn_command) \
			or ai.get("movement_status") != &"idle":
		return await _dispose_fail(fixture, "A11 controlled-tank replacement must synchronously clear old commands and set AI idle.")
	## 看不見時不得重新使用舊車記憶／導航；這是對清除 last-seen state 的可觀察驗證。
	replacement.set("vision_near_radius", 0.0)
	replacement.set("vision_far_radius", 0.0)
	await _tick(ai)
	if ai.get("movement_status") != &"idle" or not is_zero_approx(replacement.movement_command):
		return await _dispose_fail(fixture, "A11 replacement with hidden target must not resume old last-seen navigation.")
	## observer 重綁後，同一個正式新車仍要能依目前目標正常運作。
	replacement.set("vision_near_radius", 50.0)
	replacement.set("vision_far_radius", 150.0)
	target.global_position = Vector3(-80, 0, 0)
	var replacement_operates := false
	for unused in 180:
		await _tick(ai)
		replacement_operates = replacement_operates or (ai.get("movement_status") == &"moving" and replacement.movement_command > 0.0)
	if not replacement_operates:
		return await _dispose_fail(fixture, "A11 rebound vision observer and replacement controlled tank must pursue the current visible target.")
	await _dispose(fixture)
	return true


## A9：直接導航命令注入只驗 terminal decision branches；其餘案例才是四車真 physics。
func _a9_terminal_navigation_and_stuck() -> bool:
	var fixture := await _make_fixture(1, Vector3(-80, 0, 0))
	if fixture.is_empty():
		return _fail("A9 fixture failed.")
	var tank := fixture.tank as CharacterBody3D
	var navigation := TankNavigation.new()
	navigation.setup(tank)
	for unused in 4:
		await physics_frame
	## 邊界外目標仍可能有部分路線，不能在尚未行進前要求它已在末端。
	## 完全無路案例明確移除本world唯一可走region，而非誤用遠目標。
	var region := fixture.root.get_child(0) as NavigationRegion3D
	region.enabled = false
	await physics_frame
	await physics_frame
	NavigationServer3D.map_force_update(tank.get_world_3d().navigation_map)
	var no_path: Dictionary = navigation.drive(Vector3(400, 0, 400), 91, 3.0, DT)
	if no_path.get("status", &"") != &"no_path":
		return await _dispose_fail(fixture, "A9 empty-map fixture must report no_path, got %s." % no_path.get("status", &""))
	navigation.dispose()
	region.enabled = true
	await physics_frame
	await physics_frame
	await _tick(fixture.ai)
	## 真牆受阻：先執行兩次有限倒車，第三次無進展才進入終端 stuck。
	var wall := _wall_at(Vector3(-12, 1.5, 0), Vector3(2, 4, 20))
	fixture.root.add_child(wall)
	await physics_frame
	var saw_stuck := false
	var reverse_attempts := 0
	var was_reversing := false
	var actually_reversed := false
	var previous_position := tank.global_position
	for unused in 1800:
		await _tick(fixture.ai)
		var reversing: bool = float(tank.movement_command) < -0.05
		if reversing and not was_reversing:
			reverse_attempts += 1
		actually_reversed = actually_reversed or (reversing and tank.global_position.x > previous_position.x + 0.001)
		was_reversing = reversing
		previous_position = tank.global_position
		saw_stuck = saw_stuck or fixture.ai.get("movement_status") == &"stuck"
		if saw_stuck:
			break
	print("A9_RECOVERY attempts=%d actual_reverse=%s final_status=%s" % [reverse_attempts, actually_reversed, fixture.ai.get("movement_status")])
	if not saw_stuck or reverse_attempts != 2 or not actually_reversed or not is_zero_approx(tank.movement_command) or not is_zero_approx(tank.turn_command):
		return await _dispose_fail(fixture, "A9 true collision fixture must make exactly two real reverse attempts, then stop as stuck with zero body commands.")
	var stopped := tank.global_position
	for unused in 300:
		await _tick(fixture.ai)
		if fixture.ai.get("movement_status") != &"stuck" or _horizontal_distance(stopped, tank.global_position) > 0.1:
			return await _dispose_fail(fixture, "A9 stopped blocked search must remain stopped for 5s, not restart the same route.")
	wall.queue_free()
	await _dispose(fixture)
	return true


func _make_fixture(model: int, target_position: Vector3) -> Dictionary:
	var fixture := Node3D.new()
	fixture.name = "EnemyMovementFixture"
	var region := _open_navigation_region()
	var tank := TANK_SCENES[model].instantiate() as CharacterBody3D
	var target := TANK_SCENES[2].instantiate() as CharacterBody3D
	var vision := TankVision.new()
	var ai := TankCombatAI.new()
	if tank == null or target == null:
		return {}
	## 尚未加入 fixture tree 前只能設定 local transform；global_* 會產生
	## !is_inside_tree() ERROR，且根節點是 identity，local 即是本案例世界座標。
	tank.position = Vector3.ZERO
	tank.rotation = Vector3.ZERO
	target.position = target_position
	target.set_physics_process(false)
	vision.observer = tank
	ai.controlled_tank = tank
	ai.vision = vision
	fixture.add_child(region)
	fixture.add_child(tank)
	fixture.add_child(target)
	fixture.add_child(vision)
	fixture.add_child(ai)
	root.add_child(fixture)
	ai.set_physics_process(false)
	ai.call("set_target", target)
	ai.call("set_combat_enabled", true)
	for unused in 4:
		await physics_frame
	return {"root": fixture, "tank": tank, "target": target, "vision": vision, "ai": ai}


func _open_navigation_region() -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-160, 0, -160), Vector3(160, 0, -160), Vector3(160, 0, 160), Vector3(-160, 0, 160)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	return region


func _tick(ai: Node) -> void:
	ai.call("_physics_process", DT)
	await physics_frame


func _blocker_between(tank: CharacterBody3D, target: CharacterBody3D) -> StaticBody3D:
	var muzzle := tank.call("muzzle_global_position") as Vector3
	return _wall_at(muzzle.lerp(target.call("stable_world_center") as Vector3, 0.4), Vector3(1.0, 3.0, 3.0))


func _wall_at(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	return body


func _horizontal_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x - right.x, left.z - right.z).length()


func _facing_error(tank: CharacterBody3D, position: Vector3) -> float:
	var forward := -tank.global_basis.x
	forward.y = 0.0
	var center := tank.call("stable_world_center") as Vector3
	var direction := position - center
	direction.y = 0.0
	return forward.normalized().angle_to(direction.normalized())


func _dispose(fixture: Dictionary) -> void:
	(fixture.root as Node).queue_free()
	await physics_frame


func _dispose_fail(fixture: Dictionary, message: String) -> bool:
	await _dispose(fixture)
	return _fail(message)


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
