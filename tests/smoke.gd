extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"
const CONVERSION_MANIFEST := "res://docs/assets/conversion-manifest.json"
const TANK_VISUAL_SCALE := 1.7466666
const BUILDING_MODELS := {
	"OneStoryNorthWest": "1story",
	"GableRoofNorthWest": "1story-gable-roof",
	"TwoStoryWideNorthWest": "2story-wide",
	"TwoStorySlimNorthWest": "2story-slim",
	"ThreeStorySmallNorthWest": "3story-small",
	"TwoStoryNorthWest": "2story",
	"FourStoryNorthEast": "4story",
	"SixStoryNorthEast": "6story-stack",
	"OneStoryNorthEast": "1story",
	"GableRoofNorthEast": "1story-gable-roof",
	"TwoStoryWideSouthWest": "2story-wide",
	"TwoStorySlimSouthWest": "2story-slim",
	"ThreeStorySmallSouthWest": "3story-small",
	"TwoStorySouthWest": "2story",
	"FourStorySouthWest": "4story",
	"SixStorySouthWest": "6story-stack",
	"OneStorySouthEast": "1story",
	"GableRoofSouthEast": "1story-gable-roof",
	"TwoStoryWideSouthEast": "2story-wide",
	"TwoStorySlimSouthEast": "2story-slim",
	"ThreeStorySmallSouthEast": "3story-small",
	"TwoStorySouthEast": "2story",
	"OneStorySouthWestInner": "1story",
	"GableRoofSouthWestInner": "1story-gable-roof",
	"TwoStoryWideSouthMiddle": "2story-wide",
	"TwoStorySlimSouthMiddle": "2story-slim",
	"ThreeStorySmallSouthMiddle": "3story-small",
	"TwoStorySouthMiddle": "2story",
	"FourStorySouthEastInner": "4story",
	"SixStorySouthEastInner": "6story-stack",
	"OneStorySouthEastInner": "1story",
	"GableRoofSouthEastInner": "1story-gable-roof",
	"OneStoryNorthWestWest": "1story",
	"GableRoofNorthWestEast": "1story-gable-roof",
	"OneStoryNorthMiddleWest": "1story",
	"GableRoofNorthMiddleEast": "1story-gable-roof",
	"OneStoryNorthEastWest": "1story",
	"GableRoofNorthEastEast": "1story-gable-roof",
	"OneStoryMiddleWestWest": "1story",
	"GableRoofMiddleWestEast": "1story-gable-roof",
	"OneStoryMiddleEastWest": "1story",
	"GableRoofMiddleEastEast": "1story-gable-roof",
	"OneStorySouthWestWest": "1story",
	"GableRoofSouthWestEast": "1story-gable-roof",
	"OneStorySouthMiddleWest": "1story",
	"GableRoofSouthMiddleEast": "1story-gable-roof",
	"OneStorySouthEastWest": "1story",
	"GableRoofSouthEastEast": "1story-gable-roof",
}

