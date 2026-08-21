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
