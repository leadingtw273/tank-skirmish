// 出生草場自有底材；與 Binbun 草葉共用色差、調色盤及受光計算。
shader_type spatial;

uniform sampler2D noise_texture;
uniform sampler2D color_gradient;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	ALBEDO = texture(color_gradient, vec2(noise_value, 0.0)).rgb;
}

void light() {
	DIFFUSE_LIGHT += dot(LIGHT, NORMAL) * ATTENUATION * LIGHT_COLOR;
}
