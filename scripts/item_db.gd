class_name ItemDB
extends RefCounted
## アイテム・レシピ・設備の定義。data/items.json から読み込む(難易度の調整は JSON と tools/balance_sim.py で行う)。

const PATH := "res://data/items.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data


static func item(id: String) -> Dictionary:
	return data()["items"].get(id, {})


static func has(id: String) -> bool:
	return data()["items"].has(id)


static func item_name(id: String) -> String:
	return item(id).get("name", "")


static func stack(id: String) -> int:
	return int(item(id).get("stack", 100))


static func color(id: String) -> Color:
	return Color.html(item(id).get("color", "#ffffff"))


static func icon(id: String) -> String:
	return item(id).get("icon", "")


static func tool_kind(id: String) -> String:
	return item(id).get("tool", "")


static func tool_power(id: String) -> int:
	return int(item(id).get("power", 1))


static func tool_tier(id: String) -> int:
	return int(item(id).get("tier", 1))


static func place_kind(id: String) -> String:
	return item(id).get("place", "")


static func station_name(station: String) -> String:
	return data()["stations"].get(station, {}).get("name", station)


static func station_speed(station: String) -> float:
	return float(data()["stations"].get(station, {}).get("speed", 1.0))


## その設備で作れるレシピ(JSON の並び順)
static func recipes_for(station: String) -> Array:
	return data()["recipes"].filter(func(r: Dictionary) -> bool: return r["station"] == station)


## 製炉のように時間をかけて作る設備か
static func is_timed(station: String) -> bool:
	return data()["stations"].get(station, {}).has("speed")


static func categories(station: String) -> Array:
	var cats := []
	for r in recipes_for(station):
		var c: String = r.get("cat", "")
		if c != "" and not cats.has(c):
			cats.append(c)
	return cats
