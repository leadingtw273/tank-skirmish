shader_type spatial;
render_mode blend_mix;

uniform sampler2D noise_texture;
uniform sampler2D mask_texture;

uniform vec4 main_color : source_color;
uniform vec4 edge_color : source_color;
uniform vec4 glow_color : source_color;
uniform float fresnel_multiplier = 0.0;

uniform float displace_strength = 0.01;

uniform vec2 texture_scale = vec2(1.0,1.0);

void vertex() {
	vec3 displace = vec3(1.0);
	displace.y = sin(NORMAL.z * TIME);
	displace.x = sin(NORMAL.z * TIME);
	displace.z = sin(NORMAL.x * TIME);
	displace *= 0.005;
	displace += sin(UV.y * TIME * 0.4 * 20.0) * displace_strength;
	VERTEX += NORMAL * displace;
}

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}

void fragment() {
	float mask = texture(mask_texture, UV).r * 1.0;
	float fres = fresnel(1.5, NORMAL, VIEW) * mask;
	
	float wave =sin((fres + TIME * .2) *20.0)*.4 * fres;
	wave = clamp(wave, 0.0, 1.0);
	
	vec2 noise_uv = (UV + vec2(TIME * .1)) * texture_scale;
	float noise = texture(noise_texture, noise_uv).r;
	
	float fres_noise_1 = smoothstep(0.1, 0.2, (fres * noise) + pow(fres, 4.0));
	float fres_noise_2 = fres * (noise * .2 + .8);
	float value = max(fres_noise_1, fres_noise_2) - wave;
	
	vec3 flame_color = mix(main_color, edge_color, noise).rgb;
	flame_color = mix(flame_color, glow_color.rgb, pow(fres, 2.0)*.3);
	flame_color += pow(1.0 - mask, 5.0);
	
	
	ALBEDO = flame_color + (fres * fresnel_multiplier);
	EMISSION = ALBEDO * 2.0;
	ALPHA = clamp(0.0, 1.0, value + (pow(1.0 - mask, 5.0) * .5) + (fres * fresnel_multiplier));
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
