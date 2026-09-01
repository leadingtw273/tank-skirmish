## 管理單一履帶接地點的 SmokeThinVFX_01 煙塵；由世界層 SurfaceEffects 依接地互動更新。
extends Node3D

## 將 SmokeThin 原始六公尺面片縮到接近既有履帶煙塵大小的基準倍率。
const VENDOR_SCALE_FACTOR := 0.2
const SMOKE_BILLBOARD_SHADER := preload("res://src/vfx/tread_dust/smoke_thin_billboard.gdshader")
const SMOKE_BILLBOARD_PARAMETER := &"billboard"
const SMOKE_PROXIMITY_FADE_PARAMETER := &"proximity_fade"

## 煙塵粒子的等比尺寸倍率。
@export_range(0.1, 4.0, 0.05) var dust_scale := 0.85
## 每顆煙塵出生時相對於完整尺寸的比例。
@export_range(0.1, 1.0, 0.01) var initial_size_ratio := 0.65
## 每顆煙塵從生成到自然消散的秒數。
@export_range(0.1, 5.0, 0.05) var lifetime_seconds := 1.2
## 滿移動強度時，同時維持的煙塵粒子數量。
@export_range(2, 128, 1) var emission_amount := 28
## SmokeThin 使用的主色；次色與第三色會保留同色系並逐步加深。
@export var dust_color := Color(0.35, 0.35, 0.35, 1.0)

@onready var smoke_effect: Node3D = $SmokeThinVFX_01
@onready var dust_particles: GPUParticles3D = $SmokeThinVFX_01/Smoke
@onready var shadow_particles: GPUParticles3D = $SmokeThinVFX_01/ShadowCaster

var emission_intensity := 0.0


func _ready() -> void:
	_prepare_vendor_instance()
	_apply_dust_parameters()
	set_motion_intensity(0.0)


## 由 SurfaceEffects 的設定更新特效外觀、出生尺寸與粒子壽命。
func set_dust_parameters(
		next_scale: float,
		next_initial_size_ratio: float,
		next_lifetime_seconds: float,
		next_emission_amount: int,
) -> void:
	var resolved_scale := maxf(next_scale, 0.1)
	var resolved_initial_size_ratio := clampf(next_initial_size_ratio, 0.1, 1.0)
	var resolved_lifetime := maxf(next_lifetime_seconds, 0.1)
	var resolved_amount := maxi(next_emission_amount, 2)
	var parameters_changed := not is_equal_approx(dust_scale, resolved_scale) \
		or not is_equal_approx(initial_size_ratio, resolved_initial_size_ratio) \
		or not is_equal_approx(lifetime_seconds, resolved_lifetime) \
		or emission_amount != resolved_amount
	dust_scale = resolved_scale
	initial_size_ratio = resolved_initial_size_ratio
	lifetime_seconds = resolved_lifetime
	emission_amount = resolved_amount
	if parameters_changed:
		_apply_dust_parameters()


## 以 0 到 1 的實際運動強度控制 SmokeThin 主煙與陰影粒子的發射比例。
func set_motion_intensity(next_intensity: float) -> void:
	emission_intensity = clampf(next_intensity, 0.0, 1.0)
	var should_emit := emission_intensity > 0.0
	for particles in _particle_nodes():
		if not is_equal_approx(particles.amount_ratio, emission_intensity):
			particles.amount_ratio = emission_intensity
		if particles.emitting != should_emit:
			particles.emitting = should_emit


## 複製會在執行期調整的 vendor 材質，避免左右履帶共用同一份素材資源。
func _prepare_vendor_instance() -> void:
	for particles in _particle_nodes():
		particles.local_coords = false
		particles.emitting = false
		particles.amount_ratio = 0.0
		if particles.process_material != null:
			particles.process_material = particles.process_material.duplicate(true)
		if particles.material_override != null:
			particles.material_override = particles.material_override.duplicate(false)
	# 履帶專用 Shader 自行完成保留縮放的 billboard；關閉粒子層對齊，避免兩層重複旋轉。
	dust_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	var smoke_material := dust_particles.material_override as ShaderMaterial
	if smoke_material != null:
		smoke_material.shader = SMOKE_BILLBOARD_SHADER
		smoke_material.set_shader_parameter(SMOKE_BILLBOARD_PARAMETER, true)
		# 展示素材的貼面淡出會把貼近履帶與地面的煙塵吃掉；履帶 wrapper 不使用此效果。
		smoke_material.set_shader_parameter(SMOKE_PROXIMITY_FADE_PARAMETER, false)
	# 不繼承展示場景可能使用的暫停預覽值；履帶煙塵在遊戲內一律以正常時間播放。
	smoke_effect.set("speed_scale", 1.0)


func _apply_dust_parameters() -> void:
	if smoke_effect == null:
		return
	var resolved_scale := maxf(dust_scale, 0.1) * VENDOR_SCALE_FACTOR
	var resolved_lifetime := maxf(lifetime_seconds, 0.1)
	var resolved_amount := maxi(emission_amount, 2)
	smoke_effect.scale = Vector3.ONE * resolved_scale
	if smoke_effect.get("emission_amount") != resolved_amount:
		smoke_effect.set("emission_amount", resolved_amount)
	if not is_equal_approx(float(smoke_effect.get("lifetime")), resolved_lifetime):
		smoke_effect.set("lifetime", resolved_lifetime)
	smoke_effect.set("local_coords", false)
	smoke_effect.set("primary_color", dust_color)
	smoke_effect.set("secondary_color", dust_color.darkened(0.16))
	smoke_effect.set("tertiary_color", dust_color.darkened(0.43))
	for particles in _particle_nodes():
		_apply_initial_size_ratio(particles, initial_size_ratio)


## 只調整 wrapper 私有粒子材質的縮放曲線起點，不改動 Binbun 原始素材。
func _apply_initial_size_ratio(particles: GPUParticles3D, next_ratio: float) -> void:
	var process_material := particles.process_material as ParticleProcessMaterial
	if process_material == null or process_material.scale_curve == null:
		return
	var scale_curve: Curve = process_material.scale_curve.curve
	if scale_curve == null or scale_curve.point_count == 0:
		return
	scale_curve.set_point_value(0, clampf(next_ratio, 0.1, 1.0))


func _particle_nodes() -> Array[GPUParticles3D]:
	var result: Array[GPUParticles3D] = []
	if dust_particles != null:
		result.append(dust_particles)
	if shadow_particles != null:
		result.append(shadow_particles)
	return result
