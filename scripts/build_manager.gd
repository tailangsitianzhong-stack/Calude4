class_name BuildManager
extends Node3D
## 設置物(設備・家具・建築パーツ)の置き場所を決めて置く。建築パーツは 2m のマス目にそろう。
##   土台: マスの中央 / 壁・ドア・窓・柵: マスの辺 / 床・屋根・階段: マスの中央(壁の上の高さ)
## 置いた物は StaticBody3D(グループ "placed")で、meta に item・key・kind・top を持つ。

const CELL := 2.0
const WALL_H := 2.6
const WALL_T := 0.2
const FOUND_TOP := 0.25      ## 土台の上面が地面より少し高くなる量
const REACH := 5.5

var world: World
var player: Player
var occupied := {}           ## key -> 置いた物
var _scenes := {}
var _preview: Node3D
var _preview_id := ""
var _preview_ok := true
var _ok_mat: StandardMaterial3D
var _ng_mat: StandardMaterial3D
var _mats := {}


func _ready() -> void:
	_ok_mat = _ghost(Color(0.4, 1.0, 0.5, 0.45))
	_ng_mat = _ghost(Color(1.0, 0.35, 0.3, 0.45))
	_mats["wood"] = _mat(Color(0.69, 0.48, 0.28), 0.85)
	_mats["wood_dark"] = _mat(Color(0.47, 0.31, 0.17), 0.9)
	_mats["stone"] = _mat(Color(0.62, 0.62, 0.6), 0.95)
	_mats["stone_dark"] = _mat(Color(0.45, 0.45, 0.44), 0.95)
	_mats["iron"] = _mat(Color(0.56, 0.6, 0.66), 0.45, 0.7)
	_mats["iron_dark"] = _mat(Color(0.35, 0.38, 0.43), 0.5, 0.7)
	_mats["roof"] = _mat(Color(0.5, 0.3, 0.18), 0.9)
	_mats["roof_dark"] = _mat(Color(0.36, 0.21, 0.12), 0.9)
	_mats["brick"] = _mat(Color(0.66, 0.34, 0.25), 0.9)
	_mats["brick_dark"] = _mat(Color(0.48, 0.24, 0.18), 0.9)
	_mats["sandstone"] = _mat(Color(0.8, 0.66, 0.44), 0.95)
	_mats["sandstone_dark"] = _mat(Color(0.62, 0.5, 0.32), 0.95)
	_mats["tile"] = _mat(Color(0.62, 0.27, 0.2), 0.8)
	_mats["tile_dark"] = _mat(Color(0.45, 0.19, 0.14), 0.8)
	var ice := _mat(Color(0.72, 0.88, 1.0, 0.82), 0.1)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["ice"] = ice
	_mats["ice_dark"] = _mat(Color(0.6, 0.78, 0.92), 0.2)
	var glass := _mat(Color(0.65, 0.88, 1.0, 0.35), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["glass"] = glass


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _ghost(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 起動時(タイトル画面の裏)に、置ける物をすべて1回ずつ描いておく。
## 初めて置いたときにシェーダーの準備で固まるのを防ぐ。戻り値は数フレーム後に消すノード
func warm_up(at: Transform3D) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_transform = at
	var i := 0
	for id in ItemDB.data()["items"]:
		if ItemDB.place_kind(id) == "":
			continue
		var v := make_visual(id, null)
		holder.add_child(v)
		v.position = Vector3((i % 6) * 0.6 - 1.5, (i / 6) * 0.4 - 0.6, 0) 
		v.scale = Vector3.ONE * 0.1
		var ghost := make_visual(id, null)
		holder.add_child(ghost)
		ghost.position = v.position + Vector3(0.3, 0, 0)
		ghost.scale = Vector3.ONE * 0.1
		for g in ghost.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_override = _ok_mat if i % 2 == 0 else _ng_mat
		i += 1
	return holder


func scene(model: String) -> PackedScene:
	if not _scenes.has(model):
		_scenes[model] = load("res://assets/models/%s.glb" % model)
	return _scenes[model]


# ---------------------------------------------------------------- 見本と配置計算

func hide_preview() -> void:
	if _preview:
		_preview.visible = false


## 持っている物の見本を視線の先に出す。置けるなら {ok:true, ...} を返す
func update_preview(id: String) -> Dictionary:
	if id != _preview_id:
		if _preview:
			_preview.queue_free()
		_preview = make_visual(id, null)
		_preview_id = id
		_preview_ok = true
		for g in _preview.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_override = _ok_mat
		add_child(_preview)
		for g in _preview.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach := REACH + (0.0 if player.first_person else player.spring.spring_length)
	var hit := player.get_aim_hit(reach)
	if hit.is_empty():
		_preview.visible = false
		return {"ok": false, "reason": "地面を狙って設置しよう"}
	var plan := plan_placement(id, hit)
	_preview.visible = plan.has("xform")
	if plan.has("xform"):
		_preview.global_transform = plan["xform"]
		if plan.has("scale_y"):
			_preview.scale.y = plan["scale_y"]
	if plan["ok"] != _preview_ok:
		_preview_ok = plan["ok"]
		for g in _preview.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_override = _ok_mat if _preview_ok else _ng_mat
	return plan


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func _foundation_top(c: Vector2i) -> float:
	var f: Node = occupied.get("f:%d:%d" % [c.x, c.y])
	return f.get_meta("top") if f else NAN


func _facing_yaw() -> float:
	## プレイヤーの向きを 90 度単位にそろえた角度
	var y := player.global_rotation.y
	return roundf(y / (PI / 2.0)) * (PI / 2.0)


func plan_placement(id: String, hit: Dictionary) -> Dictionary:
	var kind := ItemDB.place_kind(id)
	var pos: Vector3 = hit["position"]
	var col: Node = hit["collider"]
	var placed_hit: Node = col if col.is_in_group("placed") else null
	match kind:
		"foundation":
			return _plan_foundation(pos)
		"wall", "fence":
			return _plan_edge(id, kind, pos, placed_hit)
		"floor":
			return _plan_floor(pos, placed_hit)
		"stairs":
			return _plan_stairs(pos)
		"rocket":
			if placed_hit and placed_hit.get_meta("item") == "launch_pad":
				var key := "rocket:%s" % placed_hit.get_instance_id()
				var x := Transform3D(Basis(), placed_hit.global_position + Vector3(0, 0.42, 0))
				if occupied.has(key):
					return {"ok": false, "reason": "もうロケットが載っている", "xform": x}
				return {"ok": true, "xform": x, "key": key}
			return {"ok": false, "reason": "発射台の上に置こう"}
		_:
			return _plan_free(id, hit, placed_hit)


func _plan_free(id: String, hit: Dictionary, placed_hit: Node) -> Dictionary:
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var to_player := player.global_position - pos
	var xform := Transform3D(Basis(Vector3.UP, atan2(-to_player.x, -to_player.z)), pos)
	var radius := 5.2 if id == "launch_pad" else (1.3 if ItemDB.place_kind(id) == "station" else 0.6)
	var reason := ""
	if hit["collider"] is Harvestable:
		reason = "木や岩の上には置けない"
	elif placed_hit and not (placed_hit.get_meta("kind") in ["foundation", "floor"]):
		reason = "ほかの物の上には置けない"
	elif normal.y < 0.8:
		reason = "坂が急すぎて置けない"
	elif _in_lake(pos):
		reason = "水の中には置けない"
	elif Vector2(to_player.x, to_player.z).length() < 0.9:
		reason = "自分の足元には置けない"
	else:
		for n in get_tree().get_nodes_in_group("placed") + get_tree().get_nodes_in_group("harvestable"):
			if n == placed_hit or (n.is_in_group("placed") and n.get_meta("kind") in ["foundation", "floor", "wall", "fence", "stairs"]):
				continue
			var r2 := radius + (5.0 if n.is_in_group("placed") and n.get_meta("item") == "launch_pad" else 0.5)
			if Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length() < r2:
				reason = "近くの物とぶつかる"
				break
	return {"ok": reason == "", "reason": reason, "xform": xform, "key": ""}


func _in_lake(p: Vector3) -> bool:
	return p.y < World.WATER_LEVEL and world.lake_factor(p.x, p.z) > 0.0


func _plan_foundation(pos: Vector3) -> Dictionary:
	var c := _cell_of(pos)
	var key := "f:%d:%d" % [c.x, c.y]
	var center := _cell_center(c)
	# となりに土台があれば高さをそろえる
	var top := NAN
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t := _foundation_top(c + d)
		if not is_nan(t):
			top = t if is_nan(top) else maxf(top, t)
	var lo := INF
	var hi := -INF
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		var h := world.height_at(center.x + corner.x * CELL * 0.5, center.y + corner.y * CELL * 0.5)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if is_nan(top):
		top = hi + FOUND_TOP
	var depth := top - lo + 0.6
	var xform := Transform3D(Basis(), Vector3(center.x, top, center.y))
	var reason := ""
	if occupied.has(key):
		reason = "もう土台がある"
	elif hi - lo > 2.2 or top - lo > 3.0:
		reason = "地面がでこぼこすぎる"
	elif _in_lake(Vector3(center.x, lo, center.y)):
		reason = "水の中には置けない"
	elif _blocked_by_nature(Vector2(center.x, center.y), CELL * 0.75):
		reason = "木や岩がじゃま"
	return {"ok": reason == "", "reason": reason, "xform": xform, "key": key, "scale_y": depth / 1.0, "top": top, "depth": depth}


func _blocked_by_nature(p: Vector2, r: float) -> bool:
	for n in get_tree().get_nodes_in_group("harvestable"):
		if Vector2(n.global_position.x, n.global_position.z).distance_to(p) < r:
			return true
	return false


## 壁・柵はマスの辺に置く。壁を狙ったときはその上(2階)に積む
func _plan_edge(id: String, kind: String, pos: Vector3, placed_hit: Node) -> Dictionary:
	var c: Vector2i
	var along_x: bool
	var base: float
	if placed_hit and kind == "wall" and placed_hit.get_meta("kind") == "wall":
		c = placed_hit.get_meta("cell")
		along_x = placed_hit.get_meta("along_x")
		base = placed_hit.get_meta("top")
	else:
		c = _cell_of(pos)
		var lx := pos.x - c.x * CELL
		var lz := pos.z - c.y * CELL
		var dists := [lz, CELL - lz, lx, CELL - lx]  # 北・南(x方向の辺)、西・東(z方向の辺)
		var best := 0
		for i in 4:
			if dists[i] < dists[best]:
				best = i
		along_x = best < 2
		if best == 1:
			c.y += 1
		elif best == 3:
			c.x += 1
		# 辺の両側の土台の高さ。なければ地面
		var other := c - (Vector2i(0, 1) if along_x else Vector2i(1, 0))
		base = NAN
		for cc in [c, other]:
			var t := _foundation_top(cc)
			if not is_nan(t):
				base = t if is_nan(base) else maxf(base, t)
		if is_nan(base):
			var m := _edge_mid(c, along_x)
			base = world.height_at(m.x, m.y) - 0.05
	var mid := _edge_mid(c, along_x)
	var yaw := 0.0 if along_x else PI / 2.0
	var xform := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, base, mid.y))
	var level := roundi(base * 2.0)
	var key := "%s:%s:%d:%d:%d" % ["w" if kind == "wall" else "fe", "x" if along_x else "z", c.x, c.y, level]
	var reason := ""
	if occupied.has(key):
		reason = "もう置いてある"
	elif _in_lake(Vector3(mid.x, base, mid.y)):
		reason = "水の中には置けない"
	elif not placed_hit and _blocked_by_nature(mid, 0.9):
		reason = "木や岩がじゃま"
	return {"ok": reason == "", "reason": reason, "xform": xform, "key": key, "cell": c, "along_x": along_x,
		"top": base + (WALL_H if kind == "wall" else 1.0)}


