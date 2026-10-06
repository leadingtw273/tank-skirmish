shader_type canvas_item;
render_mode unshaded;

uniform vec2 viewport_size = vec2(1.0);
uniform vec2 window_center = vec2(0.0);
uniform float radius_pixels = 0.0;
uniform sampler2D geometry_data : filter_nearest, repeat_disable;
uniform sampler2D smoke_alpha : filter_nearest, repeat_disable;
uniform float depth_min = 0.0;
uniform float depth_span = 1.0;
uniform mat4 inverse_projection;
uniform bool orthogonal = true;
uniform float normal_cos_threshold = 0.819152; // 35 degrees, not lighting/material changes.
uniform float depth_threshold = 0.06;

vec3 oct_decode(vec2 encoded) {
	vec2 xy = encoded * 2.0 - 1.0;
	vec3 normal = vec3(xy, 1.0 - abs(xy.x) - abs(xy.y));
	float fold = max(-normal.z, 0.0);
	normal.xy += vec2(normal.x >= 0.0 ? -fold : fold, normal.y >= 0.0 ? -fold : fold);
	return normalize(normal);
}

vec3 view_position(vec2 uv, float depth) {
	vec4 projected = inverse_projection * vec4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 1.0, 1.0);
	vec3 position = projected.xyz / projected.w;
	return orthogonal ? vec3(position.xy, -depth) : position * (-depth / position.z);
}

float feature(vec2 a_uv, vec2 b_uv) {
	vec4 a = texture(geometry_data, a_uv);
	vec4 b = texture(geometry_data, b_uv);
	if (a.a < 0.9 || b.a < 0.9) { return 0.0; }
	vec3 na = oct_decode(a.rg);
	vec3 nb = oct_decode(b.rg);
	if (dot(na, nb) < normal_cos_threshold) { return 1.0; }
	vec3 delta = view_position(b_uv, depth_min + b.b * depth_span) - view_position(a_uv, depth_min + a.b * depth_span);
	// Signed plane residual removes both orthographic/perspective surface slopes.
	float residual_a = abs(dot(na, delta)) / max(abs(na.z), 0.15);
	float residual_b = abs(dot(nb, delta)) / max(abs(nb.z), 0.15);
	return step(depth_threshold, min(residual_a, residual_b));
}

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
	float detail_edge = 0.0;
	if (interior > 0.9) {
		if (right.a > 0.9) { detail_edge = feature(UV, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)); }
		if (down.a > 0.9) { detail_edge = max(detail_edge, feature(UV, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y))); }
	}
	float smoke = texture(smoke_alpha, UV).a;
	float smoke_delta = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			smoke_delta = max(smoke_delta, abs(smoke - texture(smoke_alpha, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE).a));
		}
	}
	// 本車原 alpha interior 優先；煙不搶幾何內線，更不進 picking mask。
	float smoke_edge = smoothstep(0.06, 0.18, smoke_delta) * 0.35 * (1.0 - interior);
	float geometry_edge = max(max(outer_edge, internal_edge), detail_edge * 0.75);
	COLOR = vec4(1.0, 0.025, 0.045, max(geometry_edge, smoke_edge) * clip);
}
