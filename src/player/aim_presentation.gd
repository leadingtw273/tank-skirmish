## 將坦克目前的射擊方向與滑鼠瞄準目標繪製為世界座標線條。
## 它只呈現已解析的瞄準資料；不會讀取玩家輸入或旋轉坦克。
extends Node

const AIM_VERTICAL_BASIS_THRESHOLD := 0.999
const GROUND_COLLISION_LAYER := 128
const GROUND_NORMAL_MIN_DOT := 0.65
const GroundOutline = preload("res://src/player/aim_ground_outline.gd")
const SliceGroundMarkers = preload("res://src/player/aim_slice_ground_markers.gd")
const SpreadFrames = preload("res://src/player/aim_spread_frames.gd")
const SpreadConePreviewShader = preload("res://src/player/spread_cone_preview.gdshader")

@export_category("瞄準射線偵測")
## 最遠的射線偵測與瞄準線繪製終點，單位為公尺。
@export var max_aim_distance := 180.0
## 可阻擋瞄準射線的物理圖層。
@export_flags_3d_physics var aim_collision_mask := 129

@export_category("瞄準游標")
## 遊戲執行時取代系統箭頭的滑鼠準星圖片。
@export var aim_cursor_texture: Texture2D = preload("res://assets/KenneyCrosshair/PNG/Light/crosshair-014.png")
## 準星中真正對準世界目標的像素位置；預設為 64×64 圖片中心。
@export var aim_cursor_hotspot := Vector2(32.0, 32.0)
## 遊戲內準星相對於原始圖片的顯示比例；2/3 代表縮小三分之一。
@export_range(0.1, 2.0, 0.05) var aim_cursor_scale := 2.0 / 3.0

@export_category("瞄準線")
## 每條圓柱形瞄準線的半徑，單位為公尺。
@export var aim_line_radius := 0.04
## 短於此長度的線段會隱藏，以避免退化的網格，單位為公尺。
@export var aim_line_min_length := 0.05
## 射擊起點附近要隱藏的距離，讓線條避開 Tank，單位為公尺。
@export var aim_line_near_tank_hidden_distance := 3.0
## 兩條瞄準線的不透明度，0 為透明，1 為不透明。
@export_range(0.0, 1.0, 0.05) var aim_line_alpha := 0.7
## 低於此弧度角差時，滑鼠線會因與射擊線對齊而隱藏。
@export var aim_aligned_angle_radians := 0.004363323

@export_category("暫時擴散預覽")
## 顯示實際砲口的擴散圓錐，只供試玩觀察，不影響彈道或命中判定。
@export var show_spread_cone := false
## 圓錐顏色與不透明度；A 越小越透明。
@export var spread_cone_color := Color(0.2, 0.8, 1.0, 0.18)
## 圓錐與可見地面相交的截面顏色；只標示接觸區，不影響彈道。
@export var spread_cone_ground_contact_color := Color(0.02, 0.2, 0.8, 0.65)

@export_category("擴散準星切片")
## 沿砲口到白線終點顯示動態片數的框，與暫時圓錐開關互相獨立。
@export var show_spread_frames := true
## 切片框的顏色與不透明度，A越小越透明。
@export var spread_frames_color := Color(0.05, 0.06, 0.08, 0.9)
## 框線的世界寬度，單位公尺；所有片維持相同線寬。
@export_range(0.005, 0.2, 0.005) var spread_frames_line_width := 0.08
## 相鄰框的最小距離，單位公尺；不足時減少片數，至少保留一片。
@export var spread_frames_min_spacing_meters := 15.0
## 相鄰框的最大距離，單位公尺；超過時增加片數，減片後也不能超過此值。
@export var spread_frames_max_spacing_meters := 25.0
## 所有切片沿瞄準軸一起往砲口退縮的距離，單位公尺；不移動真實瞄準落點。
@export_range(0.0, 30.0, 0.5) var spread_frames_inset_meters := 0.0
## 半徑小於或等於此值時使用樣式 0，單位公尺。
@export var spread_frames_style_0_max_radius_meters := 1.0
## 半徑大於樣式 0 且小於或等於此值時使用樣式 1，單位公尺。
@export var spread_frames_style_1_max_radius_meters := 2.0
## 半徑大於樣式 1 且小於或等於此值時使用樣式 2，單位公尺。
@export var spread_frames_style_2_max_radius_meters := 4.0

