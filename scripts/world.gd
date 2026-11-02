class_name World
extends Node3D
## 最初の惑星(地球のような青空の惑星)の地表。
## 中央の草原(スタート地点・湖)を囲んで、西に森林、東に砂漠、北に雪山、南に溶岩地帯がある。
## 洞窟が3つ(雪山・砂漠・溶岩地帯)、溶岩地帯には溶岩の池・温泉・間欠泉がある。

const SIZE := 520.0          ## 地形の一辺(m)
const CELLS := 196           ## 一辺の分割数
const WATER_LEVEL := -0.8
const LAKE_CENTER := Vector2(-48.0, 34.0)
const LAKE_RADIUS := 22.0
const LAKE_DEPTH := 4.0
const ISLAND := Vector3(-43.0, 29.0, 3.8)   ## 湖の小島(x, z, 半径)
const PEAKS := [
	# 地域の境目にある山(x, z, 半径, 高さ)
	Vector4(62.0, -55.0, 34.0, 24.0),
	Vector4(-70.0, -62.0, 28.0, 18.0),
	Vector4(48.0, 80.0, 26.0, 14.0),
]
## 地域の向き(角度)。東 = 0、南(+z) = 90度
const BIOME_ANGLES := {"desert": 0.0, "lava": PI / 2.0, "forest": PI, "snow": -PI / 2.0}
const BIOME_NAMES := {"grass": "草原", "forest": "森林", "desert": "砂漠", "snow": "雪山", "lava": "溶岩地帯"}
const VOLCANO := Vector4(10.0, 185.0, 58.0, 42.0)   ## 火山(x, z, 半径, 高さ)
const CRATER_R := 10.0
## 洞窟(x, z, 半径)。入口は世界の中心を向く
const CAVES := [Vector3(-25.0, -160.0, 13.0), Vector3(165.0, 25.0, 13.0), Vector3(-80.0, 150.0, 12.0)]
const RIM_START := 225.0

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var warp := FastNoiseLite.new()
var dune := FastNoiseLite.new()
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial

## 溶岩の池・温泉・間欠泉(build で場所を決める)
var lava_pools: Array[Vector4] = []    ## x, z, 半径, 表面の高さ
var hot_springs: Array[Vector4] = []   ## x, z, 半径, 表面の高さ
var geysers: Array[Vector3] = []       ## x, z, 次に噴き出すまでの秒
var _geyser_fx: Array[CPUParticles3D] = []
var _geyser_time: Array[float] = []
var time_of_day := 0.3                 ## 0〜1(0.25 = 日の出、0.5 = 正午、0.75 = 日の入り)
const DAY_SECONDS := 600.0


func build(seed_value: int) -> void:
	noise.seed = seed_value
	noise.frequency = 0.008
	noise.fractal_octaves = 3
	detail.seed = seed_value + 1
	detail.frequency = 0.05
	detail.fractal_octaves = 2
	ridge.seed = seed_value + 2
	ridge.frequency = 0.022
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	lake_noise.seed = seed_value + 3
	lake_noise.frequency = 0.9
	warp.seed = seed_value + 4
	warp.frequency = 0.006
	dune.seed = seed_value + 5
	dune.frequency = 0.012

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_place_features(rng)
	_make_environment()
	_make_terrain()
	_make_water()
	_make_feature_meshes()
	for c in CAVES:
		_make_cave(c, rng)


# ---------------------------------------------------------------- 地域

## 地域ごとの重み(合計 1)
func biome_weights(x: float, z: float) -> Dictionary:
	var d := Vector2(x, z).length()
	var t := smoothstep(70.0, 125.0, d)
	var a := atan2(z, x) + warp.get_noise_2d(x, z) * 0.9
	var w := {"grass": 1.0 - t}
	var sum := 0.0
	var raw := {}
	for b in BIOME_ANGLES:
		var v := pow(maxf(0.0, cos(a - BIOME_ANGLES[b])), 4.0)
		raw[b] = v
		sum += v
	for b in raw:
		w[b] = t * raw[b] / maxf(sum, 0.0001)
	return w


func biome_at(x: float, z: float) -> String:
	var w := biome_weights(x, z)
	var best := "grass"
	for b in w:
		if w[b] > w[best]:
			best = b
	return best


# ---------------------------------------------------------------- 高さ

