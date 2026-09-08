shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.2, 0.15);
uniform float radius = 100.0;
uniform float near_radius = 25.0;
uniform float far_radius = 100.0;
uniform vec2 forward_direction = vec2(-1.0, 0.0);
uniform float half_angle_cos = 0.70710678;
varying vec2 ground_offset;

void vertex() {
	ground_offset = VERTEX.xz * radius;
}

void fragment() {
	// 同一張平面取圓與扇形的聯集；重疊區只著色一次。
	vec2 offset = ground_offset;
	float distance_to_center = length(offset);
	bool near_visible = distance_to_center <= near_radius;
	bool far_visible = distance_to_center <= far_radius
		&& dot(offset / max(distance_to_center, 0.00001), forward_direction) >= half_angle_cos;
	if (!near_visible && !far_visible) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
