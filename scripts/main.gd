extends Node3D
## ゲーム全体のまとめ役。最初の惑星(地表)を作り、資源・アイテム欄・画面表示を動かす。

## 叩いて取れる物の種類
const KINDS := {
	"oak": {"name": "広葉樹", "tool": "axe", "hp": 4, "drop": {"wood": 3}, "tree": true, "scene": "tree_oak", "count": 70},
	"pine": {"name": "針葉樹", "tool": "axe", "hp": 5, "drop": {"wood": 4}, "tree": true, "scene": "tree_pine", "count": 55},
	"rock": {"name": "岩", "tool": "pickaxe", "hp": 3, "drop": {"stone": 3}, "scene": "rock", "radius": 0.75, "count": 40},
	"iron": {"name": "鉄鉱脈", "tool": "pickaxe", "hp": 5, "drop": {"iron": 2, "stone": 1}, "scene": "ore_iron", "radius": 0.8, "count": 18},
	"copper": {"name": "銅鉱脈", "tool": "pickaxe", "hp": 5, "drop": {"copper": 2, "stone": 1}, "scene": "ore_copper", "radius": 0.8, "count": 12},
	"crystal": {"name": "結晶", "tool": "pickaxe", "hp": 7, "drop": {"crystal": 1}, "scene": "crystal", "radius": 0.6, "count": 7},
}
## 種類ごとに置く場所(地帯)の好み
const ZONES := {
	"oak": ["grass", "grass", "hill"],
	"pine": ["hill", "hill", "grass", "mountain"],
	"rock": ["grass", "hill", "mountain"],
	"iron": ["hill", "mountain", "mountain"],
	"copper": ["hill", "mountain"],
	"crystal": ["mountain"],
}

var rng := RandomNumberGenerator.new()
var world: World
var player: Player
var controls: TouchControls
var msg_label: Label
var _msg_time := 0.0
var _scenes := {}
var _respawn_queue: Array[Dictionary] = []   # {kind, time}
var _particles: CPUParticles3D

var inventory := Inventory.new()

# 設置
const PLACE_REACH := 5.0
var _workbench_scene: PackedScene
var _preview: Node3D
var _preview_ok_mat: StandardMaterial3D
var _preview_ng_mat: StandardMaterial3D
var _preview_valid := false
var _placed: Array[Node3D] = []
var _was_attack := false


func _ready() -> void:
	rng.seed = 20261102
	# 最初の持ち物は斧とツルハシ
	inventory.add("axe", 1)
	inventory.add("pickaxe", 1)

	world = World.new()
	add_child(world)
	world.build(1234)
	world.scatter_grass(rng, 9000, 900)

	for kind in KINDS:
		_scenes[kind] = load("res://assets/models/%s.glb" % KINDS[kind]["scene"])
	for kind in KINDS:
		for i in KINDS[kind]["count"]:
			_spawn(kind)
	_spawn_bushes(45)
	_make_particles()
	_make_preview()

	player = Player.new()
	add_child(player)
	player.global_position = world.surface(0, 0) + Vector3(0, 0.2, 0)
	player.rotation.y = deg_to_rad(200)
	player.swung.connect(_on_swung)

	_make_hud()
	_select_slot(0)
	show_message("見知らぬ惑星の草原に降り立った。\n斧で木を、ツルハシで岩や鉱石を掘ってみよう", 6.0)


# ---------------------------------------------------------------- 配置

func _random_spot(kind: String) -> Vector3:
	var prefs: Array = ZONES[kind]
	for i in 200:
		var r := sqrt(rng.randf()) * 112.0
		var a := rng.randf() * TAU
		var x := cos(a) * r
		var z := sin(a) * r
		if Vector2(x, z).length() < 9.0:
			continue  # スタート地点の周りは空けておく
		var zone := world.zone_at(x, z)
		if zone == "water" or not prefs.has(zone):
			continue
		# 好みの地帯ほど選ばれやすい
		if rng.randf() > float(prefs.count(zone)) / prefs.size() * 1.5:
			continue
		return world.surface(x, z)
	return Vector3.ZERO