func _base_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var h := noise.get_noise_2d(x, z) * 3.0 + detail.get_noise_2d(x, z) * 0.35
	return h * lerpf(0.25, 1.0, smoothstep(10.0, 45.0, d))


func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := p.length()
	var w := biome_weights(x, z)
	var base := _base_height(x, z)
	var h: float = base * w["grass"]
	if w["forest"] > 0.001:
		h += w["forest"] * (base * 1.3 + (noise.get_noise_2d(x * 2.5, z * 2.5) + 0.3) * 4.0)
	if w["desert"] > 0.001:
		var dn := dune.get_noise_2d(x, z)
		var dunes := absf(sin(x * 0.07 + dn * 3.0)) * 2.6 + dn * 2.0
		var mesa := smoothstep(0.32, 0.4, noise.get_noise_2d(x * 1.7 + 50.0, z * 1.7)) * 7.0
		h += w["desert"] * (dunes + mesa + 0.5)
	if w["snow"] > 0.001:
		var m := 4.0 + (ridge.get_noise_2d(x, z) + 1.0) * 13.0 * smoothstep(90.0, 170.0, d)
		h += w["snow"] * (base + m)
	if w["lava"] > 0.001:
		h += w["lava"] * (base * 0.7 + 0.8)

	for pk in PEAKS:
		var dist := p.distance_to(Vector2(pk.x, pk.y))
		var t := 1.0 - smoothstep(0.0, pk.z, dist)
		if t > 0.0:
			h += t * t * (pk.w * (0.75 + (ridge.get_noise_2d(x * 1.3, z * 1.3) + 1.0) * 0.3))

	# 火山と火口
	var vd := p.distance_to(Vector2(VOLCANO.x, VOLCANO.y))
	if vd < VOLCANO.z:
		var t := 1.0 - vd / VOLCANO.z
		h += pow(t, 1.6) * VOLCANO.w
		h -= (1.0 - smoothstep(CRATER_R * 0.5, CRATER_R * 1.4, vd)) * 16.0

	# 外周の山脈(世界の端)
	h += smoothstep(RIM_START, RIM_START + 30.0, d) * (18.0 + (ridge.get_noise_2d(x, z) + 1.0) * 16.0)

	# 溶岩の池・温泉のくぼみ
	for pool in lava_pools:
		h = _dent(h, p, pool, 1.2)
	for spring in hot_springs:
		h = _dent(h, p, spring, 1.4)

	# 洞窟の床は平らに
	for c in CAVES:
		var cd := p.distance_to(Vector2(c.x, c.y))
		if cd < c.z + 6.0:
			var floor_h := cave_floor(c)
			h = lerpf(floor_h, h, smoothstep(c.z - 1.0, c.z + 6.0, cd))

	# 湖(岸の形はノイズでいびつに)と小島
	var lf := lake_factor(x, z)
	if lf > 0.0:
		h = lerpf(h, WATER_LEVEL - LAKE_DEPTH, smoothstep(0.0, 1.0, lf))
		var id := p.distance_to(Vector2(ISLAND.x, ISLAND.y))
		h += (1.0 - smoothstep(ISLAND.z * 0.4, ISLAND.z * 1.6, id)) * (LAKE_DEPTH + 1.3)
	return h


## 池の中を表面より depth だけ低くする
func _dent(h: float, p: Vector2, pool: Vector4, depth: float) -> float:
	var dist := p.distance_to(Vector2(pool.x, pool.y))
	if dist > pool.z * 1.6:
		return h
	var bottom := pool.w - depth
	var t := 1.0 - smoothstep(pool.z * 0.55, pool.z * 1.15, dist)
	var rim := 1.0 - smoothstep(pool.z * 1.0, pool.z * 1.6, dist)
	h = lerpf(h, maxf(h, pool.w + 0.25), rim * (1.0 - t))   # 縁は少し盛り上げる
	return lerpf(h, bottom, t)


func cave_floor(c: Vector3) -> float:
	return _base_height(c.x, c.y) * 0.5 + 0.6


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


