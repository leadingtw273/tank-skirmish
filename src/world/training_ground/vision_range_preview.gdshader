shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.2, 0.15);

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