func _spawn(kind: String) -> void:
	var pos := _random_spot(kind)
	if pos == Vector3.ZERO:
		return
	var h := Harvestable.new()
	h.setup(kind, KINDS[kind], _scenes[kind], rng)
	add_child(h)
	h.global_position = pos - Vector3(0, 0.05, 0)
	h.destroyed.connect(_on_destroyed)


func _spawn_bushes(count: int) -> void:
	var bush: PackedScene = load("res://assets/models/bush.glb")
	for i in count:
		var pos := _random_spot("oak")
		if pos == Vector3.ZERO:
			continue
		var b: Node3D = bush.instantiate()
		b.position = pos
		b.rotation.y = rng.randf() * TAU
		b.scale = Vector3.ONE * rng.randf_range(0.7, 1.3)
		add_child(b)


func _make_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 14
	_particles.lifetime = 0.6
	_particles.explosiveness = 1.0
	_particles.direction = Vector3.UP
	_particles.spread = 70.0
	_particles.initial_velocity_min = 2.0
	_particles.initial_velocity_max = 4.0
	_particles.gravity = Vector3(0, -12, 0)
	_particles.scale_amount_min = 0.5
	_particles.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.07
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	_particles.mesh = m
	add_child(_particles)


func _burst(pos: Vector3, color: Color) -> void:
	_particles.global_position = pos
	_particles.color = color
	_particles.restart()
	_particles.emitting = true


# ---------------------------------------------------------------- 操作

func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	controls = TouchControls.new()
	controls.player = player
	controls.inventory = inventory
	controls.slot_selected.connect(_select_slot)
	controls.view_toggled.connect(func() -> void:
		player.set_first_person(not player.first_person)
		show_message("一人称視点" if player.first_person else "三人称視点", 1.2)
	)
	controls.craft_requested.connect(_on_craft)
	inventory.changed.connect(func() -> void: _select_slot(controls.selected_slot))
	layer.add_child(controls)

	msg_label = Label.new()
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_label.position.y = 60
	msg_label.add_theme_font_size_override("font_size", 24)
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	msg_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(msg_label)


func _select_slot(i: int) -> void:
	controls.selected_slot = i
	var id := inventory.id_at(i)
	# 道具なら手に持つ。素材や空の枠なら素手
	var tool_id := id if Inventory.is_tool_item(id) else ""
	# 設置できる物を持っているときは、攻撃ボタンが「設置」になる
	var placing := Inventory.is_placeable(id)
	player.can_swing = not placing
	controls.attack_label = "設置" if placing else "攻撃"
	if tool_id != player.current_tool:
		player.set_tool(tool_id)


func show_message(text: String, seconds := 2.0) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	_msg_time = seconds


func _on_swung(target: Object, point: Vector3) -> void:
	if target == null:
		return
	var h := target as Harvestable
	if player.current_tool == "":
		show_message("素手では掘れない。アイテム欄から道具を選ぼう")
		return
	var res := h.hit(player.current_tool, player.global_position)
	if not res["ok"]:
		if res["message"] != "":
			show_message(res["message"])
		return
	_burst(point, Color(0.55, 0.38, 0.2) if h.is_tree else Color(0.6, 0.6, 0.6))
	if res["done"]:
		var got := []
		for item in h.drops:
			var left := inventory.add(item, h.drops[item])
			got.append("%s +%d" % [Inventory.item_name(item), h.drops[item] - left])
			if left > 0:
				got.append("(持ち物がいっぱい)")
		show_message("  ".join(got), 1.6)


func _on_destroyed(h: Harvestable) -> void:
	# しばらくすると別の場所にまた生える
	_respawn_queue.append({"kind": h.kind, "time": rng.randf_range(40.0, 80.0)})


# ---------------------------------------------------------------- 毎フレーム

