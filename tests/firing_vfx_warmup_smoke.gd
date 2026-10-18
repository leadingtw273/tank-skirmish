## 驗四車型在預繪期間即可開砲、換車不重啟預繪，以及三幀後完整清除。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _next_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await process_frame
	else:
		await RenderingServer.frame_post_draw


func _run() -> void:
	for index in 4:
		var scene: Node3D = load("res://src/gameplay_runtime.tscn").instantiate()
		var vehicle_id := StringName("tank%d" % (index + 1))
		scene.startup_player_id = vehicle_id
		root.add_child(scene)
		current_scene = scene
		var runtime: Node = scene.get_node("CombatRuntime")
		var warmup: Node3D = runtime.get_node_or_null("FiringVfxWarmup")
		if warmup == null or warmup.get_child_count() != 4:
			_fail("Each startup must initialize exactly four shared firing FX wrappers.")
			return
		var warmup_ids: Array[int] = []
		for node in warmup.find_children("*", "Node", true, false):
			warmup_ids.append(node.get_instance_id())
			if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is Timer:
				_fail("Warmup must not create audio or timers.")
				return
		for frame in index % 3:
			await _next_frame()
		if index == 3:
			## 同一預繪生命週期內換車；預繪不應重新開始，也不應留下舊射擊來源。
			scene.replace_player_vehicle(&"tank1")
			scene.replace_player_vehicle(vehicle_id)
		if runtime.get_node_or_null("FiringVfxWarmup") != warmup:
			_fail("Changing the source must retain the existing bounded warmup.")
			return
		var player: Node3D = scene.get_node("PlayerRuntime").controlled_tank
		var controller: Node = scene.get_node("PlayerRuntime/PlayerController")
		if not controller.controls_enabled or runtime.get_registered_shot_sources() != [player] \
				or runtime.projectiles.get_child_count() != 0 or runtime.effects.get_child_count() != 0 \
				or not is_zero_approx(player.combat_tank._fire_cooldown_remaining) \
				or not player._pending_shots.is_empty() or player.recoil_application_count != 0:
			_fail("Warmup must preserve input, registration, cooldown and empty combat containers.")
			return
		var shots: Array = []
		player.shot_event_fired.connect(func(event): shots.append(event))
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		controller._unhandled_input(press)
		if shots.size() != 1 or runtime.projectiles.get_child_count() != 1 \
				or runtime.effects.get_child_count() != 1:
			_fail("The normal player controller must fire immediately during warmup for every variant.")
			return
		var flash: Node = player.combat_tank.muzzle_point.get_node_or_null("MuzzleFlash")
		if flash == null or not flash.visible \
				or not is_equal_approx(flash.global_basis.x.length(), player.combat_tank.muzzle_flash_scale):
			_fail("The real muzzle flash must retain its original visibility and variant scale.")
			return
		for frame in 4:
			await _next_frame()
		await process_frame
		if is_instance_valid(warmup) or runtime.get_child_count() != 2:
			_fail("Warmup must leave only the original combat containers after three frames.")
			return
		for id in warmup_ids:
			if is_instance_id_valid(id):
				_fail("Warmup must free all particles, meshes, lights, decals and animation players.")
				return
		scene.queue_free()
		await process_frame
	print("Firing VFX warmup smoke passed: four variants, immediate input, replacement and cleanup.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
