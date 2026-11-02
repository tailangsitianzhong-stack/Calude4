extends SceneTree
## 追加した地域・資源・水中・体温・道具・収納箱などを確かめる。
## godot --headless --script res://tests/test_features.gd

var failed := 0
var main: Node
var frames := 0
var p: Player


func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed += 1


func _init() -> void:
	# 追加のクラフト品が30種類あること
	var new_ids := ["bucket", "diving_mask", "flippers", "warm_coat", "heat_suit", "steel_axe", "steel_pickaxe", "dynamite",
		"gunpowder", "clay_brick", "gold_ingot", "heat_tile", "glue", "cloth", "gold_wire", "advanced_circuit",
		"brick_foundation", "brick_wall", "glass_wall", "sandstone_wall", "ice_wall", "tile_roof", "street_lamp", "fireplace",
		"big_chest", "flower_pot", "rug", "geo_heater", "lava_lamp", "telescope"]
	var craftable := {}
	for r in ItemDB.data()["recipes"]:
		craftable[r["id"]] = true
	var n := 0
	for id in new_ids:
		if craftable.has(id):
			n += 1
	check(n == 30, "追加のクラフト品 30 種類がすべて作れる (%d)" % n)

	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _teleport(x: float, z: float) -> void:
	p.global_position = main.world.surface(x, z) + Vector3(0, 0.3, 0)
	p.velocity = Vector3.ZERO


func _process(delta: float) -> bool:
	frames += 1
	match frames:
		2:
			p = main.player
			main._start_game()
			var w: World = main.world
			check(w.biome_at(-160, 0) == "forest" and w.biome_at(160, 0) == "desert" and w.biome_at(0, -160) == "snow" and w.biome_at(0, 160) == "lava",
				"西=森林・東=砂漠・北=雪山・南=溶岩地帯")
			check(w.lava_pools.size() >= 5 and w.hot_springs.size() >= 3 and w.geysers.size() >= 3,
				"溶岩の池 %d・温泉 %d・間欠泉 %d がある" % [w.lava_pools.size(), w.hot_springs.size(), w.geysers.size()])
			var kinds := {}
			var names := {}
			for h in root.get_tree().get_nodes_in_group("harvestable"):
				kinds[h.kind] = kinds.get(h.kind, 0) + 1
				if h.kind == "rock":
					names[h.display_name.trim_suffix("岩")] = true
			for k in ["big_tree", "cactus", "sand", "gold", "coal", "ice", "sulfur", "obsidian", "clam", "clay", "snow_pine", "basalt"]:
				if not kinds.has(k):
					print("  (見つからない: %s)" % k)
			check(kinds.size() >= 19, "資源の種類 %d" % kinds.size())
			check(names.size() >= 3, "岩の大きさがまちまち: %s" % ", ".join(names.keys()))
			# 洞窟の中に鉱石がある
			var c: Vector3 = World.CAVES[0]
			var inside := 0
			for h in root.get_tree().get_nodes_in_group("harvestable"):
				if Vector2(h.global_position.x, h.global_position.z).distance_to(Vector2(c.x, c.y)) < c.z:
					inside += 1
			check(inside >= 6, "洞窟の中に資源が %d 個" % inside)
			# 雪山で体温が下がる
			_teleport(0, -170)
		10:
			main.body_temp = 50.0
			for i in 10:
				main._update_body(0.5)
			check(main.body_temp < 45.0, "防寒コートなしだと雪山で体温が下がる (5秒で %.0f)" % main.body_temp)
			main.inventory.add("warm_coat", 1)
			main.body_temp = 50.0
			for i in 10:
				main._update_body(0.5)
			check(main.body_temp > 47.0, "防寒コートがあると下がりにくい (5秒で %.0f)" % main.body_temp)
			# 湖に潜る
			var lc := World.LAKE_CENTER + Vector2(3, 3)
			p.global_position = Vector3(lc.x, World.WATER_LEVEL - 2.5, lc.y)
			p.velocity = Vector3.ZERO
			main.oxygen = 20.0
		300:
			check(p.head_under, "湖に潜ると頭まで水の中")
			check(main.oxygen < 20.0, "潜っていると息が減る (%.1f)" % main.oxygen)
			check(main._underwater_fx.visible, "水中は青く見える")
			main.oxygen = 0.1
		320:
			check(p.force_up, "息がなくなると水面へ浮かぶ")
			# バケツで水を汲む
			main.inventory.add("bucket", 1)
			for i in Inventory.SIZE:
				if main.inventory.id_at(i) == "bucket":
					main.inventory.move(i, 5)
			main._select_slot(5)
			check(main.controls.attack_label == "汲む", "バケツを持つと攻撃ボタンが「汲む」になる")
			main._was_attack = false
			p.attack_held = true
			main._update_hand_action("bucket")
			p.attack_held = false
			check(main.inventory.total("water_bucket") == 1, "水の中でバケツを使うと水入りバケツになる")
			# 溶岩に触れると安全な場所へ戻る
			var l: Vector4 = main.world.lava_pools[1]
			main._safe_pos = main.world.surface(0, 0)
			p.global_position = Vector3(l.x, l.w - 0.5, l.y)
		325:
			check(p.global_position.distance_to(main.world.surface(0, 0)) < 3.0, "溶岩に触れると安全な場所へ戻る")
			# 収納箱
			var plan: Dictionary = {"xform": Transform3D(Basis(), main.world.surface(4, 4)), "key": ""}
			var chest: Station = main.build.place("chest", plan)
			check(chest.storage != null and chest.storage.slots.size() == 12, "収納箱は12枠")
			main.inventory.add("stone", 30)
			var si := -1
			for i in Inventory.SIZE:
				if main.inventory.id_at(i) == "stone":
					si = i
			Inventory.move_between(main.inventory, si, chest.storage, 0)
			check(chest.storage.total("stone") == 30 and main.inventory.total("stone") == 0, "持ち物から収納箱へ移せる")
			# ベッドで眠ると朝になる
			main.world.time_of_day = 0.9
			var bed: Node = main.build.place("bed", {"xform": Transform3D(Basis(), main.world.surface(-4, 4)), "key": ""})
			main._use_node = bed
			main._on_use()
			check(absf(main.world.time_of_day - 0.26) < 0.01, "夜にベッドで眠ると朝になる")
			# ダイナマイトでまとめて掘る
			var rocks: Array = root.get_tree().get_nodes_in_group("harvestable").filter(func(h): return h.kind == "rock")
			var target: Node3D = rocks[0]
			var before: int = main.inventory.total("stone")
			var dyn: Node3D = load("res://assets/models/dynamite.glb").instantiate()
			main.add_child(dyn)
			dyn.global_position = target.global_position
			main._dynamites.append({"node": dyn, "time": 0.01})
		330:
			check(main.inventory.total("stone") > 0, "ダイナマイトで岩をまとめて掘れる (石 %d)" % main.inventory.total("stone"))
			print("結果: %s" % ("すべて成功" if failed == 0 else "%d 件失敗" % failed))
			quit(failed)
	return false
