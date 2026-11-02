class_name Station
extends StaticBody3D
## 設置した設備(作業台・製炉・工業用製炉・旋盤)。
## 製炉の仲間は時間をかけて作る。素材は頼んだときに払い、できあがると持ち物に入る。

var station_id := ""
var queue: Array[Dictionary] = []   ## {recipe, left}
var progress := 0.0                 ## いま作っている物の進み具合(秒)
var blocked := false                ## 持ち物がいっぱいで受け取れず止まっている
var storage: Inventory              ## 収納箱の中身(収納箱のときだけ)
var _light: OmniLight3D


func _ready() -> void:
	var n := int(ItemDB.item(station_id).get("storage", 0))
	if n > 0:
		storage = Inventory.new(n)
	if ItemDB.is_timed(station_id):
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.55, 0.2)
		_light.omni_range = 4.0
		_light.position = Vector3(0, 0.6, 0.8)
		add_child(_light)


func is_timed() -> bool:
	return ItemDB.is_timed(station_id)


func current_time() -> float:
	if queue.is_empty():
		return 0.0
	return float(queue[0]["recipe"].get("time", 3.0)) / ItemDB.station_speed(station_id)


func enqueue(recipe: Dictionary, times: int) -> void:
	for q in queue:
		if q["recipe"] == recipe:
			q["left"] += times
			return
	queue.append({"recipe": recipe, "left": times})


## 時間を進める。できあがった物があれば {id, count} を返す
func tick(delta: float, inv: Inventory) -> Dictionary:
	var working := not queue.is_empty() and not blocked
	if _light:
		# 動いていないときは明かりを消す(明かりが多いとスマホで重くなる)
		_light.visible = working
		if working:
			_light.light_energy = 1.6 + sin(Time.get_ticks_msec() * 0.012) * 0.3
	if queue.is_empty():
		return {}
	var job: Dictionary = queue[0]
	var r: Dictionary = job["recipe"]
	var count := int(r["count"])
	if blocked:
		if inv.space_for(r["id"]) >= count:
			blocked = false
		return {}
	progress += delta
	if progress < current_time():
		return {}
	if inv.space_for(r["id"]) < count:
		blocked = true
		return {"blocked": true, "id": r["id"]}
	progress = 0.0
	inv.add(r["id"], count)
	job["left"] -= 1
	if job["left"] <= 0:
		queue.pop_front()
	return {"id": r["id"], "count": count}


## 回収するとき、まだ作っていない分の素材と、収納箱の中身を返す。入りきらなければ false
func refund(inv: Inventory) -> bool:
	if storage:
		for s in storage.slots:
			if not s.is_empty() and inv.space_for(s["id"]) < s["count"]:
				return false
		for s in storage.slots:
			if not s.is_empty():
				inv.add(s["id"], s["count"])
		storage = Inventory.new(storage.slots.size())
	for q in queue:
		for k in q["recipe"]["cost"]:
			inv.add(k, int(q["recipe"]["cost"][k]) * q["left"])
	queue.clear()
	return true
