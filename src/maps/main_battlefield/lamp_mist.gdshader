shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float noise_offset = 0.0;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float edge = exp(-radius * radius * 4.0) * (1.0 - smoothstep(0.7, 1.0, radius));
	float drift = noise(world_position.xz * 0.09 + vec2(TIME * 0.012, noise_offset));
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, textureLod(depth_texture, SCREEN_UV, 0.0).r, 1.0);
	float separation = -scene.z / scene.w + VERTEX.z;
	float soft_intersection = smoothstep(0.0, 1.2, separation);
	float warm = exp(-radius * radius * 2.5);
	ALBEDO = mix(vec3(0.06, 0.11, 0.18), vec3(1.0, 0.48, 0.14), warm);
	ALPHA = 0.11 * edge * mix(0.7, 1.0, drift) * soft_intersection;
}
