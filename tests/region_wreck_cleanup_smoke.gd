extends SceneTree

## Task 5 fixed matrix: Z1–Z4 use authored scenes and live TankController fixtures.
## This smoke intentionally observes Area3D physics overlap and public tank components;
## it never calls WreckCleanupRule internals to prove the rule.
const ZONE_SCENE := "res://src/world/regions/wreck_cleanup_zone.tscn"
const VOLUME_SCENE := "res://src/world/regions/region_volume.tscn"
const TANK1_SCENE := "res://src/actors/tank/variants/tank1/tank1.tscn"
const TANK2_SCENE := "res://src/actors/tank/variants/tank2/tank2.tscn"
const TANK3_SCENE := "res://src/actors/tank/variants/tank3/tank3.tscn"
const TANK4_SCENE := "res://src/actors/tank/variants/tank4/tank4.tscn"
const PLAYTEST_SCENE := "res://src/world/training_ground/training_ground_playtest.tscn"
const HealthComponent := preload("res://src/combat/damage/health_component.gd")
const TankController := preload("res://src/actors/tank/tank_controller.gd")


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	Input.set_custom_mouse_cursor(null)
	if not await _validate_z1_volume_contract():
		return
	if not await _validate_z2_and_z4_overlap_cleanup():
		return
	if not await _validate_z3_continuous_life_transition():
		return
	if not await _validate_authored_training_zone():
		return
	print("Region wreck cleanup smoke validation passed.")
	quit(0)


func _validate_z1_volume_contract() -> bool:
	var packed := load(VOLUME_SCENE) as PackedScene
	var volume := packed.instantiate() as Area3D if packed != null else null
	if volume == null:
		return _fail("Z1 requires RegionVolume to be an instantiable Area3D.")
	root.add_child(volume)
	var collision := volume.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var preview := volume.get_node_or_null("EditorPreview") as MeshInstance3D
	if collision == null or not collision.shape is BoxShape3D or preview == null or not preview.mesh is BoxMesh \
			or not volume.has_method("get") or not (volume.get("size") is Vector3) \
			or not (volume.get("size") as Vector3).is_equal_approx(Vector3(24, 8, 24)) \
			or volume.collision_layer != 0 or volume.collision_mask != 1 or not volume.monitoring:
		volume.queue_free()
		return _fail("Z1 RegionVolume requires Area3D mask=1/layer=0, default 24×8×24 size, Box collision, and editor preview.")
	volume.set("size", Vector3(10, 6, 14))
	await physics_frame
	var box := collision.shape as BoxShape3D
	var mesh := preview.mesh as BoxMesh
	if not box.size.is_equal_approx(Vector3(10, 6, 14)) or not mesh.size.is_equal_approx(Vector3(10, 6, 14)) \
			or preview.visible:
		volume.queue_free()
		return _fail("Z1 runtime RegionVolume must keep box/preview dimensions synchronized from size and hide green preview.")
	var live_tank := await _spawn_tank(root, TANK1_SCENE, Vector3.ZERO)
	if live_tank == null:
		volume.queue_free()
		return _fail("Z1 requires a complete live TankController fixture.")
	await physics_frame
	if not volume.get_overlapping_bodies().has(live_tank) or not is_instance_valid(live_tank):
		return await _cleanup_and_fail([volume, live_tank], "Z1 a live tank must physically enter and remain able to pass through the Area3D.")
	live_tank.global_position = Vector3(30, 0, 0)
	await physics_frame
	if not is_instance_valid(live_tank):
		return await _cleanup_and_fail([volume, live_tank], "Z1 must never remove a live tank merely for crossing the zone.")
	return await _cleanup([volume, live_tank])


