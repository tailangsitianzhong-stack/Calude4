class_name TouchControls
extends Control
## スマホ用の操作と画面表示(ボタンはすべて自前で描いている)。
## 左側: スティックで移動 / 右側: ドラッグで視点 / 右下: 攻撃・ジャンプ / 下中央: アイテム欄
## 左上: 設定 / 右上: 持ち物・視点切替 / 攻撃ボタンの左上: 回収(道具で設置物を狙ったとき)
## 設置物の近く: 設置物の上に「使う」ボタン
## PC: WASD 移動、マウスドラッグ 視点、F 攻撃、Space ジャンプ、1〜6 アイテム、V 視点、E 持ち物、R 回収、G 使う、Esc 閉じる

signal slot_selected(index: int)
signal view_toggled
signal craft_requested(recipe: Dictionary, times: int)
signal pickup_pressed
signal use_pressed
signal title_requested
signal sensitivity_changed(value: float)

const JOY_RADIUS := 90.0
const BASE_LOOK := 0.005
const SLOT_SIZE := 72.0
const SLOT_GAP := 8.0
const CRAFT_W := 470.0
const PANEL_GAP := 20.0
const ROW_H := 84.0
const TAB_H := 40.0

const C_PANEL := Color(0.11, 0.13, 0.16, 0.96)
const C_LINE := Color(1, 1, 1, 0.35)
const C_OK := Color(0.3, 0.7, 0.4)
const C_NG := Color(0.35, 0.35, 0.38)
const C_GOOD_TEXT := Color(0.75, 0.95, 0.7)
const C_BAD_TEXT := Color(1.0, 0.55, 0.5)

var player: Player
var inventory: Inventory
var active := true              ## タイトル画面のあいだは false
var selected_slot := 0
var target_name := ""
var target_ratio := -1.0
var attack_label := "攻撃"
var show_pickup := false
var pickup_label := ""
var use_target := {}            ## {label, pos} 近くの設備の「使う」ボタン
var sensitivity := 1.0

var panel := ""                 ## "" / "bag" / "settings"
var station := "hand"           ## 持ち物画面の左に出すレシピの設備
var station_node: Station       ## 製炉など、時間をかける設備のとき
var _tab := 0
var _scroll := 0.0

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _attack_index := -1
var _pressed := {}              ## タッチ番号 -> ボタンID
var _key_attack := false
var _held_slot := -1
var _list_drag := {}            ## レシピ一覧のドラッグ {index, start, scroll, moved}
var _slider_index := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ================================================================ 配置

func _buttons() -> Array:
	var s := size
	var list := [
		{"id": "settings", "pos": Vector2(56, 56), "r": 36.0},
		{"id": "view", "pos": Vector2(s.x - 62, 62), "r": 42.0},
		{"id": "bag", "pos": Vector2(s.x - 170, 62), "r": 42.0},
		{"id": "attack", "pos": Vector2(s.x - 150, s.y - 175), "r": 100.0},
		{"id": "jump", "pos": Vector2(s.x - 345, s.y - 100), "r": 72.0},
	]
	if show_pickup:
		list.append({"id": "pickup", "pos": Vector2(s.x - 300, s.y - 320), "r": 50.0})
	return list


func _use_rect() -> Rect2:
	if use_target.is_empty():
		return Rect2()
	var p: Vector2 = use_target["pos"]
	return Rect2(p - Vector2(95, 30), Vector2(190, 56))


func _hotbar_rect(i: int) -> Rect2:
	var total := Inventory.HOTBAR_SIZE * SLOT_SIZE + (Inventory.HOTBAR_SIZE - 1) * SLOT_GAP
	var x0 := (size.x - total) / 2.0
	return Rect2(Vector2(x0 + i * (SLOT_SIZE + SLOT_GAP), size.y - SLOT_SIZE - 14.0), Vector2(SLOT_SIZE, SLOT_SIZE))


func _bag_panel() -> Rect2:
	var w := 6 * SLOT_SIZE + 5 * SLOT_GAP + 48.0
	var h := minf(4 * SLOT_SIZE + 3 * SLOT_GAP + 140.0, size.y - 40.0)
	var x0 := (size.x - (CRAFT_W + PANEL_GAP + w)) / 2.0
	return Rect2(Vector2(x0 + CRAFT_W + PANEL_GAP, (size.y - h) / 2.0), Vector2(w, h))


func _craft_panel() -> Rect2:
	var p := _bag_panel()
	return Rect2(Vector2(p.position.x - PANEL_GAP - CRAFT_W, p.position.y), Vector2(CRAFT_W, p.size.y))


func _bag_rect(i: int) -> Rect2:
	var p := _bag_panel()
	var col := i % 6
	var row: int
	var extra := 0.0
	if i < Inventory.HOTBAR_SIZE:
		row = 3
		extra = 16.0
	else:
		row = (i - Inventory.HOTBAR_SIZE) / 6
	return Rect2(p.position + Vector2(24.0 + col * (SLOT_SIZE + SLOT_GAP), 56.0 + row * (SLOT_SIZE + SLOT_GAP) + extra),
		Vector2(SLOT_SIZE, SLOT_SIZE))


func _close_rect() -> Rect2:
	var p := _bag_panel()
	return Rect2(p.end.x - 54, p.position.y + 10, 44, 36)


func _tabs() -> Array:
	return ItemDB.categories(station)


func _tab_rect(i: int) -> Rect2:
	var c := _craft_panel()
	var n := _tabs().size()
	var w := (c.size.x - 32.0) / maxf(n, 1)
	return Rect2(c.position + Vector2(16 + i * w, 50), Vector2(w - 4, TAB_H - 6))


func _list_area() -> Rect2:
	var c := _craft_panel()
	var top := 52.0 + (TAB_H if not _tabs().is_empty() else 0.0)
	if station_node and station_node.is_timed():
		top += 58.0
	return Rect2(c.position + Vector2(12, top), Vector2(c.size.x - 24, c.size.y - top - 12))


