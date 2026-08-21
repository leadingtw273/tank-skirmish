extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"
const CONVERSION_MANIFEST := "res://docs/assets/conversion-manifest.json"
const TANK_VISUAL_SCALE := 1.965
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

const BUILDING_X_COLUMNS := [-70.0, -50.0, -10.0, 10.0, 50.0, 70.0]
const BUILDING_Z_ROWS := [-66.0, -44.0, -6.0, 18.0, 22.0, 54.0, 78.0]
const BLOCK_BUILDING_COUNTS := {
	"north_west": 4,
	"north_middle": 4,
	"north_east": 4,
	"middle_west": 4,
	"middle_east": 4,
	"south_west": 4,
	"south_middle": 4,
	"south_east": 4,
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
	if not _validate_collision_layout(instance):
		quit(1)
		return
	if not _validate_grid_layout(instance):
		quit(1)
		return

	print("Tank Skirmish smoke validation passed.")
	quit(0)


func _validate_collision_layout(instance: Node) -> bool:
	var manifest := _load_manifest_dimensions()
	if manifest.is_empty():
		return false

	var tank := instance.get_node_or_null("Tank") as CharacterBody3D
	if tank == null:
		push_error("Tank must be a CharacterBody3D")
		return false
	if not is_equal_approx(tank.movement_speed, 15.0) or not is_equal_approx(tank.turn_speed, 1.8):
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
	for block_name: String in BLOCK_BUILDING_COUNTS:
		block_counts[block_name] = 0
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

	for block_name: String in BLOCK_BUILDING_COUNTS:
		if block_counts[block_name] != BLOCK_BUILDING_COUNTS[block_name]:
			push_error("Block %s does not contain four aligned buildings" % block_name)
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
		if absf(building.position.x - road_x) <= 10.0 + footprint.x / 2.0:
			return false
	for road_z: float in [-82.0, -22.0, 38.0, 98.0]:
		if absf(building.position.z - road_z) <= 10.0 + footprint.z / 2.0:
			return false
	return true


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