const GRID_ROAD_TILES := {
	"NorthWestEntrance": {"scene": "street_3way.glb", "position": Vector3(-30, 0, -82), "rotation_y": PI / 2.0},
	"SouthWestEntrance": {"scene": "street_3way.glb", "position": Vector3(-30, 0, 98), "rotation_y": -PI / 2.0},
	"WestSouthEntrance": {"scene": "street_3way.glb", "position": Vector3(-90, 0, 38), "rotation_y": PI},
	"EastSouthEntrance": {"scene": "street_3way.glb", "position": Vector3(90, 0, 38), "rotation_y": 0.0},
	"NorthWestCrossing": {"scene": "street_4way.glb", "position": Vector3(-30, 0, -22), "rotation_y": 0.0},
	"MainCrossing": {"scene": "street_4way.glb", "position": Vector3(30, 0, -22), "rotation_y": 0.0},
	"SouthWestCrossing": {"scene": "street_4way.glb", "position": Vector3(-30, 0, 38), "rotation_y": 0.0},
	"SouthEastCrossing": {"scene": "street_4way.glb", "position": Vector3(30, 0, 38), "rotation_y": 0.0},
	"WestNorthA": {"scene": "street_straight.glb", "position": Vector3(-30, 0, -62), "rotation_y": PI / 2.0},
	"WestNorthB": {"scene": "street_straight.glb", "position": Vector3(-30, 0, -42), "rotation_y": PI / 2.0},
	"WestSouthA": {"scene": "street_straight.glb", "position": Vector3(-30, 0, -2), "rotation_y": PI / 2.0},
	"WestSouthB": {"scene": "street_straight.glb", "position": Vector3(-30, 0, 18), "rotation_y": PI / 2.0},
	"WestSouthC": {"scene": "street_straight.glb", "position": Vector3(-30, 0, 58), "rotation_y": PI / 2.0},
	"WestSouthD": {"scene": "street_straight.glb", "position": Vector3(-30, 0, 78), "rotation_y": PI / 2.0},
	"SouthWestA": {"scene": "street_straight.glb", "position": Vector3(-70, 0, 38), "rotation_y": 0.0},
	"SouthWestB": {"scene": "street_straight.glb", "position": Vector3(-50, 0, 38), "rotation_y": 0.0},
	"SouthWestC": {"scene": "street_straight.glb", "position": Vector3(-10, 0, 38), "rotation_y": 0.0},
	"SouthWestD": {"scene": "street_straight.glb", "position": Vector3(10, 0, 38), "rotation_y": 0.0},
	"SouthEastA": {"scene": "street_straight.glb", "position": Vector3(50, 0, 38), "rotation_y": 0.0},
	"SouthEastB": {"scene": "street_straight.glb", "position": Vector3(70, 0, 38), "rotation_y": 0.0},
}

const BUILDING_X_COLUMNS := [-74.0, -70.0, -50.0, -46.0, -14.0, -10.0, 10.0, 14.0, 46.0, 50.0, 70.0, 74.0]
const BUILDING_Z_ROWS := [-66.0, -52.0, -38.0, -6.0, 8.0, 22.0, 54.0, 68.0, 82.0]
const MIN_ROAD_SETBACK := 1.0
const BLOCK_BUILDING_COUNTS := {
	"north_west": 6,
	"north_middle": 6,
	"north_east": 6,
	"middle_west": 6,
	"middle_east": 6,
	"south_west": 6,
	"south_middle": 6,
	"south_east": 6,
}


func _init() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		push_error("Unable to load main scene: %s" % MAIN_SCENE)
		quit(1)
		return

	var instance := packed_scene.instantiate()
	if instance == null:
		push_error("Unable to instantiate main scene: %s" % MAIN_SCENE)
		quit(1)
		return

	root.add_child(instance)
	call_deferred("_validate_instance", instance)


func _validate_instance(instance: Node) -> void:
	if not _validate_tread_animations(instance):
		quit(1)
		return
	if not _validate_turret_aiming(instance):
		quit(1)
		return
	if not _validate_collision_layout(instance):
		quit(1)
		return
	if not _validate_grid_layout(instance):
		quit(1)
		return

	print("Tank Skirmish smoke validation passed.")
	quit(0)


func _validate_tread_animations(instance: Node) -> bool:
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	if tank == null:
		push_error("Tank must exist before tread animations can be validated")
		return false
	if not tank.tread_animations_available or tank.tread_animation_player == null:
		push_error("Tank tread AnimationPlayer and required clips must be available")
		return false

	for clip: StringName in [&"Tank_Forward", &"Tank_Backwards", &"Tank_TurningLeft", &"Tank_TurningRight"]:
		var animation: Animation = tank.tread_animation_player.get_animation(clip)
		if animation == null or animation.loop_mode != Animation.LOOP_LINEAR:
			push_error("Tank tread clip %s must exist and loop" % clip)
			return false
		if not _tread_clip_moves_track_bones(tank, animation, clip):
			return false
	if tank._tread_animation_for_inputs(1.0, 1.0) != &"Tank_TurningLeft" or tank._tread_animation_for_inputs(-1.0, -1.0) != &"Tank_TurningRight":
		push_error("Tank turning tread clips must take priority over movement clips")
		return false
	if tank._tread_animation_for_inputs(1.0, 0.0) != &"Tank_Forward" or tank._tread_animation_for_inputs(-1.0, 0.0) != &"Tank_Backwards" or not tank._tread_animation_for_inputs(0.0, 0.0).is_empty():
		push_error("Tank tread clip selection does not match movement input")
		return false

	tank._update_tread_animation(&"Tank_Forward")
	if tank.active_tread_animation != &"Tank_Forward" or tank.tread_animation_paused:
		push_error("Tank forward tread animation did not start")
		return false
	tank._update_tread_animation(&"")
	if not tank.tread_animation_paused:
		push_error("Tank tread animation must pause when movement stops")
		return false
	return true


