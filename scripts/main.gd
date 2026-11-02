extends Node3D
## ゲーム全体のまとめ役。地表を作り、資源・持ち物・クラフト・設置・画面表示を動かす。

## 叩いて取れる物の種類(tools/balance_sim.py の NODES と合わせてある)
const KINDS := {
	"oak": {"name": "広葉樹", "tool": "axe", "hp": 4, "drop": {"wood": 3}, "tree": true, "scene": "tree_oak", "count": 70},
	"pine": {"name": "針葉樹", "tool": "axe", "hp": 5, "drop": {"wood": 4}, "tree": true, "scene": "tree_pine", "count": 55},
	"rock": {"name": "岩", "tool": "pickaxe", "hp": 3, "drop": {"stone": 3}, "scene": "rock", "radius": 0.75, "count": 40},
	"iron": {"name": "鉄鉱脈", "tool": "pickaxe", "hp": 5, "drop": {"iron": 3, "stone": 1}, "scene": "ore_iron", "radius": 0.8, "count": 30},
	"copper": {"name": "銅鉱脈", "tool": "pickaxe", "hp": 5, "drop": {"copper": 3, "stone": 1}, "scene": "ore_copper", "radius": 0.8, "count": 20},
	"crystal": {"name": "結晶(鉄のツルハシが必要)", "tool": "pickaxe", "tier": 2, "hp": 7, "drop": {"crystal": 1}, "scene": "crystal", "radius": 0.6, "count": 12},
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
const USE_RANGE := 3.4
const PICKUP_RANGE := 4.5
const SETTINGS_PATH := "user://settings.cfg"

var rng := RandomNumberGenerator.new()
var world: World
var player: Player
var build: BuildManager
var controls: TouchControls
var title: TitleScreen
var msg_label: Label
var _msg_time := 0.0
var _scenes := {}
var _respawn_queue: Array[Dictionary] = []   # {kind, time}
var _particles: CPUParticles3D
var _was_attack := false
var _plan := {}
var _pickup_target: Node = null
var _use_node: Node = null
var _playing := false

var inventory := Inventory.new()


func _ready() -> void:
	rng.seed = 20261102
	# 最初の持ち物は石の斧と石のツルハシ
	inventory.add("axe", 1)
	inventory.add("pickaxe", 1)

	world = World.new()
	add_child(world)
	world.build(1234)
	world.scatter_grass(rng, 9000, 900)
	world.make_lake_details(rng)

	for kind in KINDS:
		_scenes[kind] = load("res://assets/models/%s.glb" % KINDS[kind]["scene"])
	for kind in KINDS:
		for i in KINDS[kind]["count"]:
			_spawn(kind)
	_spawn_bushes(45)
	_make_particles()

	player = Player.new()
	add_child(player)
	player.global_position = world.surface(0, 0) + Vector3(0, 0.2, 0)
	player.rotation.y = deg_to_rad(200)
	player.swung.connect(_on_swung)
	player.in_water = func(p: Vector3) -> bool: return p.y < World.WATER_LEVEL and world.lake_factor(p.x, p.z) > 0.0

	build = BuildManager.new()
	build.world = world
	build.player = player
	add_child(build)

	_make_hud()
	_load_settings()
	_select_slot(0)
	_show_title()
	_check_mode.call_deferred()


## 確認用: Web版の URL の末尾が #lake なら湖のそば、#bench なら作業台の前から始める
func _check_mode() -> void:
	if not OS.has_feature("web"):
		return
	var hash_value := str(JavaScriptBridge.eval("location.hash"))
	if hash_value == "#lake":
		_start_game()
		var p := World.LAKE_CENTER + (-World.LAKE_CENTER).normalized() * 30.0
		player.global_position = world.surface(p.x, p.y) + Vector3(0, 0.5, 0)
		var to := World.LAKE_CENTER - p
		player.rotation.y = atan2(-to.x, -to.y)
		player.head.rotation.x = deg_to_rad(-12)
	elif hash_value == "#house":
		_start_game()
		_build_sample_house(Vector3(6, 0, -8))
		player.global_position = world.surface(10, 2) + Vector3(0, 0.5, 0)
		player.rotation.y = atan2(-(-4.0), -(-10.0))
		player.set_first_person(false)
		player.head.rotation.x = deg_to_rad(-8)
	elif hash_value == "#bench":
		_start_game()
		for k in ["wood", "stone", "iron_ingot", "plank", "stick"]:
			inventory.add(k, 40)
		var plan := build.plan_placement("workbench", {"position": player.global_position - player.global_transform.basis.z * 2.5, "normal": Vector3.UP, "collider": world})
		plan["xform"].origin.y = world.height_at(plan["xform"].origin.x, plan["xform"].origin.z)
		var bench := build.place("workbench", plan)
		controls.open_bag("workbench", bench as Station)


# ================================================================ 資源の配置

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
		if zone == "water" or not prefs.has(zone) or world.lake_factor(x, z) > 0.0:
			continue
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


# ================================================================ 画面

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
	controls.pickup_pressed.connect(_on_pickup)
	controls.use_pressed.connect(_on_use)
	controls.title_requested.connect(_show_title)
	controls.sensitivity_changed.connect(func(v: float) -> void: _save_settings())
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

	var title_layer := CanvasLayer.new()
	title_layer.layer = 5
	add_child(title_layer)
	title = TitleScreen.new()
	title.start_pressed.connect(_start_game)
	title.restart_pressed.connect(func() -> void: get_tree().reload_current_scene())
	title_layer.add_child(title)


func _show_title() -> void:
	_playing = false
	controls.active = false
	controls.close_panel()
	title.started = title.started or _msg_time > 0.0 or inventory.total("wood") > 0
	title.visible = true
	msg_label.visible = false


func _start_game() -> void:
	var first := not title.started
	title.visible = false
	title.started = true
	controls.active = true
	msg_label.visible = true
	_playing = true
	if first:
		show_message("見知らぬ惑星の草原に降り立った。\n斧で木を、ツルハシで岩や鉱石を掘ってみよう", 6.0)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		controls.sensitivity = float(cfg.get_value("controls", "sensitivity", 1.0))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "sensitivity", controls.sensitivity)
	cfg.save(SETTINGS_PATH)


