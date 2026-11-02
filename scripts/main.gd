extends Node3D
## ゲーム全体のまとめ役。地表を作り、資源・持ち物・クラフト・設置・画面表示を動かす。

## 叩いて取れる物の種類(tools/balance_sim.py の NODES と合わせてある)
## zones: 置く地帯 / spot: 特別な置き場所 / sizes: 大きさがまちまち(大きいほど多く取れる)
const KINDS := {
	"oak": {"name": "広葉樹", "tool": "axe", "hp": 4, "drop": {"wood": 3}, "tree": true, "scene": "tree_oak", "count": 90, "zones": ["grass", "grass", "hill", "forest", "forest"]},
	"pine": {"name": "針葉樹", "tool": "axe", "hp": 5, "drop": {"wood": 4}, "tree": true, "scene": "tree_pine", "count": 50, "zones": ["hill", "hill", "mountain", "forest"]},
	"big_tree": {"name": "大木", "tool": "axe", "hp": 10, "drop": {"wood": 8, "resin": 2}, "tree": true, "scene": "tree_big", "radius": 0.65, "count": 105, "zones": ["forest"], "view": 230.0},
	"snow_pine": {"name": "雪の針葉樹", "tool": "axe", "hp": 5, "drop": {"wood": 4}, "tree": true, "scene": "tree_pine_snow", "count": 55, "zones": ["snow", "snow", "mountain"]},
	"dead_tree": {"name": "枯れ木", "tool": "axe", "hp": 2, "drop": {"wood": 2}, "tree": true, "scene": "tree_dead", "radius": 0.25, "count": 30, "zones": ["lavaland", "desert"]},
	"cactus": {"name": "サボテン", "tool": "axe", "hp": 2, "drop": {"cactus_fiber": 3}, "tree": true, "scene": "cactus", "radius": 0.35, "count": 45, "zones": ["desert"]},
	"rock": {"name": "岩", "tool": "pickaxe", "hp": 3, "drop": {"stone": 3}, "scene": "rock", "radius": 0.75, "count": 60, "sizes": true, "zones": ["grass", "hill", "mountain", "forest", "snow"]},
	"basalt": {"name": "玄武岩", "tool": "pickaxe", "hp": 3, "drop": {"stone": 3}, "scene": "basalt", "radius": 0.75, "count": 35, "sizes": true, "zones": ["lavaland"]},
	"sandstone": {"name": "砂岩", "tool": "pickaxe", "hp": 3, "drop": {"sandstone": 3}, "scene": "sandstone", "radius": 0.8, "count": 40, "sizes": true, "zones": ["desert"]},
	"sand": {"name": "砂山", "tool": "pickaxe", "hp": 2, "drop": {"sand": 4}, "scene": "sand_pile", "radius": 1.0, "count": 30, "zones": ["desert"]},
	"iron": {"name": "鉄鉱脈", "tool": "pickaxe", "hp": 5, "drop": {"iron": 3, "stone": 1}, "scene": "ore_iron", "radius": 0.8, "count": 40, "sizes": true, "zones": ["hill", "mountain", "snow"]},
	"copper": {"name": "銅鉱脈", "tool": "pickaxe", "hp": 5, "drop": {"copper": 3, "stone": 1}, "scene": "ore_copper", "radius": 0.8, "count": 28, "sizes": true, "zones": ["hill", "mountain", "desert"]},
	"coal": {"name": "石炭", "tool": "pickaxe", "hp": 4, "drop": {"coal": 3}, "scene": "ore_coal", "radius": 0.8, "count": 40, "sizes": true, "zones": ["forest", "hill", "mountain"]},
	"gold": {"name": "金鉱脈(鉄のツルハシ)", "tool": "pickaxe", "tier": 2, "hp": 7, "drop": {"gold_ore": 2, "stone": 1}, "scene": "ore_gold", "radius": 0.8, "count": 18, "sizes": true, "zones": ["desert"]},
	"crystal": {"name": "結晶(鉄のツルハシ)", "tool": "pickaxe", "tier": 2, "hp": 7, "drop": {"crystal": 1}, "scene": "crystal", "radius": 0.6, "count": 18, "sizes": true, "zones": ["mountain", "snow"]},
	"ice": {"name": "氷塊", "tool": "pickaxe", "hp": 3, "drop": {"ice": 3}, "scene": "ice", "radius": 0.75, "count": 35, "sizes": true, "zones": ["snow"]},
	"sulfur": {"name": "硫黄", "tool": "pickaxe", "hp": 3, "drop": {"sulfur": 3}, "scene": "sulfur", "radius": 0.7, "count": 24, "sizes": true, "spot": "near_vents"},
	"obsidian": {"name": "黒曜石(鋼鉄のツルハシ)", "tool": "pickaxe", "tier": 3, "hp": 8, "drop": {"obsidian": 2}, "scene": "obsidian", "radius": 0.6, "count": 16, "sizes": true, "spot": "near_lava"},
	"clam": {"name": "二枚貝(真珠)", "tool": "any", "hp": 1, "drop": {"pearl": 1}, "scene": "clam", "radius": 0.45, "count": 14, "spot": "lake_bottom"},
	"clay": {"name": "粘土", "tool": "pickaxe", "hp": 2, "drop": {"clay": 3}, "scene": "clay", "radius": 0.8, "count": 16, "spot": "lake_shallow"},
}
## 洞窟の中に必ず置く資源
const CAVE_ORES := {"iron": 2, "coal": 2, "gold": 1, "crystal": 2, "copper": 1}
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
var _safe_pos := Vector3.ZERO      ## 溶岩に落ちたときに戻る場所
var _safe_timer := 0.0
var _biome := "grass"
var _warm_node: Node3D             ## 起動時の下準備用(数フレームで消す)
var _warm_frames := 0
var _zoomed := false

