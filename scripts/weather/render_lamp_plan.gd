## 將 R3-A SVG 匯出為含繁中圖例的 PNG；需要圖形 renderer，不載入遊戲。
extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var bitmap := Image.new()
	assert(bitmap.load_svg_from_string(FileAccess.get_file_as_string(args[0])) == OK)
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600,1700)
	canvas.disable_3d = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(bitmap)
	canvas.add_child(sprite)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC"])
	var captions := [
		[Vector2(60,15),27,"LEA-212 R3-B 全圖路燈配置（12m淨距／沿路空隙≤36m）"],
		[Vector2(60,56),18,"黃點／箭頭：燈柱／燈臂　紅叉：略過　青點：出生　預計 %d 盞，略過 %d 處" % [plan.lamps.size(),plan.skipped.size()]],
		[Vector2(60,1628),18,"北在上（−Z）｜約30m交錯｜最小12m／最大沿路空隙≤36m｜人行道中心線偏移5.5m｜建築與實際形狀篩選"]]
	for caption: Array in captions:
		var label := Label.new()
		label.position = caption[0]
		label.text = caption[2]
		label.add_theme_font_override("font",font)
		label.add_theme_font_size_override("font_size",caption[1])
		label.add_theme_color_override("font_color",Color("e2e9ed"))
		canvas.add_child(label)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(canvas.get_texture().get_image().save_png(args[2]) == OK)
	print("LAMP_PLAN_PNG ",args[2])
	canvas.queue_free()
	for frame: int in 2:
		await process_frame
	quit()
