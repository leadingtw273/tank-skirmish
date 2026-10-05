shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 source_albedo : source_color = vec4(1.0);
uniform float source_roughness = 0.5;
uniform float source_metallic = 0.0;
uniform float source_specular = 0.5;
uniform vec2 window_center_pixels = vec2(0.0);
uniform float window_radius_pixels = 0.0;
uniform vec2 viewport_size = vec2(1.0);
uniform float window_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = source_albedo.rgb;
	ROUGHNESS = source_roughness;
	METALLIC = source_metallic;
	SPECULAR = source_specular;
	if (!IN_SHADOW_PASS && window_amount > 0.0 && window_radius_pixels > 0.0) {
		// SCREEN_UV keeps the same top-left origin as Camera3D.unproject_position.
		vec2 screen_pixels = SCREEN_UV * viewport_size;
		float distance_ratio = length(screen_pixels - window_center_pixels) / window_radius_pixels;
		float window_weight = 1.0 - smoothstep(0.75, 1.0, distance_ratio);
		float keep_fraction = 1.0 - 0.82 * clamp(window_amount, 0.0, 1.0) * window_weight;
		vec2 pixel = floor(FRAGCOORD.xy);
		float dither = fract(sin(dot(pixel, vec2(12.9898, 78.233))) * 43758.5453);
		if (dither > keep_fraction) {
			discard;
		}
	}
}