func _edge_mid(c: Vector2i, along_x: bool) -> Vector2:
	if along_x:
		return Vector2((c.x + 0.5) * CELL, c.y * CELL)
	return Vector2(c.x * CELL, (c.y + 0.5) * CELL)


## 床・屋根は、まわりの壁のいちばん高いところに乗せる(壁がなければ地面・土台の上)
func _plan_floor(pos: Vector3, placed_hit: Node) -> Dictionary:
	var c := _cell_of(pos)
	if placed_hit and placed_hit.get_meta("kind") == "floor":
		c = placed_hit.get_meta("cell")
	var y := NAN
	for n in get_tree().get_nodes_in_group("placed"):
		if n.get_meta("kind") != "wall":
			continue
		var wc: Vector2i = n.get_meta("cell")
		var ax: bool = n.get_meta("along_x")
		var touches := (ax and wc.x == c.x and (wc.y == c.y or wc.y == c.y + 1)) or (not ax and wc.y == c.y and (wc.x == c.x or wc.x == c.x + 1))
		if touches:
			var t: float = n.get_meta("top")
			if is_nan(y) or t > y:
				y = t
	if placed_hit and placed_hit.get_meta("kind") == "floor" and is_nan(y):
		y = placed_hit.get_meta("top")
	if is_nan(y):
		var ft := _foundation_top(c)
		var cc := _cell_center(c)
		y = ft if not is_nan(ft) else world.height_at(cc.x, cc.y) + 0.02
	var center := _cell_center(c)
	var xform := Transform3D(Basis(), Vector3(center.x, y, center.y))
	var key := "c:%d:%d:%d" % [c.x, c.y, roundi(y * 2.0)]
	var reason := "もう置いてある" if occupied.has(key) else ""
	return {"ok": reason == "", "reason": reason, "xform": xform, "key": key, "cell": c, "top": y + 0.12}