## その場所の液体 "water"(湖)/ "hot"(温泉)/ "lava" / ""
func liquid_at(p: Vector3) -> String:
	if p.y < WATER_LEVEL and lake_factor(p.x, p.z) > 0.0:
		return "water"
	var q := Vector2(p.x, p.z)
	for s in hot_springs:
		if q.distance_to(Vector2(s.x, s.y)) < s.z and p.y < s.w:
			return "hot"
	for l in lava_pools:
		if q.distance_to(Vector2(l.x, l.y)) < l.z * 0.95 and p.y < l.w + 0.15:
			return "lava"
	return ""


func in_cave(p: Vector3) -> bool:
	for c in CAVES:
		if Vector2(p.x, p.z).distance_to(Vector2(c.x, c.y)) < c.z - 1.0:
			return true
	return false


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func surface(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## 物を置く場所を決めるための「地帯」
## water / lava / cave / mountain / hill / grass / forest / desert / snow / lavaland
func zone_at(x: float, z: float) -> String:
	var h := height_at(x, z)
	if liquid_at(Vector3(x, h + 0.1, z)) != "":
		return "water"
	for pool in lava_pools + hot_springs:
		if Vector2(x, z).distance_to(Vector2(pool.x, pool.y)) < pool.z * 1.5:
			return "lava"   # 池のまわりには物を置かない
	if in_cave(Vector3(x, h, z)):
		return "cave"
	var d := Vector2(x, z).length()
	if d > RIM_START - 5.0 or Vector2(x, z).distance_to(Vector2(VOLCANO.x, VOLCANO.y)) < CRATER_R * 1.6:
		return "edge"
	var slope := 1.0 - normal_at(x, z).y
	var biome := biome_at(x, z)
	if slope > 0.35:
		return "mountain"
	match biome:
		"forest", "desert", "snow":
			return biome
		"lava":
			return "lavaland"
	if h > 9.0 or slope > 0.28:
		return "mountain"
	if h > 3.5 or slope > 0.12:
		return "hill"
	return "grass"


func _color_at(x: float, z: float, h: float, n: Vector3) -> Color:
	var w := biome_weights(x, z)
	var v := (detail.get_noise_2d(x * 0.6, z * 0.6) + 1.0) * 0.5
	var c := Color(0, 0, 0)
	var grass := Color(0.26, 0.46, 0.16).lerp(Color(0.34, 0.52, 0.18), v)
	grass = grass.lerp(Color(0.42, 0.47, 0.2), clampf((noise.get_noise_2d(x * 2.0, z * 2.0) - 0.2) * 2.0, 0.0, 0.5))
	c += grass * w["grass"]
	c += Color(0.17, 0.33, 0.12).lerp(Color(0.25, 0.36, 0.14), v) * w["forest"]
	var sand := Color(0.6, 0.45, 0.26).lerp(Color(0.68, 0.52, 0.31), v)
	c += sand * w["desert"]
	c += Color(0.74, 0.77, 0.84).lerp(Color(0.66, 0.7, 0.79), v) * w["snow"]
	var basalt := Color(0.16, 0.14, 0.14).lerp(Color(0.3, 0.27, 0.25), v)
	c += basalt * w["lava"]
	var slope := 1.0 - n.y
	var rock := Color(0.42, 0.4, 0.38)
	if w["desert"] > 0.5:
		rock = Color(0.58, 0.36, 0.24)   # 砂漠の崖は赤い
	elif w["lava"] > 0.5:
		rock = Color(0.12, 0.1, 0.1)
	c = c.lerp(rock, clampf((slope - 0.2) * 4.5, 0.0, 1.0))
	if w["desert"] < 0.5 and w["lava"] < 0.5:
		c = c.lerp(rock, clampf((h - 12.0) / 4.0, 0.0, 1.0) * (1.0 - w["snow"]))
		c = c.lerp(Color(0.95, 0.96, 0.98), clampf((h - 20.0) / 3.0, 0.0, 1.0) * clampf(1.4 - slope * 2.0, 0.0, 1.0))
	# 湖の底は泥、溶岩の池のまわりは赤く焼けた色
	if h < WATER_LEVEL and lake_factor(x, z) > 0.0:
		c = c.lerp(Color(0.24, 0.27, 0.16), clampf((WATER_LEVEL - h) / 0.6, 0.0, 1.0))
	var q := Vector2(x, z)
	for l in lava_pools:
		var dd := q.distance_to(Vector2(l.x, l.y))
		if dd < l.z * 1.8:
			c = c.lerp(Color(0.45, 0.13, 0.05), (1.0 - smoothstep(l.z * 0.9, l.z * 1.8, dd)) * 0.8)
	for sp in hot_springs:
		var dd := q.distance_to(Vector2(sp.x, sp.y))
		if dd < sp.z * 1.7:
			c = c.lerp(Color(0.85, 0.82, 0.7), (1.0 - smoothstep(sp.z * 0.9, sp.z * 1.7, dd)) * 0.7)
	for cv in CAVES:
		if q.distance_to(Vector2(cv.x, cv.y)) < cv.z:
			c = c.lerp(Color(0.2, 0.19, 0.18), 0.85)
	return c


# ---------------------------------------------------------------- 生成

## 溶岩の池・温泉・間欠泉の場所を決める
func _place_features(rng: RandomNumberGenerator) -> void:
	# 火口の溶岩(火山を盛り上げたあとの火口の底より少し上)
	var crater_level := height_at(VOLCANO.x, VOLCANO.y) + 2.5
	lava_pools.append(Vector4(VOLCANO.x, VOLCANO.y, CRATER_R * 0.9, crater_level + 1.2))
	var tries := 0
	while (lava_pools.size() < 7 or hot_springs.size() < 4 or geysers.size() < 5) and tries < 4000:
		tries += 1
		var a := rng.randf_range(PI * 0.2, PI * 0.8)
		var r := rng.randf_range(115.0, 205.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if Vector2(x, z).distance_to(Vector2(VOLCANO.x, VOLCANO.y)) < VOLCANO.z + 8.0:
			continue
		var w := biome_weights(x, z)
		if w["lava"] < 0.7:
			# 温泉は溶岩地帯の端(草原や雪山との境目)にも
			if hot_springs.size() < 4 and w["lava"] > 0.3 and w["lava"] < 0.7:
				if _far_from_features(Vector2(x, z), 25.0):
					hot_springs.append(Vector4(x, z, rng.randf_range(3.5, 5.0), _base_height(x, z) * 0.7 + 0.6))
			continue
		if not _far_from_features(Vector2(x, z), 22.0):
			continue
		var level := _base_height(x, z) * 0.7 + 0.4
		if lava_pools.size() < 7:
			lava_pools.append(Vector4(x, z, rng.randf_range(4.5, 8.0), level))
		elif hot_springs.size() < 4:
			hot_springs.append(Vector4(x, z, rng.randf_range(3.5, 5.0), level + 0.2))
		elif geysers.size() < 5:
			geysers.append(Vector3(x, z, rng.randf_range(4.0, 14.0)))


func _far_from_features(p: Vector2, dist: float) -> bool:
	for f in lava_pools + hot_springs:
		if p.distance_to(Vector2(f.x, f.y)) < dist:
			return false
	for g in geysers:
		if p.distance_to(Vector2(g.x, g.y)) < dist:
			return false
	for c in CAVES:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + dist:
			return false
	return true


func _make_terrain() -> void:
	var row := CELLS + 1
	var step := SIZE / CELLS
	var half := SIZE / 2.0
	# 高さは1回だけ計算して、法線はとなりの点との差から求める(速くするため)
	var heights := PackedFloat32Array()
	heights.resize(row * row)
	for iz in row:
		for ix in row:
			heights[iz * row + ix] = height_at(-half + ix * step, -half + iz * step)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(row * row)
	normals.resize(row * row)
	colors.resize(row * row)
	for iz in row:
		for ix in row:
			var i := iz * row + ix
			var x := -half + ix * step
			var z := -half + iz * step
			var h := heights[i]
			var hl := heights[iz * row + maxi(ix - 1, 0)]
			var hr := heights[iz * row + mini(ix + 1, CELLS)]
			var hd := heights[maxi(iz - 1, 0) * row + ix]
			var hu := heights[mini(iz + 1, CELLS) * row + ix]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			verts[i] = Vector3(x, h, z)
			normals[i] = n
			colors[i] = _color_at(x, z, h, n)
	var indices := PackedInt32Array()
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
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true   # 地面の下に入り込んでも落ちないように
	col.shape = shape
	body.add_child(col)


## 実際の地面(当たり判定)の高さ。地形のメッシュは粗いので、計算した高さと少しずれることがある
func ground_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -80, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if not hit.is_empty() else height_at(x, z)


## 溶岩の池・温泉・間欠泉の見た目
func _make_feature_meshes() -> void:
	var lava_mat := ShaderMaterial.new()
	lava_mat.shader = load("res://shaders/lava.gdshader")
	for l in lava_pools:
		_disc(Vector3(l.x, l.w, l.y), l.z * 1.15, lava_mat)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.45, 0.15)
		glow.light_energy = 2.0
		glow.omni_range = l.z * 2.2
		glow.position = Vector3(l.x, l.w + 2.0, l.y)
		add_child(glow)
	var spring_mat := ShaderMaterial.new()
	spring_mat.shader = load("res://shaders/spring.gdshader")
	for s in hot_springs:
		_disc(Vector3(s.x, s.w, s.y), s.z * 1.15, spring_mat)
		add_child(_steam(Vector3(s.x, s.w, s.y), s.z))
	for g in geysers:
		var base := surface(g.x, g.y)
		var vent := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7
		cm.bottom_radius = 1.6
		cm.height = 0.9
		vent.mesh = cm
		var vm := StandardMaterial3D.new()
		vm.albedo_color = Color(0.82, 0.76, 0.55)
		vm.roughness = 1.0
		vent.material_override = vm
		vent.position = base + Vector3(0, 0.3, 0)
		add_child(vent)
		var hole := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.35
		hm.bottom_radius = 0.35
		hm.height = 0.05
		hole.mesh = hm
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.1, 0.09, 0.08)
		hole.material_override = dark
		hole.position = base + Vector3(0, 0.76, 0)
		add_child(hole)
		var fx := _steam(base + Vector3(0, 0.8, 0), 0.4)
		fx.amount = 120
		fx.lifetime = 2.2
		fx.initial_velocity_min = 12.0
		fx.initial_velocity_max = 16.0
		fx.spread = 6.0
		fx.gravity = Vector3(0, -6, 0)
		fx.scale_amount_min = 1.5
		fx.scale_amount_max = 3.0
		fx.emitting = false
		add_child(fx)
		_geyser_fx.append(fx)
		_geyser_time.append(g.z)


