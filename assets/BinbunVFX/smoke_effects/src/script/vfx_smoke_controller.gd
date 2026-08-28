@tool
extends Node3D
class_name VFXSmokeController

## Works only in the editor. By default works like "emitting" on particles. When one_shot is enabled works as a button. 
@export var emitting : bool = true:
	set(value):
		emitting = value
		for p in _get_particles():
			p.emitting = emitting
			if emitting == true && reset_particles:
				_reset_particles()

## Wether to reset particles when animation loops
@export var reset_particles : bool = false

@export_group("General")
@export var emission_amount : int = 48:
	set(value):
		emission_amount = value
		for p in _get_particles():
			if p.is_in_group("ShadowCaster"):
				p.amount = emission_amount / 2
			else:
				p.amount = emission_amount
@export var lifetime : float = 2.0:
	set(value):
		lifetime = value
		for p in _get_particles():
			p.lifetime = lifetime
@export_range(0.0,1.0,0.05) var explosiveness : float = 0.0:
	set(value):
		explosiveness = value
		for p in _get_particles():
			p.explosiveness = explosiveness
@export_range(0, 10, 0.01) var speed_scale : float = 1.0:
	set(value):
		speed_scale = value
		_set_shader_params("time_scale", speed_scale)
		for p in _get_particles(): if is_instance_valid(p): p.speed_scale = value
@export var local_coords : bool = false:
	set(value):
		local_coords = value
		for p in _get_particles(): if is_instance_valid(p): p.local_coords = value

@export_group("Colors")
@export var primary_color : Color:
	set(value):
		primary_color = value
		_set_shader_params("primary_color", primary_color)
@export var secondary_color : Color:
	set(value):
		secondary_color = value
		_set_shader_params("secondary_color", secondary_color)
@export var tertiary_color : Color:
	set(value):
		tertiary_color = value
		_set_shader_params("tertiary_color", tertiary_color)

@export_group("Style")
@export var hard_clouds : bool = true:
	set(value):
		hard_clouds = value
		_set_shader_params("mask2_blend_mode", int(hard_clouds) * 9)
@export_range(0.0,1.0,0.01) var cloud_density : float = 0.7:
	set(value):
		cloud_density = value
		_set_shader_params("mask2_strength", cloud_density * 0.8 + 0.2)

@export_group("Shading")
@export_range(0.0,1.0,0.01) var normal_strength : float = 1.0:
	set(value):
		normal_strength = value
		_set_shader_params("normal_strength", normal_strength)
@export_range(0.0,1.0,0.01) var roughness : float = 0.8:
	set(value):
		roughness = value
		_set_shader_params("roughness", roughness)
## Emit transparent spheres to cast shadows. 
## [br][br]
## May cast shadows on the smoke itself, so it's suggested to increase [code]shadow_blur[/code] to hide that.
@export var fake_shadows : bool = true:
	set(value):
		fake_shadows = value
		get_node("ShadowCaster").visible = fake_shadows

@export_group("Transparency")
enum Alpha_Mode {
	## Smooth transparency. Most performance intensive
	SMOOTH, 
	## Displays transparency with a dithering pattern. Less performance intensive
	DITHER, 
	## Hard cut alpha. Like "Alpha Scissor" in [b]SpatialMaterial[/b]. Least performance intensive
	CUT,
	## Uses dithering and hard cut to achieve better results
	HYBRID
}
## Specifies how to handle [b]transparency[/b] within shaders.
@export var alpha_mode : Alpha_Mode = Alpha_Mode.SMOOTH:
	set(value):
		alpha_mode = value
		_set_shader_params("alpha_mode", alpha_mode)
@export_range(0.0,1.0,0.01) var alpha_cutoff : float = 0.02:
	set(value):
		alpha_cutoff = value
		_set_shader_params("alpha_cutoff", alpha_cutoff)
@export_range(0.0,1.0,0.01) var dither_cutoff : float = 0.8:
	set(value):
		dither_cutoff = value
		_set_shader_params("dither_cutoff", dither_cutoff)
@export var proximity_fade : bool = false:
	set(value):
		proximity_fade = value
		_set_shader_params("proximity_fade", proximity_fade)
@export var proximity_fade_distance : float = 1.0:
	set(value):
		proximity_fade_distance = value
		_set_shader_params("proximity_fade_distance", proximity_fade_distance)


@export_group("LODs")
## Specify resolution of meshes. 
## [br][br]
## [b]SphereMesh:[/b] Sets [code]radial_segments[/code] to the [b]value[/b] and
## [code]rings[/code] to [b]half the value[/b] 
## [br][br]
## [b]CylinderMesh:[/b] Sets [code]radial_segments[/code] to the [b]value[/b]
## [br][br]
## [b]PlaneMesh:[/b] Sets [code]subdivide_width[/code] and [code]subdivide_depth[/code] to the [b]value[/b]
@export var mesh_resolutions : int = 16:
	set(value):
		mesh_resolutions = value
		_set_mesh_resolutions(mesh_resolutions)

var particles : Array[GPUParticles3D] = []

func _get_particles() -> Array[GPUParticles3D]:
	var result : Array[GPUParticles3D] = []
	for p in get_children():
		if p is GPUParticles3D:
			result.append(p)
	return result

func _get_meshinstances() -> Array[MeshInstance3D]:
	var result : Array[MeshInstance3D] = []
	for m in get_children():
		if m is MeshInstance3D:
			result.append(m)
	return result

func _get_meshes() -> Array[Mesh]:
	var result : Array[Mesh]
	for p in _get_particles(): if is_instance_valid(p):
		result.append(p.draw_pass_1)
	for m in _get_meshinstances(): if is_instance_valid(m):
		result.append(m.mesh)
	return result

func _set_light_prop(pname : String, value) -> void:
	var light = get_node_or_null("Light")
	if light != null:
		light.set(pname, value)

func _reset_particles():
	for p in _get_particles():
		p.restart()

func _set_shader_params(name : String, value) -> void:
	for p in _get_particles():
		if is_instance_valid(p):
			if p.material_override is ShaderMaterial:
				p.material_override.set("shader_parameter/" + name, value)
	for m in _get_meshinstances():
		if is_instance_valid(m):
			if m.material_override is ShaderMaterial:
				m.material_override.set("shader_parameter/" + name, value)

func _set_mesh_resolutions(value : int) -> void:
	for m in _get_meshes(): if is_instance_valid(m):
		if m is SphereMesh:
			m.radial_segments = value
			m.rings = value/2
		if m is CylinderMesh:
			m.radial_segments = value
		if m is PlaneMesh:
			m.subdivide_width = value
			m.subdivide_depth = value
