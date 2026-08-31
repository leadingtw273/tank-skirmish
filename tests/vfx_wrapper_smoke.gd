extends SceneTree

const WRAPPER_PATH := "res://src/vfx/projectiles/javelin_projectile_vfx.tscn"
const MUZZLE_FLASH_WRAPPER_PATH := "res://src/vfx/muzzle/muzzle_flash_vfx.tscn"
const IMPACT_WRAPPER_PATH := "res://src/vfx/impacts/impact_explosion_vfx.tscn"
const TREAD_DUST_WRAPPER_PATH := "res://src/vfx/tread_dust/tread_dust_vfx.tscn"
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
			or not (muzzle_flash.get("secondary_color") as Color).is_equal_approx(Color(0.7462728, 0.52009934, 0.25385872, 1)):
		if muzzle_flash != null:
			muzzle_flash.free()
		_fail("Muzzle flash wrapper must load with the accepted vendor colors exposed on its root.")
		return
	muzzle_flash.free()

	var impact_scene := load(IMPACT_WRAPPER_PATH) as PackedScene
	var impact := impact_scene.instantiate() if impact_scene != null else null
	if impact == null \
			or not (impact.get("primary_color") as Color).is_equal_approx(Color(0.890196, 0.627451, 0.0901961, 1)) \
			or not (impact.get("secondary_color") as Color).is_equal_approx(Color(0.890196, 0, 0.152941, 1)) \
			or not (impact.get("tertiary_color") as Color).is_equal_approx(Color(0.215686, 0.215686, 0.180392, 1)):
		if impact != null:
			impact.free()
		_fail("Impact wrapper must load with the accepted Explosion 05 colors exposed on its root.")
		return
	impact.free()

	var tread_dust_scene := load(TREAD_DUST_WRAPPER_PATH) as PackedScene
	var tread_dust := tread_dust_scene.instantiate() if tread_dust_scene != null else null
	var expected_dust_color := Color(0.45, 0.38, 0.29, 0.62)
	var dust_particles := tread_dust.get_node_or_null("DustParticles") as GPUParticles3D if tread_dust != null else null
	if tread_dust == null or dust_particles == null or dust_particles.local_coords or dust_particles.emitting \
			or not (tread_dust.get("dust_color") as Color).is_equal_approx(expected_dust_color):
		if tread_dust != null:
			tread_dust.free()
		_fail("Tread dust wrapper must expose sand-brown world-space particles that begin stopped.")
		return
	tread_dust.free()

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
