extends SceneTree

const HealthComponent := preload("res://src/combat/damage/health_component.gd")
const MAIN_SCENE := preload("res://src/main.tscn")
const DEFAULT_PLAYER_TANK_SCENE := "res://src/actors/tank/variants/tank2/tank2.tscn"

const VARIANTS := {
	"tank1": {
		"scene": "res://src/actors/tank/variants/tank1/tank1.tscn",
		"damage_visuals": &"Tank1DamageVisuals",
	},
	"tank2": {
		"scene": "res://src/actors/tank/variants/tank2/tank2.tscn",
		"damage_visuals": &"Tank2DamageVisuals",
	},
	"tank3": {
		"scene": "res://src/actors/tank/variants/tank3/tank3.tscn",
		"damage_visuals": &"Tank3DamageVisuals",
	},
	"tank4": {
		"scene": "res://src/actors/tank/variants/tank4/tank4.tscn",
		"damage_visuals": &"Tank4DamageVisuals",
	},
}
const TANK_PARAMETER_NAMES := [
	"movement_speed",
	"reverse_movement_speed",
	"turn_speed",
	"turning_movement_speed_ratio",
	"tank_mass_tonnes",
	"engine_horsepower",
	"brake_force_kilonewtons",
	"turn_response",
	"turret_turn_speed",
	"gun_pitch_speed",
	"shell_damage",
]


func _init() -> void:
	call_deferred("_validate")


func _validate() -> void:
	if not await _validate_default_player_tank():
		quit(1)
		return
	for tank_id: String in VARIANTS:
		if not await _validate_variant(tank_id, VARIANTS[tank_id]):
			quit(1)
			return
	print("Tank variant parameter smoke validation passed.")
	quit(0)


func _validate_default_player_tank() -> bool:
	var main := MAIN_SCENE.instantiate() as Node3D
	if main == null:
		return _fail("Main scene must load as a Node3D.")
	root.add_child(main)
	await process_frame
	await process_frame
	var player_tank := main.get_node_or_null("Tank") as CharacterBody3D
	var valid := player_tank != null and player_tank.scene_file_path == DEFAULT_PLAYER_TANK_SCENE
	main.queue_free()
	await process_frame
	if not valid:
		return _fail("Main scene must keep Tank2 as the default player tank.")
	return true


func _validate_variant(tank_id: String, contract: Dictionary) -> bool:
	var scene_path: String = contract.scene
	var source := FileAccess.get_file_as_string(scene_path)
	if source.is_empty():
		return _fail("%s variant scene source must be readable." % tank_id)
	for parameter_name: String in TANK_PARAMETER_NAMES:
		if not source.contains("\n%s =" % parameter_name):
			return _fail("%s must save a local %s override." % [tank_id, parameter_name])
	if not source.contains("\nmaximum_health ="):
		return _fail("%s must save a local maximum_health override." % tank_id)

	var packed_scene := load(scene_path) as PackedScene
	var tank := packed_scene.instantiate() as CharacterBody3D if packed_scene != null else null
	if tank == null:
		return _fail("%s variant must load as a CharacterBody3D." % tank_id)
	root.add_child(tank)
	await process_frame
	await process_frame
	var health := tank.get_node_or_null("HealthComponent") as HealthComponent
	var damage_visuals := tank.get_node_or_null(NodePath(contract.damage_visuals))
	if health == null or damage_visuals == null or not _has_legal_parameters(tank, health):
		tank.queue_free()
		await process_frame
		return _fail("%s must expose legal movement, aiming, health, and shell-damage values." % tank_id)

	var shots: Array = []
	tank.shot_event_fired.connect(func(shot_event: Variant) -> void: shots.append(shot_event))
	tank.request_fire()
	var shot_is_valid: bool = shots.size() == 1 and shots[0].is_valid() \
		and is_equal_approx(float(shots[0].damage), tank.shell_damage)
	if not shot_is_valid:
		tank.queue_free()
		await process_frame
		return _fail("%s must freeze its local shell damage into ShotEvent." % tank_id)

	for expected_stage: int in [75, 50, 25, 0]:
		health.apply_damage(health.maximum_health * 0.25)
		if int(damage_visuals.active_damage_stage) != expected_stage:
			tank.queue_free()
			await process_frame
			return _fail("%s damage visuals must keep %d percent threshold semantics after a health override." % [tank_id, expected_stage])

	var depleted_explosion := root.get_node_or_null("TankDepletedExplosion")
	if depleted_explosion != null:
		depleted_explosion.queue_free()
	tank.queue_free()
	await process_frame
	return true


func _has_legal_parameters(tank: CharacterBody3D, health: HealthComponent) -> bool:
	return tank.movement_speed > 0.0 and tank.reverse_movement_speed > 0.0 \
		and tank.turn_speed > 0.0 and tank.turning_movement_speed_ratio >= 0.0 \
		and tank.turning_movement_speed_ratio <= 1.0 and tank.tank_mass_tonnes > 0.0 \
		and tank.engine_horsepower > 0.0 and tank.brake_force_kilonewtons > 0.0 \
		and tank.turn_response > 0.0 and tank.turret_turn_speed > 0.0 \
		and tank.gun_pitch_speed > 0.0 and tank.shell_damage > 0.0 \
		and health.maximum_health > 0.0


func _fail(message: String) -> bool:
	push_error(message)
	return false