func _select_slot(i: int) -> void:
	controls.selected_slot = i
	var id := inventory.id_at(i)
	# 道具なら手に持つ。素材や空の枠なら素手
	var tool_id := id if Inventory.is_tool_item(id) else ""
	if tool_id != player.current_tool:
		player.set_tool(tool_id)
	# 設置できる物を持っているときは、攻撃ボタンが「設置」になる
	var placing := Inventory.is_placeable(id)
	player.can_swing = not placing
	controls.attack_label = "設置" if placing else "攻撃"


func show_message(text: String, seconds := 2.0) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	_msg_time = seconds


# ================================================================ 採取

func _on_swung(target: Object, point: Vector3) -> void:
	if target == null:
		return
	var h := target as Harvestable
	var held := player.current_tool
	if held == "":
		show_message("素手では掘れない。アイテム欄から道具を選ぼう")
		return
	var res := h.hit(ItemDB.tool_kind(held), ItemDB.tool_power(held), ItemDB.tool_tier(held), player.global_position)
	if not res["ok"]:
		if res["message"] != "":
			show_message(res["message"])
		return
	_burst(point, Color(0.55, 0.38, 0.2) if h.is_tree else Color(0.6, 0.6, 0.6))
	if res["done"]:
		var got := []
		for item in h.drops:
			var left := inventory.add(item, h.drops[item])
			got.append("%s +%d" % [ItemDB.item_name(item), h.drops[item] - left])
			if left > 0:
				got.append("(持ち物がいっぱい)")
		show_message("  ".join(got), 1.6)


func _on_destroyed(h: Harvestable) -> void:
	_respawn_queue.append({"kind": h.kind, "time": rng.randf_range(40.0, 80.0)})


# ================================================================ クラフト・設置・回収

func _on_craft(recipe: Dictionary, times: int) -> void:
	var node := controls.station_node
	if node and node.is_timed():
		# 製炉: 素材を先に払って、順番に作ってもらう
		var paid := 0
		for i in times:
			if not inventory.pay(recipe["cost"]):
				break
			paid += 1
		if paid == 0:
			show_message(inventory.missing_text(recipe["cost"]), 2.2)
			return
		node.enqueue(recipe, paid)
		show_message("%s を %d 回分入れた" % [ItemDB.item_name(recipe["id"]), paid], 1.6)
		return
	var err := inventory.craft(recipe)
	if err == "":
		var n := int(recipe["count"])
		show_message("%s%s を作った" % [ItemDB.item_name(recipe["id"]), " ×%d" % n if n > 1 else ""], 1.6)
	else:
		show_message(err, 2.2)


func _update_placement(held: String) -> void:
	var pressed_now := player.attack_held and not _was_attack
	_was_attack = player.attack_held
	if not Inventory.is_placeable(held) or controls.panel != "" or not _playing:
		build.hide_preview()
		return
	_plan = build.update_preview(held)
	if pressed_now:
		if _plan.get("ok", false):
			var body := build.place(held, _plan)
			inventory.remove(held, 1)
			_burst(body.global_position + Vector3(0, 0.3, 0), Color(0.6, 0.45, 0.28))
			show_message("%s を設置した" % ItemDB.item_name(held), 1.4)
		else:
			show_message(_plan.get("reason", "ここには置けない"))


## 斧かツルハシで設置物を狙っているときは「回収」ボタンを出す
func _update_pickup(held: String) -> void:
	_pickup_target = null
	if ItemDB.tool_kind(held) != "" and controls.panel == "":
		var reach := PICKUP_RANGE + (0.0 if player.first_person else player.spring.spring_length)
		var hit := player.get_aim_hit(reach)
		if not hit.is_empty() and (hit["collider"] as Node).is_in_group("placed"):
			_pickup_target = hit["collider"]
	controls.show_pickup = _pickup_target != null
	if _pickup_target:
		controls.pickup_label = ItemDB.item_name(_pickup_target.get_meta("item"))


