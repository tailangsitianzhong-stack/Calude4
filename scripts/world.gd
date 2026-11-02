class_name World
extends Node3D
## 最初の惑星(地球のような青空の惑星)の地表。平らな草原を中心に、丘・湖・山脈がある。

const SIZE := 256.0          ## 地形の一辺(m)
const CELLS := 128           ## 一辺の分割数
const WATER_LEVEL := -0.8
const LAKE_CENTER := Vector2(-48.0, 34.0)
const LAKE_RADIUS := 20.0
const PEAKS := [
	# x, z, 半径, 高さ
	Vector4(62.0, -55.0, 34.0, 24.0),
	Vector4(-70.0, -62.0, 28.0, 18.0),
	Vector4(30.0, 78.0, 26.0, 14.0),
]

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
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

	# 湖
	var ld := p.distance_to(LAKE_CENTER)
	h -= (1.0 - smoothstep(LAKE_RADIUS * 0.4, LAKE_RADIUS, ld)) * 3.2
	return h


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
	if h < WATER_LEVEL + 0.4:
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
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(LAKE_RADIUS * 2.6, LAKE_RADIUS * 2.6)
	water.mesh = plane
	water.position = Vector3(LAKE_CENTER.x, WATER_LEVEL, LAKE_CENTER.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.75, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


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
