class_name Harvestable
extends StaticBody3D
## 木・岩・鉱脈など、道具で叩いて資源を取れるもの。

signal destroyed(node: Harvestable)

var kind := ""
var display_name := ""
var tool := ""            ## 必要な道具 "axe" / "pickaxe"
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
	max_hp = def["hp"]
	hp = max_hp
	drops = def["drop"]
	is_tree = def.get("tree", false)
	collision_layer = 4
	collision_mask = 0

	model = scene.instantiate()
	var s: float = rng.randf_range(def.get("min_scale", 0.85), def.get("max_scale", 1.2))
	model.scale = Vector3.ONE * s
	model.rotation.y = rng.randf() * TAU
	add_child(model)

	var col := CollisionShape3D.new()
	if is_tree:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35 * s
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
func hit(tool_id: String, from: Vector3) -> Dictionary:
	if _dying:
		return {"ok": false, "message": ""}
	if tool_id != tool:
		var need := "斧" if tool == "axe" else "ツルハシ"
		return {"ok": false, "message": "%sが必要(%sを選んでね)" % [need, need]}
	hp -= 1
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
