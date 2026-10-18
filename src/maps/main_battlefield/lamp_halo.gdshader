shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

varying float below_opening;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec3 billboard_world = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 用世界水平面裁掉燈罩上方；不隨相機仰俯把光斑翻到罩頂。
	below_opening = MODEL_MATRIX[3].y + 0.45 - billboard_world.y;
}

void fragment() {
	if (below_opening <= 0.0) { discard; }
	float height = below_opening / 0.75;
	float spread = mix(0.15, 0.4, clamp(height, 0.0, 1.0));
	float across = (UV.x - 0.5) / spread;
	float falloff = exp(-across * across * 3.0 - height * height * 6.0);
	falloff *= smoothstep(0.0, 0.04, below_opening) * (1.0 - smoothstep(0.55, 0.9, below_opening));
	ALBEDO = vec3(2.0, 0.85, 0.18);
	ALPHA = falloff * 0.28;
}
