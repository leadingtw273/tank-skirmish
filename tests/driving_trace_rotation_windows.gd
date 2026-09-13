## Windows 視窗驗證入口：只在本次測試將 recorder 單段設小，正式 F6 配置不變。
extends SceneTree

const PLAYTEST := "res://src/world/training_ground/training_ground_playtest.tscn"
const Recorder := preload("res://src/debug/driving_trace_recorder.gd")
const TEST_LIMIT := 262144

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load(PLAYTEST) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var recorder := root.get_node_or_null("DrivingTraceRecorder")
	if recorder == null:
		push_error("TRACE_ROTATION_WINDOWS FAIL: recorder missing")
		quit(1)
		return
	recorder.set("_limit_bytes", TEST_LIMIT)
	var initial_path := str(recorder.call("get_log_path"))
	var ready := false
	var marker_seen := false
	var frames_after_marker := 0
	for tick in 3600:
		await physics_frame
		if bool(recorder.get("_stopped")):
			push_error("TRACE_ROTATION_WINDOWS FAIL: recorder stopped")
			quit(1)
			return
		var active_path := str(recorder.call("get_log_path"))
		if not ready and active_path != initial_path:
			recorder.call("_flush")
			print("TRACE_ROTATION_WINDOWS_READY path=%s" % active_path)
			ready = true
		if ready and not marker_seen and tick % 15 == 0:
			recorder.call("_flush")
			var marker_path := str(recorder.get("_pinned_marker_path"))
			if marker_path.is_empty():
				marker_path = active_path
			var file := FileAccess.open(marker_path, FileAccess.READ)
			if file != null:
				while not file.eof_reached():
					var line := file.get_line()
					if line.is_empty():
						continue
					var row: Variant = JSON.parse_string(line)
					if row is Dictionary and row.get("type") == "marker" and row.get("label") == "f4":
						marker_seen = true
						print("TRACE_ROTATION_WINDOWS_MARKER path=%s seq=%s frame=%s" % [marker_path, row.get("seq"), row.get("frame")])
				file.close()
		if marker_seen:
			frames_after_marker += 1
			if frames_after_marker >= 120:
				recorder.call("stop")
				current_scene = null
				scene.queue_free()
				await process_frame
				await process_frame
				print("TRACE_ROTATION_WINDOWS PASS: marker after rotation and 120 continuing physics frames")
				quit(0)
				return
	push_error("TRACE_ROTATION_WINDOWS FAIL: F4 timeout after rotation")
	quit(1)
