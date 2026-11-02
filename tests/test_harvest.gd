extends SceneTree
## 木を斧で切ると木材が増え、斧で岩を叩いても掘れないことを確かめる。
## godot --headless --script res://tests/test_harvest.gd

var main: Node
var frames := 0
var stage := 0
var target: Harvestable


func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _face(kind_is_tree: bool) -> Harvestable:
	var p: Player = main.player
	var best: Harvestable = null
	for n in main.get_children():
		if n is Harvestable and n.is_tree == kind_is_tree:
			if best == null or n.global_position.length() < best.global_position.length():
				best = n
	# 2m 手前に立って、幹の高さを狙う
	var flat := Vector3(best.global_position.x, 0, best.global_position.z)
	var dir := (flat - Vector3(0, 0, 0)).normalized()
	var stand := best.global_position - dir * 1.9
	p.global_position = main.world.surface(stand.x, stand.z) + Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	p.look_at(Vector3(best.global_position.x, p.global_position.y, best.global_position.z), Vector3.UP)
	var eye := p.global_position.y + Player.EYE_HEIGHT
	var aim_y := best.global_position.y + (1.0 if kind_is_tree else 0.3)
	p.head.rotation.x = atan2(aim_y - eye, 1.9)
	return best


func _process(_delta: float) -> bool:
	frames += 1
	var p: Player = main.player
	match stage:
		0:
			if frames > 5:
				target = _face(true)
				main._select_slot(0)  # 斧
				main.controls._key_attack = true
				stage = 1
				frames = 0
		1:
			if main.inventory.total("wood") > 0:
				print("PASS: 木を切って木材 %d" % main.inventory.total("wood"))
				main.controls._key_attack = false
				target = _face(false)
				stage = 2
				frames = 0
			elif frames > 600:
				var t = p.get_target()
				print("FAIL: 木材が増えない (target %s hp=%d / ray %s hp=%s same=%s msg=%s)" % [target.kind, target.hp, t.kind if t else "none", t.hp if t else "-", t == target, main.msg_label.text])
				return true
		2:
			if frames == 5:
				main._select_slot(0)  # 斧のまま岩を叩く
				main.controls._key_attack = true
			if frames == 120:
				print(("PASS" if main.inventory.total("stone") == 0 else "FAIL") + ": 斧では岩が掘れない (石 %d)" % main.inventory.total("stone"))
				main._select_slot(1)  # ツルハシ
			if main.inventory.total("stone") > 0:
				print("PASS: ツルハシで岩を掘って石 %d" % main.inventory.total("stone"))
				return true
			if frames > 800:
				print("FAIL: ツルハシで石が増えない")
				return true
	return false
