## 管理單一履帶接地點的沙土煙塵；由 TankController 依實際移動速度更新，不判斷地面種類。
extends Node3D

## 煙塵粒子的等比尺寸倍率。
@export_range(0.1, 4.0, 0.05) var dust_scale := 0.85
## 每顆煙塵從生成到自然消散的秒數。
@export_range(0.1, 5.0, 0.05) var lifetime_seconds := 1.2
## 滿移動強度時，同時維持的煙塵粒子數量。
@export_range(1, 128, 1) var emission_amount := 28
## 預設為沙土灰褐色的煙塵顏色，避免使用毒霧綠色。
@export var dust_color := Color(0.45, 0.38, 0.29, 0.62)

@onready var dust_particles: GPUParticles3D = $DustParticles

var emission_intensity := 0.0


func _ready() -> void:
	_apply_dust_parameters()
	set_motion_intensity(0.0)


## 由坦克 Inspector 的設定更新特效外觀與粒子壽命。
func set_dust_parameters(next_scale: float, next_lifetime_seconds: float, next_emission_amount: int) -> void:
	var resolved_scale := maxf(next_scale, 0.1)
	var resolved_lifetime := maxf(next_lifetime_seconds, 0.1)
	var resolved_amount := maxi(next_emission_amount, 1)
	var parameters_changed := not is_equal_approx(dust_scale, resolved_scale) \
		or not is_equal_approx(lifetime_seconds, resolved_lifetime) \
		or emission_amount != resolved_amount
	dust_scale = resolved_scale
	lifetime_seconds = resolved_lifetime
	emission_amount = resolved_amount
	if parameters_changed:
		_apply_dust_parameters()


## 以 0 到 1 的實際運動強度控制發射比例；不改寫粒子總量，避免加速時反覆重建粒子系統。
func set_motion_intensity(next_intensity: float) -> void:
	emission_intensity = clampf(next_intensity, 0.0, 1.0)
	if dust_particles == null:
		return
	if not is_equal_approx(dust_particles.amount_ratio, emission_intensity):
		dust_particles.amount_ratio = emission_intensity
	var should_emit := emission_intensity > 0.0
	if dust_particles.emitting != should_emit:
		dust_particles.emitting = should_emit


func _apply_dust_parameters() -> void:
	if dust_particles == null:
		return
	var resolved_lifetime := maxf(lifetime_seconds, 0.1)
	if not is_equal_approx(dust_particles.lifetime, resolved_lifetime):
		dust_particles.lifetime = resolved_lifetime
	if dust_particles.amount != emission_amount:
		dust_particles.amount = emission_amount
	var process_material := dust_particles.process_material as ParticleProcessMaterial
	if process_material == null:
		push_error("Tread dust VFX requires a ParticleProcessMaterial.")
		return
	var resolved_scale_min := maxf(dust_scale * 0.65, 0.01)
	var resolved_scale_max := maxf(dust_scale, resolved_scale_min)
	if not process_material.color.is_equal_approx(dust_color):
		process_material.color = dust_color
	if not is_equal_approx(process_material.scale_min, resolved_scale_min):
		process_material.scale_min = resolved_scale_min
	if not is_equal_approx(process_material.scale_max, resolved_scale_max):
		process_material.scale_max = resolved_scale_max
