shader_type spatial;
render_mode blend_mix;

uniform sampler2D noise_texture_1;
uniform vec2 texture_scale = vec2(1.0,1.0);
uniform float edge_softness = 0.5;
uniform float mask_from = 0.3;
uniform float mask_to = 1.0;

void vertex() {
	// Called for every vertex the material is visible on.
	VERTEX += NORMAL * (sin((UV.y + TIME * .4) * 40.0)*0.01);
}

void fragment() {
	float mask = smoothstep(mask_from,mask_to,UV.y);

	vec2 noise_uv = UV * texture_scale + vec2(0.0, TIME * 1.0);

	float noise = texture(noise_texture_1,noise_uv).r;

	float masked_noise = mask * noise;
	masked_noise = smoothstep(0.15, .2, masked_noise);
	float tip = smoothstep(0.5,1.0,mask);

	ALBEDO = mix(vec3(1.0, noise * mask *.5+ .5, 0.2), vec3(1.0,0.9,0.8), tip);
	EMISSION = ALBEDO * 2.0;

	ALPHA = masked_noise + tip;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
