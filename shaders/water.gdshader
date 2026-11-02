shader_type spatial;
// 湖の水面。深さの画像で色と透明度を変え、岸には白い泡、表面には流れる小さな波。
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.32, 0.72, 0.72);
uniform vec3 deep_color : source_color = vec3(0.04, 0.22, 0.42);

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	VERTEX.y += sin(world_xz.x * 0.6 + TIME * 1.3) * 0.025 + cos(world_xz.y * 0.5 + TIME * 1.1) * 0.025;
}

void fragment() {
	float d = texture(depth_tex, UV).r;
	if (d <= 0.0) {
		discard;
	}
	float deep = smoothstep(0.0, 0.55, d);
	vec3 col = mix(shallow_color, deep_color, deep);
	// 岸の泡(ゆらゆら動く)
	float edge = 0.035 + 0.02 * sin(TIME * 1.7 + world_xz.x * 0.8 + world_xz.y * 0.6);
	float foam = 1.0 - smoothstep(0.0, edge, d);
	col = mix(col, vec3(0.95), foam * 0.85);
	ALBEDO = col;
	ALPHA = clamp(mix(0.45, 0.93, deep) + foam * 0.4, 0.0, 1.0);
	vec2 uv1 = world_xz * 0.05 + vec2(TIME * 0.012, TIME * 0.008);
	vec2 uv2 = world_xz * 0.08 - vec2(TIME * 0.01, -TIME * 0.014);
	NORMAL_MAP = normalize(texture(wave_normal, uv1).rgb + texture(wave_normal, uv2).rgb - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