func _disc(center: Vector3, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	pm.subdivide_width = 12
	pm.subdivide_depth = 12
	mi.mesh = pm
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _steam(pos: Vector3, radius: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 24
	p.lifetime = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.7
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.16)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.material = m
	p.mesh = sm
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	return p


## 洞窟: でこぼこした岩のドーム。入口は世界の中心を向いている
func _make_cave(c: Vector3, rng: RandomNumberGenerator) -> void:
	var floor_h := cave_floor(c)
	var center := Vector3(c.x, floor_h - 0.5, c.y)
	var entrance := Vector2(-c.x, -c.y).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var biome := biome_at(c.x, c.y)
	var rock := Color(0.36, 0.34, 0.33)
	if biome == "snow":
		rock = Color(0.55, 0.6, 0.66)
	elif biome == "desert":
		rock = Color(0.62, 0.42, 0.3)
	elif biome == "lava":
		rock = Color(0.15, 0.13, 0.13)
	var cn := FastNoiseLite.new()
	cn.seed = rng.randi()
	cn.frequency = 0.25
	var seg := 28
	var rings := 10
	var pts := []
	for ri in rings + 1:
		var row := []
		var phi := float(ri) / rings * (PI / 2.0)   # 0 = 地面、PI/2 = 天井
		for si in seg + 1:
			var th := float(si) / seg * TAU
			var dir := Vector3(cos(th) * cos(phi), sin(phi), sin(th) * cos(phi))
			var rad := c.z * (1.0 + cn.get_noise_3dv(dir * 3.0) * 0.18)
			var p := center + Vector3(dir.x * rad, dir.y * rad * 0.62, dir.z * rad)
			if ri == 0:
				p.y = center.y - 1.0
			row.append([p, th])
		pts.append(row)
	for ri in rings:
		for si in seg:
			var th: float = pts[ri][si][1] + PI / seg
			var dir2 := Vector2(cos(th), sin(th))
			# 入口(下のほうの、中心に向いた部分)を開ける
			if dir2.dot(entrance) > 0.82 and ri < 6:
				continue
			var a: Vector3 = pts[ri][si][0]
			var b: Vector3 = pts[ri][si + 1][0]
			var cc: Vector3 = pts[ri + 1][si][0]
			var d: Vector3 = pts[ri + 1][si + 1][0]
			for v in [a, b, cc, b, d, cc]:
				st.set_color(rock.darkened(randf() * 0.15))
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	# 入口の両脇の大岩と、中で光るキノコ
	for s in [-1.0, 1.0]:
		var side: Vector2 = Vector2(-entrance.y, entrance.x) * s
		var bp: Vector2 = Vector2(c.x, c.y) + entrance * (c.z * 0.92) + side * (c.z * 0.55)
		var boulder := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.4
		sm.height = 4.0
		sm.radial_segments = 8
		sm.rings = 5
		boulder.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = rock
		boulder.material_override = bm
		boulder.position = surface(bp.x, bp.y) + Vector3(0, 0.8, 0)
		add_child(boulder)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.4, 0.9, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.3, 0.8, 1.0)
	glow_mat.emission_energy_multiplier = 2.5
	var cap := SphereMesh.new()
	cap.radius = 0.22
	cap.height = 0.22
	cap.is_hemisphere = true
	cap.material = glow_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cap
	mm.instance_count = 40
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, c.z - 1.5)
		var q := Vector2(c.x, c.y) + Vector2(cos(a), sin(a)) * r
		var s := rng.randf_range(0.6, 1.8)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(q.x, floor_h + 0.05, q.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.8, 1.0)
	light.light_energy = 0.9
	light.omni_range = c.z * 1.1
	light.position = center + Vector3(0, 4.0, 0)
	add_child(light)