# 体の状態
var oxygen := 20.0
var body_temp := 50.0              ## 0(凍える)〜50(ふつう)〜100(暑すぎる)
var _underwater_fx: ColorRect
var _bubbles: CPUParticles3D
var _weather: CPUParticles3D
var _land_fog := 0.0015
var _dynamites: Array[Dictionary] = []

var inventory := Inventory.new()


func _ready() -> void:
	rng.seed = 20261102
	# 最初の持ち物は石の斧と石のツルハシ
	inventory.add("axe", 1)
	inventory.add("pickaxe", 1)

	world = World.new()
	add_child(world)
	world.build(1234)
	world.scatter_grass(rng, 12000, 900)
	world.make_lake_details(rng)

	for kind in KINDS:
		_scenes[kind] = load("res://assets/models/%s.glb" % KINDS[kind]["scene"])
	for kind in KINDS:
		for i in KINDS[kind]["count"]:
			_spawn(kind)
	for c in World.CAVES:
		for kind in CAVE_ORES:
			for i in CAVE_ORES[kind]:
				_spawn(kind, _cave_spot(c))
	_spawn_bushes(70)
	_make_particles()

	player = Player.new()
	add_child(player)
	player.global_position = world.surface(0, 0) + Vector3(0, 0.2, 0)
	player.rotation.y = deg_to_rad(200)
	player.swung.connect(_on_swung)
	player.in_water = func(p: Vector3) -> bool: return world.liquid_at(p) in ["water", "hot"]
	_safe_pos = player.global_position
	player.respawn_point = _safe_pos

	build = BuildManager.new()
	build.world = world
	build.player = player
	add_child(build)

	_make_hud()
	_make_effects()
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
	elif hash_value in ["#forest", "#desert", "#snow", "#lava", "#cave", "#dive"]:
		_start_game()
		var spots := {"#forest": Vector2(-150, 10), "#desert": Vector2(150, -20), "#snow": Vector2(-30, -140)}
		var look_at := Vector2.ZERO
		var pos := Vector2.ZERO
		if spots.has(hash_value):
			pos = spots[hash_value]
			look_at = pos * 1.4
		elif hash_value == "#lava":
			# 溶岩地帯のいちばん奥の溶岩の池
			var l: Vector4 = world.lava_pools[1]
			for cand in world.lava_pools.slice(1):
				if Vector2(cand.x, cand.y).length() > Vector2(l.x, l.y).length():
					l = cand
			pos = Vector2(l.x, l.y) + Vector2(l.z + 7.0, 0).rotated(0.6)
			look_at = Vector2(l.x, l.y)
		elif hash_value == "#cave":
			var c: Vector3 = World.CAVES[1]
			var out := Vector2(-c.x, -c.y).normalized()
			pos = Vector2(c.x, c.y) + out * (c.z * 0.4)
			look_at = Vector2(c.x, c.y)
		elif hash_value == "#dive":
			pos = World.LAKE_CENTER + Vector2(5, -4)
			look_at = World.LAKE_CENTER + Vector2(-5, 4)
		player.global_position = Vector3(pos.x, world.ground_y(pos.x, pos.y) + 0.4, pos.y)
		if hash_value == "#dive":
			player.global_position.y = World.WATER_LEVEL - 2.2
		var to := look_at - pos
		player.rotation.y = atan2(-to.x, -to.y)
		player.head.rotation.x = deg_to_rad(-6)
		world.time_of_day = 0.4
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
	var def: Dictionary = KINDS[kind]
	match def.get("spot", ""):
		"near_vents", "near_lava":
			var centers: Array[Vector4] = []
			for l in world.lava_pools.slice(1):
				centers.append(l)
			if def["spot"] == "near_vents":
				for g in world.geysers:
					centers.append(Vector4(g.x, g.y, 1.0, 0.0))
			for i in 60:
				var c: Vector4 = centers[rng.randi() % centers.size()]
				var a := rng.randf() * TAU
				var r := c.z * 1.7 + rng.randf_range(1.0, 6.0)
				var x := c.x + cos(a) * r
				var z := c.y + sin(a) * r
				if world.zone_at(x, z) in ["lavaland", "mountain", "hill"]:
					return world.surface(x, z)
			return Vector3.ZERO
		"lake_bottom", "lake_shallow":
			for i in 200:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * World.LAKE_RADIUS * 1.2
				var x := World.LAKE_CENTER.x + cos(a) * r
				var z := World.LAKE_CENTER.y + sin(a) * r
				var h := world.height_at(x, z)
				var depth := World.WATER_LEVEL - h
				var ok := depth > 1.2 if def["spot"] == "lake_bottom" else (depth > -0.2 and depth < 1.4)
				if ok and world.lake_factor(x, z) > 0.0:
					return Vector3(x, h, z)
			return Vector3.ZERO
	var prefs: Array = def["zones"]
	for i in 300:
		var r := sqrt(rng.randf()) * 215.0
		var a := rng.randf() * TAU
		var x := cos(a) * r
		var z := sin(a) * r
		if Vector2(x, z).length() < 9.0:
			continue  # スタート地点の周りは空けておく
		var zone := world.zone_at(x, z)
		if not prefs.has(zone):
			continue
		if rng.randf() > float(prefs.count(zone)) / prefs.size() * 1.5:
			continue
		return world.surface(x, z)
	return Vector3.ZERO


