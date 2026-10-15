## 原道路包路燈的自有剛體、光源及一次性淡出生命週期。
extends RigidBody3D

const ATMOSPHERE := preload("res://src/maps/main_battlefield/lamp_atmosphere.gd")
# 第 20 視覺層只供路燈模型：月光仍投影，暖燈可排除燈具本身。
const LAMP_SHADOW_LAYER := 1 << 19
@export_range(1, 2) var model_variant := 1
var toppled := false
var toppled_seconds := 0.0
var contact_count := 0
var light: OmniLight3D
var heads: Array[MeshInstance3D] = []
var visuals: Array[GeometryInstance3D] = []

func _ready() -> void:
	mass = 160.0
	collision_layer = 128
	collision_mask = 129
	contact_monitor = true
	max_contacts_reported = 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 3, 0)
	linear_damp = 0.7
	angular_damp = 0.8
	axis_lock_linear_x = true
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	var source := load("res://assets/AtomicRealmModularRoads/lighting/lamp_%d.glb" % model_variant) as PackedScene
	var model := source.instantiate() as Node3D
	model.name = "OriginalModel"
	add_child(model)
	_collect_visuals(model)
	var pole := CapsuleShape3D.new()
	pole.radius = 0.18
	pole.height = 6.2
	_add_shape(pole, Vector3(0, 3.1, 0))
	var arm := BoxShape3D.new()
	arm.size = Vector3(2.9 if model_variant == 2 else 1.6, 0.24, 0.32)
	_add_shape(arm, Vector3(0 if model_variant == 2 else 0.62, 6.06, 0))
	var head_positions := PackedFloat32Array([-1.12, 1.12] if model_variant == 2 else [1.12])
	for x: float in head_positions:
		var head := MeshInstance3D.new()
		head.name = "WarmHead%d" % heads.size()
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := SphereMesh.new()
		mesh.radius = 0.16
		mesh.height = 0.18
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1, 0.72, 0.32)
		material.emission_enabled = true
		material.emission = Color(1, 0.58, 0.16)
		material.emission_energy_multiplier = 3.0
		mesh.material = material
		head.mesh = mesh
		head.position = Vector3(x, 6.02, 0)
		add_child(head)
		heads.append(head)
		visuals.append(head)
	light = OmniLight3D.new()
	light.name = "WarmLight"
	# 光源置於實際燈頭下方，避開燈柱及燈罩，保留模型對月光的柱影。
	light.position = Vector3(1.12, 5.65, 0)
	light.light_color = Color(1, 0.58, 0.14)
	light.light_energy = 6.0
	light.omni_range = 22.0
	light.omni_attenuation = 1.5
	light.shadow_caster_mask = 0xFFFFFFFF ^ LAMP_SHADOW_LAYER
	add_child(light)
	var atmosphere := ATMOSPHERE.new()
	atmosphere.name = "LampAtmosphere"
	add_child(atmosphere)
	body_entered.connect(_body_entered)

func _add_shape(shape: Shape3D, offset: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = offset
	add_child(collider)

func _collect_visuals(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(node as GeometryInstance3D).layers = LAMP_SHADOW_LAYER
		visuals.append(node as GeometryInstance3D)
	for child: Node in node.get_children():
		_collect_visuals(child)

func _body_entered(body: Node) -> void:
	if not body is ContactTank:
		return
	contact_count += 1
	if toppled:
		return
	toppled = true
	# 光及自有發光材質在首個接觸回呼立即熄滅；不碰原 GLB 材質。
	light.visible = false
	for head: MeshInstance3D in heads:
		var material := head.mesh.material as StandardMaterial3D
		material.emission_enabled = false
		material.albedo_color = Color(0.16, 0.15, 0.13)
	axis_lock_linear_x = false
	axis_lock_linear_z = false
	axis_lock_angular_x = false
	axis_lock_angular_y = false
	axis_lock_angular_z = false
	sleeping = false
	var direction: Vector3 = (body as RigidBody3D).linear_velocity
	direction.y = 0
	if direction.length_squared() < 0.01:
		direction = global_position - (body as Node3D).global_position
		direction.y = 0
	apply_torque_impulse(Vector3.UP.cross(direction.normalized()) * mass * 5.0)

func set_light_active(active: bool, casts_shadow: bool) -> void:
	# 距離更新不能重新點亮已倒下的燈。
	if toppled:
		return
	light.visible = active
	light.shadow_enabled = active and casts_shadow

func _physics_process(delta: float) -> void:
	if not toppled:
		return
	toppled_seconds += delta
	if toppled_seconds >= 7.0:
		queue_free()
	elif toppled_seconds >= 5.0:
		for visual: GeometryInstance3D in visuals:
			visual.transparency = clampf((toppled_seconds - 5.0) / 2.0, 0, 1)