func _plan_stairs(pos: Vector3) -> Dictionary:
	var c := _cell_of(pos)
	var center := _cell_center(c)
	var ft := _foundation_top(c)
	var base := ft if not is_nan(ft) else world.height_at(center.x, center.y) - 0.02
	var xform := Transform3D(Basis(Vector3.UP, _facing_yaw()), Vector3(center.x, base, center.y))
	var key := "s:%d:%d:%d" % [c.x, c.y, roundi(base * 2.0)]
	var reason := "もう置いてある" if occupied.has(key) else ""
	if reason == "" and is_nan(ft) and _blocked_by_nature(center, CELL * 0.7):
		reason = "木や岩がじゃま"
	return {"ok": reason == "", "reason": reason, "xform": xform, "key": key, "cell": c}


# ---------------------------------------------------------------- 設置と回収

func place(id: String, plan: Dictionary) -> Node3D:
	var kind := ItemDB.place_kind(id)
	var body: StaticBody3D = Station.new() if kind == "station" else StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("placed")
	body.set_meta("item", id)
	body.set_meta("kind", kind)
	body.set_meta("key", plan.get("key", ""))
	for k in ["cell", "along_x", "top"]:
		if plan.has(k):
			body.set_meta(k, plan[k])
	if body is Station:
		(body as Station).station_id = id
	var visual := make_visual(id, body, plan.get("depth", 1.0))
	body.add_child(visual)
	add_child(body)
	body.global_transform = plan["xform"]
	if plan.get("key", "") != "":
		occupied[plan["key"]] = body
	return body