func _recipes() -> Array:
	var all := ItemDB.recipes_for(station)
	var tabs := _tabs()
	if tabs.is_empty():
		return all
	var cat: String = tabs[clampi(_tab, 0, tabs.size() - 1)]
	return all.filter(func(r: Dictionary) -> bool: return r.get("cat", "") == cat)


func _row_rect(i: int) -> Rect2:
	var a := _list_area()
	return Rect2(a.position + Vector2(4, i * (ROW_H + 6) - _scroll), Vector2(a.size.x - 8, ROW_H))


## レシピの行のボタン。時間をかける設備は ×1 と ×5
func _row_buttons(i: int) -> Array:
	var r := _row_rect(i)
	var y := r.position.y + (r.size.y - 46) / 2.0
	if station_node and station_node.is_timed():
		return [{"times": 1, "rect": Rect2(r.end.x - 136, y, 62, 46), "label": "×1"},
			{"times": 5, "rect": Rect2(r.end.x - 68, y, 62, 46), "label": "×5"}]
	return [{"times": 1, "rect": Rect2(r.end.x - 90, y, 82, 46), "label": "作る"}]


func _max_scroll() -> float:
	var n := _recipes().size()
	return maxf(0.0, n * (ROW_H + 6) - _list_area().size.y)


func _settings_rect() -> Rect2:
	var w := 520.0
	var h := 330.0
	return Rect2((size - Vector2(w, h)) / 2.0, Vector2(w, h))


func _slider_rect() -> Rect2:
	var p := _settings_rect()
	return Rect2(p.position + Vector2(40, 130), Vector2(p.size.x - 80, 10))


func _settings_buttons() -> Array:
	var p := _settings_rect()
	return [
		{"id": "title", "label": "タイトルに戻る", "rect": Rect2(p.position + Vector2(40, 210), Vector2(210, 60))},
		{"id": "close_settings", "label": "閉じる", "rect": Rect2(p.position + Vector2(p.size.x - 250, 210), Vector2(210, 60))},
	]


# ================================================================ 入力

func open_bag(station_id: String, node: Station = null) -> void:
	panel = "bag"
	station = station_id
	station_node = node
	_tab = 0
	_scroll = 0.0
	_held_slot = -1
	_release_all()


func close_panel() -> void:
	panel = ""
	station_node = null
	_held_slot = -1
	_release_all()


func _release_all() -> void:
	_joy_index = -1
	_joy_vec = Vector2.ZERO
	_look_index = -1
	_attack_index = -1
	_list_drag = {}
	_slider_index = -1
	queue_redraw()


func _hit_test(p: Vector2) -> String:
	if panel == "settings":
		for b in _settings_buttons():
			if (b["rect"] as Rect2).has_point(p):
				return b["id"]
		if _slider_rect().grow(26).has_point(p):
			return "slider"
		if _settings_rect().has_point(p):
			return "panel"
		return "close_settings"
	if panel == "bag":
		if _close_rect().grow(6).has_point(p):
			return "close"
		for i in Inventory.SIZE:
			if _bag_rect(i).has_point(p):
				return "bag%d" % i
		for i in _tabs().size():
			if _tab_rect(i).has_point(p):
				return "tab%d" % i
		if _list_area().has_point(p):
			return "list"
		if _bag_panel().has_point(p) or _craft_panel().has_point(p):
			return "panel"
		return "close"
	if not use_target.is_empty() and _use_rect().has_point(p):
		return "use"
	for b in _buttons():
		if p.distance_to(b["pos"]) <= b["r"] + 10.0:
			return b["id"]
	for i in Inventory.HOTBAR_SIZE:
		if _hotbar_rect(i).grow(4).has_point(p):
			return "slot%d" % i
	return ""


func _press(id: String, index: int, pos: Vector2) -> void:
	_pressed[index] = id
	match id:
		"attack":
			_attack_index = index
		"jump":
			player.jump_requested = true
		"view":
			view_toggled.emit()
		"bag":
			open_bag("hand")
		"close":
			close_panel()
		"settings":
			panel = "settings"
			_release_all()
		"close_settings":
			close_panel()
		"title":
			close_panel()
			title_requested.emit()
		"pickup":
			pickup_pressed.emit()
		"use":
			use_pressed.emit()
		"slider":
			_slider_index = index
			_set_slider(pos.x)
		"list":
			_list_drag = {"index": index, "start": pos, "scroll": _scroll, "moved": false}
		"panel":
			pass
		_:
			if id.begins_with("slot"):
				slot_selected.emit(int(id.substr(4)))
			elif id.begins_with("tab"):
				_tab = int(id.substr(3))
				_scroll = 0.0
			elif id.begins_with("bag"):
				_tap_bag_slot(int(id.substr(3)))


func _set_slider(x: float) -> void:
	var r := _slider_rect()
	var t := clampf((x - r.position.x) / r.size.x, 0.0, 1.0)
	sensitivity = snappedf(lerpf(0.3, 2.5, t), 0.1)
	sensitivity_changed.emit(sensitivity)


## レシピ一覧は、指を動かさずに離したときだけボタンが押されたことにする(スクロールと区別するため)
func _release_list(pos: Vector2) -> void:
	if _list_drag.get("moved", true):
		return
	var recipes := _recipes()
	for i in recipes.size():
		for b in _row_buttons(i):
			if (b["rect"] as Rect2).grow(4).has_point(pos) and _list_area().has_point(pos):
				craft_requested.emit(recipes[i], b["times"])
				return


func _tap_bag_slot(i: int) -> void:
	if _held_slot == -1:
		if inventory.id_at(i) != "":
			_held_slot = i
	else:
		inventory.move(_held_slot, i)
		_held_slot = -1
		slot_selected.emit(selected_slot)


