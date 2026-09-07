shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 cone_color : source_color = vec4(0.2, 0.8, 1.0, 0.18);
uniform vec4 ground_contact_color : source_color = vec4(0.02, 0.2, 0.8, 0.65);
uniform mat4 world_to_cone;

void fragment() {
	// 從畫面深度還原可見地面位置；不新增物理碰撞，也不使用固定地板高度。
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 ground_position = world.xyz / world.w;
	vec3 local_position = (world_to_cone * vec4(ground_position, 1.0)).xyz;
	// 圓錐本地 Y 為 -0.5 到 +0.5；半徑從尖端的 0 線性增加到 1。
	float axial = local_position.y + 0.5;
	float radial = length(local_position.xz);
	vec3 surface_normal = normalize(cross(dFdx(ground_position), dFdy(ground_position)));
	bool on_ground = abs(surface_normal.y) > 0.65;
	bool inside_cone = axial >= 0.0 && axial <= 1.0 && radial <= axial;
	bool contact = depth > 0.0 && on_ground && inside_cone;
	vec4 color = contact ? ground_contact_color : cone_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
