shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 source_albedo : source_color = vec4(1.0);
uniform bool has_source_texture = false;
uniform sampler2D source_albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float source_roughness = 0.5;
uniform float source_metallic = 0.0;
uniform float source_specular = 0.5;
uniform vec2 window_center_pixels = vec2(0.0);
uniform float window_radius_pixels = 0.0;
uniform vec2 viewport_size = vec2(1.0);
uniform float window_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool foreground_enabled = false;
uniform float foreground_depth = 0.0;
// Deliberately no source_color: the producer is a linear HDR data texture.
uniform sampler2D nearest_surface_depth : filter_nearest, repeat_disable;

void fragment() {
	// Match the opaque cut using one render pixel in logical screen units.
	// Derivatives must be evaluated before any conditional discard.
	vec2 screen_pixels = SCREEN_UV * viewport_size;
	vec2 pixel_footprint = fwidth(screen_pixels);
	float aperture_radius = max(window_radius_pixels - max(pixel_footprint.x, pixel_footprint.y), 0.0);
	if (IN_SHADOW_PASS || window_amount <= 0.0 || window_radius_pixels <= 0.0
			|| (foreground_enabled && VERTEX.z <= foreground_depth)) {
		discard;
	}
	// Match the opaque cut exactly; the window's final inner pixel is opaque.
	float radius = length(screen_pixels - window_center_pixels) / max(aperture_radius, 0.001);
	if (aperture_radius <= 0.0 || radius >= 1.0) {
		discard;
	}
	vec4 packed_depth = texture(nearest_surface_depth, SCREEN_UV);
	vec3 bytes = floor(packed_depth.rgb * 255.0 + 0.5);
	float nearest_depth = dot(bytes, vec3(65536.0, 256.0, 1.0)) / 4096.0;
	// One code step plus camera-space float rounding, far below model layers.
	if (packed_depth.a < 0.5 || abs(-VERTEX.z - nearest_depth) > 0.0005) {
		discard;
	}
	ALBEDO = source_albedo.rgb;
	if (has_source_texture) {
		ALBEDO *= texture(source_albedo_texture, UV).rgb;
	}
	ROUGHNESS = source_roughness;
	METALLIC = source_metallic;
	SPECULAR = source_specular;
	// Continuous alpha: clear at the center, almost clear across the inner
	// region, then a smooth outer transition to the untouched opaque pass.
	float radial_alpha = 0.06 * smoothstep(0.0, 0.70, radius) + 0.94 * smoothstep(0.70, 1.0, radius);
	ALPHA = mix(1.0, radial_alpha, clamp(window_amount, 0.0, 1.0));
}