@export_category("地面擴散範圍框")
## 獨立顯示圓錐與地面的近似梯形交界，不需開啟淡藍圓錐。
@export var show_ground_spread_outline := true
## 地面框顏色與不透明度；Alpha 0.4 表示40%不透明。
@export var ground_spread_outline_color := Color(0.05, 0.06, 0.08, 0.4)
## 地面範圍框線的世界寬度，單位公尺。
@export_range(0.01, 1.0, 0.01) var ground_spread_outline_width := 0.12
## 每段實線長度，單位公尺。
@export_range(0.05, 5.0, 0.05) var ground_spread_dash_length := 0.8
## 每段留白長度，單位公尺；0為連續實線。
@export_range(0.0, 5.0, 0.05) var ground_spread_gap_length := 0.0

@export_category("切片地面定位")
## 每個可見切片中心向正下方連到地面，落點顯示空心三角形。
@export var show_slice_ground_markers := true
## 定位線與三角形的顏色；預設深色、Alpha 0.75。
@export var slice_ground_marker_color := Color(0.05, 0.06, 0.08, 0.75)
## 定位線與三角形框線的世界寬度，單位公尺。
@export_range(0.01, 1.0, 0.01) var slice_ground_marker_width := 0.08
## 三角形中心到前方尖端的距離，單位公尺。
@export_range(0.1, 5.0, 0.1) var slice_ground_triangle_size := 0.6
## 切片中心離地低於此高度時只隱藏三角形；定位線與切片保留，單位公尺。
@export_range(0.0, 5.0, 0.05) var slice_ground_triangle_min_height := 1.0

var slice_ground_markers: Node3D
var ground_spread_outline: Node3D
var spread_frames: Node3D

var controlled_tank: Node3D
var actual_aim_line: MeshInstance3D
var mouse_aim_line: MeshInstance3D
var spread_cone_preview: MeshInstance3D
var scaled_aim_cursor_texture: ImageTexture
var world_target := Vector3.ZERO


## 註冊此呈現要跟隨其砲口與碰撞形狀的坦克。
func set_controlled_tank(tank: Node3D) -> void:
	controlled_tank = tank


## 設定滑鼠準星，並一次建立可重複使用的瞄準線與暫時擴散網格。
func initialize_presentation() -> void:
	if actual_aim_line == null:
		actual_aim_line = _create_aim_line("ActualAimLine", Color.WHITE)
		mouse_aim_line = _create_aim_line("MouseAimLine", Color.RED)
	if spread_cone_preview == null:
		spread_cone_preview = _create_aim_line("SpreadConePreview", spread_cone_color)
		var cone := spread_cone_preview.mesh as CylinderMesh
		## 本地 -Y 端為砲口尖端，+Y 端為擴散圓面；縮放由當下角度與長度決定。
		cone.bottom_radius = 0.0
		cone.top_radius = 1.0
		cone.radial_segments = 48
		var material := ShaderMaterial.new()
		material.shader = SpreadConePreviewShader
		material.set_shader_parameter("cone_color", spread_cone_color)
		material.set_shader_parameter("ground_contact_color", spread_cone_ground_contact_color)
		material.render_priority = Material.RENDER_PRIORITY_MAX - 1
		spread_cone_preview.material_override = material
	_apply_aim_cursor()
	if slice_ground_markers == null:
		slice_ground_markers = SliceGroundMarkers.new()
		slice_ground_markers.name = "SliceGroundMarkers"
		add_child(slice_ground_markers)
	if ground_spread_outline == null:
		ground_spread_outline = GroundOutline.new()
		ground_spread_outline.name = "GroundSpreadOutline"
		add_child(ground_spread_outline)
	if spread_frames == null:
		spread_frames = SpreadFrames.new()
		spread_frames.name = "SpreadFrames"
		add_child(spread_frames)
		spread_frames.initialize()