func _process(delta: float) -> void:
	_update_placement()
	for r in _respawn_queue:
		r["time"] -= delta
	for r in _respawn_queue.filter(func(x: Dictionary) -> bool: return x["time"] <= 0.0):
		_spawn(r["kind"])
		_respawn_queue.erase(r)

	var t := player.get_target()
	if t:
		var h := t as Harvestable
		controls.target_name = h.display_name
		controls.target_ratio = float(h.hp) / h.max_hp
	else:
		controls.target_ratio = -1.0

	if _msg_time > 0.0:
		_msg_time -= delta
		if _msg_time < 0.5:
			msg_label.modulate.a = maxf(_msg_time / 0.5, 0.0)


# ---------------------------------------------------------------- クラフトと設置

func _on_craft(i: int) -> void:
	var rec: Dictionary = Inventory.RECIPES[i]
	var err := inventory.craft(rec)
	if err == "":
		show_message("%s を作った" % Inventory.item_name(rec["id"]), 1.6)
	else:
		show_message(err, 2.2)


func _make_preview() -> void:
	_workbench_scene = load("res://assets/models/workbench.glb")
	_preview = _workbench_scene.instantiate()
	_preview.visible = false
	add_child(_preview)
	_preview_ok_mat = _ghost_material(Color(0.4, 1.0, 0.5, 0.45))
	_preview_ng_mat = _ghost_material(Color(1.0, 0.35, 0.3, 0.45))
	for m in _preview.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ghost_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	return m


## 設置できる物を持っているとき、視線の先に半透明の見本を出す。攻撃(設置)ボタンを押した瞬間に置く
func _update_placement() -> void:
	var held := inventory.id_at(controls.selected_slot)
	var pressed_now := player.attack_held and not _was_attack
	_was_attack = player.attack_held
	if not Inventory.is_placeable(held) or controls.bag_open:
		_preview.visible = false
		return

	var reach := PLACE_REACH + (0.0 if player.first_person else player.spring.spring_length)
	var hit := player.get_aim_hit(reach)
	if hit.is_empty():
		_preview.visible = false
		if pressed_now:
			show_message("地面を狙って設置しよう")
		return

	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var reason := ""
	if hit["collider"] is Harvestable or (hit["collider"] as Node).is_in_group("placed"):
		reason = "ほかの物の上には置けない"
	elif normal.y < 0.8:
		reason = "坂が急すぎて置けない"
	elif pos.y < World.WATER_LEVEL and Vector2(pos.x, pos.z).distance_to(World.LAKE_CENTER) < World.LAKE_RADIUS * 1.3:
		reason = "水の中には置けない"
	elif Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length() < 1.0:
		reason = "自分の足元には置けない"
	else:
		for n in get_children():
			if (n is Harvestable or n.is_in_group("placed")) and Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length() < 1.4:
				reason = "近くの物とぶつかる"
				break
	_preview_valid = reason == ""

	# 作業する側(正面)をプレイヤーに向ける
	var to_player := player.global_position - pos
	_preview.global_position = pos
	_preview.rotation = Vector3(0, atan2(-to_player.x, -to_player.z), 0)
	_preview.visible = true
	for m in _preview.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).material_override = _preview_ok_mat if _preview_valid else _preview_ng_mat

	if pressed_now:
		if _preview_valid:
			_place(held, _preview.global_transform)
		else:
			show_message(reason)


func _place(id: String, xform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("placed")
	body.set_meta("item", id)
	var model: Node3D = _workbench_scene.instantiate()
	body.add_child(model)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.32, 0.92, 0.6)
	col.shape = box
	col.position.y = 0.46
	body.add_child(col)
	add_child(body)
	body.global_transform = xform
	_placed.append(body)
	inventory.remove(id, 1)
	_burst(xform.origin + Vector3(0, 0.3, 0), Color(0.6, 0.45, 0.28))
	show_message("%s を設置した" % Inventory.item_name(id), 1.6)
