shader_type canvas_item;
render_mode unshaded;

uniform vec2 viewport_size = vec2(1.0);
uniform vec2 window_center = vec2(0.0);
uniform float radius_pixels = 0.0;

void fragment() {
	float interior = texture(TEXTURE, UV).a;
	float expanded = interior;
	// 約兩像素的圓形鄰域；先提原始 silhouette 外邊，再裁共同窗口。
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			if (x * x + y * y <= 4) {
				expanded = max(expanded, texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE).a);
			}
		}
	}
	float edge = max(expanded - interior, 0.0);
	float distance_pixels = length(UV * viewport_size - window_center);
	float clip = 1.0 - smoothstep(max(radius_pixels - 2.0, 0.0), radius_pixels, distance_pixels);
	COLOR = vec4(1.0, 0.025, 0.045, edge * clip);
}
