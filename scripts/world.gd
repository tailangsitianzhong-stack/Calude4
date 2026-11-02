class_name World
extends Node3D
## 最初の惑星(地球のような青空の惑星)の地表。平らな草原を中心に、丘・湖・山脈がある。

const SIZE := 256.0          ## 地形の一辺(m)
const CELLS := 128           ## 一辺の分割数
const WATER_LEVEL := -0.8
const LAKE_CENTER := Vector2(-48.0, 34.0)
const LAKE_RADIUS := 22.0
const LAKE_DEPTH := 4.0
const ISLAND := Vector3(-43.0, 29.0, 3.8)   ## 湖の小島(x, z, 半径)
const PEAKS := [
	# x, z, 半径, 高さ
	Vector4(62.0, -55.0, 34.0, 24.0),
	Vector4(-70.0, -62.0, 28.0, 18.0),
	Vector4(30.0, 78.0, 26.0, 14.0),
]

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var sun: DirectionalLight3D


func build(seed_value: int) -> void:
	noise.seed = seed_value
	noise.frequency = 0.008
	noise.fractal_octaves = 3
	detail.seed = seed_value + 1
	detail.frequency = 0.05
	detail.fractal_octaves = 2
	ridge.seed = seed_value + 2
	ridge.frequency = 0.025
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	lake_noise.seed = seed_value + 3
	lake_noise.frequency = 0.9

	_make_environment()
	_make_terrain()
	_make_water()


# ---------------------------------------------------------------- 高さ

func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := p.length()
	var h := noise.get_noise_2d(x, z) * 3.0 + detail.get_noise_2d(x, z) * 0.35

	# スタート地点の周りはなだらかな草原
	h *= lerpf(0.25, 1.0, smoothstep(10.0, 45.0, d))

	# 外周の山脈(世界の端)
	var rim := smoothstep(78.0, 120.0, d)
	h += rim * (14.0 + (ridge.get_noise_2d(x, z) + 1.0) * 14.0)

	# 内側の山
	for pk in PEAKS:
		var dist := p.distance_to(Vector2(pk.x, pk.y))
		var t := 1.0 - smoothstep(0.0, pk.z, dist)
		if t > 0.0:
			h += t * t * (pk.w * (0.75 + (ridge.get_noise_2d(x * 1.3, z * 1.3) + 1.0) * 0.3))

	# 湖(岸の形はノイズでいびつに)と小島
	var lf := lake_factor(x, z)
	if lf > 0.0:
		h = lerpf(h, WATER_LEVEL - LAKE_DEPTH, smoothstep(0.0, 1.0, lf))
		var id := p.distance_to(Vector2(ISLAND.x, ISLAND.y))
		h += (1.0 - smoothstep(ISLAND.z * 0.4, ISLAND.z * 1.6, id)) * (LAKE_DEPTH + 1.3)
	return h


## 湖の中心に近いほど 1、岸の外は 0
func lake_factor(x: float, z: float) -> float:
	var v := Vector2(x, z) - LAKE_CENTER
	var d := v.length()
	if d > LAKE_RADIUS * 1.5:
		return 0.0
	var dir := v / maxf(d, 0.001)
	var r := LAKE_RADIUS * (1.0 + lake_noise.get_noise_2d(dir.x * 2.0, dir.y * 2.0) * 0.45)
	return 1.0 - smoothstep(r * 0.45, r, d)


