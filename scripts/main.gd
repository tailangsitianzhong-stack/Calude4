extends Node3D
## ゲーム全体のまとめ役。最初の惑星(地表)を作り、資源・アイテム欄・画面表示を動かす。

const ITEM_NAMES := {"wood": "木材", "stone": "石", "iron": "鉄鉱石", "copper": "銅鉱石", "crystal": "結晶"}
const ITEM_ORDER := ["wood", "stone", "iron", "copper", "crystal"]

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
var inv_label: Label
var msg_label: Label
var _msg_time := 0.0
var _scenes := {}
var _respawn_queue: Array[Dictionary] = []   # {kind, time}
var _particles: CPUParticles3D

var inventory := {}
var hotbar := [
	{"id": "axe", "label": "斧"},
	{"id": "pickaxe", "label": "ツルハシ"},
]


func _ready() -> void:
	rng.seed = 20261102
	for k in ITEM_ORDER:
		inventory[k] = 0

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
	controls.slots = hotbar
	controls.slot_selected.connect(_select_slot)
	controls.view_toggled.connect(func() -> void:
		player.set_first_person(not player.first_person)
		show_message("一人称視点" if player.first_person else "三人称視点", 1.2)
	)
	layer.add_child(controls)

	inv_label = Label.new()
	inv_label.position = Vector2(18, 12)
	inv_label.add_theme_font_size_override("font_size", 20)
	inv_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	inv_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(inv_label)

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
	var id: String = hotbar[i]["id"] if i < hotbar.size() else ""
	player.set_tool(id)


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
			inventory[item] += h.drops[item]
			got.append("%s +%d" % [ITEM_NAMES[item], h.drops[item]])
		show_message("  ".join(got), 1.6)


func _on_destroyed(h: Harvestable) -> void:
	# しばらくすると別の場所にまた生える
	_respawn_queue.append({"kind": h.kind, "time": rng.randf_range(40.0, 80.0)})


# ---------------------------------------------------------------- 毎フレーム

func _process(delta: float) -> void:
	for r in _respawn_queue:
		r["time"] -= delta
	for r in _respawn_queue.filter(func(x: Dictionary) -> bool: return x["time"] <= 0.0):
		_spawn(r["kind"])
		_respawn_queue.erase(r)

	var parts := []
	for k in ITEM_ORDER:
		if inventory[k] > 0 or k in ["wood", "stone"]:
			parts.append("%s %d" % [ITEM_NAMES[k], inventory[k]])
	inv_label.text = "  ".join(parts)

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
