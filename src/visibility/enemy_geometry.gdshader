shader_type spatial;
render_mode unshaded, fog_disabled;

uniform float depth_min = 0.0;
uniform float depth_span = 1.0;

vec2 oct_encode(vec3 normal) {
	normal /= abs(normal.x) + abs(normal.y) + abs(normal.z);
	vec2 encoded = normal.xy;
	if (normal.z < 0.0) {
		encoded = (1.0 - abs(encoded.yx)) * vec2(encoded.x >= 0.0 ? 1.0 : -1.0, encoded.y >= 0.0 ? 1.0 : -1.0);
	}
	return encoded * 0.5 + 0.5;
}

void fragment() {
	// Opaque occupancy: depth never participates in transparent blending.
	ALBEDO = vec3(oct_encode(normalize(NORMAL)), clamp((-VERTEX.z - depth_min) / depth_span, 0.0, 1.0));
}