func in_lake(x: float, z: float) -> bool:
	return lake_factor(x, z) > 0.0 and height_at(x, z) < WATER_LEVEL


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func surface(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## 草原や山などの「地帯」。物を置く場所を決めるのに使う
func zone_at(x: float, z: float) -> String:
	var h := height_at(x, z)
	var slope := 1.0 - normal_at(x, z).y
	if lake_factor(x, z) > 0.0 and h < WATER_LEVEL + 0.4:
		return "water"
	if h > 9.0 or slope > 0.28:
		return "mountain"
	if h > 3.5 or slope > 0.12:
		return "hill"
	return "grass"


func _color_at(x: float, z: float, h: float, n: Vector3) -> Color:
	var grass := Color(0.26, 0.46, 0.16).lerp(Color(0.34, 0.52, 0.18), (detail.get_noise_2d(x * 0.6, z * 0.6) + 1.0) * 0.5)
	var dry := Color(0.42, 0.47, 0.2)
	var mud := Color(0.24, 0.27, 0.16)
	var rock := Color(0.42, 0.4, 0.38)
	var snow := Color(0.95, 0.96, 0.98)
	var c := grass.lerp(dry, clampf((noise.get_noise_2d(x * 2.0, z * 2.0) - 0.2) * 2.0, 0.0, 0.5))
	# 水の中だけ泥っぽく(岸までは草)
	if h < WATER_LEVEL:
		c = c.lerp(mud, clampf((WATER_LEVEL - h) / 0.6, 0.0, 1.0))
	var slope := 1.0 - n.y
	c = c.lerp(rock, clampf((slope - 0.18) * 5.0, 0.0, 1.0))
	c = c.lerp(rock, clampf((h - 9.0) / 4.0, 0.0, 1.0))
	c = c.lerp(snow, clampf((h - 20.0) / 3.0, 0.0, 1.0) * clampf(1.4 - slope * 2.0, 0.0, 1.0))
	return c


# ---------------------------------------------------------------- 生成

func _make_terrain() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var step := SIZE / CELLS
	var half := SIZE / 2.0
	for iz in CELLS + 1:
		for ix in CELLS + 1:
			var x := -half + ix * step
			var z := -half + iz * step
			var h := height_at(x, z)
			var n := normal_at(x, z)
			verts.append(Vector3(x, h, z))
			normals.append(n)
			colors.append(_color_at(x, z, h, n))
	var row := CELLS + 1
	for iz in CELLS:
		for ix in CELLS:
			var i := iz * row + ix
			# 上から見て時計回り = 表面
			indices.append_array([i, i + 1, i + row, i + 1, i + row + 1, i + row])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)


func _make_water() -> void:
	# 湖の深さを画像に焼き込んで、水面の色(浅い所は明るく、深い所は濃く)と岸の白い泡に使う
	var extent := LAKE_RADIUS * 3.2
	var res := 128
	var img := Image.create(res, res, false, Image.FORMAT_RF)
	for iy in res:
		for ix in res:
			var x := LAKE_CENTER.x + (float(ix) / (res - 1) - 0.5) * extent
			var z := LAKE_CENTER.y + (float(iy) / (res - 1) - 0.5) * extent
			var depth := 0.0
			if lake_factor(x, z) > 0.0:
				depth = clampf((WATER_LEVEL - height_at(x, z)) / LAKE_DEPTH, -1.0, 1.0)
			img.set_pixel(ix, iy, Color(depth, 0, 0))
	var depth_tex := ImageTexture.create_from_image(img)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("depth_tex", depth_tex)
	var n1 := NoiseTexture2D.new()
	n1.seamless = true
	n1.as_normal_map = true
	n1.bump_strength = 6.0
	n1.width = 256
	n1.height = 256
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	n1.noise = fn
	mat.set_shader_parameter("wave_normal", n1)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	water.mesh = plane
	water.material_override = mat
	water.position = Vector3(LAKE_CENTER.x, WATER_LEVEL, LAKE_CENTER.y)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


## 湖のまわりの飾り: 葦・スイレン・岸の石・桟橋
func make_lake_details(rng: RandomNumberGenerator) -> void:
	add_child(_reeds(rng))
	add_child(_lily_pads(rng))
	add_child(_shore_stones(rng))
	_make_pier()


