shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float falloff = exp(-radius * radius * 5.5) * (1.0 - smoothstep(0.6, 1.0, radius));
	ALBEDO = vec3(2.0, 0.85, 0.18);
	ALPHA = falloff * 0.48;
}
