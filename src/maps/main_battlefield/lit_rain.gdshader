shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, ambient_light_disabled, specular_disabled;

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
	ALBEDO = vec3(0.60, 0.72, 0.85);
	EMISSION = ALBEDO;
	ALPHA = 0.36;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * 3.5;
	}
}