func _apply_aim_cursor() -> void:
	## 保留 vendor 原圖，僅在記憶體產生縮放版，並同步縮放真正的瞄準熱點。
	if aim_cursor_texture == null:
		return
	var cursor_image := aim_cursor_texture.get_image()
	if cursor_image == null or cursor_image.is_empty():
		return
	var safe_scale := maxf(aim_cursor_scale, 0.01)
	var scaled_size := Vector2i(
		maxi(roundi(cursor_image.get_width() * safe_scale), 1),
		maxi(roundi(cursor_image.get_height() * safe_scale), 1),
	)
	cursor_image.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_LANCZOS)
	scaled_aim_cursor_texture = ImageTexture.create_from_image(cursor_image)
	Input.set_custom_mouse_cursor(
		scaled_aim_cursor_texture,
		Input.CURSOR_ARROW,
		aim_cursor_hotspot * safe_scale,
	)


## 更新滑鼠選取的世界目標，並重繪兩條瞄準線。
func set_world_target(target: Vector3) -> void:
	world_target = target
	_update_aim_lines()


## 供訓練場開關靶切換暫時預覽，只改顯示、不改坦克擴散或射擊。
func toggle_spread_cone() -> void:
	show_spread_cone = not show_spread_cone
	_update_aim_lines()


func _create_aim_line(line_name: String, color: Color) -> MeshInstance3D:
	## 建立以本地 Y 軸為長度方向的圓柱，並關閉深度測試使其始終可作為瞄準輔助線看見。
	var line := MeshInstance3D.new()
	line.name = line_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = aim_line_radius
	cylinder.bottom_radius = aim_line_radius
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	line.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material.albedo_color = Color(color.r, color.g, color.b, aim_line_alpha)
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	add_child(line)
	return line


func _update_aim_lines() -> void:
	## 實線從真實砲口射出；滑鼠線從砲塔樞紐射出，僅在兩者方向有可辨識差異時顯示。
	if actual_aim_line == null or mouse_aim_line == null or controlled_tank == null:
		return
	var muzzle_position := controlled_tank.call("muzzle_global_position") as Vector3
	var actual_direction := controlled_tank.call("muzzle_global_direction") as Vector3
	# 同一次射線結果同時決定端點與命中類別，避免穿過物件去判斷後方地面。
	var aim_hit := _resolve_aim_ray(muzzle_position, actual_direction)
	var actual_end: Vector3 = aim_hit["position"]
	var half_angle := float(controlled_tank.call("get_current_spread_degrees"))
	# 同一幀只有需要地面框或貼地末片時才取樣一次，兩種呈現共用同份局部平面資料。
	var ground := _sample_ground(muzzle_position, actual_end) if show_ground_spread_outline or bool(aim_hit["is_ground"]) else {}
	_set_aim_line_path(actual_aim_line, muzzle_position, actual_end)
	_update_spread_cone(muzzle_position, actual_end, half_angle)
	_update_ground_spread_outline(muzzle_position, actual_end, half_angle, ground)
	var excluded_frame := _update_spread_reticle(muzzle_position, actual_end, bool(aim_hit["is_ground"]), half_angle, ground)
	_update_slice_ground_markers(actual_direction, excluded_frame)
	var firing_target_offset := world_target - muzzle_position
	if firing_target_offset.length_squared() <= 0.001:
		mouse_aim_line.visible = false
		return
	var firing_target_direction := firing_target_offset.normalized()
	if actual_direction.angle_to(firing_target_direction) <= aim_aligned_angle_radians:
		mouse_aim_line.visible = false
		return

	var turret_pivot := controlled_tank.get("turret_pivot") as Node3D
	var mouse_line_origin := turret_pivot.global_position
	var mouse_line_offset := world_target - mouse_line_origin
	if mouse_line_offset.length_squared() <= 0.001:
		mouse_aim_line.visible = false
		return
	var mouse_line_direction := mouse_line_offset.normalized()
	_set_aim_line_path(
		mouse_aim_line,
		mouse_line_origin,
		_aim_line_end(mouse_line_origin, mouse_line_direction),
		_tank_aim_line_clearance_distance(mouse_line_origin),
	)


