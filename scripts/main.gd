extends Node3D
## ゲーム全体のまとめ役。惑星・プレイヤー・資源・建物・画面表示を作って動かす。

const RES_NAMES := {"ore": "鉱石", "crystal": "結晶"}
const ORE_COUNT := 26
const CRYSTAL_COUNT := 16
const COLLECT_RANGE := 3.2
const DRILL_COST := {"crystal": 3}
const DOME_COST := {"ore": 10, "crystal": 2}
const DRILL_INTERVAL := 4.0
const COLONISTS_PER_DOME := 5
const GOAL_COLONISTS := 20
const DAY_LENGTH := 180.0  # 秒

var rng := RandomNumberGenerator.new()
var planet: Planet
var player: Player
var controls: TouchControls
var hud_label: Label
var info_label: Label
var msg_label: Label
var sun_pivot: Node3D

var stock := {"ore": 0, "crystal": 0}
var colonists := 0
var resource_nodes: Array[Dictionary] = []   # {node, type}
var buildings: Array[Dictionary] = []        # {node, type, head}
var _drill_timer := 0.0
var _respawn_timer := 0.0
var _msg_time := 0.0
var _won := false
var _time := 0.0

var _ore_mat: StandardMaterial3D
var _crystal_mat: StandardMaterial3D
var _metal_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _light_mat: StandardMaterial3D


func _ready() -> void:
	rng.seed = 7
	_make_materials()
	_make_environment()

	planet = Planet.new()
	add_child(planet)
	planet.generate()

	for i in ORE_COUNT:
		_spawn_resource("ore")
	for i in CRYSTAL_COUNT:
		_spawn_resource("crystal")

	player = Player.new()
	player.planet_center = planet.global_position
	player.sea_level = planet.sea_level
	add_child(player)
	# 太陽が当たっている昼側に降り立つ
	var sun_dir := sun_pivot.global_transform.basis.z.normalized()
	var start_dir := planet.random_land_dir(rng, 1.0, 4.0)
	for i in 60:
		if start_dir.dot(sun_dir) > 0.7:
			break
		start_dir = planet.random_land_dir(rng, 1.0, 4.0)
	player.spawn_at(planet.surface_point(start_dir) + start_dir * 1.0)

	_make_hud()
	show_message("未知の惑星に着陸した!\n鉱石と結晶を集めて、入植者%d人の基地を作ろう" % GOAL_COLONISTS, 6.0)


# ---------------------------------------------------------------- 見た目の準備

func _make_materials() -> void:
	_ore_mat = StandardMaterial3D.new()
	_ore_mat.albedo_color = Color(0.85, 0.5, 0.2)
	_ore_mat.metallic = 0.6
	_ore_mat.roughness = 0.45

	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.albedo_color = Color(0.4, 0.95, 1.0)
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Color(0.2, 0.85, 1.0)
	_crystal_mat.emission_energy_multiplier = 1.6
	_crystal_mat.roughness = 0.1

	_metal_mat = StandardMaterial3D.new()
	_metal_mat.albedo_color = Color(0.75, 0.77, 0.8)
	_metal_mat.metallic = 0.7
	_metal_mat.roughness = 0.35

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.roughness = 0.05
	_glass_mat.metallic_specular = 1.0

	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1.0, 0.8, 0.3)
	_light_mat.emission_energy_multiplier = 3.0


func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.55, 0.8)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 太陽(ゆっくり回って昼と夜ができる)
	sun_pivot = Node3D.new()
	sun_pivot.rotation = Vector3(0.4, 0.0, 0.25)
	add_child(sun_pivot)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun_pivot.add_child(sun)
	var sun_ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 30.0
	sm.height = 60.0
	sun_ball.mesh = sm
	var sun_mat := StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_color = Color(1.0, 0.92, 0.7)
	sun_ball.material_override = sun_mat
	sun_ball.position = Vector3(0, 0, 900)  # ライトは -Z 向きに照らすので、太陽は +Z 側
	sun_pivot.add_child(sun_ball)

	# 月
	var moon := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 18.0
	mm.height = 36.0
	moon.mesh = mm
	var moon_mat := StandardMaterial3D.new()
	moon_mat.albedo_color = Color(0.7, 0.68, 0.75)
	moon.material_override = moon_mat
	moon.position = Vector3(-260, 140, -380)
	add_child(moon)

	_make_stars()