func pick_up(body: Node) -> void:
	var key: String = body.get_meta("key", "")
	if key != "":
		occupied.erase(key)
	# ロケットが載っている発射台を回収したら、ロケットの予約も外す
	occupied.erase("rocket:%s" % body.get_instance_id())
	body.queue_free()


# ---------------------------------------------------------------- 見た目と当たり判定

## 建築パーツの箱を材質ごとに1つのメッシュへまとめる(描画の負荷を減らす)
class PieceBuilder:
	var tools := {}

	func box(size: Vector3, xf: Transform3D, m: Material) -> void:
		if not tools.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[m] = st
		var bm := BoxMesh.new()
		bm.size = size
		(tools[m] as SurfaceTool).append_from(bm, 0, xf)

	func commit() -> MeshInstance3D:
		var mesh := ArrayMesh.new()
		for m in tools:
			(tools[m] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, m)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		return mi


## 見た目(と、body があれば当たり判定)を作る
func make_visual(id: String, body: Node, depth := 1.0) -> Node3D:
	var kind := ItemDB.place_kind(id)
	var root := Node3D.new()
	var mat_name: String = ItemDB.item(id).get("mat", "wood")
	var m: StandardMaterial3D = _mats.get(mat_name, _mats["wood"])
	var md: StandardMaterial3D = _mats.get(mat_name + "_dark", m)
	var pb := PieceBuilder.new()
	match kind:
		"foundation":
			_box(pb, body, Vector3(CELL, depth, CELL), Vector3(0, -depth / 2.0, 0), m)
			# 縁取りは上面より少し下げて、上面と重ならないようにする(重なるとちらつく)
			_box(pb, null, Vector3(CELL + 0.04, 0.08, CELL + 0.04), Vector3(0, -0.07, 0), md)
		"wall":
			_make_wall(pb, body, id, m, md)
		"fence":
			for x in [-0.95, 0.0, 0.95]:
				_box(pb, null, Vector3(0.12, 1.1, 0.12), Vector3(x, 0.55, 0), md)
			for y in [0.4, 0.85]:
				_box(pb, null, Vector3(CELL - 0.14, 0.08, 0.06), Vector3(0, y, 0), m)
			_box(null, body, Vector3(CELL, 1.1, 0.12), Vector3(0, 0.55, 0), null)
		"floor":
			if mat_name in ["roof", "tile"] or id == "iron_roof":
				_box(pb, body, Vector3(CELL + 0.3, 0.12, CELL + 0.3), Vector3(0, 0.06, 0), m)
				for i in 5:
					_box(pb, null, Vector3(CELL + 0.3, 0.05, 0.08), Vector3(0, 0.15, -0.9 + i * 0.45), md)
			else:
				_box(pb, body, Vector3(CELL, 0.1, CELL), Vector3(0, 0.05, 0), m)
				for i in 4:
					_box(pb, null, Vector3(0.03, 0.12, CELL - 0.02), Vector3(-0.75 + i * 0.5, 0.05, 0), md)
		"stairs":
			for i in 6:
				var h := (i + 1) * WALL_H / 6.0
				var z := CELL / 2.0 - (i + 0.5) * CELL / 6.0
				_box(pb, null, Vector3(1.6, 0.12, CELL / 6.0), Vector3(0, h - 0.06, z), m)
				_box(pb, null, Vector3(1.56, h - 0.13, 0.05), Vector3(0, (h - 0.13) / 2.0, z + CELL / 12.0 - 0.03), md)
			if body:
				# 斜めの当たり判定で登れるようにする
				var ramp := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(1.6, 0.1, Vector2(CELL, WALL_H).length())
				ramp.shape = shape
				ramp.position = Vector3(0, WALL_H / 2.0, 0)
				ramp.rotation.x = atan2(WALL_H, CELL)
				body.add_child(ramp)
		_:
			var model: String = ItemDB.item(id).get("model", "")
			root.add_child(scene(model).instantiate())
			if body:
				_add_model_collision(body, id)
				var light_h: float = ItemDB.item(id).get("light", 0.0)
				if light_h > 0.0:
					var light := OmniLight3D.new()
					light.light_color = Color(1.0, 0.75, 0.4)
					light.light_energy = 1.6
					light.omni_range = 8.0
					light.position.y = light_h
					light.add_to_group("night_light")
					root.add_child(light)
	if not pb.tools.is_empty():
		root.add_child(pb.commit())
	return root