func _validate_z2_and_z4_overlap_cleanup() -> bool:
	var fixture := Node3D.new()
	fixture.name = "ZoneCleanupFixture"
	root.add_child(fixture)
	var zone_a := await _spawn_zone(fixture, Vector3.ZERO)
	var zone_b := await _spawn_zone(fixture, Vector3(80, 0, 0))
	if zone_a == null or zone_b == null:
		return await _cleanup_and_fail([fixture], "Z4 requires two independent WreckCleanupZone instances, not a global singleton.")
	var tanks: Array[Node] = []
	for entry in [[TANK1_SCENE, Vector3.ZERO], [TANK2_SCENE, Vector3(2, 0, 2)], [TANK3_SCENE, Vector3(10.5, 0, 0)], [TANK4_SCENE, Vector3(80, 0, 0)]]:
		var tank := await _spawn_tank(fixture, entry[0] as String, entry[1] as Vector3)
		if tank == null:
			return await _cleanup_and_fail([fixture], "Z2 requires four complete TankController fixtures.")
		tanks.append(tank)
	var outside_corpse := await _spawn_tank(fixture, TANK1_SCENE, Vector3(40, 0, 0))
	## 這台與區域相交、也是真殘骸，但不屬 Rule.scene_root；不得被跨場景掃除。
	var foreign_root := Node3D.new()
	root.add_child(foreign_root)
	var foreign_corpse := await _spawn_tank(foreign_root, TANK2_SCENE, Vector3(1, 0, -4))
	var non_tank := StaticBody3D.new()
	fixture.add_child(non_tank)
	non_tank.global_position = Vector3.ZERO
	var non_tank_shape := CollisionShape3D.new()
	var non_tank_box := BoxShape3D.new()
	non_tank_box.size = Vector3.ONE
	non_tank_shape.shape = non_tank_box
	non_tank.add_child(non_tank_shape)
	if outside_corpse == null or foreign_corpse == null:
		return await _cleanup_and_fail([fixture, foreign_root], "Z2 requires nearby and foreign-scene corpse fixtures.")
	## 先以存活實例讀原生 Area3D overlap；Rule 不會刪活車，故可安全證明部位而非中心相交。
	await physics_frame
	## Tank3 centre remains outside the 24m box, but one collision part crosses its +X edge.
	var area_a := zone_a.get_node_or_null("RegionVolume") as Area3D
	var area_b := zone_b.get_node_or_null("RegionVolume") as Area3D
	if area_a == null or area_b == null or not area_a.get_overlapping_bodies().has(tanks[2]) \
			or not area_b.get_overlapping_bodies().has(tanks[3]):
		return await _cleanup_and_fail([fixture, foreign_root], "Z2 requires a collision-part-only overlap; centre position alone is not acceptable.")
	for index in tanks.size():
		if not _deplete(tanks[index] as Node, index == 0):
			return await _cleanup_and_fail([fixture], "Z2 must kill fixtures through HealthComponent/DamageReceiver public damage entry points.")
	if not _deplete(outside_corpse, false):
		return await _cleanup_and_fail([fixture], "Z2 requires a real dead corpse outside the zone.")
	if not _deplete(foreign_corpse, false):
		return await _cleanup_and_fail([fixture, foreign_root], "Z2 requires a real overlapping corpse outside Rule.scene_root.")
	if not await _wait_freed(tanks, 12):
		return await _cleanup_and_fail([fixture], "Z2/Z4 must queue-free every dead TankController overlapping either zone on physics updates.")
	if not is_instance_valid(outside_corpse) or not is_instance_valid(foreign_corpse) or not is_instance_valid(non_tank):
		return await _cleanup_and_fail([fixture, foreign_root], "Z2/Z4 must preserve outside, foreign-scene, and non-tank objects.")
	return await _cleanup([fixture, foreign_root])