func _make_stars() -> void:
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(2.2, 2.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	star_mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = star_mesh
	mm.instance_count = 700
	for i in mm.instance_count:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var s := rng.randf_range(0.4, 1.4)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), d * 1500.0))
		var tint := rng.randf()
		var c := Color(1, 1, 1) if tint < 0.7 else (Color(0.7, 0.8, 1.0) if tint < 0.85 else Color(1.0, 0.85, 0.7))
		mm.set_instance_color(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	controls = TouchControls.new()
	controls.player = player
	controls.action_pressed.connect(_on_action)
	layer.add_child(controls)

	hud_label = Label.new()
	hud_label.position = Vector2(20, 14)
	hud_label.add_theme_font_size_override("font_size", 24)
	hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud_label)

	info_label = Label.new()
	info_label.position = Vector2(20, 92)
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(info_label)

	msg_label = Label.new()
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_label.position.y = 70
	msg_label.add_theme_font_size_override("font_size", 26)
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	msg_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(msg_label)


func show_message(text: String, seconds := 2.5) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	_msg_time = seconds


# ---------------------------------------------------------------- 資源

func _orient_on_surface(n: Node3D, dir: Vector3, sink := 0.1) -> void:
	var up := dir.normalized()
	var p := planet.surface_point(up) - up * sink
	var ref := Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT
	var tangent := up.cross(ref).normalized()
	tangent = tangent.rotated(up, rng.randf() * TAU)
	n.transform = Transform3D(Basis.looking_at(tangent, up), p)


func _spawn_resource(type: String) -> void:
	var n := Node3D.new()
	if type == "ore":
		for i in 3:
			var rock := MeshInstance3D.new()
			var box := BoxMesh.new()
			var s := rng.randf_range(0.45, 0.8)
			box.size = Vector3(s, s * 0.8, s)
			rock.mesh = box
			rock.material_override = _ore_mat
			rock.position = Vector3(rng.randf_range(-0.4, 0.4), s * 0.3, rng.randf_range(-0.4, 0.4))
			rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
			n.add_child(rock)
	else:
		for i in 3:
			var shard := MeshInstance3D.new()
			var prism := PrismMesh.new()
			var h := rng.randf_range(0.9, 1.6) * (1.0 if i == 0 else 0.6)
			prism.size = Vector3(0.35, h, 0.35)
			shard.mesh = prism
			shard.material_override = _crystal_mat
			shard.position = Vector3(rng.randf_range(-0.3, 0.3), h * 0.45, rng.randf_range(-0.3, 0.3))
			shard.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
			n.add_child(shard)
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.3, 0.9, 1.0)
		glow.light_energy = 0.8
		glow.omni_range = 4.0
		glow.position.y = 0.8
		n.add_child(glow)
	add_child(n)
	_orient_on_surface(n, planet.random_land_dir(rng, 0.3, 7.0))
	resource_nodes.append({"node": n, "type": type})


