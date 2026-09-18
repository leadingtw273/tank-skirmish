extends SceneTree

const DATA := "res://src/world/roads/base_snap_points.json"
const BASE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/"
const EXPECTED_COUNTS := {
	"Road1": 2, "Road1_Curve1": 2, "Road1_Curve2": 2, "Road1_Curve3": 2,
	"Road1_Curve4": 2, "Road2_T": 3, "Road2_X": 4, "Road6_End": 1,
	"Road10_90angle_Corner": 2, "Road11_Y_Splitter": 3, "Road11_Y_Splitter_45": 3,
	"Road12_Diagonal_Splitter_L": 3, "Road12_Diagonal_Splitter_R": 3, "Road3_Crossing": 2,
}

func _initialize() -> void:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	assert(source is Dictionary and source.has("models"), "base snap JSON schema")
	var models: Dictionary = source.models
	assert(models.keys().size() == EXPECTED_COUNTS.size(), "complete base road inventory")
	var ports: int = 0
	for model: String in EXPECTED_COUNTS:
		assert(models.has(model), "missing " + model)
		var model_ports: Array = models[model]
		assert(model_ports.size() == EXPECTED_COUNTS[model], "port count " + model)
		assert(load_model(model) != null, "GLB unreadable " + model)
		for port: Dictionary in model_ports:
			assert(port.has_all(["name", "position", "outward"]), "port schema " + model)
			var position: Vector3 = Vector3(port.position[0], port.position[1], port.position[2])
			var outward: Vector3 = Vector3(port.outward[0], port.outward[1], port.outward[2])
			assert(is_zero_approx(position.y) and is_zero_approx(outward.y), "ground-plane cap " + model)
			assert(is_equal_approx(outward.length(), 1.0), "unit outward " + model)
			ports += 1
	print("BASE_PORTS_SMOKE_RESULT models=%d ports=%d status=pass" % [models.size(), ports])
	quit()

func load_model(model: String) -> PackedScene:
	var path: String = "res://assets/AtomicRealmModularRoads/parking/PLUS/gltf/Road3_Crossing.glb" if model == "Road3_Crossing" else BASE + model + ".glb"
	return load(path) as PackedScene
