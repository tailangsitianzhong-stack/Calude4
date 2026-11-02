class_name Inventory
extends RefCounted
## 持ち物。先頭の6枠がアイテム欄(ホットバー)、残りがかばん。素材は1枠に100個まで重なる。

signal changed

const HOTBAR_SIZE := 6
const BAG_SIZE := 18
const SIZE := HOTBAR_SIZE + BAG_SIZE

## アイテムの定義。stack は1枠に入る最大数、tool は手に持って使う道具、place は地面に設置できる物
const ITEMS := {
	"axe": {"name": "石の斧", "stack": 1, "tool": true},
	"pickaxe": {"name": "石のツルハシ", "stack": 1, "tool": true},
	"workbench": {"name": "作業台", "stack": 10, "place": true},
	"wood": {"name": "木材", "stack": 100},
	"stone": {"name": "石", "stack": 100},
	"iron": {"name": "鉄鉱石", "stack": 100},
	"copper": {"name": "銅鉱石", "stack": 100},
	"crystal": {"name": "結晶", "stack": 100},
}

## クラフトの作り方(持ち物画面の左に並ぶ順)
const RECIPES := [
	{"id": "workbench", "count": 1, "cost": {"wood": 6, "stone": 6, "iron": 6}},
	{"id": "pickaxe", "count": 1, "cost": {"wood": 3, "stone": 3}},
	{"id": "axe", "count": 1, "cost": {"wood": 3, "stone": 3}},
]

## 各枠は {} (空) か {"id": String, "count": int}
var slots: Array[Dictionary] = []


func _init() -> void:
	for i in SIZE:
		slots.append({})


static func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else ""


static func is_tool_item(id: String) -> bool:
	return ITEMS.has(id) and ITEMS[id].get("tool", false)


static func is_placeable(id: String) -> bool:
	return ITEMS.has(id) and ITEMS[id].get("place", false)


## 入れられなかった数を返す(持ち物がいっぱいのとき 0 より大きい)
func add(id: String, count: int) -> int:
	var max_stack: int = ITEMS[id]["stack"]
	# まず同じ素材の枠に重ねる(アイテム欄 → かばんの順)
	for s in slots:
		if count <= 0:
			break
		if s.get("id", "") == id and s["count"] < max_stack:
			var n := mini(count, max_stack - s["count"])
			s["count"] += n
			count -= n
	# 残りは空いている枠へ
	for i in SIZE:
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
	return slots[i].get("id", "") if i >= 0 and i < SIZE else ""


## 2つの枠を入れ替える。同じ素材なら重ねられるだけ重ねる
func move(from: int, to: int) -> void:
	if from == to:
		return
	var a := slots[from]
	var b := slots[to]
	if not a.is_empty() and not b.is_empty() and a["id"] == b["id"]:
		var max_stack: int = ITEMS[a["id"]]["stack"]
		var n := mini(a["count"], max_stack - b["count"])
		b["count"] += n
		a["count"] -= n
		if a["count"] <= 0:
			slots[from] = {}
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


## 入りきる数(重ねられる分 + 空き枠)
func space_for(id: String) -> int:
	var max_stack: int = ITEMS[id]["stack"]
	var n := 0
	for s in slots:
		if s.is_empty():
			n += max_stack
		elif s["id"] == id:
			n += max_stack - s["count"]
	return n


## 取り除けなかった数を返す。アイテム欄より後ろ(かばん)から先に使う
func remove(id: String, count: int) -> int:
	for i in range(SIZE - 1, -1, -1):
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
		if total(k) < cost[k]:
			return false
	return true


## 作れたら ""、作れなければ理由を返す
func craft(recipe: Dictionary) -> String:
	var cost: Dictionary = recipe["cost"]
	if not can_afford(cost):
		var need := []
		for k in cost:
			if total(k) < cost[k]:
				need.append("%s があと %d" % [item_name(k), cost[k] - total(k)])
		return "素材が足りない(%s)" % "、".join(need)
	for k in cost:
		remove(k, cost[k])
	if space_for(recipe["id"]) < recipe["count"]:
		for k in cost:
			add(k, cost[k])
		return "持ち物がいっぱいで受け取れない"
	add(recipe["id"], recipe["count"])
	return ""
