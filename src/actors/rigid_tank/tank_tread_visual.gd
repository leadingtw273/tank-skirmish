## Cosmetic belt motion only. Never receives a physics body or applies forces.
extends RefCounted

const SPEED_RATE := 6.0
var sides: Dictionary = {}
var reference_speed := 1.0
var multiplier := 1.0
var half_width := 1.0
var ready := false

func configure(player: AnimationPlayer, clip: StringName, reference: float, scale: float, width: float) -> bool:
	var source := player.get_animation(clip)
	if source == null or source.length <= 0.0: return false
	reference_speed = maxf(reference, 0.001)
	multiplier = scale
	half_width = width
	var animation_root := player.get_node(player.root_node)
	var total := 0
	for side in ["left", "right"]:
		var animation := source.duplicate() as Animation
		var suffix := ".L" if side == "left" else ".R"
		for index in range(animation.get_track_count() - 1, -1, -1):
			var path := animation.track_get_path(index)
			if path.get_subname_count() != 1 or not String(path.get_subname(0)).ends_with(suffix):
				animation.remove_track(index)
		var bindings: Array[Dictionary] = []
		for index in animation.get_track_count():
			var path := animation.track_get_path(index)
			var skeleton := animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
			if skeleton == null: return false
			var bone := skeleton.find_bone(path.get_subname(0))
			var type := animation.track_get_type(index)
			if bone < 0 or type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]: return false
			bindings.append({"skeleton": skeleton, "bone": bone, "type": type})
		if bindings.is_empty(): return false
		total += bindings.size()
		sides[side] = {"animation": animation, "bindings": bindings, "speed": 0.0, "target": 0.0, "phase": 0.0, "travel": 0.0}
	if total != source.get_track_count(): return false
	player.stop(true)
	player.active = false # One visual owner; no original AnimationPlayer competing for bones.
	ready = true
	return true

func step(delta: float, linear: float, command_yaw: float) -> void:
	if not ready or not is_finite(delta) or delta <= 0.0: return
	for side in sides:
		var data: Dictionary = sides[side]
		data.target = linear + command_yaw * half_width * (1.0 if side == "left" else -1.0)
		data.speed = move_toward(data.speed, data.target, SPEED_RATE * delta)
		# One conversion for straight, curved and pivot motion; negative speed reverses phase.
		var advance: float = data.speed / reference_speed * multiplier * delta
		data.travel += advance
		data.phase = fposmod(data.phase + advance, (data.animation as Animation).length)
		_sample(data)

func _sample(data: Dictionary) -> void:
	var animation: Animation = data.animation
	for index in data.bindings.size():
		var binding: Dictionary = data.bindings[index]
		var skeleton: Skeleton3D = binding.skeleton
		match binding.type:
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(binding.bone, animation.position_track_interpolate(index, data.phase) * skeleton.motion_scale)
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(binding.bone, animation.rotation_track_interpolate(index, data.phase))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(binding.bone, animation.scale_track_interpolate(index, data.phase))