func _input(event: InputEvent) -> void:
	if player == null or not active:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var id := _hit_test(t.position)
			if id != "":
				_press(id, t.index, t.position)
			elif t.position.x < size.x * 0.4 and _joy_index == -1:
				_joy_index = t.index
				_joy_origin = t.position
				_joy_vec = Vector2.ZERO
			elif _look_index == -1:
				_look_index = t.index
				_look_last = t.position
		else:
			if t.index == _joy_index:
				_joy_index = -1
				_joy_vec = Vector2.ZERO
			if t.index == _look_index:
				_look_index = -1
			if t.index == _attack_index:
				_attack_index = -1
			if t.index == _slider_index:
				_slider_index = -1
			if _list_drag.get("index", -99) == t.index:
				_release_list(t.position)
				_list_drag = {}
			_pressed.erase(t.index)
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			var off := d.position - _joy_origin
			if off.length() > JOY_RADIUS:
				off = off.normalized() * JOY_RADIUS
			_joy_vec = Vector2(off.x, -off.y) / JOY_RADIUS
		elif d.index == _slider_index:
			_set_slider(d.position.x)
		elif _list_drag.get("index", -99) == d.index:
			var dy: float = d.position.y - _list_drag["start"].y
			if absf(dy) > 10.0:
				_list_drag["moved"] = true
			_scroll = clampf(_list_drag["scroll"] - dy, 0.0, _max_scroll())
		elif d.index == _look_index or d.index == _attack_index:
			if _look_last == Vector2.ZERO:
				_look_last = d.position
			player.look_delta += (d.position - _look_last) * BASE_LOOK * sensitivity
			_look_last = d.position
	elif event is InputEventMouseButton and panel == "bag":
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_scroll = clampf(_scroll + (-60.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0), 0.0, _max_scroll())
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_F:
			_key_attack = k.pressed and panel == ""
		elif k.pressed and not k.echo:
			match k.keycode:
				KEY_SPACE:
					player.jump_requested = true
				KEY_V:
					view_toggled.emit()
				KEY_E, KEY_TAB, KEY_I:
					if panel == "bag":
						close_panel()
					else:
						open_bag("hand")
				KEY_ESCAPE:
					if panel != "":
						close_panel()
					else:
						panel = "settings"
				KEY_R:
					if show_pickup:
						pickup_pressed.emit()
				KEY_G:
					if not use_target.is_empty():
						use_pressed.emit()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
					slot_selected.emit(k.keycode - KEY_1)


func _process(_delta: float) -> void:
	if player == null:
		return
	if _attack_index == -1 and _look_index == -1:
		_look_last = Vector2.ZERO
	player.attack_held = (_attack_index != -1 or _key_attack) and panel == "" and active
	if _joy_index != -1:
		player.move_input = _joy_vec
	elif panel != "" or not active:
		player.move_input = Vector2.ZERO
	else:
		var k := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			k.y += 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			k.y -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			k.x += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			k.x -= 1
		player.move_input = k.normalized()
	queue_redraw()


# ================================================================ 描画

func _draw() -> void:
	if not active:
		return
	var font := get_theme_default_font()
	var center := size / 2.0

	if panel == "":
		_draw_aim(font, center)
		_draw_stick(font)
		if not use_target.is_empty():
			_draw_use_button(font)

	var pressed_ids := _pressed.values()
	for b in _buttons():
		var id: String = b["id"]
		if panel != "" and id != "bag" and id != "settings":
			continue
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var on: bool = pressed_ids.has(id) or (id == "attack" and _key_attack) or (id == "bag" and panel == "bag") or (id == "settings" and panel == "settings")
		var fill := Color(0.1, 0.12, 0.15, 0.62 if on else 0.4)
		if id == "pickup":
			fill = Color(0.75, 0.45, 0.12, 0.85 if on else 0.65)
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0, TAU, 48, Color(1, 1, 1, 0.9 if on else 0.6), 3.0)
		_draw_button_icon(font, id, pos, r)

	if panel == "":
		for i in Inventory.HOTBAR_SIZE:
			_draw_slot(font, _hotbar_rect(i), i, i == selected_slot)
		var held := inventory.id_at(selected_slot)
		if held != "":
			var r0 := _hotbar_rect(0)
			draw_string(font, Vector2(r0.position.x, r0.position.y - 10), ItemDB.item_name(held), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	elif panel == "bag":
		_draw_bag(font)
	elif panel == "settings":
		_draw_settings(font)


func _draw_aim(font: Font, center: Vector2) -> void:
	var aim_col := Color(1, 1, 1, 0.9) if target_ratio >= 0.0 else Color(1, 1, 1, 0.5)
	draw_arc(center, 9, 0, TAU, 24, aim_col, 2.0)
	draw_circle(center, 2.0, aim_col)
	if target_ratio >= 0.0:
		draw_string(font, center + Vector2(-120, 44), target_name, HORIZONTAL_ALIGNMENT_CENTER, 240, 20, Color.WHITE)
		var bar := Rect2(center + Vector2(-50, 54), Vector2(100, 7))
		draw_rect(bar, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(target_ratio, 0.0, 1.0), bar.size.y)), Color(0.45, 0.9, 0.4))


func _draw_stick(font: Font) -> void:
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
		draw_circle(_joy_origin + Vector2(_joy_vec.x, -_joy_vec.y) * JOY_RADIUS, 38, Color(1, 1, 1, 0.5))
	else:
		var hint := Vector2(160, size.y - 180)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
		draw_string(font, hint + Vector2(-60, 8), "移動", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 1, 1, 0.5))


