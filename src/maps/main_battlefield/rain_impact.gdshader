shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, ambient_light_disabled, specular_disabled;

varying float age;
varying float variation;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	variation = INSTANCE_CUSTOM.x;
	VERTEX *= mix(0.65,1.3,INSTANCE_CUSTOM.z);
}

void fragment() {
	float radius = length(UV-vec2(0.5))*2.0;
	float ring = exp(-pow((radius-mix(0.08,0.86,age))/0.12,2.0));
	float fade = smoothstep(0.0,0.06,age) * pow(max(0.0,1.0-age),1.7);
	ALBEDO = vec3(0.48,0.60,0.70);
	EMISSION = ALBEDO * 0.22;
	ALPHA = ring * fade * mix(0.28,0.48,variation);
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * 2.6;
	}
}