## 間欠泉: ときどき噴き出す。噴き出しているあいだに上に乗ると吹き飛ばされる
func update_geysers(delta: float) -> void:
	for i in geysers.size():
		_geyser_time[i] -= delta
		if _geyser_time[i] <= 0.0:
			_geyser_fx[i].emitting = not _geyser_fx[i].emitting
			_geyser_time[i] = 4.0 if _geyser_fx[i].emitting else randf_range(10.0, 18.0)


func geyser_push(p: Vector3) -> bool:
	for i in geysers.size():
		if _geyser_fx[i].emitting and Vector2(p.x, p.z).distance_to(Vector2(geysers[i].x, geysers[i].y)) < 1.4:
			return true
	return false


func near_geyser(p: Vector3, r: float) -> bool:
	for g in geysers:
		if Vector2(p.x, p.z).distance_to(Vector2(g.x, g.y)) < r:
			return true
	return false


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
	add_child(_seaweed(rng))
	_make_pier()
	_make_fish(rng)


## 湖の底の水草(ゆらゆら揺れる)
func _seaweed(rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a := i * TAU / 4.0 + 0.5
		var w := Vector3(-sin(a), 0, cos(a)) * 0.07
		var h := 1.2 + 0.4 * (i % 2)
		var segs := 4
		for k in segs:
			var y0 := h * k / segs
			var y1 := h * (k + 1) / segs
			var c0 := Color(0.12, 0.35, 0.2).lerp(Color(0.3, 0.6, 0.3), float(k) / segs)
			var c1 := Color(0.12, 0.35, 0.2).lerp(Color(0.3, 0.6, 0.3), float(k + 1) / segs)
			var o0 := Vector3(cos(a), 0, sin(a)) * 0.05 * k
			var o1 := Vector3(cos(a), 0, sin(a)) * 0.05 * (k + 1)
			for v in [[o0 - w, y0, c0], [o0 + w, y0, c0], [o1 + w * 0.7, y1, c1], [o0 - w, y0, c0], [o1 + w * 0.7, y1, c1], [o1 - w * 0.7, y1, c1]]:
				st.set_color(v[2])
				st.add_vertex(v[0] + Vector3(0, v[1], 0))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/seaweed.gdshader")
	mesh.surface_set_material(0, mat)
	return _scatter(mesh, _shore_points(rng, 220, -LAKE_DEPTH, -1.2), rng, 0.7, 1.6, true)


## 湖を泳ぐ魚
var _fish: Array[Dictionary] = []


func _make_fish(rng: RandomNumberGenerator) -> void:
	var colors := [Color(0.95, 0.55, 0.2), Color(0.5, 0.7, 0.85), Color(0.85, 0.85, 0.4), Color(0.9, 0.35, 0.45)]
	for i in 14:
		var root := Node3D.new()
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 8
		sm.rings = 4
		body.mesh = sm
		body.scale = Vector3(0.6, 0.8, 1.6)
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[i % colors.size()]
		m.roughness = 0.4
		body.material_override = m
		root.add_child(body)
		var tail := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.18, 0.16, 0.03)
		tail.mesh = pm
		tail.material_override = m
		tail.rotation = Vector3(PI / 2.0, 0, 0)
		tail.position = Vector3(0, 0, 0.26)
		root.add_child(tail)
		add_child(root)
		_fish.append({"node": root, "tail": tail, "angle": rng.randf() * TAU, "radius": rng.randf_range(4.0, LAKE_RADIUS * 0.6),
			"depth": rng.randf_range(0.8, LAKE_DEPTH - 1.0), "speed": rng.randf_range(0.15, 0.35) * (1 if i % 2 else -1),
			"phase": rng.randf() * TAU})