func _draw_use_button(font: Font) -> void:
	var r := _use_rect()
	var on := _pressed.values().has("use")
	# 吹き出しの三角(設置物を指す)
	draw_colored_polygon(PackedVector2Array([r.get_center() + Vector2(-10, 28), r.get_center() + Vector2(10, 28), r.get_center() + Vector2(0, 42)]), Color(0.18, 0.5, 0.85, 0.9))
	draw_rect(r, Color(0.18, 0.5, 0.85, 1.0 if on else 0.88))
	draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 36), use_target["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)


# ---------------------------------------------------------------- ボタンのアイコン

func _draw_button_icon(font: Font, id: String, c: Vector2, r: float) -> void:
	var w := Color.WHITE
	var k := minf(r / 42.0, 1.35)
	if id == "attack":
		c += Vector2(0, -14)  # 下に文字を入れるので少し上へ
	match id:
		"attack":
			if attack_label == "設置":
				# 下向きの矢印と、置かれる箱
				draw_rect(Rect2(c + Vector2(-26, 8) * k, Vector2(52, 30) * k), w, false, 4.0 * k)
				draw_line(c + Vector2(0, -36) * k, c + Vector2(0, -2) * k, w, 6.0 * k)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -10) * k, c + Vector2(14, -10) * k, c + Vector2(0, 6) * k]), w)
			else:
				# ツルハシと斧を交差させた形
				var wood := Color(0.95, 0.85, 0.7)
				draw_line(c + Vector2(-26, 30) * k, c + Vector2(22, -22) * k, wood, 6.0 * k)
				draw_line(c + Vector2(26, 30) * k, c + Vector2(-22, -22) * k, wood, 6.0 * k)
				draw_polyline(PackedVector2Array([c + Vector2(4, -36) * k, c + Vector2(22, -24) * k, c + Vector2(32, -6) * k]), w, 7.0 * k)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-36, -34) * k, c + Vector2(-16, -36) * k, c + Vector2(-14, -16) * k, c + Vector2(-32, -14) * k]), w)
			draw_string(font, Vector2(c.x - r, c.y + 72), attack_label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 24, Color(1, 1, 1, 0.9))
		"jump":
			for i in 2:
				var y := (i * 16 - 12) * k
				draw_polyline(PackedVector2Array([c + Vector2(-20 * k, y + 12 * k), c + Vector2(0, y - 6 * k), c + Vector2(20 * k, y + 12 * k)]), w, 6.0 * k)
		"bag":
			# リュック
			draw_rect(Rect2(c + Vector2(-17, -12) * k, Vector2(34, 32) * k), w)
			draw_arc(c + Vector2(0, -12) * k, 10 * k, PI, TAU, 12, w, 4.0 * k)
			draw_rect(Rect2(c + Vector2(-10, 0) * k, Vector2(20, 12) * k), Color(0.1, 0.12, 0.15))
			draw_line(c + Vector2(-10, 6) * k, c + Vector2(10, 6) * k, w, 2.0 * k)
		"view":
			# 目(一人称)と、人の形(三人称)
			if player.first_person:
				draw_arc(c, 18 * k, PI * 0.15, PI * 0.85, 16, w, 4.0 * k)
				draw_arc(c, 18 * k, PI * 1.15, PI * 1.85, 16, w, 4.0 * k)
				draw_circle(c, 8 * k, w)
			else:
				draw_circle(c + Vector2(0, -12) * k, 8 * k, w)
				draw_rect(Rect2(c + Vector2(-11, -2) * k, Vector2(22, 22) * k), w)
		"settings":
			# 歯車
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 12 * k, c + Vector2(cos(a), sin(a)) * 21 * k, w, 7.0 * k)
			draw_circle(c, 14 * k, w)
			draw_circle(c, 6 * k, Color(0.1, 0.12, 0.15))
		"pickup":
			# 上向きの矢印と手
			draw_line(c + Vector2(0, 14) * k, c + Vector2(0, -22) * k, w, 6.0 * k)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -12) * k, c + Vector2(14, -12) * k, c + Vector2(0, -30) * k]), w)
			draw_rect(Rect2(c + Vector2(-20, 14) * k, Vector2(40, 8) * k), w)
			draw_string(font, Vector2(c.x - r, c.y + r + 18), pickup_label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 16, Color.WHITE)


# ---------------------------------------------------------------- 持ち物とクラフト

