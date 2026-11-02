extends SceneTree
## クラフト・製炉・設置(作業台・土台と壁)・回収・「使う」ボタンを確かめる。
## godot --headless --script res://tests/test_craft.gd

var failed := 0
var main: Node
var frames := 0


func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed += 1


func _recipe(station: String, id: String) -> Dictionary:
	for r in ItemDB.recipes_for(station):
		if r["id"] == id:
			return r
	return {}


func _init() -> void:
	check(ItemDB.recipes_for("workbench").size() == 50, "作業台で作れる物は 50 種類 (%d)" % ItemDB.recipes_for("workbench").size())
	check(ItemDB.item_name("axe") == "石の斧" and ItemDB.item_name("pickaxe") == "石のツルハシ", "最初の道具は石の斧・石のツルハシ")
	check(_recipe("workbench", "furnace")["cost"].keys() == ["stone"], "製炉は石だけで作れる")

	var inv := Inventory.new()
	var bench := _recipe("hand", "workbench")
	check(inv.craft(bench) != "", "素材がないと作業台は作れない")
	inv.add("wood", 10)
	inv.add("stone", 10)
	inv.add("iron", 6)
	check(inv.craft(bench) == "" and inv.total("workbench") == 1, "木材・石・鉄鉱石 6 ずつで作業台を作れる")
	check(inv.total("wood") == 4 and inv.total("stone") == 4 and inv.total("iron") == 0, "素材が 6 ずつ減る")
	inv.add("wood", 2)
	check(inv.craft(_recipe("workbench", "plank")) == "" and inv.total("plank") == 3, "作業台: 木材2 → 板材3")

	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _give_and_hold(id: String, n: int) -> void:
	main.inventory.add(id, n)
	for i in Inventory.HOTBAR_SIZE:
		if main.inventory.id_at(i) == id:
			main._select_slot(i)
			return
	# アイテム欄が埋まっていたら6番目と入れ替える
	for i in Inventory.SIZE:
		if main.inventory.id_at(i) == id:
			main.inventory.move(i, 5)
			main._select_slot(5)
			return


func _press_attack() -> void:
	main.controls._key_attack = true


func _release_attack() -> void:
	main.controls._key_attack = false


func _process(_delta: float) -> bool:
	frames += 1
	var p: Player = main.player
	match frames:
		3:
			main._start_game()
			check(main.controls.active, "タイトルの「はじめる」で操作できるようになる")
		5:
			_give_and_hold("workbench", 1)
			check(main.controls.attack_label == "設置", "作業台を選ぶと攻撃ボタンが「設置」になる")
			p.head.rotation.x = deg_to_rad(-40)
		12:
			_press_attack()
		14:
			_release_attack()
		20:
			var benches := root.get_tree().get_nodes_in_group("placed")
			check(benches.size() == 1 and benches[0] is Station, "作業台を設置できる")
			check(main.inventory.total("workbench") == 0, "設置すると作業台が減る")
			check(not main.controls.use_target.is_empty(), "作業台に近づくと「使う」ボタンが出る")
			main._on_use()
			check(main.controls.panel == "bag" and main.controls.station == "workbench", "「使う」で作業台の画面が開く")
			check(main.controls._tabs().size() >= 6, "作業台の画面にはカテゴリのタブがある (%d)" % main.controls._tabs().size())
			main.controls.close_panel()
			# 道具を持って作業台を狙うと「回収」ボタン
			main._select_slot(0)
		24:
			check(main.controls.show_pickup, "斧で設置物を狙うと「回収」ボタンが出る")
			main._on_pickup()
		28:
			check(root.get_tree().get_nodes_in_group("placed").size() == 0 and main.inventory.total("workbench") == 1, "回収すると作業台が持ち物に戻る")
			# 製炉で鉄を作る(時間がかかる)
			main.inventory.add("iron", 4)
			main.inventory.add("wood", 2)
			_give_and_hold("furnace", 1)
			p.head.rotation.x = deg_to_rad(-40)
		32:
			_press_attack()
		34:
			_release_attack()
		40:
			var furnace: Station = null
			for n in root.get_tree().get_nodes_in_group("placed"):
				if n.get_meta("item") == "furnace":
					furnace = n
			check(furnace != null, "製炉を設置できる")
			if furnace:
				main._on_use()
				main.controls.station_node = furnace
				main._on_craft(_recipe("furnace", "iron_ingot"), 2)
				check(furnace.queue.size() == 1 and main.inventory.total("iron") == 0, "製炉に鉄鉱石を入れると素材が先に減る")
				furnace.progress = 999.0
		42:
			check(main.inventory.total("iron_ingot") == 2, "時間がたつと鉄ができる (%d)" % main.inventory.total("iron_ingot"))
			main.controls.close_panel()
			# 土台を置き、その辺に壁を置く
			_give_and_hold("wood_foundation", 1)
			p.global_position = main.world.surface(0, 0) + Vector3(0, 0.2, 0)
			p.rotation.y = 0.0
			p.head.rotation.x = deg_to_rad(-35)
		46:
			_press_attack()
		48:
			_release_attack()
		54:
			var f := root.get_tree().get_nodes_in_group("placed").filter(func(n: Node) -> bool: return n.get_meta("kind") == "foundation")
			check(f.size() == 1, "土台を設置できる")
			if f.size() == 1:
				var fp: Vector3 = f[0].global_position
				check(is_equal_approx(fposmod(fp.x, 2.0), 1.0) and is_equal_approx(fposmod(fp.z, 2.0), 1.0), "土台は 2m のマス目の中心にそろう (%.2f, %.2f)" % [fp.x, fp.z])
			_give_and_hold("wood_wall", 1)
		60:
			_press_attack()
		62:
			_release_attack()
		68:
			var w := root.get_tree().get_nodes_in_group("placed").filter(func(n: Node) -> bool: return n.get_meta("kind") == "wall")
			check(w.size() == 1, "壁を設置できる")
			if w.size() == 1:
				var wp: Vector3 = w[0].global_position
				var on_edge := is_equal_approx(fposmod(wp.x, 2.0), 0.0) or is_equal_approx(fposmod(wp.z, 2.0), 0.0)
				check(on_edge, "壁はマスの辺にそろう (%.2f, %.2f)" % [wp.x, wp.z])
			print("結果: %s" % ("すべて成功" if failed == 0 else "%d 件失敗" % failed))
			quit(failed)
	return false
