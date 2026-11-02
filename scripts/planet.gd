class_name Planet
extends StaticBody3D
## 球体の惑星。立方体を膨らませた「キューブスフィア」にノイズで起伏を付けて作る。

@export var radius := 40.0          ## 海面の高さ(惑星の基本半径)
@export var height_scale := 7.0     ## 起伏の大きさ
@export var resolution := 56        ## 立方体1面あたりの分割数
@export var noise_seed := 20261102

var noise := FastNoiseLite.new()
var sea_level := 0.0

const COLOR_SAND := Color(0.86, 0.74, 0.52)
const COLOR_SOIL := Color(0.66, 0.33, 0.22)
const COLOR_MOSS := Color(0.36, 0.52, 0.42)
const COLOR_ROCK := Color(0.36, 0.33, 0.34)
const COLOR_ICE := Color(0.93, 0.96, 1.0)


func generate() -> void:
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.3
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.5
	sea_level = radius

	collision_layer = 1
	collision_mask = 0

	var mesh := _build_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	add_child(col)

	_add_water()
	_add_atmosphere()


## 方向(単位ベクトル)からその地点の地表の高さ(中心からの距離)を返す
func height_at(dir: Vector3) -> float:
	var e := noise.get_noise_3dv(dir) + 0.12
	var h := signf(e) * pow(absf(e), 1.25) * height_scale * 1.8
	if h < 0.0:
		h *= 0.6  # 海底はなだらかに
	return radius + h


func surface_point(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	return d * height_at(d)


## 海より上の、ほどよく平らな場所の方向をランダムに返す
func random_land_dir(rng: RandomNumberGenerator, min_rel := 0.4, max_rel := 6.0) -> Vector3:
	for i in 300:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var rel := height_at(d) - sea_level
		if rel > min_rel and rel < max_rel and normal_at(d).dot(d) > 0.85:
			return d
	return Vector3.UP


func normal_at(dir: Vector3) -> Vector3:
	var ref := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var t1 := dir.cross(ref).normalized()
	var t2 := dir.cross(t1).normalized()
	var e := 0.006
	var p0 := dir * height_at(dir)
	var d1 := (dir + t1 * e).normalized()
	var d2 := (dir + t2 * e).normalized()
	var p1 := d1 * height_at(d1)
	var p2 := d2 * height_at(d2)
	var n := (p1 - p0).cross(p2 - p0).normalized()
	if n.dot(dir) < 0.0:
		n = -n
	return n


func _color_at(dir: Vector3, h: float, n: Vector3) -> Color:
	var rel := h - sea_level
	var c: Color
	if rel < 0.6:
		c = COLOR_SAND
	elif rel < 2.5:
		c = COLOR_SAND.lerp(COLOR_SOIL, clampf((rel - 0.6) / 1.0, 0.0, 1.0))
	elif rel < 5.5:
		c = COLOR_SOIL.lerp(COLOR_MOSS, clampf((rel - 2.5) / 3.0, 0.0, 1.0) * 0.6)
	elif rel < 8.0:
		c = COLOR_MOSS.lerp(COLOR_ROCK, clampf((rel - 5.5) / 2.0, 0.0, 1.0))
	else:
		c = COLOR_ROCK.lerp(COLOR_ICE, clampf((rel - 8.0) / 1.5, 0.0, 1.0))
	# 急な斜面は岩肌にする
	var slope := 1.0 - n.dot(dir)
	c = c.lerp(COLOR_ROCK, clampf((slope - 0.12) * 4.0, 0.0, 0.8))
	# 細かな色むら
	var v := noise.get_noise_3dv(dir * 9.0) * 0.08
	return Color(c.r + v, c.g + v, c.b + v)


static func _cube_to_sphere(p: Vector3) -> Vector3:
	var x2 := p.x * p.x
	var y2 := p.y * p.y
	var z2 := p.z * p.z
	return Vector3(
		p.x * sqrt(1.0 - y2 / 2.0 - z2 / 2.0 + y2 * z2 / 3.0),
		p.y * sqrt(1.0 - z2 / 2.0 - x2 / 2.0 + z2 * x2 / 3.0),
		p.z * sqrt(1.0 - x2 / 2.0 - y2 / 2.0 + x2 * y2 / 3.0)
	).normalized()


func _build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var n := resolution
	var faces: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]

	for f in faces:
		var axis_a := Vector3(f.y, f.z, f.x)
		var axis_b := f.cross(axis_a)
		var base := verts.size()
		for y in n + 1:
			for x in n + 1:
				var px := float(x) / n * 2.0 - 1.0
				var py := float(y) / n * 2.0 - 1.0
				var dir := _cube_to_sphere(f + axis_a * px + axis_b * py)
				var h := height_at(dir)
				var nrm := normal_at(dir)
				verts.append(dir * h)
				normals.append(nrm)
				colors.append(_color_at(dir, h, nrm))

		# Godotは時計回りが表面。面ごとに向きを確かめて合わせる
		var a := verts[base]
		var b := verts[base + n + 1]
		var c := verts[base + 1]
		var flip := (b - a).cross(c - a).dot(a) > 0.0
		for y in n:
			for x in n:
				var i := base + y * (n + 1) + x
				var i_down := i + n + 1
				if flip:
					indices.append_array([i, i + 1, i_down, i + 1, i_down + 1, i_down])
				else:
					indices.append_array([i, i_down, i + 1, i + 1, i_down, i_down + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_water() -> void:
	var water := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = sea_level
	sphere.height = sea_level * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	water.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.42, 0.68, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.metallic_specular = 0.8
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _add_atmosphere() -> void:
	# 宇宙から見たときにうっすら光る大気の層(内側から見ても邪魔にならない程度)
	var atmo := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius + height_scale * 2.2
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	atmo.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 0.7, 1.0, 0.06)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	atmo.material_override = mat
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmo)