func _tread_clip_moves_track_bones(tank: Node, animation: Animation, clip: StringName) -> bool:
	var skeleton := _find_skeleton(tank)
	if skeleton == null:
		push_error("Tank tread animation validation requires a Skeleton3D")
		return false

	var track_bones: Array[int] = []
	for bone_id in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(bone_id)).contains("Track"):
			track_bones.append(bone_id)
	if track_bones.is_empty():
		push_error("Tank tread animation validation requires Track bones")
		return false

	tank.tread_animation_player.play(clip)
	tank.tread_animation_player.seek(0.0, true)
	tank.tread_animation_player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var baseline: Array[Transform3D] = []
	for bone_id in track_bones:
		baseline.append(skeleton.get_bone_pose(bone_id))

	for fraction in [0.25, 0.5, 0.75]:
		tank.tread_animation_player.seek(animation.length * fraction, true)
		tank.tread_animation_player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		for index in range(track_bones.size()):
			if not baseline[index].is_equal_approx(skeleton.get_bone_pose(track_bones[index])):
				return true

	push_error("Tank tread clip %s contains no visible Track bone motion" % clip)
	return false


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _validate_turret_aiming(instance: Node) -> bool:
	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	if tank == null:
		push_error("Tank must exist before turret aiming can be validated")
		return false
	if not is_equal_approx(tank.turret_turn_speed, 1.777778):
		push_error("Tank turret turn speed does not match the approved value")
		return false

	var scale_root := tank.get_node_or_null("Tank2/AgentTeamScaleRoot") as Node3D
	var turret_pivot := scale_root.get_node_or_null("TurretPivot") as Node3D if scale_root != null else null
	var turret := turret_pivot.get_node_or_null("Tank_Turret") as MeshInstance3D if turret_pivot != null else null
	var gun := turret_pivot.get_node_or_null("Tank_Gun") as MeshInstance3D if turret_pivot != null else null
	if turret_pivot == null or turret == null or gun == null:
		push_error("Tank gun and turret must share a runtime TurretPivot")
		return false
	if turret.get_parent() != turret_pivot or gun.get_parent() != turret_pivot:
		push_error("Tank gun and turret must remain attached to the same runtime pivot")
		return false

	var chassis_position := tank.global_position
	var chassis_rotation := tank.global_rotation
	var plus_z_target := turret_pivot.global_position + Vector3.BACK * 20.0
	tank._aim_turret_at(plus_z_target, 10.0)
	var muzzle_forward := -turret_pivot.global_transform.basis.x.normalized()
	if muzzle_forward.dot(Vector3.BACK) < 0.999:
		push_error("Tank local -X muzzle axis must rotate toward a +Z target")
		return false
	if not tank.global_position.is_equal_approx(chassis_position) or not tank.global_rotation.is_equal_approx(chassis_rotation):
		push_error("Turret aiming must not move or rotate the tank chassis")
		return false

	var held_yaw := turret_pivot.global_rotation.y
	tank._aim_turret_at(turret_pivot.global_position, 1.0)
	if not is_equal_approx(turret_pivot.global_rotation.y, held_yaw) or is_nan(turret_pivot.global_rotation.y):
		push_error("A near turret target must preserve the current yaw")
		return false
	var aim_plane := Plane(Vector3.UP, turret_pivot.global_position.y)
	if aim_plane.intersects_ray(turret_pivot.global_position, Vector3.RIGHT) != null:
		push_error("A ray parallel to the turret-height plane must not produce an aim target")
		return false

	return true


