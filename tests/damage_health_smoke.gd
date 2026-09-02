extends SceneTree

const HealthComponent := preload("res://src/combat/damage/health_component.gd")
const DamageReceiver := preload("res://src/combat/damage/damage_receiver.gd")
const ShotEvent := preload("res://src/combat/shot_event.gd")
const TRAINING_TARGET_SCENE := "res://src/world/training_ground/training_target.tscn"


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	if not await _validate_damage_components() or not await _validate_training_target():
		quit(1)
		return
	print("Damage and training target smoke validation passed.")
	quit(0)


func _validate_damage_components() -> bool:
	var host := Node.new()
	var health := HealthComponent.new()
	var receiver := DamageReceiver.new()
	host.add_child(health)
	host.add_child(receiver)
	receiver.set("health_component", health)
	root.add_child(host)
	await process_frame

	var depleted_count := [0]
	health.depleted.connect(func() -> void: depleted_count[0] += 1)
	if not is_equal_approx(health.maximum_health, 100.0) \
			or not is_equal_approx(health.current_health, 100.0):
		host.queue_free()
		return _fail("HealthComponent must initialize at its 100-point maximum.")
	if receiver.receive_damage(0.0) or receiver.receive_damage(-25.0):
		host.queue_free()
		return _fail("DamageReceiver must reject non-positive damage.")
	for index in range(4):
		if not receiver.receive_damage(25.0) \
				or not is_equal_approx(health.current_health, 75.0 - 25.0 * index):
			host.queue_free()
			return _fail("Four 25-point hits must reduce health from 100 to zero.")
	if depleted_count[0] != 1 or receiver.receive_damage(25.0):
		host.queue_free()
		return _fail("A depleted HealthComponent must notify once and reject further damage.")
	receiver.enabled = false
	health.reset_to_maximum()
	if receiver.receive_damage(25.0) or not is_equal_approx(health.current_health, 100.0):
		host.queue_free()
		return _fail("A disabled DamageReceiver must not change health.")
	host.queue_free()

	var shot := ShotEvent.new(Transform3D.IDENTITY, Vector3.RIGHT, RID(), 25.0)
	if not is_equal_approx(shot.damage, 25.0):
		return _fail("ShotEvent must preserve the damage snapshot supplied at fire time.")
	return true


func _validate_training_target() -> bool:
	var packed_scene := load(TRAINING_TARGET_SCENE) as PackedScene
	var target := packed_scene.instantiate() as Node3D if packed_scene != null else null
	if target == null:
		return _fail("TrainingTarget scene must load.")
	root.add_child(target)
	await process_frame
	var tank := target.get_node_or_null("SubjectSlot/Tank") as CharacterBody3D
	var health := target.get_node_or_null("SubjectSlot/Tank/HealthComponent") as HealthComponent
	var receiver := target.get_node_or_null("SubjectSlot/Tank/DamageReceiver") as DamageReceiver
	var label := target.get_node_or_null("HealthLabel3D") as Label3D
	var controller := target.get_node_or_null("TrainingTargetController")
	if tank == null or health == null or receiver == null or label == null or controller == null \
			or target.get_node_or_null("PlayerRuntime") != null:
		target.queue_free()
		return _fail("TrainingTarget must wrap one complete, uncontrolled Tank with health UI and controller.")
	if label.text != "100 / 100" or not is_equal_approx(float(controller.reset_delay_seconds), 3.0):
		target.queue_free()
		return _fail("TrainingTarget must begin at 100 / 100 and use a three-second reset delay.")
	controller.reset_delay_seconds = 0.01
	for index in range(4):
		receiver.receive_damage(25.0)
	if label.text != "0 / 100" or receiver.enabled:
		target.queue_free()
		return _fail("TrainingTarget must show zero and disable damage after the fourth hit.")
	if receiver.receive_damage(25.0) or not is_zero_approx(health.current_health):
		target.queue_free()
		return _fail("TrainingTarget must ignore damage while waiting to reset.")
	await create_timer(0.02).timeout
	await process_frame
	var reset_is_valid := label.text == "100 / 100" and receiver.enabled \
		and is_equal_approx(health.current_health, 100.0)
	target.queue_free()
	if not reset_is_valid:
		return _fail("TrainingTarget must restore only health and damage reception after its delay.")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
