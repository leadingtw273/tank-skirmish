// 專案自有平面草皮；公尺尺度的世界座標使色差固定於地表。
shader_type spatial;

uniform vec4 grass_dark : source_color = vec4(0.27, 0.36, 0.22, 1.0);
uniform vec4 grass_light : source_color = vec4(0.36, 0.43, 0.28, 1.0);
uniform float patch_size_meters : hint_range(1.0, 64.0, 0.5) = 12.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.92;

varying vec2 ground_world_xz;

float patch_hash(vec2 point) {
	vec3 mixed = fract(vec3(point.x, point.y, point.x) * 0.1031);
	mixed += dot(mixed, mixed.yzx + 33.33);
	return fract((mixed.x + mixed.y) * mixed.z);
}

float patch_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(
		mix(patch_hash(cell), patch_hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(patch_hash(cell + vec2(0.0, 1.0)), patch_hash(cell + vec2(1.0, 1.0)), blend.x),
		blend.y
	);
}

void vertex() {
	ground_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 patch_position = ground_world_xz / max(patch_size_meters, 0.001);
	float variation = patch_noise(patch_position) * 0.75
		+ patch_noise(patch_position * 3.0 + vec2(19.7, 8.3)) * 0.25;
	ALBEDO = mix(grass_dark.rgb, grass_light.rgb, variation);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
