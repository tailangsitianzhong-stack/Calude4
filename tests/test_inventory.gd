extends SceneTree
## 持ち物の重なり方(100個で1枠)と入れ替えを確かめる。
## godot --headless --script res://tests/test_inventory.gd

var failed := 0


func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed += 1


func _init() -> void:
	var inv := Inventory.new()
	inv.add("axe", 1)
	inv.add("pickaxe", 1)
	check(inv.id_at(0) == "axe" and inv.id_at(1) == "pickaxe", "斧とツルハシがアイテム欄の1・2番目")

	inv.add("wood", 3)
	check(inv.id_at(2) == "wood" and inv.slots[2]["count"] == 3, "木材が空いている3番目の枠に入る")

	inv.add("wood", 120)
	check(inv.slots[2]["count"] == 100 and inv.slots[3]["count"] == 23, "100個を超えた分は次の枠へ (100 + 23)")
	check(inv.total("wood") == 123, "木材の合計 123")

	inv.add("stone", 5)
	check(inv.id_at(4) == "stone", "石は別の枠に入る")

	inv.move(3, 2)
	check(inv.slots[2]["count"] == 100 and inv.slots[3]["count"] == 23, "満杯の枠へは重ねられず、そのまま")

	inv.move(4, 10)
	check(inv.id_at(4) == "" and inv.id_at(10) == "stone", "石をかばんへ移動")

	inv.move(0, 10)
	check(inv.id_at(0) == "stone" and inv.id_at(10) == "axe", "斧と石を入れ替え")

	var full := Inventory.new()
	var left := full.add("stone", 100 * Inventory.SIZE + 7)
	check(left == 7, "持ち物がいっぱいなら入りきらない数を返す (7)")

	print("結果: %s" % ("すべて成功" if failed == 0 else "%d 件失敗" % failed))
	quit(failed)
