shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, ambient_light_disabled, specular_disabled;

varying float opacity;

void vertex() {
	vec3 position = MODEL_MATRIX[3].xyz;
	vec4 center = VIEW_MATRIX * vec4(position,1.0);
	// 水平分量直接來自粒子真實速度；只朝向相機展寬，保留投影後的落下方向。
	vec3 velocity = vec3(INSTANCE_CUSTOM.z,-mix(17.0,21.0,INSTANCE_CUSTOM.x)-6.6*INSTANCE_CUSTOM.y,INSTANCE_CUSTOM.w);
	vec2 projected = (VIEW_MATRIX * vec4(normalize(velocity),0.0)).xy;
	vec2 along = normalize(projected + vec2(0.00001));
	vec2 across = vec2(along.y,-along.x);
	float height_layer = smoothstep(2.0,31.0,position.y);
	float depth_layer = 1.0-smoothstep(70.0,180.0,-center.z);
	float width = mix(0.55,1.1,fract(INSTANCE_CUSTOM.x*37.0+0.7)) * mix(0.62,1.1,height_layer);
	float length_scale = mix(0.55,1.45,fract(INSTANCE_CUSTOM.x*19.0+0.3)) * mix(0.65,1.05,height_layer);
	// 正交 F5 的原雨絲多半不到 0.3px；保留世界座標，僅補足柔邊取樣的最小寬度。
	float pixels_per_meter = length((PROJECTION_MATRIX * vec4(across,0.0,0.0)).xy * VIEWPORT_SIZE * 0.5);
	float world_width = max(0.028*width,mix(0.65,0.95,fract(INSTANCE_CUSTOM.x*43.0))/pixels_per_meter);
	float along_pixels = length((PROJECTION_MATRIX * vec4(along,0.0,0.0)).xy * VIEWPORT_SIZE * 0.5);
	// 遠景仍是細短斜線；避免長度縮到與寬度相近而讀成雪點。
	float world_length = max(0.38*length_scale,mix(5.5,8.0,fract(INSTANCE_CUSTOM.x*29.0))/along_pixels);
	VERTEX = vec3(across*(VERTEX.x/0.028)*world_width + along*(VERTEX.y/0.38)*world_length,0.0);
	MODELVIEW_MATRIX = mat4(1.0);
	MODELVIEW_MATRIX[3] = center;
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);
	opacity = mix(0.58,1.0,fract(INSTANCE_CUSTOM.x*53.0+0.2));
	opacity *= mix(0.85,1.0,height_layer) * mix(0.80,1.0,depth_layer);
}

void fragment() {
	float edge = 1.0-smoothstep(0.10,0.5,abs(UV.x-0.5));
	float ends = smoothstep(0.0,0.14,UV.y) * (1.0-smoothstep(0.60,1.0,UV.y));
	ALBEDO = vec3(0.48,0.60,0.74);
	EMISSION = ALBEDO * 0.32;
	ALPHA = 0.55 * opacity * edge * ends;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * 12.0;
	}
}
