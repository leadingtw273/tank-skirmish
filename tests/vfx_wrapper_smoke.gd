extends SceneTree

const WRAPPER_PATH := "res://src/vfx/projectiles/javelin_projectile_vfx.tscn"
const MUZZLE_FLASH_WRAPPER_PATH := "res://src/vfx/muzzle/muzzle_flash_vfx.tscn"
const PROJECTILE_PATH := "res://src/combat/projectile.tscn"
const VENDOR_OVERVIEW_PATHS := [
	"res://assets/BinbunVFX/poison_effects/poison_effects_scene.tscn",
	"res://assets/BinbunVFX/smoke_effects/smoke_effects_scene.tscn",
]
const EXPECTED_PRIMARY := Color(0.96067125, 0.9248042, 0.8747243, 1)
const EXPECTED_SECONDARY := Color(1, 0.31764707, 0, 1)


func _init() -> void:
	for overview_path in VENDOR_OVERVIEW_PATHS:
		var overview_scene := load(overview_path) as PackedScene
		var overview := overview_scene.instantiate() if overview_scene != null else null
		if overview == null:
			_fail("Vendor overview scene must load: %s" % overview_path)
			return
		overview.free()

	var muzzle_flash_scene := load(MUZZLE_FLASH_WRAPPER_PATH) as PackedScene
	var muzzle_flash := muzzle_flash_scene.instantiate() if muzzle_flash_scene != null else null
	if muzzle_flash == null or not (muzzle_flash.get("primary_color") as Color).is_equal_approx(Color.WHITE) \
			or not (muzzle_flash.get("secondary_color") as Color).is_equal_approx(Color(1, 0.270588, 0, 1)):
		if muzzle_flash != null:
			muzzle_flash.free()
		_fail("Muzzle flash wrapper must load with the accepted vendor colors exposed on its root.")
		return
	muzzle_flash.free()

	var wrapper_scene := load(WRAPPER_PATH) as PackedScene
	if wrapper_scene == null:
		_fail("Javelin wrapper scene must load.")
		return

	var wrapper := wrapper_scene.instantiate()
	if not _has_expected_colors(wrapper):
		wrapper.free()
		return
	root.add_child(wrapper)
	if not _materials_received_wrapper_colors(wrapper):
		wrapper.queue_free()
		return
	wrapper.queue_free()

	var projectile_scene := load(PROJECTILE_PATH) as PackedScene
	var projectile := projectile_scene.instantiate() if projectile_scene != null else null
	if projectile == null:
		_fail("Gameplay projectile scene must load.")
		return
	var javelin := projectile.get_node_or_null("JavelinVFX")
	if javelin == null or javelin.scene_file_path != WRAPPER_PATH:
		projectile.free()
		_fail("Gameplay projectile must instance the src Javelin wrapper.")
		return
	projectile.free()

	print("VFX wrapper smoke validation passed.")
	quit(0)


func _has_expected_colors(wrapper: Node) -> bool:
	if not (wrapper.get("primary_color") as Color).is_equal_approx(EXPECTED_PRIMARY):
		_fail("Javelin wrapper primary color drifted.")
		return false
	if not (wrapper.get("secondary_color") as Color).is_equal_approx(EXPECTED_SECONDARY):
		_fail("Javelin wrapper secondary color drifted.")
		return false
	return true


func _materials_received_wrapper_colors(wrapper: Node) -> bool:
	for node_name in ["Head", "Core", "Trail"]:
		var mesh := wrapper.get_node_or_null(node_name) as MeshInstance3D
		var material := mesh.material_override as ShaderMaterial if mesh != null else null
		if material == null:
			_fail("Javelin wrapper is missing material for %s." % node_name)
			return false
		if not (material.get_shader_parameter("primary_color") as Color).is_equal_approx(EXPECTED_PRIMARY):
			_fail("Javelin wrapper did not apply primary color to %s." % node_name)
			return false
		if not (material.get_shader_parameter("secondary_color") as Color).is_equal_approx(EXPECTED_SECONDARY):
			_fail("Javelin wrapper did not apply secondary color to %s." % node_name)
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