func _nearest_resource() -> Dictionary:
	var best := {}
	var best_d := INF
	for r in resource_nodes:
		var d := player.global_position.distance_to((r["node"] as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = {"res": r, "dist": d}
	return best


# ---------------------------------------------------------------- 操作

func _on_action(id: String) -> void:
	if _won and id != "jump":
		return
	match id:
		"collect":
			_try_collect()
		"drill":
			_try_build("drill")
		"dome":
			_try_build("dome")


func _try_collect() -> void:
	var near := _nearest_resource()
	if near.is_empty() or near["dist"] > COLLECT_RANGE:
		show_message("近くに資源がない")
		return
	var r: Dictionary = near["res"]
	var amount := rng.randi_range(2, 4) if r["type"] == "ore" else rng.randi_range(1, 2)
	stock[r["type"]] += amount
	(r["node"] as Node3D).queue_free()
	resource_nodes.erase(r)
	show_message("%s を %d 個手に入れた" % [RES_NAMES[r["type"]], amount], 1.6)


func _can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if stock[k] < cost[k]:
			return false
	return true


func _try_build(type: String) -> void:
	var cost: Dictionary = DRILL_COST if type == "drill" else DOME_COST
	if not _can_afford(cost):
		var need := []
		for k in cost:
			need.append("%s%d" % [RES_NAMES[k], cost[k]])
		show_message("資源が足りない(必要: %s)" % " ".join(need))
		return
	var up := player.get_up()
	var spot_dir := (player.global_position + player.get_forward() * 3.0 - planet.global_position).normalized()
	if planet.height_at(spot_dir) < planet.sea_level + 0.2:
		show_message("水の中には建てられない")
		return
	var spot := planet.surface_point(spot_dir)
	for b in buildings:
		if (b["node"] as Node3D).global_position.distance_to(spot) < 4.0:
			show_message("ほかの建物に近すぎる")
			return
	for k in cost:
		stock[k] -= cost[k]

	var n := Node3D.new()
	var head: Node3D = null
	if type == "drill":
		head = _make_drill(n)
	else:
		_make_dome(n)
	add_child(n)
	# プレイヤーの方を向けて建てる
	var to_player := player.global_position - spot
	to_player = (to_player - spot_dir * to_player.dot(spot_dir)).normalized()
	if to_player.length() < 0.5:
		to_player = up.cross(Vector3.RIGHT).normalized()
	n.transform = Transform3D(Basis.looking_at(to_player, spot_dir), spot - spot_dir * 0.15)
	buildings.append({"node": n, "type": type, "head": head})

	if type == "drill":
		show_message("採掘機を建てた!鉱石を自動で掘ってくれる")
	else:
		colonists += COLONISTS_PER_DOME
		show_message("居住ドームが完成!入植者が%d人増えた" % COLONISTS_PER_DOME)
		if colonists >= GOAL_COLONISTS and not _won:
			_won = true
			show_message("開拓成功!\n入植者%d人の基地ができた。ここからが本当の開拓だ" % colonists, 12.0)


func _make_drill(n: Node3D) -> Node3D:
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 1.1
	cyl.height = 0.6
	base.mesh = cyl
	base.position.y = 0.3
	base.material_override = _metal_mat
	n.add_child(base)

	var tower := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.5, 2.6, 0.5)
	tower.mesh = tb
	tower.position.y = 1.6
	tower.material_override = _ore_mat
	n.add_child(tower)

	var head := Node3D.new()
	head.position.y = 2.9
	n.add_child(head)
	for i in 3:
		var blade := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(1.6, 0.12, 0.25)
		blade.mesh = bb
		blade.rotation.y = i * TAU / 3.0
		blade.material_override = _metal_mat
		head.add_child(blade)
	var lamp := MeshInstance3D.new()
	var ls := SphereMesh.new()
	ls.radius = 0.18
	ls.height = 0.36
	lamp.mesh = ls
	lamp.position.y = 0.2
	lamp.material_override = _light_mat
	head.add_child(lamp)
	return head


func _make_dome(n: Node3D) -> void:
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.3
	cyl.bottom_radius = 2.4
	cyl.height = 0.5
	ring.mesh = cyl
	ring.position.y = 0.25
	ring.material_override = _metal_mat
	n.add_child(ring)

	var dome := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 2.2
	hs.height = 2.2
	hs.is_hemisphere = true
	dome.mesh = hs
	dome.position.y = 0.5
	dome.material_override = _glass_mat
	n.add_child(dome)

	var inner := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(1.4, 1.0, 1.0)
	inner.mesh = ib
	inner.position = Vector3(0, 1.0, 0)
	inner.material_override = _metal_mat
	n.add_child(inner)

	var door := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(0.9, 1.3, 0.8)
	door.mesh = db
	door.position = Vector3(0, 0.9, -2.2)
	door.material_override = _metal_mat
	n.add_child(door)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 1.2
	light.omni_range = 7.0
	light.position.y = 1.8
	n.add_child(light)


# ---------------------------------------------------------------- 毎フレーム

func _process(delta: float) -> void:
	_time += delta
	sun_pivot.rotate_object_local(Vector3.UP, TAU / DAY_LENGTH * delta)

	# 結晶はゆっくり回る
	for r in resource_nodes:
		if r["type"] == "crystal":
			(r["node"] as Node3D).rotate_object_local(Vector3.UP, delta * 0.6)

	# 採掘機の稼働
	var drills := 0
	for b in buildings:
		if b["type"] == "drill":
			drills += 1
			(b["head"] as Node3D).rotate_object_local(Vector3.UP, delta * 4.0)
	if drills > 0:
		_drill_timer += delta
		if _drill_timer >= DRILL_INTERVAL:
			_drill_timer -= DRILL_INTERVAL
			stock["ore"] += drills

	# 取り尽くした資源は少しずつ別の場所に湧く
	_respawn_timer += delta
	if _respawn_timer > 15.0:
		_respawn_timer = 0.0
		var ores := 0
		for r in resource_nodes:
			if r["type"] == "ore":
				ores += 1
		if ores < ORE_COUNT / 2:
			_spawn_resource("ore")
		if resource_nodes.size() - ores < CRYSTAL_COUNT / 2:
			_spawn_resource("crystal")

	_update_hud(delta)


func _update_hud(delta: float) -> void:
	hud_label.text = "鉱石 %d   結晶 %d   入植者 %d / %d" % [stock["ore"], stock["crystal"], colonists, GOAL_COLONISTS]

	var near := _nearest_resource()
	var info := ""
	var can_collect := false
	if not near.is_empty():
		var r: Dictionary = near["res"]
		var dist: float = near["dist"]
		can_collect = dist <= COLLECT_RANGE
		if can_collect:
			info = "%s がすぐそばにある → 採取" % RES_NAMES[r["type"]]
		else:
			info = "最寄りの資源: %s(%dm・%s)" % [RES_NAMES[r["type"]], int(dist), _direction_hint((r["node"] as Node3D).global_position)]
	var drills := 0
	for b in buildings:
		if b["type"] == "drill":
			drills += 1
	if drills > 0:
		info += "\n採掘機 %d台が稼働中(%d秒ごとに鉱石+%d)" % [drills, int(DRILL_INTERVAL), drills]
	if player.is_underwater():
		info += "\n水中:動きが遅くなる"
	info_label.text = info

	controls.enabled["collect"] = can_collect
	controls.enabled["drill"] = _can_afford(DRILL_COST) and not _won
	controls.enabled["dome"] = _can_afford(DOME_COST) and not _won
	controls.queue_redraw()

	if _msg_time > 0.0:
		_msg_time -= delta
		if _msg_time < 0.6:
			msg_label.modulate.a = maxf(_msg_time / 0.6, 0.0)


func _direction_hint(target: Vector3) -> String:
	var up := player.get_up()
	var to := target - player.global_position
	to = to - up * to.dot(up)
	if to.length() < 0.01:
		return "足元"
	to = to.normalized()
	var fwd := player.get_forward()
	var right := fwd.cross(up)
	var angle := rad_to_deg(atan2(to.dot(right), to.dot(fwd)))
	if absf(angle) < 30.0:
		return "前方"
	if absf(angle) > 150.0:
		return "後ろ"
	if angle > 0.0:
		return "右前" if angle < 90.0 else "右後ろ"
	return "左前" if angle > -90.0 else "左後ろ"