func _draw_bag(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	_draw_craft(font)
	var p := _bag_panel()
	draw_rect(p, C_PANEL)
	draw_rect(p, C_LINE, false, 2.0)
	draw_string(font, p.position + Vector2(24, 38), "持ち物", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var cl := _close_rect()
	draw_rect(cl, Color(1, 1, 1, 0.12))
	draw_string(font, Vector2(cl.position.x, cl.position.y + 26), "×", HORIZONTAL_ALIGNMENT_CENTER, cl.size.x, 24, Color.WHITE)
	for i in Inventory.SIZE:
		_draw_slot(font, _bag_rect(i), i, i == selected_slot and i < Inventory.HOTBAR_SIZE)
		if i == _held_slot:
			draw_rect(_bag_rect(i).grow(3), Color(0.4, 0.9, 1.0), false, 3.0)
	var hb := _bag_rect(0)
	draw_string(font, Vector2(hb.position.x, hb.position.y - 6), "アイテム欄", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	var info := "枠をタップ → 移動先の枠をタップで入れ替え"
	if _held_slot != -1:
		var id := inventory.id_at(_held_slot)
		info = "%s × %d を選択中。移動先をタップ" % [ItemDB.item_name(id), inventory.slots[_held_slot]["count"]]
	draw_string(font, Vector2(p.position.x + 24, p.end.y - 18), info, HORIZONTAL_ALIGNMENT_LEFT, p.size.x - 48, 15, Color(1, 1, 1, 0.75))


func _draw_craft(font: Font) -> void:
	var c := _craft_panel()
	draw_rect(c, C_PANEL)
	draw_rect(c, C_LINE, false, 2.0)
	draw_string(font, c.position + Vector2(20, 38), ItemDB.station_name(station), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

	var tabs := _tabs()
	for i in tabs.size():
		var tr := _tab_rect(i)
		draw_rect(tr, Color(0.3, 0.55, 0.85, 0.9) if i == _tab else Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(tr.position.x, tr.position.y + 23), tabs[i], HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 15, Color.WHITE)

	# 製炉の作業状況
	if station_node and station_node.is_timed():
		var a := _list_area()
		var box := Rect2(Vector2(a.position.x, a.position.y - 54), Vector2(a.size.x, 48))
		draw_rect(box, Color(1, 1, 1, 0.06))
		if station_node.queue.is_empty():
			draw_string(font, box.position + Vector2(12, 30), "待機中(素材を入れると作り始める)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))
		else:
			var job: Dictionary = station_node.queue[0]
			var waiting := 0
			for q in station_node.queue:
				waiting += q["left"]
			var label := "作成中: %s(あと %d 回)" % [ItemDB.item_name(job["recipe"]["id"]), waiting]
			if station_node.blocked:
				label = "持ち物がいっぱいで止まっている"
			draw_string(font, box.position + Vector2(12, 22), label, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24, 15, Color.WHITE)
			var bar := Rect2(box.position + Vector2(12, 30), Vector2(box.size.x - 24, 8))
			draw_rect(bar, Color(0, 0, 0, 0.5))
			var t := clampf(station_node.progress / maxf(station_node.current_time(), 0.01), 0.0, 1.0)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), Color(1.0, 0.6, 0.2))

	var area := _list_area()
	var recipes := _recipes()
	for i in recipes.size():
		var row := _row_rect(i)
		if row.end.y < area.position.y or row.position.y > area.end.y:
			continue
		_draw_recipe_row(font, recipes[i], i, row, area)
	# 一覧の上下は少し暗くして、続きがあることを示す
	if _scroll > 1.0:
		draw_rect(Rect2(area.position, Vector2(area.size.x, 10)), Color(0, 0, 0, 0.35))
	if _scroll < _max_scroll() - 1.0:
		draw_rect(Rect2(Vector2(area.position.x, area.end.y - 10), Vector2(area.size.x, 10)), Color(0, 0, 0, 0.35))
		draw_string(font, Vector2(area.position.x, area.end.y + 10), "▼ 上下にドラッグでスクロール", HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 12, Color(1, 1, 1, 0.5))


func _draw_recipe_row(font: Font, rec: Dictionary, i: int, row: Rect2, area: Rect2) -> void:
	# 一覧の外にはみ出す部分は描かない(行の単位で切る)
	if row.position.y < area.position.y - 2 or row.end.y > area.end.y + 2:
		var visible := row.intersection(area)
		draw_rect(visible, Color(1, 1, 1, 0.04))
		return
	var ok := inventory.can_afford(rec["cost"])
	draw_rect(row, Color(1, 1, 1, 0.06))
	var icon := Rect2(row.position + Vector2(6, (row.size.y - 64) / 2.0), Vector2(64, 64))
	draw_rect(icon, Color(0.08, 0.1, 0.12, 0.8))
	_draw_item_icon(icon, rec["id"])
	var n := int(rec["count"])
	var title := ItemDB.item_name(rec["id"]) + ("  ×%d" % n if n > 1 else "")
	var tx := icon.end.x + 10
	draw_string(font, Vector2(tx, row.position.y + 30), title, HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 170, 18, Color.WHITE)
	var x := tx
	var y := row.position.y + 56
	var limit := row.end.x - (150.0 if station_node and station_node.is_timed() else 100.0)
	for k in rec["cost"]:
		var have := inventory.total(k)
		var need := int(rec["cost"][k])
		var txt := "%s %d/%d" % [ItemDB.item_name(k), mini(have, 999), need]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if x + w > limit:
			x = tx
			y += 17
		draw_string(font, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_GOOD_TEXT if have >= need else C_BAD_TEXT)
		x += w + 10
	for b in _row_buttons(i):
		var br: Rect2 = b["rect"]
		draw_rect(br, Color(C_OK, 0.9) if ok else Color(C_NG, 0.6))
		draw_string(font, Vector2(br.position.x, br.position.y + 30), b["label"], HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 18, Color.WHITE if ok else Color(1, 1, 1, 0.45))


func _draw_settings(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
	var p := _settings_rect()
	draw_rect(p, C_PANEL)
	draw_rect(p, C_LINE, false, 2.0)
	draw_string(font, p.position + Vector2(28, 44), "設定", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	draw_string(font, p.position + Vector2(40, 104), "視点の感度", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(font, p.position + Vector2(p.size.x - 140, 104), "%.1f" % sensitivity, HORIZONTAL_ALIGNMENT_RIGHT, 100, 20, Color(1.0, 0.85, 0.4))
	var s := _slider_rect()
	draw_rect(s, Color(1, 1, 1, 0.2))
	var t := (sensitivity - 0.3) / (2.5 - 0.3)
	draw_rect(Rect2(s.position, Vector2(s.size.x * t, s.size.y)), Color(0.3, 0.55, 0.85))
	draw_circle(Vector2(s.position.x + s.size.x * t, s.get_center().y), 16, Color.WHITE)
	draw_string(font, Vector2(s.position.x, s.end.y + 26), "遅い", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	draw_string(font, Vector2(s.end.x - 60, s.end.y + 26), "速い", HORIZONTAL_ALIGNMENT_RIGHT, 60, 13, Color(1, 1, 1, 0.6))
	for b in _settings_buttons():
		var r: Rect2 = b["rect"]
		var on := _pressed.values().has(b["id"])
		draw_rect(r, Color(0.3, 0.55, 0.85, 1.0 if on else 0.85) if b["id"] == "close_settings" else Color(1, 1, 1, 0.22 if on else 0.12))
		draw_rect(r, C_LINE, false, 1.5)
		draw_string(font, Vector2(r.position.x, r.position.y + 38), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)


func _draw_slot(font: Font, rect: Rect2, i: int, selected: bool) -> void:
	draw_rect(rect, Color(0.08, 0.1, 0.12, 0.65))
	draw_rect(rect, Color(1.0, 0.85, 0.3) if selected else Color(1, 1, 1, 0.35), false, 3.0 if selected else 1.5)
	if i < Inventory.HOTBAR_SIZE:
		draw_string(font, rect.position + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
	var s: Dictionary = inventory.slots[i]
	if s.is_empty():
		return
	_draw_item_icon(rect, s["id"])
	if s["count"] > 1:
		draw_string_outline(font, Vector2(rect.position.x, rect.end.y - 6), str(s["count"]), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 6, 18, 5, Color.BLACK)
		draw_string(font, Vector2(rect.position.x, rect.end.y - 6), str(s["count"]), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 6, 18, Color.WHITE)


# ---------------------------------------------------------------- アイテムのアイコン(data/items.json の icon と color で描き分け)

func _draw_item_icon(rect: Rect2, id: String) -> void:
	var c := rect.get_center() + Vector2(0, -2)
	var col := ItemDB.color(id)
	var dark := col.darkened(0.35)
	var light := col.lightened(0.3)
	var wood := Color(0.62, 0.42, 0.24)
	var s := rect.size.x / 72.0
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in pts:
			out.append(c + q * s)
		return out
	match ItemDB.icon(id):
		"axe":
			draw_line(c + Vector2(-13, 18) * s, c + Vector2(11, -15) * s, wood, 4.0)
			draw_colored_polygon(P.call([Vector2(5, -20), Vector2(20, -18), Vector2(18, -2), Vector2(9, -9)]), col)
		"pick":
			draw_line(c + Vector2(-13, 18) * s, c + Vector2(11, -15) * s, wood, 4.0)
			draw_polyline(P.call([Vector2(-9, -20), Vector2(6, -18), Vector2(15, -11), Vector2(21, 2)]), col, 4.0)
		"log":
			draw_rect(Rect2(c + Vector2(-18, -9) * s, Vector2(36, 18) * s), col)
			draw_circle(c + Vector2(18, 0) * s, 9 * s, Color(0.82, 0.66, 0.42))
			draw_arc(c + Vector2(18, 0) * s, 5 * s, 0, TAU, 16, col, 1.5)
		"rock", "ore":
			var pts: PackedVector2Array = P.call([Vector2(-17, 8), Vector2(-12, -10), Vector2(3, -16), Vector2(17, -6), Vector2(15, 11), Vector2(-4, 15)])
			draw_colored_polygon(pts, Color(0.6, 0.6, 0.58) if ItemDB.icon(id) == "rock" else Color(0.42, 0.4, 0.4))
			if ItemDB.icon(id) == "ore":
				for q in [Vector2(-6, -4), Vector2(6, 4), Vector2(5, -8), Vector2(-8, 7)]:
					draw_circle(c + q * s, 3.5 * s, col)
		"gem":
			draw_colored_polygon(P.call([Vector2(0, -20), Vector2(11, -4), Vector2(0, 18), Vector2(-11, -4)]), col)
			draw_colored_polygon(P.call([Vector2(0, -20), Vector2(11, -4), Vector2(0, -4)]), light)
		"ingot":
			draw_colored_polygon(P.call([Vector2(-20, 8), Vector2(-12, -6), Vector2(12, -6), Vector2(20, 8)]), col)
			draw_colored_polygon(P.call([Vector2(-12, -6), Vector2(12, -6), Vector2(8, -12), Vector2(-8, -12)]), light)
		"lump":
			draw_circle(c + Vector2(-6, 2) * s, 10 * s, col)
			draw_circle(c + Vector2(7, -3) * s, 8 * s, col.lightened(0.15))
		"glass":
			draw_rect(Rect2(c + Vector2(-16, -16) * s, Vector2(32, 32) * s), Color(col, 0.7))
			draw_line(c + Vector2(-8, 8) * s, c + Vector2(8, -8) * s, Color.WHITE, 2.0)
		"fuel":
			draw_rect(Rect2(c + Vector2(-12, -14) * s, Vector2(24, 30) * s), Color(0.85, 0.85, 0.88))
			draw_rect(Rect2(c + Vector2(-12, -2) * s, Vector2(24, 10) * s), col)
			draw_rect(Rect2(c + Vector2(-4, -20) * s, Vector2(8, 6) * s), dark)
		"plank":
			for i in 3:
				draw_rect(Rect2(c + Vector2(-20, -14 + i * 10) * s, Vector2(40, 8) * s), col if i % 2 == 0 else col.darkened(0.15))
		"stick":
			for i in 3:
				draw_line(c + Vector2(-14 + i * 8, 16) * s, c + Vector2(-4 + i * 8, -16) * s, col, 3.5)
		"brick":
			for row in 3:
				for k in 2:
					var off := 0.0 if row % 2 == 0 else 9.0
					draw_rect(Rect2(c + Vector2(-19 + off + k * 18, -14 + row * 10) * s, Vector2(16, 8) * s), col.darkened(0.08 * ((row + k) % 2)))
		"rope":
			draw_arc(c, 13 * s, 0, TAU, 20, col, 5.0)
			draw_arc(c, 6 * s, 0, TAU, 14, col.darkened(0.2), 4.0)
		"plate":
			draw_colored_polygon(P.call([Vector2(-18, 6), Vector2(-6, -12), Vector2(18, -12), Vector2(6, 6)]), col)
			draw_colored_polygon(P.call([Vector2(-18, 6), Vector2(6, 6), Vector2(6, 11), Vector2(-18, 11)]), dark)
		"rod":
			draw_line(c + Vector2(-16, 14) * s, c + Vector2(16, -14) * s, col, 6.0)
			draw_line(c + Vector2(-16, 14) * s, c + Vector2(16, -14) * s, light, 2.0)
		"nails":
			for i in 3:
				var x := (-10 + i * 10) * s
				draw_line(c + Vector2(x, -12), c + Vector2(x, 14 * s), col, 3.0)
				draw_line(c + Vector2(x - 5 * s, -12), c + Vector2(x + 5 * s, -12), col, 3.0)
		"gear":
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 10 * s, c + Vector2(cos(a), sin(a)) * 18 * s, col, 6.0 * s)
			draw_circle(c, 12 * s, col)
			draw_circle(c, 5 * s, Color(0.08, 0.1, 0.12))
		"screw":
			draw_rect(Rect2(c + Vector2(-9, -16) * s, Vector2(18, 6) * s), col)
			for i in 5:
				draw_line(c + Vector2(-5, -8 + i * 5) * s, c + Vector2(5, -6 + i * 5) * s, col, 3.0)
		"pipe":
			draw_rect(Rect2(c + Vector2(-20, -7) * s, Vector2(40, 14) * s), col)
			draw_rect(Rect2(c + Vector2(-20, -7) * s, Vector2(40, 4) * s), light)
			draw_circle(c + Vector2(20, 0) * s, 7 * s, dark)
		"bearing":
			draw_arc(c, 16 * s, 0, TAU, 24, col, 5.0)
			for i in 6:
				var a := i * TAU / 6.0
				draw_circle(c + Vector2(cos(a), sin(a)) * 10 * s, 3 * s, light)
			draw_arc(c, 5 * s, 0, TAU, 12, col, 3.0)
		"wire":
			for i in 3:
				draw_arc(c + Vector2(0, (i - 1) * 6) * s, 14 * s, 0.2, PI - 0.2, 12, col, 3.0)
		"spring":
			var pts := PackedVector2Array()
			for i in 13:
				pts.append(c + Vector2(-16 + i * 2.7, (8 if i % 2 else -8)) * s)
			draw_polyline(pts, col, 3.0)
		"nozzle":
			draw_colored_polygon(P.call([Vector2(-6, -16), Vector2(6, -16), Vector2(16, 16), Vector2(-16, 16)]), col)
			draw_rect(Rect2(c + Vector2(-8, -20) * s, Vector2(16, 5) * s), dark)
		"valve":
			draw_rect(Rect2(c + Vector2(-20, 4) * s, Vector2(40, 10) * s), Color(0.7, 0.72, 0.76))
			draw_line(c + Vector2(0, 4) * s, c + Vector2(0, -10) * s, Color(0.7, 0.72, 0.76), 4.0)
			draw_arc(c + Vector2(0, -12) * s, 9 * s, 0, TAU, 16, col, 4.0)
		"motor":
			draw_rect(Rect2(c + Vector2(-16, -12) * s, Vector2(28, 24) * s), col)
			draw_rect(Rect2(c + Vector2(12, -3) * s, Vector2(10, 6) * s), Color(0.75, 0.76, 0.8))
			for i in 4:
				draw_line(c + Vector2(-12 + i * 7, -12) * s, c + Vector2(-12 + i * 7, 12) * s, col.darkened(0.25), 2.0)
		"circuit":
			draw_rect(Rect2(c + Vector2(-18, -14) * s, Vector2(36, 28) * s), col)
			draw_rect(Rect2(c + Vector2(-6, -6) * s, Vector2(12, 12) * s), Color(0.15, 0.15, 0.18))
			for q in [Vector2(-14, -10), Vector2(10, 8), Vector2(-12, 8)]:
				draw_circle(c + q * s, 2.5 * s, Color(0.95, 0.8, 0.3))
		"battery":
			draw_rect(Rect2(c + Vector2(-10, -14) * s, Vector2(20, 30) * s), Color(0.25, 0.25, 0.28))
			draw_rect(Rect2(c + Vector2(-10, -14) * s, Vector2(20, 12) * s), col)
			draw_rect(Rect2(c + Vector2(-4, -19) * s, Vector2(8, 5) * s), Color(0.75, 0.76, 0.8))
		"panel":
			draw_rect(Rect2(c + Vector2(-18, -16) * s, Vector2(36, 32) * s), col)
			for q in [Vector2(-14, -12), Vector2(14, -12), Vector2(-14, 12), Vector2(14, 12)]:
				draw_circle(c + q * s, 2.5 * s, Color(0.5, 0.52, 0.56))
		"tank":
			draw_rect(Rect2(c + Vector2(-11, -14) * s, Vector2(22, 30) * s), col)
			draw_circle(c + Vector2(0, -14) * s, 11 * s, col)
			draw_rect(Rect2(c + Vector2(-11, 0) * s, Vector2(22, 5) * s), Color(0.82, 0.25, 0.2))
		"engine":
			draw_rect(Rect2(c + Vector2(-10, -18) * s, Vector2(20, 14) * s), col)
			draw_colored_polygon(P.call([Vector2(-6, -4), Vector2(6, -4), Vector2(14, 16), Vector2(-14, 16)]), col.darkened(0.3))
		"cone":
			draw_colored_polygon(P.call([Vector2(0, -20), Vector2(14, 14), Vector2(-14, 14)]), Color(0.82, 0.25, 0.2))
			draw_rect(Rect2(c + Vector2(-14, 12) * s, Vector2(28, 6) * s), col)
		"fin":
			draw_colored_polygon(P.call([Vector2(-12, -16), Vector2(-12, 16), Vector2(14, 16), Vector2(2, -4)]), col)
		"capsule":
			draw_circle(c + Vector2(0, -4) * s, 15 * s, col)
			draw_rect(Rect2(c + Vector2(-15, -4) * s, Vector2(30, 18) * s), col)
			draw_circle(c + Vector2(0, -4) * s, 6 * s, Color(0.3, 0.6, 0.85))
		"rocket":
			draw_rect(Rect2(c + Vector2(-7, -10) * s, Vector2(14, 24) * s), col)
			draw_colored_polygon(P.call([Vector2(-7, -10), Vector2(7, -10), Vector2(0, -22)]), Color(0.82, 0.25, 0.2))
			draw_colored_polygon(P.call([Vector2(-7, 6), Vector2(-14, 18), Vector2(-7, 14)]), Color(0.82, 0.25, 0.2))
			draw_colored_polygon(P.call([Vector2(7, 6), Vector2(14, 18), Vector2(7, 14)]), Color(0.82, 0.25, 0.2))
		"pad":
			draw_rect(Rect2(c + Vector2(-20, 8) * s, Vector2(40, 8) * s), col)
			draw_rect(Rect2(c + Vector2(10, -18) * s, Vector2(5, 26) * s), Color(0.7, 0.72, 0.76))
			draw_line(c + Vector2(-16, 8) * s, c + Vector2(16, 8) * s, Color(0.95, 0.72, 0.12), 2.0)
		"station":
			draw_rect(Rect2(c + Vector2(-22, -10) * s, Vector2(44, 8) * s), col)
			draw_rect(Rect2(c + Vector2(-19, -2) * s, Vector2(6, 20) * s), col.darkened(0.3))
			draw_rect(Rect2(c + Vector2(13, -2) * s, Vector2(6, 20) * s), col.darkened(0.3))
			draw_rect(Rect2(c + Vector2(-10, -16) * s, Vector2(12, 6) * s), Color(0.55, 0.56, 0.6))
		"furnace":
			draw_rect(Rect2(c + Vector2(-16, -10) * s, Vector2(32, 28) * s), col)
			draw_rect(Rect2(c + Vector2(-8, 2) * s, Vector2(16, 10) * s), Color(1.0, 0.55, 0.15))
			draw_rect(Rect2(c + Vector2(4, -22) * s, Vector2(8, 12) * s), col.darkened(0.3))
		"lathe":
			draw_rect(Rect2(c + Vector2(-20, 2) * s, Vector2(40, 14) * s), col)
			draw_rect(Rect2(c + Vector2(-18, -12) * s, Vector2(12, 14) * s), col)
			draw_line(c + Vector2(-6, -6) * s, c + Vector2(16, -6) * s, Color(0.8, 0.82, 0.86), 3.0)
		"foundation":
			draw_colored_polygon(P.call([Vector2(-20, -2), Vector2(0, -12), Vector2(20, -2), Vector2(0, 8)]), col.lightened(0.15))
			draw_colored_polygon(P.call([Vector2(-20, -2), Vector2(0, 8), Vector2(0, 16), Vector2(-20, 6)]), col)
			draw_colored_polygon(P.call([Vector2(0, 8), Vector2(20, -2), Vector2(20, 6), Vector2(0, 16)]), dark)
		"wall", "door", "window":
			draw_rect(Rect2(c + Vector2(-18, -18) * s, Vector2(36, 34) * s), col)
			draw_rect(Rect2(c + Vector2(-18, -18) * s, Vector2(36, 34) * s), dark, false, 2.0)
			if ItemDB.icon(id) == "door":
				draw_rect(Rect2(c + Vector2(-7, -4) * s, Vector2(14, 20) * s), dark)
			elif ItemDB.icon(id) == "window":
				draw_rect(Rect2(c + Vector2(-9, -10) * s, Vector2(18, 14) * s), Color(0.65, 0.88, 1.0))
		"floor":
			draw_colored_polygon(P.call([Vector2(-20, 0), Vector2(0, -10), Vector2(20, 0), Vector2(0, 10)]), col)
			draw_line(c + Vector2(-10, -5) * s, c + Vector2(10, 5) * s, dark, 1.5)
			draw_line(c + Vector2(-10, 5) * s, c + Vector2(10, -5) * s, dark, 1.5)
		"roof":
			draw_colored_polygon(P.call([Vector2(-22, 8), Vector2(0, -14), Vector2(22, 8)]), col)
			draw_rect(Rect2(c + Vector2(-14, 8) * s, Vector2(28, 10) * s), Color(0.7, 0.5, 0.3))
		"stairs":
			for i in 4:
				draw_rect(Rect2(c + Vector2(-18 + i * 9, 14 - (i + 1) * 8) * s, Vector2(9, (i + 1) * 8) * s), col.darkened(0.06 * i))
		"fence":
			for x in [-14, 0, 14]:
				draw_rect(Rect2(c + Vector2(x - 2, -14) * s, Vector2(5, 30) * s), col)
			for y in [-6, 6]:
				draw_rect(Rect2(c + Vector2(-18, y) * s, Vector2(36, 4) * s), col.darkened(0.2))
		"torch":
			draw_line(c + Vector2(0, 18) * s, c + Vector2(0, -6) * s, wood, 4.0)
			draw_circle(c + Vector2(0, -12) * s, 7 * s, col)
			draw_circle(c + Vector2(0, -12) * s, 3.5 * s, Color(1, 0.95, 0.6))
		"lantern":
			draw_rect(Rect2(c + Vector2(-9, -12) * s, Vector2(18, 22) * s), col)
			draw_rect(Rect2(c + Vector2(-11, -15) * s, Vector2(22, 4) * s), Color(0.3, 0.3, 0.32))
			draw_rect(Rect2(c + Vector2(-11, 10) * s, Vector2(22, 4) * s), Color(0.3, 0.3, 0.32))
		"table":
			draw_rect(Rect2(c + Vector2(-20, -6) * s, Vector2(40, 6) * s), col)
			draw_rect(Rect2(c + Vector2(-17, 0) * s, Vector2(4, 16) * s), col.darkened(0.3))
			draw_rect(Rect2(c + Vector2(13, 0) * s, Vector2(4, 16) * s), col.darkened(0.3))
		"chair":
			draw_rect(Rect2(c + Vector2(-10, -18) * s, Vector2(4, 34) * s), col.darkened(0.2))
			draw_rect(Rect2(c + Vector2(-10, 0) * s, Vector2(20, 5) * s), col)
			draw_rect(Rect2(c + Vector2(7, 5) * s, Vector2(4, 11) * s), col.darkened(0.2))
		"bed":
			draw_rect(Rect2(c + Vector2(-20, -2) * s, Vector2(40, 12) * s), Color(0.5, 0.33, 0.18))
			draw_rect(Rect2(c + Vector2(-18, -8) * s, Vector2(36, 8) * s), col)
			draw_rect(Rect2(c + Vector2(10, -12) * s, Vector2(10, 6) * s), Color(0.95, 0.95, 0.9))
		"chest":
			draw_rect(Rect2(c + Vector2(-18, -10) * s, Vector2(36, 26) * s), col)
			draw_rect(Rect2(c + Vector2(-18, -10) * s, Vector2(36, 8) * s), col.darkened(0.2))
			draw_rect(Rect2(c + Vector2(-3, -4) * s, Vector2(6, 8) * s), Color(0.3, 0.3, 0.32))
		_:
			draw_rect(Rect2(c + Vector2(-16, -16) * s, Vector2(32, 32) * s), col)