func _make_wall(pb: PieceBuilder, body: Node, id: String, m: Material, md: Material) -> void:
	var variant: String = ItemDB.item(id).get("variant", "")
	var w := CELL
	var h := WALL_H
	var t := WALL_T
	var side := (w - 1.0) / 2.0
	if variant == "door":
		# 幅 1m・高さ 2.1m の入口。扉は開いた状態
		_box(pb, body, Vector3(side, h, t), Vector3(-0.5 - side / 2.0, h / 2.0, 0), m)
		_box(pb, body, Vector3(side, h, t), Vector3(0.5 + side / 2.0, h / 2.0, 0), m)
		_box(pb, body, Vector3(1.0, h - 2.1, t), Vector3(0, 2.1 + (h - 2.1) / 2.0, 0), m)
		var hinge := Transform3D(Basis(Vector3.UP, deg_to_rad(-100)), Vector3(-0.5, 0, t / 2.0 + 0.04))
		pb.box(Vector3(0.95, 2.05, 0.06), hinge * Transform3D(Basis(), Vector3(0.475, 1.03, 0)), md)
		pb.box(Vector3(0.08, 0.08, 0.1), hinge * Transform3D(Basis(), Vector3(0.78, 1.0, 0.03)), _mats["iron"])
	elif variant == "window":
		_box(pb, body, Vector3(side, h, t), Vector3(-0.5 - side / 2.0, h / 2.0, 0), m)
		_box(pb, body, Vector3(side, h, t), Vector3(0.5 + side / 2.0, h / 2.0, 0), m)
		_box(pb, body, Vector3(1.0, 0.9, t), Vector3(0, 0.45, 0), m)
		_box(pb, body, Vector3(1.0, h - 1.8, t), Vector3(0, 1.8 + (h - 1.8) / 2.0, 0), m)
		_box(pb, body, Vector3(1.0, 0.9, 0.04), Vector3(0, 1.35, 0), _mats["glass"])
		_box(pb, null, Vector3(0.06, 0.9, 0.08), Vector3(0, 1.35, 0), md)
		_box(pb, null, Vector3(1.0, 0.06, 0.08), Vector3(0, 1.35, 0), md)
	elif variant == "glass":
		_box(pb, body, Vector3(w - 0.2, h - 0.2, 0.05), Vector3(0, h / 2.0, 0), _mats["glass"])
		for x in [-0.33, 0.33]:
			_box(pb, null, Vector3(0.05, h - 0.2, 0.08), Vector3(x, h / 2.0, 0), md)
		_box(pb, null, Vector3(w, 0.1, t), Vector3(0, 0.05, 0), md)
	else:
		_box(pb, body, Vector3(w, h, t), Vector3(0, h / 2.0, 0), m)
	# 縁取り(柱と梁)。柱は梁より少し厚く・低くして、面が重ならないようにする
	_box(pb, null, Vector3(0.14, h - 0.02, t + 0.06), Vector3(-w / 2.0 + 0.07, (h - 0.02) / 2.0, 0), md)
	_box(pb, null, Vector3(0.14, h - 0.02, t + 0.06), Vector3(w / 2.0 - 0.07, (h - 0.02) / 2.0, 0), md)
	_box(pb, null, Vector3(w - 0.3, 0.12, t + 0.04), Vector3(0, h - 0.05, 0), md)
	if variant == "" and mat_name_of(id) in ["wood"]:
		for i in 4:
			_box(pb, null, Vector3(w - 0.3, 0.03, t + 0.02), Vector3(0, 0.55 + i * 0.5, 0), md)
	elif variant == "" and mat_name_of(id) in ["brick", "stone", "sandstone"]:
		for i in 5:
			_box(pb, null, Vector3(w - 0.3, 0.025, t + 0.015), Vector3(0, 0.42 + i * 0.42, 0), md)