func _cave_spot(c: Vector3) -> Vector3:
	var a := rng.randf() * TAU
	var r := rng.randf_range(2.5, c.z - 2.5)
	var x := c.x + cos(a) * r
	var z := c.y + sin(a) * r
	return world.surface(x, z)


func _spawn(kind: String, at := Vector3.ZERO) -> void:
	var pos := at if at != Vector3.ZERO else _random_spot(kind)
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
		for g in b.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).visibility_range_end = 90.0
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
	# 設置できる物・バケツ・ダイナマイトを持っているときは、攻撃ボタンの役目が変わる
	var placing := Inventory.is_placeable(id)
	var kind := ItemDB.tool_kind(id)
	player.can_swing = not placing and not (kind in ["bucket", "bucket_full", "dynamite"])
	controls.attack_label = "設置" if placing else ({"bucket": "汲む", "bucket_full": "まく", "dynamite": "投げる"}.get(kind, "攻撃"))


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
	if _pickup_target is Station and not (_pickup_target as Station).refund(inventory):
		show_message("中身が持ち物に入りきらない")
		return
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
		if _zoomed:
			_zoomed = false
			player.camera.fov = 72.0
		return
	var id: String = _use_node.get_meta("item")
	var height := 7.6 if id == "rocket" else (2.8 if id == "industrial_furnace" else 1.9)
	var top: Vector3 = (_use_node as Node3D).global_position + Vector3(0, height, 0)
	if player.camera.is_position_behind(top):
		return
	var pos := player.camera.unproject_position(top)
	# 画面のピクセル座標を、操作画面(拡大縮小された座標)に合わせる
	pos *= controls.size / get_viewport().get_visible_rect().size
	var item := ItemDB.item(id)
	var label := "%sを使う" % ItemDB.item_name(id)
	if id == "rocket":
		label = "ロケットに乗る"
	elif item.has("storage"):
		label = "%sを開ける" % ItemDB.item_name(id)
	elif item.get("sleep", false):
		label = "ベッドで眠る"
	elif id == "telescope":
		label = "望遠鏡をのぞく" if not _zoomed else "望遠鏡から離れる"
	controls.use_target = {"label": label, "pos": pos}