func _validate_collision_layout(instance: Node) -> bool:
	var manifest := _load_manifest_dimensions()
	if manifest.is_empty():
		return false

	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	if tank == null:
		push_error("Tank must be a CharacterBody3D")
		return false
	if not is_equal_approx(tank.movement_speed, 15.0) or not is_equal_approx(tank.turn_speed, 0.8):
		push_error("Tank movement exports do not match the approved values")
		return false
	if not _validate_box_collision(tank, manifest["tank2"] * TANK_VISUAL_SCALE):
		push_error("Tank collision shape is missing, disabled, or incorrectly sized")
		return false

	for building_name: String in BUILDING_MODELS:
		var building := instance.get_node_or_null("Buildings/%s" % building_name) as StaticBody3D
		if building == null:
			push_error("Building %s must be a StaticBody3D" % building_name)
			return false
		if not _validate_box_collision(building, manifest[BUILDING_MODELS[building_name]]):
			push_error("Building %s collision shape is missing, disabled, or incorrectly sized" % building_name)
			return false
		if not is_equal_approx(building.rotation.y, 0.0) and not is_equal_approx(building.rotation.y, PI / 2.0):
			push_error("Building %s must use an orthogonal rotation" % building_name)
			return false

	if instance.get_node("Buildings").get_child_count() != BUILDING_MODELS.size():
		push_error("Building count does not match the approved town layout")
		return false

	return true


func _validate_grid_layout(instance: Node) -> bool:
	var roads := instance.get_node_or_null("Roads") as Node
	if roads == null:
		push_error("Roads node is missing")
		return false

	for road_name: String in GRID_ROAD_TILES:
		var requirement: Dictionary = GRID_ROAD_TILES[road_name]
		var road := roads.get_node_or_null(road_name) as Node3D
		if road == null:
			push_error("Required grid road %s is missing" % road_name)
			return false
		if road.scene_file_path.get_file() != requirement["scene"]:
			push_error("Grid road %s must use %s" % [road_name, requirement["scene"]])
			return false
		if not road.position.is_equal_approx(requirement["position"]) or not is_equal_approx(road.rotation.y, requirement["rotation_y"]):
			push_error("Grid road %s has an unexpected transform" % road_name)
			return false

	var block_counts := {}
	var block_edge_counts := {}
	for block_name: String in BLOCK_BUILDING_COUNTS:
		block_counts[block_name] = 0
		block_edge_counts[block_name] = {"north": 0, "south": 0, "west": 0, "east": 0}
	for building in instance.get_node("Buildings").get_children():
		var static_building := building as StaticBody3D
		if static_building == null:
			push_error("Buildings may only contain StaticBody3D nodes")
			return false
		if not _matches_grid_coordinate(static_building.position.x, BUILDING_X_COLUMNS) or not _matches_grid_coordinate(static_building.position.z, BUILDING_Z_ROWS):
			push_error("Building %s is not on the regular street grid" % static_building.name)
			return false
		if not _clears_road_axes(static_building):
			push_error("Building %s overlaps a road axis" % static_building.name)
			return false
		var block_name := _town_block_for(static_building.position)
		if block_name == "center":
			push_error("The tank spawn block must remain clear")
			return false
		block_counts[block_name] += 1
		for edge: String in _block_edges_for(static_building.position):
			block_edge_counts[block_name][edge] += 1

	for block_name: String in BLOCK_BUILDING_COUNTS:
		if block_counts[block_name] != BLOCK_BUILDING_COUNTS[block_name]:
			push_error("Block %s does not contain six aligned buildings" % block_name)
			return false
		for edge: String in ["north", "south", "west", "east"]:
			if block_edge_counts[block_name][edge] == 0:
				push_error("Block %s is missing buildings along its %s street edge" % [block_name, edge])
				return false
	if not _validate_building_footprints(instance.get_node("Buildings")):
		return false
	return true