## 更新擴散切片；貼地末片會回傳給地面定位器排除。
func _update_spread_reticle(origin: Vector3, end: Vector3, on_ground: bool, half_angle: float, ground: Dictionary) -> Node3D:
	if spread_frames == null:
		return null
	# 只有最先命中地面時固定貼地款；立體物件或未命中皆恢復圓錐切片規則。
	var terminal_style := 1 if on_ground else -1
	spread_frames.update_frames(
		origin,
		end,
		half_angle,
		show_spread_frames,
		spread_frames_color,
		spread_frames_line_width,
		aim_line_near_tank_hidden_distance,
		spread_frames_style_0_max_radius_meters,
		spread_frames_style_1_max_radius_meters,
		spread_frames_style_2_max_radius_meters,
		spread_frames_min_spacing_meters,
		spread_frames_max_spacing_meters,
		spread_frames_inset_meters,
		terminal_style,
	)
	if on_ground:
		return _place_terminal_reticle_on_ground(ground)
	return null


func _place_terminal_reticle_on_ground(ground: Dictionary) -> Node3D:
	if spread_frames == null or not spread_frames.visible or spread_frames.frames.is_empty():
		return null
	var terminal: Node3D = spread_frames.frames.back()
	if not terminal.visible:
		return terminal
	if ground.is_empty():
		terminal.visible = false
		return terminal
	var normal: Vector3 = ground["normal"]
	var point: Vector3 = ground["position"]
	var toward_tank := controlled_tank.global_position - point
	toward_tank -= normal * toward_tank.dot(normal)
	if toward_tank.length_squared() < 0.0001:
		toward_tank = Vector3.FORWARD - normal * Vector3.FORWARD.dot(normal)
	toward_tank = toward_tank.normalized()
	var radius := terminal.global_basis.x.length()
	# 原準心在本地XY平面；把本地Z對齊地面法線，本地Y（圖樣上方）朝坦克。
	var ground_basis := Basis(toward_tank.cross(normal).normalized(), toward_tank, normal)
	terminal.global_transform = Transform3D(ground_basis.scaled(Vector3.ONE * radius), point + normal * 0.03)
	return terminal


## 中途切片仍畫離地定位；最後貼地準心不重複加線與三角形。
func _update_slice_ground_markers(forward: Vector3, excluded_frame: Node3D = null) -> void:
	if slice_ground_markers == null:
		return
	var samples: Array[Dictionary] = []
	if show_slice_ground_markers and spread_frames != null and spread_frames.is_visible_in_tree():
		for frame: Node3D in spread_frames.frames:
			if frame == excluded_frame:
				continue
			if not frame.is_visible_in_tree():
				continue
			var center := frame.global_position
			# 從中心正上方一點開始，只查地面圖層；地下中心與無地面不畫定位。
			var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.05, center + Vector3.DOWN * 400.0, GROUND_COLLISION_LAYER)
			query.collide_with_areas = false
			query.hit_from_inside = true
			var hit := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				continue
			var point: Vector3 = hit["position"]
			var normal: Vector3 = hit["normal"]
			if normal.dot(Vector3.UP) < GROUND_NORMAL_MIN_DOT or center.y < point.y - 0.001:
				continue
			samples.append({"center": center, "ground": point, "normal": normal})
	slice_ground_markers.update_markers(samples, forward, show_slice_ground_markers, slice_ground_marker_color, slice_ground_marker_width, slice_ground_triangle_size, slice_ground_triangle_min_height)


## 更新地面範圍框，只消費本幀已取得的局部平面資料。
func _update_ground_spread_outline(origin: Vector3, end: Vector3, half_angle: float, ground: Dictionary) -> void:
	if ground_spread_outline == null:
		return
	if not show_ground_spread_outline or half_angle <= 0.0:
		ground_spread_outline.visible = false
		return
	if ground.is_empty():
		ground_spread_outline.visible = false
		return
	ground_spread_outline.update_outline(origin, end, half_angle, ground["position"], ground["normal"], true, ground_spread_outline_color, ground_spread_outline_width, ground_spread_dash_length, ground_spread_gap_length)


func _update_spread_cone(origin: Vector3, end: Vector3, half_angle: float) -> void:
	## 圓面半徑 = 長度 × tan(半角)，不重新取樣彈道。
	if spread_cone_preview == null:
		return
	if not show_spread_cone or half_angle <= 0.0:
		spread_cone_preview.visible = false
		return
	_set_aim_line_segment(spread_cone_preview, origin, end)
	if not spread_cone_preview.visible:
		return
	var radius := origin.distance_to(end) * tan(deg_to_rad(half_angle))
	var cone_transform := spread_cone_preview.global_transform
	cone_transform.basis.x *= radius
	cone_transform.basis.z *= radius
	spread_cone_preview.global_transform = cone_transform
	var material := spread_cone_preview.material_override as ShaderMaterial
	material.set_shader_parameter("cone_color", spread_cone_color)
	material.set_shader_parameter("ground_contact_color", spread_cone_ground_contact_color)
	material.set_shader_parameter("world_to_cone", cone_transform.affine_inverse())