func _shore_points(rng: RandomNumberGenerator, count: int, min_h: float, max_h: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var tries := 0
	while pts.size() < count and tries < count * 40:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * LAKE_RADIUS * 1.5
		var x := LAKE_CENTER.x + cos(a) * r
		var z := LAKE_CENTER.y + sin(a) * r
		var h := height_at(x, z)
		if lake_factor(x, z) <= 0.0 and h > WATER_LEVEL + 0.4:
			continue
		if h - WATER_LEVEL >= min_h and h - WATER_LEVEL <= max_h:
			pts.append(Vector3(x, h, z))
	return pts


func _reeds(rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.32, 0.5, 0.22)
	var tip := Color(0.55, 0.68, 0.32)
	for i in 6:
		var a := i * TAU / 6.0 + 0.3 * i
		var off := Vector3(cos(a), 0, sin(a)) * 0.12
		var h := 1.1 + 0.35 * (i % 3)
		var lean := Vector3(cos(a), 0, sin(a)) * 0.15
		var w := Vector3(-sin(a), 0, cos(a)) * 0.025
		st.set_color(green); st.add_vertex(off - w)
		st.set_color(green); st.add_vertex(off + w)
		st.set_color(tip); st.add_vertex(off + lean + Vector3(0, h, 0))
	# ガマの穂
	for i in 2:
		var c := Vector3(0.05 - i * 0.1, 1.25 + i * 0.2, 0.03)
		for f in [[Vector3(-0.03, 0, 0), Vector3(0.03, 0, 0)], [Vector3(0, 0, -0.03), Vector3(0, 0, 0.03)]]:
			var brown := Color(0.42, 0.26, 0.14)
			st.set_color(brown); st.add_vertex(c + f[0])
			st.set_color(brown); st.add_vertex(c + f[1])
			st.set_color(brown); st.add_vertex(c + f[1] + Vector3(0, 0.22, 0))
			st.set_color(brown); st.add_vertex(c + f[0])
			st.set_color(brown); st.add_vertex(c + f[1] + Vector3(0, 0.22, 0))
			st.set_color(brown); st.add_vertex(c + f[0] + Vector3(0, 0.22, 0))
	st.generate_normals()
	return _scatter(st.commit(), _shore_points(rng, 260, -0.7, 0.35), rng, 0.8, 1.3, true)


func _lily_pads(rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.25, 0.5, 0.2)
	var seg := 14
	for i in seg - 1:  # 1か所切れ込みのある円
		var a0 := (i + 0.5) * TAU / seg
		var a1 := (i + 1.5) * TAU / seg
		st.set_color(c); st.add_vertex(Vector3.ZERO)
		st.set_color(c); st.add_vertex(Vector3(cos(a1), 0, sin(a1)) * 0.38)
		st.set_color(c); st.add_vertex(Vector3(cos(a0), 0, sin(a0)) * 0.38)
	st.generate_normals()
	var pads := _shore_points(rng, 90, -2.0, -0.4)
	for i in pads.size():
		pads[i].y = WATER_LEVEL + 0.02
	var mmi := _scatter(st.commit(), pads, rng, 0.7, 1.4, false)
	# ところどころに花
	for i in range(0, pads.size(), 6):
		var flower := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.12
		flower.mesh = sm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.7, 0.85) if i % 12 else Color(1, 1, 0.95)
		flower.material_override = fm
		flower.position = pads[i] + Vector3(0.05, 0.05, 0.05)
		add_child(flower)
	return mmi


func _shore_stones(rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.26
	sm.radial_segments = 7
	sm.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.34, 0.31)
	m.roughness = 0.95
	sm.material = m
	return _scatter(sm, _shore_points(rng, 70, -0.3, 0.5), rng, 0.5, 1.3, false)


func _scatter(mesh: Mesh, pts: Array[Vector3], rng: RandomNumberGenerator, smin: float, smax: float, use_vc: bool) -> MultiMeshInstance3D:
	if mesh.get_surface_count() > 0 and mesh.surface_get_material(0) == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = use_vc
		m.vertex_color_is_srgb = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.9
		mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		var s := rng.randf_range(smin, smax)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s)), pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## 草原側の岸から湖へ伸びる木の桟橋(歩ける)
