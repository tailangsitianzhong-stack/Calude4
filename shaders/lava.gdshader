shader_type spatial;
// 溶岩の表面。ゆっくり流れる明るい割れ目と、黒く冷えた皮。
render_mode unshaded, cull_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.55, 0.12);
uniform vec3 warm : source_color = vec3(0.85, 0.18, 0.04);
uniform vec3 crust : source_color = vec3(0.12, 0.05, 0.03);

varying vec2 world_xz;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// 円の外は描かない
	float r = length(UV - 0.5) * 2.0;
	if (r > 1.0 + vnoise(world_xz * 0.8) * 0.06 - 0.06) {
		discard;
	}
	vec2 p = world_xz * 0.35;
	float n = vnoise(p + vec2(TIME * 0.05, TIME * 0.03)) * 0.6 + vnoise(p * 2.3 - vec2(TIME * 0.08, 0.0)) * 0.4;
	// 冷えた黒い皮は少しだけ。ほとんどは赤く光る溶岩
	float cracks = smoothstep(0.22, 0.4, n);
	vec3 col = mix(crust, warm, cracks);
	col = mix(col, hot, smoothstep(0.45, 0.68, n));
	ALBEDO = col * (1.0 + 0.15 * sin(TIME * 2.0 + n * 6.0));
}
