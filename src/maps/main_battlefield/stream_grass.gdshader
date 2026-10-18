shader_type spatial;
render_mode blend_mix;

uniform bool billboard = false;

uniform sampler2D shape_texture;
uniform sampler2D shape_atlas;
uniform bool use_atlas = false;

group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient;
uniform float random_variation : hint_range(0.0, 1.0, 0.001) = 0.002;

group_uniforms Wind;
uniform sampler2D wind_texture;
uniform vec2 wind_velocity;

group_uniforms Transparency;
uniform float alpha_cut_start : hint_range(0.0, 1.0, 0.05) = 0.1;
uniform float alpha_cut_end : hint_range(0.0, 1.0, 0.05) = 0.9;
uniform int alpha_mode : hint_enum("Smooth", "Dithered", "Cut") = 0;

// Project-owned derivative; vendor bytes and appearance algorithms remain unchanged.
uniform vec2 stream_focus;
uniform float stream_time;
uniform vec4 view_edge_0;
uniform vec4 view_edge_1;
uniform vec4 view_edge_2;
uniform vec4 view_edge_3;
varying flat int id;
varying flat float stream_alpha;

float edge_distance(vec2 point, vec4 edge) {
	vec2 direction = edge.zw - edge.xy;
	return (direction.x * (point.y - edge.y) - direction.y * (point.x - edge.x)) / max(length(direction), 0.001);
}
varying vec3 world_pos;

#include "res://assets/BinbunGrass/shader/util/dither.gdshaderinc"

vec2 atlas_uv(vec2 uv, int index, int size){
	int tile_count = size * size;
	int i = index % tile_count;
	float x = float(i % size);
	float y = float(i / size);
	vec2 tile_size = 1.0 / vec2(float(size));
	return uv* tile_size + (vec2(x, y) * tile_size);
}

float randomf(int index, int seed){
	float value = sin(float(index + seed)) * 0.5 + 0.5;
	return value;
}

float wind_noise(){
	float value = texture(wind_texture, (world_pos.xz*0.03) - (vec2(TIME * 0.01) * wind_velocity)).r;
	return value;
}

vec3 wind(vec2 uv){
	float wind_noise = wind_noise();
	float wind_affect = pow(1.0 - uv.y, 2.0);
	vec3 value = vec3(
		wind_noise * (wind_velocity.x),
		0.0,
		wind_noise * (wind_velocity.y)) * 0.25;
	value *= wind_affect;
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	id = int(INSTANCE_CUSTOM.x);
	float layer = INSTANCE_CUSTOM.y;
	float ground_distance = distance(world_pos.xz, stream_focus);
	float view_distance = min(min(edge_distance(world_pos.xz, view_edge_0), edge_distance(world_pos.xz, view_edge_1)),
		min(edge_distance(world_pos.xz, view_edge_2), edge_distance(world_pos.xz, view_edge_3)));
	float density_alpha = layer < 0.5 ? 1.0 : (layer < 1.5 ? smoothstep(-8.0, 8.0, view_distance) : 1.0 - smoothstep(48.0, 64.0, ground_distance));
	stream_alpha = density_alpha * smoothstep(0.0, 0.35, stream_time - INSTANCE_CUSTOM.z);
	if (stream_alpha <= 0.0) {
		VERTEX = vec3(0.0);
	} else {

	if(billboard){
		mat4 billboard_matrix = mat4(
				MAIN_CAM_INV_VIEW_MATRIX[0],
				MAIN_CAM_INV_VIEW_MATRIX[1],
				MAIN_CAM_INV_VIEW_MATRIX[2],
				MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * billboard_matrix;

		VERTEX += (VIEW_MATRIX * vec4(wind(UV), 0.0)).xyz;
	} else {
		VERTEX += wind(UV);
	}
	}
	NORMAL = vec3(0.0,1.0,0.0);
}

void fragment() {
	float shape_value = texture(shape_texture, UV).r;
	if(use_atlas){
		vec2 atlas_uv = atlas_uv(UV, id, 2);
		shape_value = texture(shape_atlas, atlas_uv).r;
	}

	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	if(randomf(id,1) < random_variation) noise_value += 0.4;
	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));

	ALBEDO = color.rgb;

	float alpha = shape_value;
	// 與出生草相同的 coverage 路徑；串流漸入仍保留原 alpha，生成／密度／風動不變。
	ALPHA_HASH_SCALE = 1.0;
	if(alpha_mode == 0){
		ALPHA = alpha * stream_alpha;
	} else {
		alpha = clamp((shape_value - alpha_cut_start) / (alpha_cut_end - alpha_cut_start), 0.0, 1.0);
		if(alpha_mode == 1){
			alpha = step(bayer4(FRAGCOORD.xy) + 0.01, alpha);
		}
		if(alpha < 0.1) discard;
	}

}

void light(){
	float ndotl = dot(LIGHT, NORMAL) * ATTENUATION;
	DIFFUSE_LIGHT += ndotl * LIGHT_COLOR;
}
