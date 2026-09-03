shader_type spatial;
render_mode blend_mix;

uniform sampler2D noise_texture_1;
uniform float wave_scale = 30.0;

uniform vec4 main_color : source_color;
uniform vec4 edge_color : source_color;
uniform vec4 glow_color : source_color;

uniform float speed = 1.0;

uniform vec2 texture_scale = vec2(1.0,1.0);
uniform float mask_scale = 0.4;

vec2 scale(vec2 uv, float x, float y){
	mat2 scale = mat2(vec2(1.0/x, 0.0), vec2(0.0, 1.0/y));

	uv -= 0.5;
	uv = uv * scale;
	uv += 0.5;
	return uv;
}

float mask(vec2 uv){
	float mask = distance(vec2(0.5), scale(uv, mask_scale, mask_scale));
	mask = clamp(mask, 0.0, 1.0);
	return mask;
}

float wave(float mask, float w_scale, float w_speed){
	float wave = mix(.5, 1.0, sin((mask * w_scale * mask_scale) - (TIME * w_speed)*speed)) * 2.0;
	float masked_wave = wave * (1.0 - mask);
	return masked_wave;
}

void vertex(){
	VERTEX.y = wave(mask(UV), wave_scale, 10.0)*.1;
}

void fragment() {
	vec2 warp_noise_uv = (UV*1.5 - vec2(TIME * .1, TIME * .05)) * texture_scale;
	float warp_noise = texture(noise_texture_1, warp_noise_uv).r;
	vec2 noise_uv = (UV + vec2(TIME * .1)) * texture_scale;
	float noise = texture(noise_texture_1, noise_uv).r;

	noise = clamp(0.0,1.0, noise * warp_noise * 1.5);

	float mask = mask(UV);

	float noise_wave = wave(mask, wave_scale, 10.0) * noise;
	noise_wave = smoothstep(0.05,0.2,noise_wave);
	noise_wave += wave(mask, 10.0, 10.0)*.1;

	vec3 wave_color = mix(main_color, edge_color, noise_wave).rgb;
	wave_color = mix(wave_color, glow_color.rgb, pow(1.0-mask, 4.0));

	ALBEDO = wave_color;
	ALPHA = noise_wave;
	EMISSION = ALBEDO * 2.0;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