func _aim_line_end(origin: Vector3, direction: Vector3) -> Vector3:
	return _resolve_aim_ray(origin, direction)["position"] as Vector3


func _resolve_aim_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	## 射線在世界座標中排除控制坦克本身，命中時縮短到碰撞點，否則保留最遠距離。
	var normalized_direction := direction.normalized()
	if normalized_direction.is_zero_approx():
		return {"position": origin, "hit": false, "is_ground": false, "normal": Vector3.ZERO}
	var fallback_end := origin + normalized_direction * max_aim_distance
	var query := PhysicsRayQueryParameters3D.create(origin, fallback_end, aim_collision_mask, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	var collision := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	var collider := collision.get("collider") as CollisionObject3D
	var on_ground := collider != null and (collider.collision_layer & GROUND_COLLISION_LAYER) != 0
	return {"position": collision.get("position", fallback_end), "hit": not collision.is_empty(), "is_ground": on_ground, "normal": collision.get("normal", Vector3.ZERO)}


## 只查既有地面圖層，取得局部平面；不將建築或草當成地面，也不更動彈道。
func _sample_ground(origin: Vector3, end: Vector3) -> Dictionary:
	var probe := Vector3(end.x, maxf(origin.y, end.y) + 100.0, end.z)
	var query := PhysicsRayQueryParameters3D.create(probe, probe - Vector3.UP * 400.0, GROUND_COLLISION_LAYER)
	query.collide_with_areas = false
	var hit := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit["normal"]
	if normal.dot(Vector3.UP) < GROUND_NORMAL_MIN_DOT:
		return {}
	return {"position": hit["position"], "normal": normal}


func _set_aim_line_segment(line: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	## 將圓柱的本地 Y 軸對齊線段；接近垂直時改用另一參考軸，避免叉積退化。
	var segment := end - start
	var length := segment.length()
	if length < aim_line_min_length:
		line.visible = false
		return
	var direction := segment / length
	var reference_axis := Vector3.UP
	if absf(direction.dot(Vector3.UP)) >= AIM_VERTICAL_BASIS_THRESHOLD:
		reference_axis = Vector3.FORWARD
	var x_axis := reference_axis.cross(direction).normalized()
	var z_axis := x_axis.cross(direction).normalized()
	line.global_transform = Transform3D(Basis(x_axis, direction * length, z_axis), start + segment * 0.5)
	line.visible = true


func _set_aim_line_path(line: MeshInstance3D, origin: Vector3, end: Vector3, hidden_distance := -1.0) -> void:
	## 先裁掉起點附近會穿過車體的區段，再以剩餘的世界座標線段更新圓柱。
	var path := end - origin
	var length := path.length()
	var requested_hidden_distance := aim_line_near_tank_hidden_distance if hidden_distance < 0.0 else hidden_distance
	var safe_hidden_distance := maxf(requested_hidden_distance, 0.0)
	if length <= safe_hidden_distance:
		line.visible = false
		return
	_set_aim_line_segment(line, origin + path / length * safe_hidden_distance, end)


func _tank_aim_line_clearance_distance(origin: Vector3) -> float:
	## 以碰撞盒所有世界座標角點的最遠距離決定隱藏量，讓任意砲塔角度都能避開車身。
	var tank_collision := controlled_tank.get("tank_collision") as CollisionShape3D
	var collision_box := tank_collision.shape as BoxShape3D
	if collision_box == null:
		return origin.distance_to(controlled_tank.call("muzzle_global_position") as Vector3) + aim_line_near_tank_hidden_distance
	var half_size := collision_box.size * 0.5
	var farthest_corner_distance := 0.0
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var corner := tank_collision.global_transform * Vector3(half_size.x * x_sign, half_size.y * y_sign, half_size.z * z_sign)
				farthest_corner_distance = maxf(farthest_corner_distance, origin.distance_to(corner))
	return farthest_corner_distance + aim_line_near_tank_hidden_distance