func mat_name_of(id: String) -> String:
	return ItemDB.item(id).get("mat", "")


func _box(pb: PieceBuilder, body: Node, size: Vector3, pos: Vector3, m: Material) -> void:
	if pb and m:
		pb.box(size, Transform3D(Basis(), pos), m)
	if body:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = pos
		body.add_child(col)


func _add_model_collision(body: Node, id: String) -> void:
	var sizes := {
		"workbench": [Vector3(1.32, 0.92, 0.6), 0.46],
		"furnace": [Vector3(1.2, 1.0, 1.2), 0.5],
		"industrial_furnace": [Vector3(1.75, 1.4, 1.35), 0.7],
		"lathe": [Vector3(1.7, 1.3, 0.62), 0.65],
		"launch_pad": [Vector3(5.0, 0.4, 5.0), 0.2],
		"rocket": [Vector3(1.4, 7.0, 1.4), 3.5],
		"table": [Vector3(1.2, 0.78, 0.75), 0.39],
		"chair": [Vector3(0.46, 0.5, 0.46), 0.25],
		"bed": [Vector3(1.0, 0.55, 2.0), 0.27],
		"chest": [Vector3(0.94, 0.66, 0.6), 0.33],
		"torch": [Vector3(0.15, 1.4, 0.15), 0.7],
		"lantern": [Vector3(0.3, 1.8, 0.3), 0.9],
		"street_lamp": [Vector3(0.4, 3.2, 0.4), 1.6],
		"fireplace": [Vector3(1.6, 1.3, 0.85), 0.65],
		"big_chest": [Vector3(1.44, 0.9, 0.74), 0.45],
		"flower_pot": [Vector3(0.45, 0.8, 0.45), 0.4],
		"rug": [Vector3(1.8, 0.04, 1.2), 0.02],
		"geo_heater": [Vector3(0.9, 1.5, 0.5), 0.75],
		"lava_lamp": [Vector3(0.4, 0.95, 0.4), 0.47],
		"telescope": [Vector3(1.0, 1.6, 1.2), 0.8],
	}
	var s: Array = sizes.get(id, [Vector3(1, 1, 1), 0.5])
	var size: Vector3 = s[0]
	if id == "bed":
		size = Vector3(1.0, 0.55, 2.0)
	_box(null, body, size, Vector3(0, s[1], 0), null)
	if id == "launch_pad":
		# 発射台の塔
		_box(null, body, Vector3(0.6, 8.4, 0.6), Vector3(1.9, 4.4, 0), null)