func _on_use() -> void:
	if _use_node == null or not is_instance_valid(_use_node):
		return
	var id: String = _use_node.get_meta("item")
	var item := ItemDB.item(id)
	if id == "rocket":
		show_message("ロケットが完成した!\n宇宙へ飛び立つ方法は、これから決めます", 5.0)
	elif item.get("sleep", false):
		if world.is_night():
			world.time_of_day = 0.26
			world.apply_time()
			show_message("ぐっすり眠った。朝になった", 3.0)
		else:
			show_message("眠れるのは夜だけ")
	elif id == "telescope":
		_zoomed = not _zoomed
		player.camera.fov = 14.0 if _zoomed else 72.0
		show_message("遠くまでよく見える(もう一度押すと戻る)" if _zoomed else "望遠鏡から離れた", 2.0)
	else:
		controls.open_bag(id, _use_node as Station)


# ================================================================ 毎フレーム

func _process(delta: float) -> void:
	if not _playing:
		player.look_delta.x += delta * 0.05  # タイトルの間はゆっくり見回す
	if _warm_node and _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			_warm_node.queue_free()
			_warm_node = null
	var held := inventory.id_at(controls.selected_slot)
	if _playing:
		# 地面の下に入り込んでしまったら、地面の上に戻す
		var pp := player.global_position
		if pp.y < world.height_at(pp.x, pp.z) - 2.5 and not world.in_cave(pp):
			player.global_position = Vector3(pp.x, world.ground_y(pp.x, pp.z) + 0.6, pp.z)
			player.velocity = Vector3.ZERO
		world.advance_time(delta)
		_update_body(delta)
		_update_hand_action(held)
		_update_dynamite(delta)
		_update_biome()
	world.update_geysers(delta)
	world.update_fish(delta)
	_update_underwater_view()
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


# ================================================================ 地域・体の状態・道具

func _make_effects() -> void:
	# 水中の青い色
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_underwater_fx = ColorRect.new()
	_underwater_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_underwater_fx.color = Color(0.05, 0.32, 0.45, 0.32)
	_underwater_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underwater_fx.visible = false
	layer.add_child(_underwater_fx)
	# 水中の泡
	_bubbles = _particles_like(Color(0.85, 0.95, 1.0, 0.7), 0.04)
	_bubbles.amount = 16
	_bubbles.lifetime = 2.5
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 25.0
	_bubbles.gravity = Vector3(0, 1.5, 0)
	_bubbles.initial_velocity_min = 0.3
	_bubbles.initial_velocity_max = 0.8
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = 0.3
	_bubbles.emitting = false
	player.add_child(_bubbles)
	_bubbles.position = Vector3(0, Player.EYE_HEIGHT - 0.2, -0.5)
	# 雪や火の粉(地域によって切り替える)
	_weather = _particles_like(Color.WHITE, 0.05)
	_weather.amount = 220
	_weather.lifetime = 5.0
	_weather.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_weather.emission_box_extents = Vector3(18, 1, 18)
	_weather.direction = Vector3.DOWN
	_weather.gravity = Vector3(0, -1.2, 0)
	_weather.initial_velocity_min = 0.5
	_weather.initial_velocity_max = 1.2
	_weather.emitting = false
	player.add_child(_weather)
	_weather.position = Vector3(0, 9, 0)
	_land_fog = world.env.fog_density
	# 起動時の下準備: 置ける物をすべて一度描いておく(タイトル画面の裏)
	_warm_node = build.warm_up(player.camera.global_transform * Transform3D(Basis(), Vector3(0, 0, -2.5)))
	_warm_frames = 6