func _on_pickup() -> void:
	if _pickup_target == null or not is_instance_valid(_pickup_target):
		return
	var id: String = _pickup_target.get_meta("item")
	if id == "launch_pad" and build.occupied.has("rocket:%s" % _pickup_target.get_instance_id()):
		show_message("先にロケットを回収しよう")
		return
	if inventory.space_for(id) < 1:
		show_message("持ち物がいっぱいで回収できない")
		return
	if _pickup_target is Station:
		(_pickup_target as Station).refund(inventory)
	_burst(_pickup_target.global_position + Vector3(0, 0.4, 0), Color(0.7, 0.6, 0.45))
	build.pick_up(_pickup_target)
	inventory.add(id, 1)
	show_message("%s を回収した" % ItemDB.item_name(id), 1.4)
	_pickup_target = null


## 近くの設備の上に「使う」ボタンを出す
func _update_use_button() -> void:
	_use_node = null
	controls.use_target = {}
	if controls.panel != "" or not _playing:
		return
	var best := USE_RANGE
	for n in get_tree().get_nodes_in_group("placed"):
		var id: String = n.get_meta("item")
		if not (n is Station or id == "rocket"):
			continue
		var d := Vector2(n.global_position.x - player.global_position.x, n.global_position.z - player.global_position.z).length()
		var r := best + (2.0 if id == "rocket" else 0.0)
		if d < r:
			best = d
			_use_node = n
	if _use_node == null:
		return
	var id: String = _use_node.get_meta("item")
	var height := 7.6 if id == "rocket" else (2.8 if id == "industrial_furnace" else 1.9)
	var top: Vector3 = (_use_node as Node3D).global_position + Vector3(0, height, 0)
	if player.camera.is_position_behind(top):
		return
	var pos := player.camera.unproject_position(top)
	# 画面のピクセル座標を、操作画面(拡大縮小された座標)に合わせる
	pos *= controls.size / get_viewport().get_visible_rect().size
	var label := "%sを使う" % ItemDB.item_name(id)
	if id == "rocket":
		label = "ロケットに乗る"
	controls.use_target = {"label": label, "pos": pos}


func _on_use() -> void:
	if _use_node == null or not is_instance_valid(_use_node):
		return
	if _use_node.get_meta("item") == "rocket":
		show_message("ロケットが完成した!\n宇宙へ飛び立つ方法は、これから決めます", 5.0)
		return
	controls.open_bag(_use_node.get_meta("item"), _use_node as Station)


# ================================================================ 毎フレーム

func _process(delta: float) -> void:
	if not _playing:
		player.look_delta.x += delta * 0.05  # タイトルの間はゆっくり見回す
	var held := inventory.id_at(controls.selected_slot)
	_update_placement(held)
	_update_pickup(held)
	_update_use_button()

	for n in get_tree().get_nodes_in_group("placed"):
		if n is Station:
			var res: Dictionary = (n as Station).tick(delta, inventory)
			if res.get("blocked", false):
				show_message("持ち物がいっぱいで %s を受け取れない" % ItemDB.item_name(res["id"]))
			elif res.has("count"):
				show_message("%s ×%d ができた" % [ItemDB.item_name(res["id"]), res["count"]], 1.4)

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


## 確認用: 2x2マスの小屋(土台・壁・ドア・窓・屋根)と設備を並べる
func _build_sample_house(origin: Vector3) -> void:
	var fake := func(p: Vector3, col: Node = world) -> Dictionary:
		return {"position": p, "normal": Vector3.UP, "collider": col}
	var base := Vector3(floorf(origin.x / 2.0) * 2.0, 0, floorf(origin.z / 2.0) * 2.0)
	for cx in 2:
		for cz in 2:
			var p := base + Vector3(cx * 2 + 1, 0, cz * 2 + 1)
			build.place("wood_foundation", build.plan_placement("wood_foundation", fake.call(p)))
	var edges := [
		["wood_wall", Vector3(1, 0, 0.1)], ["window_wall", Vector3(3, 0, 0.1)],
		["wood_wall", Vector3(1, 0, 3.9)], ["wood_door", Vector3(3, 0, 3.9)],
		["wood_wall", Vector3(0.1, 0, 1)], ["wood_wall", Vector3(0.1, 0, 3)],
		["window_wall", Vector3(3.9, 0, 1)], ["wood_wall", Vector3(3.9, 0, 3)],
	]
	for e in edges:
		var plan := build.plan_placement(e[0], fake.call(base + e[1]))
		if plan["ok"]:
			build.place(e[0], plan)
	for cx in 2:
		for cz in 2:
			var plan := build.plan_placement("wood_roof", fake.call(base + Vector3(cx * 2 + 1, 0, cz * 2 + 1)))
			build.place("wood_roof", plan)
	for item in [["furnace", Vector3(-2.5, 0, 6)], ["lathe", Vector3(1.5, 0, 7.5)], ["torch", Vector3(5.5, 0, 5)]]:
		var p: Vector3 = base + item[1]
		var plan := build.plan_placement(item[0], fake.call(world.surface(p.x, p.z)))
		build.place(item[0], plan)