func _make_pier() -> void:
	var dir := (-LAKE_CENTER).normalized()
	# 岸(水面と同じ高さになる所)を探す
	var start := LAKE_CENTER
	for i in 200:
		var p := LAKE_CENTER + dir * (i * 0.25)
		if height_at(p.x, p.y) > WATER_LEVEL + 0.3:
			start = p
			break
	var length := 9.0
	var deck_y := WATER_LEVEL + 0.55
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var yaw := atan2(dir.x, dir.y)
	var center := start - dir * (length / 2.0 - 1.0)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, deck_y, center.y))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.6, 0.42, 0.26)
	wood.roughness = 0.85
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.38, 0.26, 0.15)
	for i in int(length / 0.32):
		var plank := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 0.07, 0.29)
		plank.mesh = bm
		plank.material_override = wood if i % 3 else dark
		plank.position = Vector3(0, 0, -length / 2.0 + 0.16 + i * 0.32)
		body.add_child(plank)
	for zi in 4:
		for x in [-0.85, 0.85]:
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.1
			cm.height = 3.6
			post.mesh = cm
			post.material_override = dark
			post.position = Vector3(x, -1.6, -length / 2.0 + 0.3 + zi * (length - 0.6) / 3.0)
			body.add_child(post)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.1, length)
	col.shape = shape
	body.add_child(col)


func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.48, 0.86)
	sky_mat.sky_horizon_color = Color(0.68, 0.8, 0.92)
	sky_mat.ground_horizon_color = Color(0.68, 0.8, 0.92)
	sky_mat.ground_bottom_color = Color(0.3, 0.38, 0.3)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 2.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

	# 遠くに見えるもう一つの月(ここが地球ではないことのしるし)
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 40.0
	sm.height = 80.0
	moon.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.86, 0.88, 0.95, 0.55)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	moon.material_override = mm
	moon.position = Vector3(-500, 330, -900)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)


## 草と花をたくさん生やす(見た目だけ)
func scatter_grass(rng: RandomNumberGenerator, count: int, flower_count: int) -> void:
	add_child(_tuft_multimesh(rng, count, false))
	add_child(_tuft_multimesh(rng, flower_count, true))


func _tuft_multimesh(rng: RandomNumberGenerator, count: int, flowers: bool) -> MultiMeshInstance3D:
	# 3枚の細い三角形を交差させた草の束
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 3 if flowers else 5
	for i in blades:
		var a := i * TAU / blades + 0.4 * i
		var dir := Vector3(cos(a), 0, sin(a)) * (0.05 if flowers else 0.045)
		var lean := Vector3(sin(a), 0, -cos(a)) * (0.0 if flowers else 0.08 + 0.03 * (i % 2))
		var tip_h := 0.32 if flowers else 0.3 + 0.08 * (i % 3)
		var base_col := Color(0.25, 0.48, 0.18)
		var tip_col := Color(0.55, 0.78, 0.32)
		st.set_normal(Vector3.UP)
		st.set_color(base_col)
		st.add_vertex(-dir)
		st.set_color(base_col)
		st.add_vertex(dir)
		st.set_color(tip_col)
		st.add_vertex(lean + Vector3(0, tip_h, 0))
	if flowers:
		for i in 4:
			var a := i * PI / 2.0
			st.set_normal(Vector3.UP)
			st.set_color(Color.WHITE)
			st.add_vertex(Vector3(0, 0.34, 0))
			st.set_color(Color.WHITE)
			st.add_vertex(Vector3(cos(a), 0, sin(a)) * 0.07 + Vector3(0, 0.36, 0))
			st.set_color(Color.WHITE)
			st.add_vertex(Vector3(cos(a + 0.9), 0, sin(a + 0.9)) * 0.07 + Vector3(0, 0.36, 0))
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var petal_colors := [Color(1.0, 0.92, 0.3), Color(1.0, 0.55, 0.7), Color(0.75, 0.6, 1.0), Color(1, 1, 1)]
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 6:
		tries += 1
		var r := sqrt(rng.randf()) * 95.0
		var a := rng.randf() * TAU
		var x := cos(a) * r
		var z := sin(a) * r
		if zone_at(x, z) != "grass":
			continue
		var s := rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		mm.set_instance_transform(placed, Transform3D(basis, surface(x, z) - Vector3(0, 0.03, 0)))
		var tint: Color = petal_colors[rng.randi() % petal_colors.size()] if flowers else Color(1, 1, 1).darkened(rng.randf() * 0.2)
		mm.set_instance_color(placed, tint)
		placed += 1
	mm.visible_instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
