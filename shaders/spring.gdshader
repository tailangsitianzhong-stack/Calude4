shader_type spatial;
// 温泉の湯。乳白色がかった青緑で、ゆらゆら揺れる。
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform vec3 color : source_color = vec3(0.3, 0.62, 0.62);

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	VERTEX.y += sin(world_xz.x * 1.5 + TIME * 2.0) * 0.02 + cos(world_xz.y * 1.3 + TIME * 1.7) * 0.02;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r > 0.97) {
		discard;
	}
	float ripple = sin(r * 18.0 - TIME * 2.5) * 0.5 + 0.5;
	ALBEDO = mix(color, vec3(0.75, 0.8, 0.78), ripple * 0.1 + smoothstep(0.85, 0.97, r) * 0.4);
	ALPHA = 0.82;
	ROUGHNESS = 0.45;
	SPECULAR = 0.15;
}
