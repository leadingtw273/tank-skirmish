## 將坦克目前的射擊方向與滑鼠瞄準目標繪製為世界座標線條。
## 它只呈現已解析的瞄準資料；不會讀取玩家輸入或旋轉坦克。
extends Node

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

const AIM_VERTICAL_BASIS_THRESHOLD := 0.999

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
		material.shader = preload("res://src/player/spread_cone_preview.gdshader")
		material.set_shader_parameter("cone_color", spread_cone_color)
		material.set_shader_parameter("ground_contact_color", spread_cone_ground_contact_color)
		material.render_priority = Material.RENDER_PRIORITY_MAX - 1
		spread_cone_preview.material_override = material
	_apply_aim_cursor()


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
	var actual_end := _aim_line_end(muzzle_position, actual_direction)
	_set_aim_line_path(actual_aim_line, muzzle_position, actual_end)
	_update_spread_cone(muzzle_position, actual_end)

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


func _update_spread_cone(origin: Vector3, end: Vector3) -> void:
	## 只讀取當下擴散半角；圓面半徑 = 長度 × tan(半角)，不重新取樣彈道。
	if spread_cone_preview == null:
		return
	var half_angle := float(controlled_tank.call("get_current_spread_degrees"))
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
	## 射線在世界座標中排除控制坦克本身，命中時縮短到碰撞點，否則保留最遠距離。
	var normalized_direction := direction.normalized()
	if normalized_direction.is_zero_approx():
		return origin
	var fallback_end := origin + normalized_direction * max_aim_distance
	var query := PhysicsRayQueryParameters3D.create(origin, fallback_end, aim_collision_mask, [controlled_tank.get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	var collision := controlled_tank.get_world_3d().direct_space_state.intersect_ray(query)
	return collision.get("position", fallback_end) as Vector3


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
