class_name Harvestable
extends StaticBody3D
## 木・岩・鉱脈など、道具で叩いて資源を取れるもの。

signal destroyed(node: Harvestable)

var kind := ""
var display_name := ""
var tool := ""            ## 必要な道具 "axe" / "pickaxe"
var tier := 1             ## 必要な道具の段階(2 = 鉄の道具)
var max_hp := 1
var hp := 1
var drops := {}
var is_tree := false
var model: Node3D
var _shake := 0.0
var _dying := false


func setup(kind_id: String, def: Dictionary, scene: PackedScene, rng: RandomNumberGenerator) -> void:
	kind = kind_id
	display_name = def["name"]
	tool = def["tool"]
	tier = def.get("tier", 1)
	add_to_group("harvestable")
	is_tree = def.get("tree", false)
	collision_layer = 4
	collision_mask = 0

	# 岩や鉱石は大きさがまちまち。大きいほど硬く、たくさん取れる
	var size_mul := 1.0
	var hp_mul := 1.0
	var drop_mul := 1.0
	if def.get("sizes", false):
		var roll := rng.randf()
		if roll < 0.3:
			size_mul = 0.6; hp_mul = 0.6; drop_mul = 0.5
			display_name = "小さな" + display_name
		elif roll < 0.75:
			pass
		elif roll < 0.95:
			size_mul = 1.5; hp_mul = 1.8; drop_mul = 2.0
			display_name = "大きな" + display_name
		else:
			size_mul = 2.2; hp_mul = 3.0; drop_mul = 3.5
			display_name = "巨大な" + display_name
	max_hp = maxi(1, roundi(def["hp"] * hp_mul))
	hp = max_hp
	drops = {}
	for k in def["drop"]:
		drops[k] = maxi(1, ceili(def["drop"][k] * drop_mul))

	model = scene.instantiate()
	var s: float = rng.randf_range(def.get("min_scale", 0.85), def.get("max_scale", 1.2)) * size_mul
	model.scale = Vector3.ONE * s
	model.rotation.y = rng.randf() * TAU
	add_child(model)
	# 遠くの物は描かない(スマホで重くならないように)
	var view: float = def.get("view", 170.0 if is_tree else 110.0) * maxf(size_mul, 1.0)
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).visibility_range_end = view
		(g as GeometryInstance3D).visibility_range_end_margin = 10.0

	var col := CollisionShape3D.new()
	if is_tree:
		var cyl := CylinderShape3D.new()
		cyl.radius = def.get("radius", 0.35) * s
		cyl.height = 4.0 * s
		col.shape = cyl
		col.position.y = 2.0 * s
	else:
		var sph := SphereShape3D.new()
		sph.radius = def.get("radius", 0.7) * s
		col.shape = sph
		col.position.y = 0.3 * s
	add_child(col)


## 叩かれたとき。結果を辞書で返す {ok, message, done}
func hit(tool_kind: String, power: int, tool_tier: int, from: Vector3) -> Dictionary:
	if _dying:
		return {"ok": false, "message": ""}
	if tool != "any" and tool_kind != tool:
		var need := "斧" if tool == "axe" else "ツルハシ"
		return {"ok": false, "message": "%sが必要(%sを選んでね)" % [need, need]}
	if tool_tier < tier:
		var need := "鉄" if tier == 2 else "鋼鉄"
		return {"ok": false, "message": "%sの%sでないと掘れない" % [need, "斧" if tool == "axe" else "ツルハシ"]}
	hp -= power
	_shake = 0.25
	if hp <= 0:
		_die(from)
		return {"ok": true, "done": true}
	return {"ok": true, "done": false}


func _die(from: Vector3) -> void:
	_dying = true
	collision_layer = 0
	var tw := create_tween()
	if is_tree:
		# プレイヤーと反対側へ倒れる
		var away := global_position - from
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		var axis := Vector3.UP.cross(away).normalized()
		var start := model.transform
		tw.tween_method(func(t: float) -> void:
			model.transform = Transform3D(Basis(axis, t * t * 1.5) * start.basis, start.origin)
		, 0.0, 1.0, 1.1)
		tw.tween_property(model, "scale", Vector3.ZERO, 0.4)
	else:
		tw.tween_property(model, "scale", model.scale * 1.15, 0.08)
		tw.tween_property(model, "scale", Vector3.ZERO, 0.25)
	tw.tween_callback(func() -> void:
		destroyed.emit(self)
		queue_free()
	)


func _process(delta: float) -> void:
	if _shake > 0.0 and not _dying:
		_shake -= delta
		var k := maxf(_shake, 0.0) * 0.12
		model.position = Vector3(randf_range(-k, k), 0.0, randf_range(-k, k))
		if _shake <= 0.0:
			model.position = Vector3.ZERO
