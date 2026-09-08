shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform vec4 line_color : source_color = vec4(0.05, 0.06, 0.08, 0.4);
uniform float dash_length = 1.0;
uniform float gap_length = 0.0;

void fragment() {
	float period = max(dash_length + gap_length, 0.0001);
	if (gap_length > 0.0 && mod(UV.x, period) > dash_length) {
		discard;
	}
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a;
}
