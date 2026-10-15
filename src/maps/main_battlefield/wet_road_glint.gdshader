shader_type spatial;
render_mode blend_add, cull_disabled, depth_draw_never, ambient_light_disabled, specular_disabled, fog_disabled;

uniform vec3 lamp_positions[6];
uniform float lamp_active[6];
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
	ALBEDO = vec3(1.0);
	ALPHA = 0.42;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
	vec3 light_direction = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
	for (int i = 0; i < 6; i++) {
		vec3 lamp_direction = normalize(lamp_positions[i] - world_position);
		if (lamp_active[i] < 0.5 || dot(light_direction, lamp_direction) < 0.999999) { continue; }
		vec2 toward_camera = normalize(INV_VIEW_MATRIX[2].xz);
		float mirror_offset = lamp_positions[i].y * length(INV_VIEW_MATRIX[2].xz) / max(INV_VIEW_MATRIX[2].y, 0.1);
		vec2 delta = world_position.xz - lamp_positions[i].xz - toward_camera * mirror_offset;
		float along = dot(delta, toward_camera) / 6.5;
		float across = dot(delta, vec2(-toward_camera.y, toward_camera.x)) / 0.85;
		float film = 0.93 + 0.07 * noise(world_position.xz * 0.75 + vec2(TIME * 0.025, 0.0));
		float reflection = exp(-across * across * 2.0 - along * along * 1.2) * film;
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * reflection * 6.0;
	}
	}
}
