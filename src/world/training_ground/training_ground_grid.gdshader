shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// The grid is evaluated from world coordinates so it remains continuous across the ground mesh.
uniform vec4 ground_color : source_color = vec4(0.34, 0.36, 0.38, 1.0);
uniform vec4 grid_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float grid_spacing : hint_range(0.25, 10.0, 0.25) = 1.0;
uniform float grid_width : hint_range(0.001, 0.25, 0.001) = 0.025;

varying vec3 training_ground_world_position;


void vertex() {
	training_ground_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 grid_coordinates = training_ground_world_position.xz / grid_spacing;
	vec2 cell_distance = min(fract(grid_coordinates), 1.0 - fract(grid_coordinates));
	float line_distance = min(cell_distance.x, cell_distance.y);
	float antialias_width = max(fwidth(line_distance), 0.0001);
	float line = 1.0 - smoothstep(grid_width, grid_width + antialias_width, line_distance);

	ALBEDO = mix(ground_color.rgb, grid_color.rgb, line);
	ROUGHNESS = 0.9;
}
