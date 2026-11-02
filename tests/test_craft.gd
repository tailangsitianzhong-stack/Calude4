extends SceneTree
## クラフト(作業台・石の斧・石のツルハシ)と、作業台を地面に設置できることを確かめる。
## godot --headless --script res://tests/test_craft.gd

var failed := 0
var main: Node
var frames := 0


func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed += 1


func _init() -> void:
	var inv := Inventory.new()
	inv.add("axe", 1)
	inv.add("pickaxe", 1)
	check(Inventory.item_name("axe") == "石の斧" and Inventory.item_name("pickaxe") == "石のツルハシ", "最初の道具は石の斧・石のツルハシ")

	var bench: Dictionary = Inventory.RECIPES[0]
	check(bench["id"] == "workbench", "クラフトの1番目は作業台")
	check(inv.craft(bench) != "", "素材がないと作業台は作れない")
	inv.add("wood", 10)
	inv.add("stone", 10)
	inv.add("iron", 5)
	check(inv.craft(bench) != "" and inv.total("wood") == 10, "鉄鉱石が1つ足りないと作れず、素材も減らない")
	inv.add("iron", 1)
	check(inv.craft(bench) == "", "木材・石・鉄鉱石 6 ずつで作業台を作れる")
	check(inv.total("workbench") == 1 and inv.total("wood") == 4 and inv.total("stone") == 4 and inv.total("iron") == 0, "素材が 6 ずつ減る")
	check(inv.craft(Inventory.RECIPES[1]) == "" and inv.total("pickaxe") == 2, "木材3・石3で石のツルハシを作れる")
	check(inv.total("wood") == 1 and inv.total("stone") == 1, "ツルハシの分だけ素材が減る")
	check(inv.craft(Inventory.RECIPES[2]) != "", "素材が足りなければ石の斧は作れない")

	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	var p: Player = main.player
	if frames == 5:
		main.inventory.add("workbench", 1)
		var slot := -1
		for i in Inventory.HOTBAR_SIZE:
			if main.inventory.id_at(i) == "workbench":
				slot = i
		main._select_slot(slot)
		check(main.controls.attack_label == "設置", "作業台を選ぶと攻撃ボタンが「設置」になる")
		p.head.rotation.x = deg_to_rad(-40)  # 足元の少し先の地面を見る
	if frames == 15:
		check(main._preview.visible, "視線の先に作業台の見本が出る")
		main.controls._key_attack = true
	if frames == 18:
		main.controls._key_attack = false
	if frames == 25:
		var placed := root.get_tree().get_nodes_in_group("placed")
		check(placed.size() == 1, "作業台が地面に設置される")
		check(main.inventory.total("workbench") == 0, "設置すると持ち物から作業台が減る")
		if placed.size() == 1:
			var d := Vector2(placed[0].global_position.x - p.global_position.x, placed[0].global_position.z - p.global_position.z).length()
			check(d > 1.0 and d < 5.5, "プレイヤーの前方 1〜5.5m に置かれる (%.1fm)" % d)
		check(main.controls.attack_label == "攻撃", "使い切ると攻撃ボタンに戻る")
		print("結果: %s" % ("すべて成功" if failed == 0 else "%d 件失敗" % failed))
		quit(failed)
	return false
