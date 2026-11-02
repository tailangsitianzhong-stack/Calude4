shader_type spatial;
// 水草。上のほうほど大きく揺れる。
render_mode cull_disabled;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.2 + wp.x * 0.7 + wp.z * 0.5) * 0.18 * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += cos(TIME * 0.9 + wp.x * 0.4) * 0.1 * VERTEX.y;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
}
