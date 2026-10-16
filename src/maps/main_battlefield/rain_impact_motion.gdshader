shader_type particles;
render_mode disable_force, disable_velocity;

void start() {
	VELOCITY = vec3(0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
}
