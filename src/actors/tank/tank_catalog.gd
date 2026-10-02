## 四款可駕駛坦克的唯一車型入口；地圖與重生只保存這個穩定 ID。
extends RefCounted

const IDS: Array[StringName] = [&"tank1", &"tank2", &"tank3", &"tank4"]

const _DEFINITIONS := {
	&"tank1": {
		"donor_path": "res://src/actors/tank/variants/tank1/tank1.tscn",
		"side_drive_force_limit": 115200.0,
		"recoil_impulse": 18000.0,
	},
	&"tank2": {
		"donor_path": "res://src/actors/tank/variants/tank2/tank2.tscn",
		"side_drive_force_limit": 120000.0,
		"recoil_impulse": 12000.0,
	},
	&"tank3": {
		"donor_path": "res://src/actors/tank/variants/tank3/tank3.tscn",
		"side_drive_force_limit": 134400.0,
		"recoil_impulse": 9000.0,
	},
	&"tank4": {
		"donor_path": "res://src/actors/tank/variants/tank4/tank4.tscn",
		"side_drive_force_limit": 158400.0,
		"recoil_impulse": 24000.0,
	},
}

const _SCENE_PATHS := {
	&"tank1": "res://src/actors/rigid_tank/variants/tank1.tscn",
	&"tank2": "res://src/actors/rigid_tank/player_rigid_tank.tscn",
	&"tank3": "res://src/actors/rigid_tank/variants/tank3.tscn",
	&"tank4": "res://src/actors/rigid_tank/variants/tank4.tscn",
}


static func definition(id: StringName) -> Dictionary:
	var result := _DEFINITIONS.get(id, {}) as Dictionary
	if result.is_empty():
		push_error("TankCatalog does not recognize vehicle ID '%s'." % id)
		return {}
	return result.duplicate()


static func scene(id: StringName) -> PackedScene:
	var path := _SCENE_PATHS.get(id, "") as String
	if path.is_empty():
		push_error("TankCatalog does not recognize vehicle ID '%s'." % id)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("TankCatalog could not load rigid scene for vehicle ID '%s'." % id)
	return packed


static func instantiate(id: StringName) -> Node3D:
	var packed := scene(id)
	var tank := packed.instantiate() as Node3D if packed != null else null
	if tank == null:
		push_error("TankCatalog could not instantiate vehicle ID '%s'." % id)
	return tank
