shader_type spatial;
render_mode blend_mix;

uniform sampler2D noise_texture_1;
uniform vec2 texture_scale = vec2(1.0,1.0);
uniform float edge_softness = 0.5;
uniform float mask_from = 0.3;
uniform float mask_to = 1.0;

void vertex() {
	VERTEX += NORMAL * (sin((UV.y + TIME * .4) * 20.0)*0.005) * (sin((VERTEX.x + TIME * .2) * 60.0) * 2.0);
}

float fresnel(float amount, vec3 normal, vec3 view)
{
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}

void fragment() {
	vec2 noise_uv = UV + vec2(0.0, TIME * .1);
	float noise = texture(noise_texture_1, noise_uv).r;

	float mask = abs(sin((UV.y + -TIME * .1) * 30.0));

	float masked_noise = pow(mask * noise, 2.0);
	masked_noise = smoothstep(0.1, .3, masked_noise);

	vec3 dark = vec3(.5,noise*0.5,0.0);
	vec3 light = vec3(1.0, noise * .5 + .5, 0.2);

	vec3 main_color = mix(dark, light, masked_noise);

	ALBEDO = vec3(main_color);
	EMISSION = ALBEDO * 2.0;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
