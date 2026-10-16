## 僅在開場前三個 render frame 提交正式特效的微型繪製；不建立砲彈或遊戲事件。
extends Node3D

const MICRO_SCALE := 0.000001
const DRAW_FRAMES := 3

var _drawn_frames := 0


func begin() -> void:
	## 先取動畫中有幾何的時刻，再停動畫；避免後續動畫覆寫微型尺寸或燈光能量。
	for animation: AnimationPlayer in find_children("*", "AnimationPlayer", true, false):
		animation.advance(0.08)
		animation.pause()
	_miniaturize(self)
	## 無 GPU 的 smoke 不會發出 frame_post_draw；以三個 process frame 驗生命週期。
	set_process(DisplayServer.get_name() == "headless")
	if is_processing():
		return
	RenderingServer.frame_pre_draw.connect(_position_for_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)


func _miniaturize(node: Node) -> void:
	if node != self and node is Node3D:
		node.position *= MICRO_SCALE
	if node is MeshInstance3D:
		node.scale *= MICRO_SCALE
	elif node is GPUParticles3D:
		## 粒子不一定繼承父節點 scale；縮的是粒子 transform，連 shader 的頂點位移一起縮。
		var motion := node.process_material.duplicate(true) as ParticleProcessMaterial
		motion.scale_min *= MICRO_SCALE
		motion.scale_max *= MICRO_SCALE
		motion.initial_velocity_min *= MICRO_SCALE
		motion.initial_velocity_max *= MICRO_SCALE
		motion.gravity *= MICRO_SCALE
		motion.emission_box_extents *= MICRO_SCALE
		motion.emission_sphere_radius *= MICRO_SCALE
		node.process_material = motion
		node.preprocess = 0.08
	elif node is Light3D:
		## 保留正式 light type/range/shadow 路徑；非零能量不足以改變任何螢幕像素。
		node.light_energy = 0.000000000001
	elif node is Decal:
		node.size *= MICRO_SCALE
	for child in node.get_children():
		_miniaturize(child)


func _position_for_draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	## 使用正式相機更新後的視錐中央、地表附近；不修改相機或另造 world/environment。
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var point: Variant = Plane(Vector3.UP, 0.15).intersects_ray(origin, direction)
	global_position = point if point != null else camera.project_position(center, camera.near + 1.0)


func _after_draw() -> void:
	_drawn_frames += 1
	if _drawn_frames >= DRAW_FRAMES:
		set_process(false)
		_disconnect_render_signals()
		queue_free()


func _process(_delta: float) -> void:
	_after_draw()


func _disconnect_render_signals() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_position_for_draw):
		RenderingServer.frame_pre_draw.disconnect(_position_for_draw)
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)


func _exit_tree() -> void:
	_disconnect_render_signals()
