shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

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

void fragment() {
	// Compute the actual render-pixel footprint before any divergent discard.
	vec2 screen_pixels = SCREEN_UV * viewport_size;
	vec2 pixel_footprint = fwidth(screen_pixels);
	float aperture_radius = max(window_radius_pixels - max(pixel_footprint.x, pixel_footprint.y), 0.0);
	ALBEDO = source_albedo.rgb;
	if (has_source_texture) {
		ALBEDO *= texture(source_albedo_texture, UV).rgb;
	}
	ROUGHNESS = source_roughness;
	METALLIC = source_metallic;
	SPECULAR = source_specular;
	if (!IN_SHADOW_PASS && window_amount > 0.0 && window_radius_pixels > 0.0
			&& (!foreground_enabled || VERTEX.z > foreground_depth)) {
		// SCREEN_UV keeps the same top-left origin as Camera3D.unproject_position.
		// Keep the final pixel inside the shared window fully opaque, including
		// the PBR derivative footprint neighboring the aperture's hard cut.
		// The opaque pass keeps the original depth/PBR outside the aperture,
		// and the full geometry in shadow passes. next_pass fills only this hole.
		if (length(screen_pixels - window_center_pixels) < aperture_radius) {
			discard;
		}
	}
}
