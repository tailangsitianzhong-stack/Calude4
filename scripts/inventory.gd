class_name Inventory
extends RefCounted
## 持ち物。先頭の6枠がアイテム欄(ホットバー)、残りがかばん。素材は1枠に100個まで重なる。

signal changed

const HOTBAR_SIZE := 6
const BAG_SIZE := 18
const SIZE := HOTBAR_SIZE + BAG_SIZE

## アイテムの定義。stack は1枠に入る最大数、tool は手に持って使う道具
const ITEMS := {
	"axe": {"name": "斧", "stack": 1, "tool": true},
	"pickaxe": {"name": "ツルハシ", "stack": 1, "tool": true},
	"wood": {"name": "木材", "stack": 100},
	"stone": {"name": "石", "stack": 100},
	"iron": {"name": "鉄鉱石", "stack": 100},
	"copper": {"name": "銅鉱石", "stack": 100},
	"crystal": {"name": "結晶", "stack": 100},
}

## 各枠は {} (空) か {"id": String, "count": int}
var slots: Array[Dictionary] = []


func _init() -> void:
	for i in SIZE:
		slots.append({})


static func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else ""


static func is_tool_item(id: String) -> bool:
	return ITEMS.has(id) and ITEMS[id].get("tool", false)


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
