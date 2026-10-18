shader_type spatial;
// 水面的短暫反光加在原路面上；不以透明底色蓋掉既有濕路高光。
render_mode blend_add, cull_disabled, depth_draw_never, ambient_light_disabled, specular_disabled;

varying float age;
varying float variation;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	variation = INSTANCE_CUSTOM.x;
	VERTEX *= mix(1.1,1.6,INSTANCE_CUSTOM.z);
}

void fragment() {
	float radius = length(UV-vec2(0.5))*2.0;
	// F5 的小環仍保留柔邊取樣；不讓不足一像素的環厚在遠景消失。
	float ring_width = max(0.09,fwidth(radius)*0.35);
	float ring = exp(-pow((radius-mix(0.30,0.92,age))/ring_width,2.0));
	float fade = smoothstep(0.0,0.06,age) * pow(max(0.0,1.0-age),1.1);
	ALBEDO = vec3(0.48,0.60,0.70);
	EMISSION = ALBEDO * 0.015;
	ALPHA = ring * fade * mix(0.55,0.75,variation);
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * 10.0;
	}
}
