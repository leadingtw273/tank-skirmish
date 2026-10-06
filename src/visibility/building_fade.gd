class_name BuildingFade
extends RefCounted

const FADE_SHADER := preload("res://src/visibility/building_fade.gdshader")
const SOFT_SHADER := preload("res://src/visibility/building_fade_soft.gdshader")
const COPIED_PROPERTIES := [&"albedo_color", &"roughness", &"metallic", &"metallic_specular"]

class SurfaceState extends RefCounted:
	var mesh: WeakRef
	var surface: int
	var original: Material
	var replacement: ShaderMaterial

var _building: WeakRef
var _surfaces: Array[SurfaceState] = []
var _meshes: Array[WeakRef] = []
var _defaults := StandardMaterial3D.new()


func _init(building: Node3D) -> void:
	if not is_instance_valid(building):
		return
	_building = weakref(building)
	_defaults.cull_mode = BaseMaterial3D.CULL_DISABLED
	_collect(building)


func update_window(center_pixels: Vector2, radius_pixels: float, viewport_size: Vector2, amount: float, foreground_depth: float = -INF) -> void:
	if not is_valid():
		return
	for state in _surfaces:
		for material in [state.replacement, state.replacement.next_pass]:
			material.set_shader_parameter(&"window_center_pixels", center_pixels)
			material.set_shader_parameter(&"window_radius_pixels", maxf(radius_pixels, 0.0))
			material.set_shader_parameter(&"viewport_size", viewport_size.max(Vector2.ONE))
			material.set_shader_parameter(&"window_amount", clampf(amount, 0.0, 1.0))
			material.set_shader_parameter(&"foreground_enabled", is_finite(foreground_depth))
			material.set_shader_parameter(&"foreground_depth", foreground_depth if is_finite(foreground_depth) else 0.0)


func restore() -> void:
	for state in _surfaces:
		var instance := state.mesh.get_ref() as MeshInstance3D
		if is_instance_valid(instance) and instance.mesh != null and state.surface < instance.mesh.get_surface_count():
			instance.set_surface_override_material(state.surface, state.original)
	_surfaces.clear()
	_meshes.clear()


func is_valid() -> bool:
	return _building != null and is_instance_valid(_building.get_ref())


func affected_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for reference in _meshes:
		var instance := reference.get_ref() as MeshInstance3D
		if is_instance_valid(instance):
			result.append(instance)
	return result


func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		_override_surfaces(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child)


func _override_surfaces(instance: MeshInstance3D) -> void:
	# Instance-wide materials take precedence over surface overrides.
	if instance.mesh == null or instance.material_override != null or instance.material_overlay != null:
		return
	var affected := false
	for surface in instance.mesh.get_surface_count():
		var source := instance.get_active_material(surface) as StandardMaterial3D
		if not _supports_source(source):
			continue
		var state := SurfaceState.new()
		state.mesh = weakref(instance)
		state.surface = surface
		state.original = instance.get_surface_override_material(surface)
		state.replacement = ShaderMaterial.new()
		state.replacement.shader = FADE_SHADER
		var soft := ShaderMaterial.new()
		soft.shader = SOFT_SHADER
		state.replacement.next_pass = soft
		for material in [state.replacement, soft]:
			material.set_shader_parameter(&"source_albedo", source.albedo_color)
			material.set_shader_parameter(&"source_roughness", source.roughness)
			material.set_shader_parameter(&"source_metallic", source.metallic)
			material.set_shader_parameter(&"source_specular", source.metallic_specular)
		instance.set_surface_override_material(surface, state.replacement)
		_surfaces.append(state)
		affected = true
	if affected:
		_meshes.append(weakref(instance))


func _supports_source(source: StandardMaterial3D) -> bool:
	if source == null or source.albedo_color.a != 1.0:
		return false
	# This adapter implements only the catalog's opaque, untextured PBR model.
	# Reject extra material features instead of silently losing their appearance.
	for property in source.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var property_name := StringName(property.name)
		if String(property_name).begins_with("resource_") or property_name in COPIED_PROPERTIES:
			continue
		if source.get(property_name) != _defaults.get(property_name):
			return false
	return true