func _matches_grid_coordinate(value: float, allowed_values: Array) -> bool:
	for allowed_value: float in allowed_values:
		if is_equal_approx(value, allowed_value):
			return true
	return false


func _clears_road_axes(building: StaticBody3D) -> bool:
	var collision := building.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as BoxShape3D
	var footprint := shape.size
	if is_equal_approx(building.rotation.y, PI / 2.0):
		footprint = Vector3(footprint.z, footprint.y, footprint.x)
	for road_x: float in [-90.0, -30.0, 30.0, 90.0]:
		if absf(building.position.x - road_x) - 10.0 - footprint.x / 2.0 < MIN_ROAD_SETBACK:
			return false
	for road_z: float in [-82.0, -22.0, 38.0, 98.0]:
		if absf(building.position.z - road_z) - 10.0 - footprint.z / 2.0 < MIN_ROAD_SETBACK:
			return false
	return true


func _block_edges_for(position: Vector3) -> Array[String]:
	var edges: Array[String] = []
	var x_near_west_road := is_equal_approx(fposmod(position.x + 14.0, 60.0), 0.0)
	var x_near_east_road := is_equal_approx(fposmod(position.x - 14.0, 60.0), 0.0)
	var z_near_north_road := is_equal_approx(fposmod(position.z + 66.0, 60.0), 0.0)
	var z_near_south_road := is_equal_approx(fposmod(position.z + 38.0, 60.0), 0.0)
	if x_near_west_road:
		edges.append("west")
	if x_near_east_road:
		edges.append("east")
	if z_near_north_road:
		edges.append("north")
	if z_near_south_road:
		edges.append("south")
	return edges


func _validate_building_footprints(buildings: Node) -> bool:
	var placed_buildings := buildings.get_children()
	for first_index in range(placed_buildings.size()):
		var first := placed_buildings[first_index] as StaticBody3D
		for second_index in range(first_index + 1, placed_buildings.size()):
			var second := placed_buildings[second_index] as StaticBody3D
			if _footprints_overlap(first, second):
				push_error("Building footprints overlap: %s and %s" % [first.name, second.name])
				return false
	return true


func _footprints_overlap(first: StaticBody3D, second: StaticBody3D) -> bool:
	var first_footprint := _footprint_for(first)
	var second_footprint := _footprint_for(second)
	return absf(first.position.x - second.position.x) < (first_footprint.x + second_footprint.x) / 2.0 and absf(first.position.z - second.position.z) < (first_footprint.z + second_footprint.z) / 2.0


func _footprint_for(building: StaticBody3D) -> Vector3:
	var shape := (building.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var footprint := shape.size
	if is_equal_approx(building.rotation.y, PI / 2.0):
		footprint = Vector3(footprint.z, footprint.y, footprint.x)
	return footprint


func _town_block_for(position: Vector3) -> String:
	var column := ""
	if position.x < -30.0:
		column = "west"
	elif position.x < 30.0:
		column = "middle"
	else:
		column = "east"
	if position.z < -22.0:
		return "north_%s" % column
	if position.z < 38.0:
		return "center" if column == "middle" else "middle_%s" % column
	return "south_%s" % column


func _load_manifest_dimensions() -> Dictionary:
	var file := FileAccess.open(CONVERSION_MANIFEST, FileAccess.READ)
	if file == null:
		push_error("Unable to open conversion manifest")
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Unable to parse conversion manifest")
		return {}

	var dimensions := {}
	for model: Dictionary in json.data.models:
		var size: Array = model.measuredGodotXyz
		dimensions[model.id] = Vector3(size[0], size[1], size[2])
	return dimensions


func _validate_box_collision(body: CollisionObject3D, expected_size: Vector3) -> bool:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled:
		return false
	var shape := collision.shape as BoxShape3D
	return shape != null and shape.size.is_equal_approx(expected_size)