func _validate_z3_continuous_life_transition() -> bool:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var in_zone_then_dead := await _spawn_tank(fixture, TANK1_SCENE, Vector3.ZERO)
	var dead_then_moved := await _spawn_tank(fixture, TANK2_SCENE, Vector3(50, 0, 0))
	var already_dead := await _spawn_tank(fixture, TANK3_SCENE, Vector3(30, 0, 0))
	if in_zone_then_dead == null or dead_then_moved == null or already_dead == null or not _deplete(already_dead, false):
		return await _cleanup_and_fail([fixture], "Z3 requires live and pre-dead complete tank fixtures.")
	## 建立區域前殘骸已在預定位置：驗原生 overlap 起始狀態，不依賴 body_entered。
	var initial_zone := await _spawn_zone(fixture, Vector3(30, 0, 0))
	var zone := await _spawn_zone(fixture, Vector3.ZERO)
	if initial_zone == null or zone == null:
		return await _cleanup_and_fail([fixture], "Z3 requires zones for both already-overlapping and continuous cases.")
	if not await _wait_freed([already_dead], 8):
		return await _cleanup_and_fail([fixture], "Z3 must clear a corpse already inside when the zone begins processing.")
	await physics_frame
	if not is_instance_valid(in_zone_then_dead) or not _deplete(in_zone_then_dead, true):
		return await _cleanup_and_fail([fixture], "Z3 live-in-zone tank must survive until its real health depletion.")
	if not await _wait_freed([in_zone_then_dead], 8):
		return await _cleanup_and_fail([fixture], "Z3 must clear a tank that entered alive and later died without a new enter event.")
	if not _deplete(dead_then_moved, false):
		return await _cleanup_and_fail([fixture], "Z3 requires a real corpse before it moves into the area.")
	dead_then_moved.global_position = Vector3.ZERO
	await physics_frame
	if not await _wait_freed([dead_then_moved], 8):
		return await _cleanup_and_fail([fixture], "Z3 must clear an already-dead corpse after it moves into the area.")
	return await _cleanup([fixture])


func _validate_authored_training_zone() -> bool:
	var packed := load(PLAYTEST_SCENE) as PackedScene
	var playtest := packed.instantiate() as Node3D if packed != null else null
	if playtest == null:
		return _fail("Z1/Z5 authored verification requires training_ground_playtest.")
	root.add_child(playtest)
	var zone := playtest.get_node_or_null("PlayerSpawnPoint/WreckCleanupZone") as Node3D
	var area := zone.get_node_or_null("RegionVolume") as Area3D if zone != null else null
	var rule := zone.get_node_or_null("WreckCleanupRule") as Node if zone != null else null
	if zone == null or area == null or rule == null or not (area.get("size") as Vector3).is_equal_approx(Vector3(24, 8, 24)) \
			or not is_equal_approx(area.position.y, 4.0) or rule.get("area") != area or rule.get("scene_root") != playtest:
		return await _cleanup_and_fail([playtest], "Z1 authored WreckCleanupZone must place RegionVolume at local Y=4 and bind its own Area3D plus playtest root.")
	return await _cleanup([playtest])


func _spawn_zone(parent: Node3D, position: Vector3) -> Node3D:
	var packed := load(ZONE_SCENE) as PackedScene
	var zone := packed.instantiate() as Node3D if packed != null else null
	if zone == null:
		return null
	parent.add_child(zone)
	zone.global_position = position
	var rule := zone.get_node_or_null("WreckCleanupRule") as Node
	if rule != null:
		rule.set("scene_root", parent)
	await physics_frame
	return zone


func _spawn_tank(parent: Node, scene_path: String, position: Vector3) -> Node3D:
	var packed := load(scene_path) as PackedScene
	var tank := packed.instantiate() as Node3D if packed != null else null
	if tank == null or not tank is TankController:
		return null
	parent.add_child(tank)
	tank.global_position = position
	await physics_frame
	return tank


func _deplete(tank: Node, through_receiver: bool) -> bool:
	var health := tank.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return false
	if through_receiver:
		var receiver := tank.get_node_or_null("DamageReceiver") as Node
		return receiver != null and bool(receiver.call("receive_damage", health.current_health))
	return health.apply_damage(health.current_health)


func _wait_freed(nodes: Array, limit: int) -> bool:
	for _step in limit:
		await physics_frame
		await process_frame
		var all_freed := true
		for node in nodes:
			if is_instance_valid(node):
				all_freed = false
				break
		if all_freed:
			return true
	return false


func _cleanup(nodes: Array) -> bool:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	return true


func _cleanup_and_fail(nodes: Array, message: String) -> bool:
	await _cleanup(nodes)
	return _fail(message)


func _fail(message: String) -> bool:
	Input.set_custom_mouse_cursor(null)
	push_error(message)
	quit(1)
	return false
