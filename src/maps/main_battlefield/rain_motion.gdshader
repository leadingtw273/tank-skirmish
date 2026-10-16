shader_type particles;
render_mode disable_force;

uint hash_value(uint value) {
	value = (value ^ (value >> 16u)) * 73244475u;
	value = (value ^ (value >> 16u)) * 73244475u;
	return value ^ (value >> uint(16));
}

float random_value(uint state) {
	return float(hash_value(state) & 16777215u) / 16777216.0;
}

vec2 wind(float time) {
	float gust = 1.0 + 0.4 * sin(time * 0.72);
	return vec2(2.2,-1.4) * gust + vec2(0.55*sin(time*0.43),0.65*sin(time*0.51));
}

vec4 drop_random(uint state) {
	// NUMBER 隨引擎週期更新；碰撞後的提早重生另混入時間，避免同一槽位在週期內重用落點。
	return vec4(random_value(state),random_value(state+31u),random_value(state+41u),random_value(state+53u));
}

void start() {
	vec4 sample = drop_random(NUMBER ^ RANDOM_SEED ^ uint(TIME * 65536.0));
	CUSTOM = vec4(sample.x,0.0,0.0,0.0);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3] = EMISSION_TRANSFORM * vec4((sample.yzw*2.0-1.0)*vec3(80.0,1.0,80.0),1.0);
	COLOR = vec4(1.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec2 breeze = wind(TIME);
	breeze += 0.28 * vec2(sin(TIME*3.7 + CUSTOM.x*TAU),cos(TIME*3.1 + CUSTOM.x*19.0));
	VELOCITY = vec3(breeze.x,-mix(17.0,21.0,CUSTOM.x)-3.0*CUSTOM.y*LIFETIME,breeze.y);
	// 把真實水平速度交給 draw shader；避免粒子 renderer 的對齊模式抹掉朝向。
	CUSTOM.zw = VELOCITY.xz;
	if (COLLIDED) {
		// 沿真正碰撞法線退回表面上方；不另猜地板高度，所以屋頂也有落雨錨點。
		vec3 normal = normalize(COLLISION_NORMAL);
		mat4 surface = mat4(1.0);
		surface[1].xyz = normal;
		vec3 reference = abs(normal.z) < 0.9 ? vec3(0.0,0.0,1.0) : vec3(1.0,0.0,0.0);
		surface[0].xyz = normalize(cross(normal,reference));
		surface[2].xyz = normalize(cross(surface[0].xyz,normal));
		surface[3].xyz = TRANSFORM[3].xyz + normal * (COLLISION_DEPTH + 0.018);
		uint impact_seed = INDEX ^ uint(TIME * 65536.0);
		emit_subparticle(surface,vec3(0.0),COLOR,vec4(CUSTOM.x,0.0,random_value(impact_seed),random_value(impact_seed+19u)),
			FLAG_EMIT_POSITION | FLAG_EMIT_ROT_SCALE | FLAG_EMIT_VELOCITY | FLAG_EMIT_COLOR | FLAG_EMIT_CUSTOM);
		// 此滴在接觸屋頂／地面時結束，槽位直接換到高空的全新落點；不在屋簷接續滴水。
		vec4 sample = drop_random(NUMBER ^ RANDOM_SEED ^ uint(TIME * 65536.0));
		CUSTOM = vec4(sample.x,0.0,0.0,0.0);
		TRANSFORM = mat4(1.0);
		TRANSFORM[3] = EMISSION_TRANSFORM * vec4((sample.yzw*2.0-1.0)*vec3(80.0,1.0,80.0),1.0);
		COLOR = vec4(1.0);
	}
}
