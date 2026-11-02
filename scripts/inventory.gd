class_name Inventory
extends RefCounted
## 持ち物。先頭の6枠がアイテム欄(ホットバー)、残りがかばん。素材は1枠に100個まで重なる。
## アイテムとレシピの定義は data/items.json(ItemDB)にある。

signal changed

const HOTBAR_SIZE := 6
const BAG_SIZE := 18
const SIZE := HOTBAR_SIZE + BAG_SIZE

## 各枠は {} (空) か {"id": String, "count": int}
var slots: Array[Dictionary] = []


func _init(size := SIZE) -> void:
	for i in size:
		slots.append({})


static func item_name(id: String) -> String:
	return ItemDB.item_name(id)


static func is_tool_item(id: String) -> bool:
	return ItemDB.tool_kind(id) != ""


static func is_placeable(id: String) -> bool:
	return ItemDB.place_kind(id) != ""


## 入れられなかった数を返す(持ち物がいっぱいのとき 0 より大きい)
func add(id: String, count: int) -> int:
	var max_stack := ItemDB.stack(id)
	# まず同じ素材の枠に重ねる(アイテム欄 → かばんの順)
	for s in slots:
		if count <= 0:
			break
		if s.get("id", "") == id and s["count"] < max_stack:
			var n := mini(count, max_stack - s["count"])
			s["count"] += n
			count -= n
	# 残りは空いている枠へ
	for i in slots.size():
		if count <= 0:
			break
		if slots[i].is_empty():
			var n := mini(count, max_stack)
			slots[i] = {"id": id, "count": n}
			count -= n
	changed.emit()
	return count


func total(id: String) -> int:
	var n := 0
	for s in slots:
		if s.get("id", "") == id:
			n += s["count"]
	return n


func id_at(i: int) -> String:
	return slots[i].get("id", "") if i >= 0 and i < slots.size() else ""


## 2つの枠を入れ替える。同じ素材なら重ねられるだけ重ねる
func move(from: int, to: int) -> void:
	if from == to:
		return
	var a := slots[from]
	var b := slots[to]
	if not a.is_empty() and not b.is_empty() and a["id"] == b["id"]:
		var n := mini(a["count"], ItemDB.stack(a["id"]) - b["count"])
		b["count"] += n
		a["count"] -= n
		if a["count"] <= 0:
			slots[from] = {}
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


## 別の持ち物(収納箱など)との間で枠を入れ替える
static func move_between(a: Inventory, i: int, b: Inventory, j: int) -> void:
	if a == b:
		a.move(i, j)
		return
	var x := a.slots[i]
	var y := b.slots[j]
	if not x.is_empty() and not y.is_empty() and x["id"] == y["id"]:
		var n := mini(x["count"], ItemDB.stack(x["id"]) - y["count"])
		y["count"] += n
		x["count"] -= n
		if x["count"] <= 0:
			a.slots[i] = {}
	else:
		a.slots[i] = y
		b.slots[j] = x
	a.changed.emit()
	b.changed.emit()


## 装備の効果(持っているだけで効く)
func has_gear(effect: String) -> bool:
	for s in slots:
		if not s.is_empty() and ItemDB.item(s["id"]).get("gear", "") == effect:
			return true
	return false


## 入りきる数(重ねられる分 + 空き枠)
func space_for(id: String) -> int:
	var max_stack := ItemDB.stack(id)
	var n := 0
	for s in slots:
		if s.is_empty():
			n += max_stack
		elif s["id"] == id:
			n += max_stack - s["count"]
	return n


## 取り除けなかった数を返す。かばん(後ろの枠)から先に使う
func remove(id: String, count: int) -> int:
	for i in range(slots.size() - 1, -1, -1):
		if count <= 0:
			break
		var s := slots[i]
		if s.get("id", "") == id:
			var n := mini(count, s["count"])
			s["count"] -= n
			count -= n
			if s["count"] <= 0:
				slots[i] = {}
	changed.emit()
	return count


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if total(k) < int(cost[k]):
			return false
	return true


func missing_text(cost: Dictionary) -> String:
	var need := []
	for k in cost:
		var short := int(cost[k]) - total(k)
		if short > 0:
			need.append("%s があと %d" % [item_name(k), short])
	return "素材が足りない(%s)" % "、".join(need)


## 素材を払う。払えなければ false
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		remove(k, int(cost[k]))
	return true


## その場で作る(手元・作業台・旋盤)。作れたら ""、作れなければ理由を返す
func craft(recipe: Dictionary) -> String:
	var cost: Dictionary = recipe["cost"]
	if not can_afford(cost):
		return missing_text(cost)
	pay(cost)
	var count := int(recipe["count"])
	if space_for(recipe["id"]) < count:
		for k in cost:
			add(k, int(cost[k]))
		return "持ち物がいっぱいで受け取れない"
	add(recipe["id"], count)
	# バケツを使うレシピは、空のバケツが戻ってくる
	for k in recipe.get("returns", {}):
		add(k, int(recipe["returns"][k]))
	return ""