func update_fish(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for f in _fish:
		f["angle"] += f["speed"] * delta
		var a: float = f["angle"]
		var r: float = f["radius"] + sin(t * 0.3 + f["phase"]) * 2.0
		var pos := Vector3(LAKE_CENTER.x + cos(a) * r, WATER_LEVEL - f["depth"] + sin(t + f["phase"]) * 0.2, LAKE_CENTER.y + sin(a) * r)
		var node: Node3D = f["node"]
		var dir := Vector3(-sin(a), 0, cos(a)) * signf(f["speed"])
		node.position = pos
		node.look_at(pos - dir, Vector3.UP)
		(f["tail"] as Node3D).rotation.y = sin(t * 8.0 + f["phase"]) * 0.5


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
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 2.6
	env.tonemap_exposure = 0.92
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5
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
	apply_time()


## 昼と夜。夜は短め(昼の2倍の速さで進む)
func advance_time(delta: float) -> void:
	var night := time_of_day < 0.22 or time_of_day > 0.78
	time_of_day = fposmod(time_of_day + delta / DAY_SECONDS * (2.0 if night else 1.0), 1.0)
	apply_time()


func is_night() -> bool:
	return time_of_day < 0.24 or time_of_day > 0.76


## 0〜1: 昼の明るさ
func daylight() -> float:
	return clampf(sin((time_of_day - 0.25) * TAU) * 2.5 + 0.5, 0.0, 1.0)


func apply_time() -> void:
	var day := daylight()
	var elev := sin((time_of_day - 0.25) * TAU)    # 太陽の高さ(-1〜1)
	# 太陽は東から昇って西へ。夜は地平線の下なので光を消す
	sun.rotation = Vector3(-clampf(asin(clampf(elev, 0.0, 1.0)), 0.08, 1.4), deg_to_rad(-35.0) + (0.5 - time_of_day) * 2.0, 0.0)
	var dusk := clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0)  # 朝焼け・夕焼け
	sun.light_energy = 0.95 * day
	sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.6, 0.35), dusk)
	sun.shadow_enabled = day > 0.15
	var top_day := Color(0.22, 0.48, 0.86)
	var hor_day := Color(0.68, 0.8, 0.92)
	var top_night := Color(0.02, 0.04, 0.12)
	var hor_night := Color(0.08, 0.1, 0.22)
	sky_mat.sky_top_color = top_night.lerp(top_day, day)
	sky_mat.sky_horizon_color = hor_night.lerp(hor_day, day).lerp(Color(0.95, 0.55, 0.35), dusk * 0.7)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.3, 0.38, 0.3) * (0.3 + day * 0.7)
	env.ambient_light_energy = 0.12 + 0.18 * day
	env.fog_light_color = Color(0.12, 0.14, 0.25).lerp(Color(0.7, 0.8, 0.9), day)
	for l in get_tree().get_nodes_in_group("night_light") if is_inside_tree() else []:
		(l as Light3D).light_energy = 0.4 + 1.6 * (1.0 - day)


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
		var r := sqrt(rng.randf()) * 150.0
		var a := rng.randf() * TAU
		var x := cos(a) * r
		var z := sin(a) * r
		var zone := zone_at(x, z)
		if zone != "grass" and (flowers or zone != "forest"):
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
