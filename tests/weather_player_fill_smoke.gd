## 主圖玩家補光的跟隨、換車、死亡與卸載；不替代視覺審查。
extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _expect(label: String, passed: bool) -> void:
	print("WEATHER_PLAYER_FILL ", label, " PASS" if passed else " FAIL")
	if not passed:
		failures.append(label)

func _frames(count: int) -> void:
	for unused: int in count:
		await physics_frame

func _run() -> void:
	var main := load("res://src/main.tscn").instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	var runtime := main.get_node("PlayerRuntime")
	runtime.call("set_controls_enabled", false)
	main.get_node("PlayerSpawnGroup/CameraRig").set_process(false)
	await _frames(180)
	var weather := main.get_node("World/MainWeather")
	var tank := runtime.get("controlled_tank") as Node3D
	var fill := weather.get("player_fill") as OmniLight3D
	_expect("alive-local-fill", is_instance_valid(fill) and fill.get_parent() == tank and fill.visible and not fill.shadow_enabled and fill.omni_range <= 8.0)
	var previous_position := fill.global_position
	tank.global_position += Vector3(3, 0, 2)
	_expect("follows-controlled-car", fill.global_position.distance_to(previous_position + Vector3(3, 0, 2)) < 0.001)
	var previous_light: WeakRef = weakref(fill)
	var next := main.call("replace_player_vehicle", &"tank1") as Node3D
	_expect("switch-hides-old-immediately", not fill.visible)
	await _frames(2)
	fill = weather.get("player_fill") as OmniLight3D
	_expect("switch-rebinds-once", previous_light.get_ref() == null and is_instance_valid(fill) and fill.get_parent() == next and fill.visible)
	var road_lights := 0
	var shadows := 0
	for lamp in weather.get("lamps"):
		road_lights += int(lamp.light.visible)
		shadows += int(lamp.light.shadow_enabled)
	_expect("six-roads-plus-one-no-new-shadow", weather.get("lamps").size() == 6 and road_lights <= 6 and shadows <= 2 and not fill.shadow_enabled)
	previous_light = weakref(fill)
	(next.get_node("HealthComponent") as HealthComponent).apply_damage(100000.0)
	_expect("death-hides-before-wreck-free", is_instance_valid(next) and not fill.visible and weather.get("player_fill") == null)
	await _frames(2)
	_expect("death-frees-light", previous_light.get_ref() == null)
	runtime.call("set_controlled_tank", null)
	runtime.call("set_controlled_tank", next)
	_expect("dead-car-never-relit", weather.get("player_fill") == null)
	next = main.call("replace_player_vehicle", &"tank2") as Node3D
	fill = weather.get("player_fill") as OmniLight3D
	_expect("replacement-alive-car-lit", is_instance_valid(fill) and fill.get_parent() == next)
	previous_light = weakref(fill)
	weather.queue_free()
	await _frames(2)
	_expect("map-unload-cleans-car-child", previous_light.get_ref() == null)
	main.queue_free()
	await _frames(2)
	print("WEATHER_PLAYER_FILL failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