func _particles_like(c: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	sm.material = m
	p.mesh = sm
	p.local_coords = false
	return p


## 地域が変わったら知らせて、雪や火の粉を降らせる
func _update_biome() -> void:
	var p := player.global_position
	var b := world.biome_at(p.x, p.z)
	if world.in_cave(p):
		b = "cave"
	if b == _biome:
		return
	_biome = b
	var names := World.BIOME_NAMES.duplicate()
	names["cave"] = "洞窟"
	var hint := {"snow": "寒さに注意(防寒コート・松明・温泉で温まる)", "lava": "暑さと溶岩に注意(耐熱スーツがあると安心)",
		"desert": "砂・サボテン・金が見つかる", "forest": "大木から樹脂が取れる", "cave": "鉱石がたくさん眠っている"}
	show_message("%s に入った\n%s" % [names.get(b, ""), hint.get(b, "")], 3.0)
	var m := _weather.mesh.surface_get_material(0) as StandardMaterial3D
	if b == "snow":
		m.albedo_color = Color(1, 1, 1, 0.9)
		_weather.gravity = Vector3(0, -1.2, 0)
		_weather.emitting = true
	elif b == "lava":
		m.albedo_color = Color(1.0, 0.5, 0.15, 0.9)
		_weather.gravity = Vector3(0, 0.6, 0)
		_weather.emitting = true
	else:
		_weather.emitting = false


## 体温・息・溶岩・間欠泉
func _update_body(delta: float) -> void:
	var p := player.global_position
	var w := world.biome_weights(p.x, p.z)
	var liquid := world.liquid_at(p + Vector3(0, 0.3, 0))

	# 溶岩に触れたら、安全な場所へ戻る
	if world.liquid_at(p + Vector3(0, 0.1, 0)) == "lava":
		player.global_position = _safe_pos + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO
		body_temp = minf(body_temp + 25.0, 100.0)
		show_message("あつっ!溶岩に触れた", 2.0)
		return
	_safe_timer -= delta
	if _safe_timer <= 0.0 and player.is_on_floor() and liquid == "":
		_safe_timer = 1.0
		_safe_pos = p
		player.respawn_point = p

	# 間欠泉の上にいると吹き上げられる
	if world.geyser_push(p) and player.launch_velocity == 0.0 and player.velocity.y < 5.0:
		player.launch_velocity = 15.0
		show_message("間欠泉に吹き飛ばされた!", 1.5)

	# 体温: 雪山では下がり、溶岩地帯では上がる。熱を出す物や温泉の近くでは温まる
	var target := 50.0
	var rate := 6.0
	var heat := _heat_nearby(p)
	if liquid == "hot":
		target = 60.0
		rate = 15.0
	elif heat > 0.0:
		target = 55.0
		rate = 6.0 + heat
	elif w["snow"] > 0.5 and not world.in_cave(p):
		target = 0.0
		rate = 2.2 * (0.15 if inventory.has_gear("cold") else 1.0) * (1.4 if world.is_night() else 1.0)
	elif w["lava"] > 0.5:
		var near_lava := false
		for l in world.lava_pools:
			if Vector2(p.x, p.z).distance_to(Vector2(l.x, l.y)) < l.z + 6.0:
				near_lava = true
		target = 100.0
		rate = (5.0 if near_lava else 1.8) * (0.12 if inventory.has_gear("heat") else 1.0)
	body_temp = move_toward(body_temp, target, rate * delta)
	var cold := body_temp < 15.0
	var hot := body_temp > 85.0
	player.speed_mul = 0.55 if (cold or hot) else 1.0
	controls.temperature = body_temp if (absf(body_temp - 50.0) > 3.0 or w["snow"] > 0.5 or w["lava"] > 0.5) else -1.0
	var tick := fmod(Time.get_ticks_msec() / 1000.0, 6.0) < delta
	if cold and tick:
		show_message("凍えそう…動きが遅くなる(松明や温泉で温まろう)", 2.5)
	elif hot and tick:
		show_message("暑すぎる…動きが遅くなる(耐熱スーツがほしい)", 2.5)

	# 息: 頭まで潜ると減る。なくなると水面へ浮かぶ
	var max_o := 20.0 * (3.0 if inventory.has_gear("oxygen") else 1.0)
	player.swim_mul = 1.7 if inventory.has_gear("swim") else 1.0
	if player.head_under:
		oxygen = maxf(oxygen - delta, 0.0)
		if oxygen <= 0.0 and not player.force_up:
			player.force_up = true
			show_message("息が続かない!", 1.5)
	else:
		oxygen = minf(oxygen + delta * 8.0, max_o)
		player.force_up = false
	controls.oxygen = oxygen / max_o if (player.head_under or oxygen < max_o - 0.1) else -1.0


## 近くにある熱を出す物(松明・暖炉・ヒーターなど)の強さ
func _heat_nearby(p: Vector3) -> float:
	var best := 0.0
	for n in get_tree().get_nodes_in_group("placed"):
		var r: float = ItemDB.item(n.get_meta("item")).get("heat", 0.0)
		if r > 0.0 and (n as Node3D).global_position.distance_to(p) < r:
			best = maxf(best, r)
	for s in world.hot_springs:
		if Vector2(p.x, p.z).distance_to(Vector2(s.x, s.y)) < s.z + 3.0:
			best = maxf(best, 8.0)
	return best


## 水中の見え方(青い霧と泡)
func _update_underwater_view() -> void:
	var cam := player.camera.global_position
	var under := world.liquid_at(cam) in ["water", "hot"]
	_underwater_fx.visible = under
	_bubbles.emitting = under
	if under:
		world.env.fog_density = 0.07
		world.env.fog_light_color = Color(0.08, 0.32, 0.42)
	elif world.env.fog_density != _land_fog:
		world.env.fog_density = _land_fog
		world.apply_time()


## バケツで汲む・まく、ダイナマイトを投げる
func _update_hand_action(held: String) -> void:
	var kind := ItemDB.tool_kind(held)
	if not (kind in ["bucket", "bucket_full", "dynamite"]) or controls.panel != "":
		return
	if not (player.attack_held and not _was_attack):
		return
	if kind == "bucket":
		var cam := player.camera.global_position
		var fwd := -player.camera.global_transform.basis.z
		for i in 30:
			var liquid := world.liquid_at(cam + fwd * (0.3 + i * 0.18))
			if liquid != "":
				var filled: String = {"water": "water_bucket", "lava": "lava_bucket", "hot": "hot_water"}[liquid]
				inventory.remove("bucket", 1)
				inventory.add(filled, 1)
				show_message("%s を手に入れた" % ItemDB.item_name(filled), 1.6)
				return
		show_message("水・温泉・溶岩に向けて使おう")
	elif kind == "bucket_full":
		inventory.remove(held, 1)
		inventory.add("bucket", 1)
		show_message("バケツを空にした", 1.2)
	elif kind == "dynamite":
		var hit := player.get_aim_hit(9.0)
		var pos: Vector3 = hit["position"] if not hit.is_empty() else player.global_position - player.global_transform.basis.z * 6.0
		pos.y = maxf(pos.y, world.height_at(pos.x, pos.z))
		var node: Node3D = load("res://assets/models/dynamite.glb").instantiate()
		node.scale = Vector3.ONE * 2.0
		add_child(node)
		node.global_position = pos + Vector3(0, 0.2, 0)
		var spark := _particles_like(Color(1.0, 0.8, 0.3), 0.03)
		spark.amount = 20
		spark.lifetime = 0.4
		spark.direction = Vector3.UP
		spark.spread = 60.0
		spark.initial_velocity_min = 1.0
		spark.initial_velocity_max = 2.0
		node.add_child(spark)
		spark.position = Vector3(0, 0.25, 0)
		spark.emitting = true
		_dynamites.append({"node": node, "time": 2.2})
		inventory.remove("dynamite", 1)
		show_message("ダイナマイトを投げた!離れて!", 1.5)


func _update_dynamite(delta: float) -> void:
	for d in _dynamites.duplicate():
		d["time"] -= delta
		if d["time"] > 0.0:
			continue
		_dynamites.erase(d)
		var node: Node3D = d["node"]
		var pos := node.global_position
		node.queue_free()
		# 爆発: まわりの岩や鉱石をまとめて掘る(木と黒曜石はそのまま)
		var boom := _particles_like(Color(1.0, 0.6, 0.2, 0.9), 0.25)
		boom.amount = 60
		boom.lifetime = 0.9
		boom.one_shot = true
		boom.explosiveness = 1.0
		boom.spread = 180.0
		boom.initial_velocity_min = 4.0
		boom.initial_velocity_max = 9.0
		boom.gravity = Vector3(0, -6, 0)
		add_child(boom)
		boom.global_position = pos
		boom.emitting = true
		get_tree().create_timer(1.5).timeout.connect(boom.queue_free)
		var got := {}
		for h in get_tree().get_nodes_in_group("harvestable"):
			var hv := h as Harvestable
			if hv.global_position.distance_to(pos) < 4.5 and hv.tier < 3 and not hv.is_tree:
				var res := hv.hit(hv.tool if hv.tool != "any" else "pickaxe", 999, 2, pos)
				if res.get("done", false):
					for k in hv.drops:
						got[k] = got.get(k, 0) + hv.drops[k]
		var parts := []
		for k in got:
			inventory.add(k, got[k])
			parts.append("%s +%d" % [ItemDB.item_name(k), got[k]])
		show_message("ドカン!" + ("  " + "  ".join(parts) if not parts.is_empty() else "(何もなかった)"), 2.2)
		if player.global_position.distance_to(pos) < 3.5:
			player.launch_velocity = 7.0
