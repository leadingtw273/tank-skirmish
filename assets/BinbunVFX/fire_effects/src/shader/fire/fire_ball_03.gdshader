shader_type spatial;
render_mode blend_mix;

uniform sampler2D noise_texture_1;
uniform vec2 texture_scale = vec2(1.0,1.0);
uniform float edge_softness = 0.5;
uniform float mask_from = 0.3;
uniform float mask_to = 1.0;

uniform vec4 glow_color : source_color = vec4(1.0,0.9,0.8,1.0);

float fresnel(float amount, vec3 normal, vec3 view)
{
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}

void vertex() {
	vec3 displace = vec3(1.0);
	displace.y = sin(NORMAL.z * TIME);
	displace.x = sin(NORMAL.z * TIME);
	displace.z = sin(NORMAL.x * TIME);
	displace *= 0.005;
	displace += sin(UV.y * TIME * 0.4 * 20.0) * 0.01;
	VERTEX += NORMAL * displace;
}


void fragment() {
	vec2 noise_uv_1 = UV + vec2(0.0, TIME * .1);
	float noise = texture(noise_texture_1, noise_uv_1).r;

	vec2 noise_uv_2 = UV + vec2(0.0, -TIME * .1);
	float mask = texture(noise_texture_1, noise_uv_2).r;

	float masked_noise = pow(mask * noise, 2.0);
	masked_noise = smoothstep(0.1, .3, masked_noise);

	vec3 dark = vec3(.5,noise*0.5,0.0);
	vec3 light = vec3(1.0, noise * .5 + .5, 0.2);

	vec3 main_color = mix(dark, light, masked_noise);
	main_color = mix(main_color, glow_color.rgb, fresnel(2.0, NORMAL, VIEW));

	ALBEDO = vec3(main_color);
	EMISSION = ALBEDO * 2.0;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
