extends SceneTree
## Generates four finite, snap-exact compact-road loops using only Road1 12m pieces.

const OUT := "res://src/samples/roads/compact_loop_demo.tscn"
const ROAD1 := "res://src/world/roads/items/base/Road1/Road1_B__Road1_A.tscn"
const CORNER := "res://src/world/roads/items/base/Road10_90angle_Corner/Road1_B__Road1_A.tscn"
const ROAD11 := "res://src/world/roads/items/custom/Road11_Y_Splitter_45_Custom/Default.tscn"
const ROAD12_L := "res://src/world/roads/items/custom/Road12_Diagonal_Splitter_L_Custom/Default.tscn"
const ROAD12_R := "res://src/world/roads/items/custom/Road12_Diagonal_Splitter_R_Custom/Default.tscn"
const Q := 0.7071067811865476

func _init() -> void:
	var root := Node3D.new()
	root.name = "CompactLoopDemo"
	var failures := []
	for result: Dictionary in [build_loop(root, "SmallRight", ROAD11, Vector2(4.59158, 13.59158), 1, 1, 0.03, Vector3(-90, 0, 0)), build_loop(root, "SmallLeft", ROAD11, Vector2(-4.59158, 13.59158), -1, 1, 0.03, Vector3(90, 0, 0)), build_loop(root, "LargeLeft", ROAD12_L, Vector2(10.259273, 10.226008), 1, 3, 0.03, Vector3(-180, 0, 0)), build_loop(root, "LargeRight", ROAD12_R, Vector2(-10.259273, 10.226008), -1, 3, 0.03, Vector3(180, 0, 0))]:
		if float(result.endgap) > 0.001 or int(result.road1_count) != int(result.expected_road1):
			failures.append(result)
	if not failures.is_empty():
		push_error("Compact loop verification failed: " + JSON.stringify(failures))
		quit(1)
		return
	add_preview(root)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	if ResourceSaver.save(scene, OUT) != OK:
		push_error("Cannot save compact loop demo")
		quit(1)
		return
	print("COMPACT_LOOP_DEMO_RESULT endgap_max=0.000000 loops=4")
	quit()

func add_preview(root: Node3D) -> void:
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.5
	var world_environment := WorldEnvironment.new()
	world_environment.name = "PreviewEnvironment"
	world_environment.environment = environment
	root.add_child(world_environment)
	world_environment.owner = root
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 470.0
	camera.position = Vector3(0, 360, 90)
	camera.basis = Basis.looking_at(-camera.position, Vector3.UP)
	camera.current = true
	root.add_child(camera)
	camera.owner = root
	var light := DirectionalLight3D.new()
	light.name = "PreviewSun"
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.15
	root.add_child(light)
	light.owner = root

# sign=+1 turns clockwise through Right/Diagonal L; sign=-1 is the explicit
# L/R mirror, not a negative-scale instance.  Every connecting straight has
# length 12*k: small k=1, large k=3.  The paired halves turn 180° each.
func build_loop(parent: Node3D, name_: String, y_scene_path: String, exit_local: Vector2, sign_: int, k: int, y: float, offset: Vector3) -> Dictionary:
	var holder := Node3D.new()
	holder.name = name_
	holder.position = offset
	parent.add_child(holder)
	holder.owner = parent
	var south := Vector2(0, -6 if y_scene_path != ROAD11 else 3)
	var corner_south := Vector2(0, -6)
	var road1_count := 0
	var heading := 0.0
	var translation := Vector2.ZERO
	var start := south
	for index in 4:
		place(holder, y_scene_path, "Y%d" % (index + 1), translation, heading, y)
		var exit := translation + rotate_2d(exit_local, heading)
		var outward := rotate_2d(Vector2(float(sign_) * Q, Q), heading)
		var after_y := fposmod(heading + float(sign_) * 45.0, 360.0)
		if index == 1 or index == 3:
			var corner_heading := after_y if sign_ > 0 else fposmod(after_y + 90.0, 360.0)
			var corner_entry := corner_south if sign_ > 0 else Vector2(6, 0)
			var corner_exit := Vector2(6, 0) if sign_ > 0 else corner_south
			var corner_outward := Vector2(1, 0) if sign_ > 0 else Vector2(0, -1)
			var next_heading := fposmod(corner_heading + 90.0, 360.0) if sign_ > 0 else fposmod(corner_heading + 180.0, 360.0)
			translation = exit - rotate_2d(corner_entry, corner_heading)
			place(holder, CORNER, "Corner%d" % (index / 2 + 1), translation, corner_heading, y)
			exit = translation + rotate_2d(corner_exit, corner_heading)
			outward = rotate_2d(corner_outward, corner_heading)
			translation = exit + outward * 12.0 * float(k) - rotate_2d(south, next_heading)
			heading = next_heading
		else:
			road1_count += add_straights(holder, exit, outward, k, y)
			translation = exit + outward * 12.0 * float(k) - rotate_2d(south, after_y)
			heading = after_y
		if index == 1 or index == 3:
			road1_count += add_straights(holder, exit, outward, k, y)
	var final := translation + rotate_2d(south, heading)
	var endgap := final.distance_to(start)
	return {"name": name_, "endgap": endgap, "road1_count": road1_count, "expected_road1": 4 * k}

func add_straights(parent: Node3D, start: Vector2, outward: Vector2, count: int, y: float) -> int:
	var heading := atan2(outward.x, outward.y)
	for index in count:
		var node := (load(ROAD1) as PackedScene).instantiate() as Node3D
		node.name = "Road1_%d" % index
		node.position = Vector3(start.x + outward.x * (6.0 + 12.0 * index), y, start.y + outward.y * (6.0 + 12.0 * index))
		node.rotation.y = heading
		parent.add_child(node)
		node.owner = parent.owner
	return count

func place(parent: Node3D, path: String, name_: String, position_: Vector2, heading: float, y: float) -> void:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.name = name_
	node.position = Vector3(position_.x, y, position_.y)
	node.rotation.y = deg_to_rad(heading)
	parent.add_child(node)
	node.owner = parent.owner

func rotate_2d(value: Vector2, degrees: float) -> Vector2:
	var radians := deg_to_rad(degrees)
	return Vector2(value.x * cos(radians) + value.y * sin(radians), -value.x * sin(radians) + value.y * cos(radians))
