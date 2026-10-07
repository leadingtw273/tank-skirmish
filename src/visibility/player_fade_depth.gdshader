shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform bool surface_enabled = true;
uniform vec2 window_center_pixels = vec2(0.0);
uniform float window_radius_pixels = 0.0;
uniform vec2 viewport_size = vec2(1.0);
uniform bool foreground_enabled = false;
uniform float foreground_depth = 0.0;

void fragment() {
	vec2 screen_pixels = SCREEN_UV * viewport_size;
	vec2 footprint = fwidth(screen_pixels);
	float aperture = max(window_radius_pixels - max(footprint.x, footprint.y), 0.0);
	if (!surface_enabled || length(screen_pixels - window_center_pixels) >= aperture
			|| (foreground_enabled && VERTEX.z <= foreground_depth)) {
		discard;
	}
	// RGB bytes preserve 1/4096 m precision in the linear HDR attachment.
	// Zero RGB + zero alpha is the clear background, never a valid surface.
	float code = floor(clamp(-VERTEX.z * 4096.0, 1.0, 16777215.0) + 0.5);
	ALBEDO = vec3(floor(code / 65536.0), mod(floor(code / 256.0), 256.0), mod(code, 256.0)) / 255.0;
}
