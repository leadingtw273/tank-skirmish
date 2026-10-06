shader_type canvas_item;
render_mode unshaded;

uniform vec2 viewport_size = vec2(1.0);
uniform vec2 window_center = vec2(0.0);
uniform float radius_pixels = 0.0;

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float interior = mask.a;
	float expanded = interior;
	// 約兩像素的圓形鄰域；先提原始 silhouette 外邊，再裁共同窗口。
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			if (x * x + y * y <= 4) {
				expanded = max(expanded, texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE).a);
			}
		}
	}
	float outer_edge = max(expanded - interior, 0.0);
	// 僅在兩個真 silhouette 像素間取粗部件鄰界；同部件的 mesh／surface 不產線。
	// 正向兩個鄰點把內線限在約一像素，不取三角面、法線或貼圖細節。
	vec4 right = texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0));
	vec4 down = texture(TEXTURE, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y));
	float internal_edge = 0.0;
	if (interior > 0.9) {
		if (right.a > 0.9 && length(mask.rgb - right.rgb) > 0.5) {
			internal_edge = 1.0;
		}
		if (down.a > 0.9 && length(mask.rgb - down.rgb) > 0.5) {
			internal_edge = 1.0;
		}
	}
	float distance_pixels = length(UV * viewport_size - window_center);
	float clip = 1.0 - smoothstep(max(radius_pixels - 2.0, 0.0), radius_pixels, distance_pixels);
	COLOR = vec4(1.0, 0.025, 0.045, max(outer_edge, internal_edge) * clip);
}
