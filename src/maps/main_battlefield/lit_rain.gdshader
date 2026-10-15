shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 lamp_positions[6];
uniform vec3 lamp_colors[6];
uniform float lamp_active[6];
uniform float lamp_ranges[6];
varying vec3 world_position;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	world_position = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 scattered_light = vec3(0.0);
	float illumination = 0.0;
	for (int i = 0; i < 6; i++) {
		float falloff = max(1.0 - distance(world_position, lamp_positions[i]) / max(lamp_ranges[i], 0.01), 0.0);
		float amount = falloff * falloff * lamp_active[i];
		scattered_light += lamp_colors[i] * amount * 0.8;
		illumination = max(illumination, amount);
	}
	// unshaded 的可見 HDR 輸出使用 ALBEDO。
	ALBEDO = vec3(0.60, 0.72, 0.85) + scattered_light;
	ALPHA = mix(0.36, 0.65, smoothstep(0.03, 0.48, illumination));
}
