shader_type particles;
render_mode disable_force, disable_velocity;

void start() {
	VELOCITY = vec3(0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	// sub-emitter 不走一般發射週期；透明不等於回收，必須主動讓出槽位。
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
}
