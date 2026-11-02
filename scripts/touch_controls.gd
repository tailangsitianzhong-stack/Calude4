class_name TouchControls
extends Control
## スマホ用の操作と画面表示。
## 左側: バーチャルスティックで移動 / 右側: ドラッグで視点 / 右下: 攻撃・ジャンプ / 下中央: アイテム欄
## 右上: 視点切替・持ち物。持ち物を開くと、枠をタップ → 別の枠をタップで入れ替えられる。
## PC: WASD 移動、マウスドラッグ 視点、F 攻撃、Space ジャンプ、1〜6 アイテム、V 視点切替、E/Tab 持ち物

signal slot_selected(index: int)
signal view_toggled
signal craft_requested(index: int)

const JOY_RADIUS := 90.0
const LOOK_SENSITIVITY := 0.005
const SLOT_SIZE := 72.0
const SLOT_GAP := 8.0
const CRAFT_W := 450.0
const PANEL_GAP := 20.0
const CRAFT_ROW_H := 96.0

var player: Player
var inventory: Inventory
var selected_slot := 0
var target_name := ""
var target_ratio := -1.0       ## 狙っている物の残り体力(0〜1)、なければ -1
var bag_open := false
var attack_label := "攻撃"   ## 設置できる物を持っているときは「設置」

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _attack_index := -1
var _pressed := {}             ## タッチ番号 -> ボタンID
var _key_attack := false
var _held_slot := -1           ## 持ち物画面で選んでいる枠


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------- 配置

func _buttons() -> Array:
	var s := size
	return [
		{"id": "attack", "label": attack_label, "pos": Vector2(s.x - 150, s.y - 175), "r": 100.0},
		{"id": "jump", "label": "ジャンプ", "pos": Vector2(s.x - 345, s.y - 100), "r": 72.0},
		{"id": "view", "label": "視点", "pos": Vector2(s.x - 62, 62), "r": 42.0},
		{"id": "bag", "label": "持ち物", "pos": Vector2(s.x - 170, 62), "r": 42.0},
	]


func _hotbar_rect(i: int) -> Rect2:
	var total := Inventory.HOTBAR_SIZE * SLOT_SIZE + (Inventory.HOTBAR_SIZE - 1) * SLOT_GAP
	var x0 := (size.x - total) / 2.0
	return Rect2(Vector2(x0 + i * (SLOT_SIZE + SLOT_GAP), size.y - SLOT_SIZE - 14.0), Vector2(SLOT_SIZE, SLOT_SIZE))


## 持ち物画面(右側)。左にクラフト画面が並ぶので、2つ合わせて中央に置く
func _panel_rect() -> Rect2:
	var w := 6 * SLOT_SIZE + 5 * SLOT_GAP + 48.0
	var h := 4 * SLOT_SIZE + 3 * SLOT_GAP + 140.0
	var x0 := (size.x - (CRAFT_W + PANEL_GAP + w)) / 2.0
	return Rect2(Vector2(x0 + CRAFT_W + PANEL_GAP, (size.y - h) / 2.0 - 20.0), Vector2(w, h))


func _craft_rect() -> Rect2:
	var p := _panel_rect()
	return Rect2(Vector2(p.position.x - PANEL_GAP - CRAFT_W, p.position.y), Vector2(CRAFT_W, p.size.y))


func _craft_row_rect(i: int) -> Rect2:
	var c := _craft_rect()
	return Rect2(c.position + Vector2(16, 56 + i * (CRAFT_ROW_H + 8)), Vector2(CRAFT_W - 32, CRAFT_ROW_H))


func _craft_button_rect(i: int) -> Rect2:
	var r := _craft_row_rect(i)
	return Rect2(Vector2(r.end.x - 92, r.position.y + (r.size.y - 48) / 2.0), Vector2(80, 48))


## 持ち物画面の枠。かばん(3段)が上、アイテム欄(1段)が下
func _bag_rect(i: int) -> Rect2:
	var p := _panel_rect()
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
	var p := _panel_rect()
	return Rect2(p.end.x - 54, p.position.y + 10, 44, 36)


func _hit_test(p: Vector2) -> String:
	if bag_open:
		if _close_rect().grow(6).has_point(p):
			return "close"
		for i in Inventory.SIZE:
			if _bag_rect(i).has_point(p):
				return "bag%d" % i
		for i in Inventory.RECIPES.size():
			if _craft_button_rect(i).grow(6).has_point(p):
				return "craft%d" % i
		if _panel_rect().has_point(p) or _craft_rect().has_point(p):
			return "panel"
		return "close"
	for b in _buttons():
		if p.distance_to(b["pos"]) <= b["r"] + 10.0:
			return b["id"]
	for i in Inventory.HOTBAR_SIZE:
		if _hotbar_rect(i).grow(4).has_point(p):
			return "slot%d" % i
	return ""


# ---------------------------------------------------------------- 入力

func toggle_bag() -> void:
	bag_open = not bag_open
	_held_slot = -1
	_joy_index = -1
	_joy_vec = Vector2.ZERO
	_look_index = -1
	_attack_index = -1
	queue_redraw()


func _press(id: String, index: int) -> void:
	_pressed[index] = id
	match id:
		"attack":
			_attack_index = index
		"jump":
			player.jump_requested = true
		"view":
			view_toggled.emit()
		"bag", "close":
			toggle_bag()
		"panel":
			pass
		_:
			if id.begins_with("slot"):
				slot_selected.emit(int(id.substr(4)))
			elif id.begins_with("craft"):
				craft_requested.emit(int(id.substr(5)))
			elif id.begins_with("bag"):
				_tap_bag_slot(int(id.substr(3)))


func _tap_bag_slot(i: int) -> void:
	if _held_slot == -1:
		if inventory.id_at(i) != "":
			_held_slot = i
	else:
		inventory.move(_held_slot, i)
		_held_slot = -1
		slot_selected.emit(selected_slot)  # 手に持つ物を更新
	queue_redraw()


func _input(event: InputEvent) -> void:
	if player == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var id := _hit_test(t.position)
			if id != "":
				_press(id, t.index)
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
			_pressed.erase(t.index)
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			var off := d.position - _joy_origin
			if off.length() > JOY_RADIUS:
				off = off.normalized() * JOY_RADIUS
			_joy_vec = Vector2(off.x, -off.y) / JOY_RADIUS
		elif d.index == _look_index or d.index == _attack_index:
			# 攻撃ボタンを押したまま指を動かしても視点を回せる
			if _look_last == Vector2.ZERO:
				_look_last = d.position
			player.look_delta += (d.position - _look_last) * LOOK_SENSITIVITY
			_look_last = d.position
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_F:
			_key_attack = k.pressed and not bag_open
		elif k.pressed and not k.echo:
			match k.keycode:
				KEY_SPACE:
					player.jump_requested = true
				KEY_V:
					view_toggled.emit()
				KEY_E, KEY_TAB, KEY_I:
					toggle_bag()
				KEY_ESCAPE:
					if bag_open:
						toggle_bag()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
					slot_selected.emit(k.keycode - KEY_1)


func _process(_delta: float) -> void:
	if player == null:
		return
	if _attack_index == -1 and _look_index == -1:
		_look_last = Vector2.ZERO
	player.attack_held = (_attack_index != -1 or _key_attack) and not bag_open
	if _joy_index != -1:
		player.move_input = _joy_vec
	elif bag_open:
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


# ---------------------------------------------------------------- 描画

func _draw() -> void:
	var font := get_theme_default_font()
	var center := size / 2.0

	if not bag_open:
		# 照準と、狙っている物の名前・体力
		var aim_col := Color(1, 1, 1, 0.9) if target_ratio >= 0.0 else Color(1, 1, 1, 0.5)
		draw_arc(center, 9, 0, TAU, 24, aim_col, 2.0)
		draw_circle(center, 2.0, aim_col)
		if target_ratio >= 0.0:
			draw_string(font, center + Vector2(-120, 44), target_name, HORIZONTAL_ALIGNMENT_CENTER, 240, 20, Color.WHITE)
			var bar := Rect2(center + Vector2(-50, 54), Vector2(100, 7))
			draw_rect(bar, Color(0, 0, 0, 0.5))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * target_ratio, bar.size.y)), Color(0.45, 0.9, 0.4))

		# スティック
		if _joy_index != -1:
			draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
			draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
			draw_circle(_joy_origin + Vector2(_joy_vec.x, -_joy_vec.y) * JOY_RADIUS, 38, Color(1, 1, 1, 0.5))
		else:
			var hint := Vector2(160, size.y - 180)
			draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
			draw_string(font, hint + Vector2(-60, 8), "移動", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 1, 1, 0.5))

	# ボタン
	var pressed_ids := _pressed.values()
	for b in _buttons():
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var on: bool = pressed_ids.has(b["id"]) or (b["id"] == "attack" and _key_attack) or (b["id"] == "bag" and bag_open)
		if bag_open and b["id"] != "bag":
			continue
		draw_circle(pos, r, Color(0.1, 0.12, 0.15, 0.6 if on else 0.38))
		draw_arc(pos, r, 0, TAU, 48, Color(1, 1, 1, 0.9 if on else 0.6), 3.0)
		var fs := 34 if b["id"] == "attack" else (24 if b["id"] == "jump" else 17)
		draw_string(font, Vector2(pos.x - r, pos.y + fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)

	# アイテム欄
	if not bag_open:
		for i in Inventory.HOTBAR_SIZE:
			_draw_slot(font, _hotbar_rect(i), i, i == selected_slot)
		var held := inventory.id_at(selected_slot)
		if held != "":
			var r0 := _hotbar_rect(0)
			draw_string(font, Vector2(r0.position.x, r0.position.y - 10), Inventory.item_name(held),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	else:
		_draw_bag(font)


func _draw_bag(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	_draw_craft(font)
	var p := _panel_rect()
	draw_rect(p, Color(0.11, 0.13, 0.16, 0.96))
	draw_rect(p, Color(1, 1, 1, 0.35), false, 2.0)
	draw_string(font, p.position + Vector2(24, 38), "持ち物", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var c := _close_rect()
	draw_rect(c, Color(1, 1, 1, 0.12))
	draw_string(font, Vector2(c.position.x, c.position.y + 26), "×", HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 24, Color.WHITE)

	for i in Inventory.SIZE:
		_draw_slot(font, _bag_rect(i), i, i == selected_slot and i < Inventory.HOTBAR_SIZE)
		if i == _held_slot:
			draw_rect(_bag_rect(i).grow(3), Color(0.4, 0.9, 1.0), false, 3.0)
	var hb := _bag_rect(0)
	draw_string(font, Vector2(hb.position.x, hb.position.y - 6), "アイテム欄", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))

	# 説明と合計
	var info := "枠をタップ → 移動先の枠をタップで入れ替え"
	if _held_slot != -1:
		var id := inventory.id_at(_held_slot)
		info = "%s × %d を選択中。移動先をタップ" % [Inventory.item_name(id), inventory.slots[_held_slot]["count"]]
	draw_string(font, Vector2(p.position.x + 24, p.end.y - 18), info, HORIZONTAL_ALIGNMENT_LEFT, p.size.x - 48, 15, Color(1, 1, 1, 0.75))


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


func _draw_item_icon(rect: Rect2, id: String) -> void:
	var c := rect.get_center() + Vector2(0, -2)
	var wood := Color(0.62, 0.42, 0.24)
	var steel := Color(0.8, 0.82, 0.86)
	var stone := Color(0.6, 0.6, 0.58)
	match id:
		"axe":
			draw_line(c + Vector2(-13, 18), c + Vector2(11, -15), wood, 4.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(5, -20), c + Vector2(20, -18), c + Vector2(18, -2), c + Vector2(9, -9)]), steel)
		"pickaxe":
			draw_line(c + Vector2(-13, 18), c + Vector2(11, -15), wood, 4.0)
			draw_polyline(PackedVector2Array([c + Vector2(-9, -20), c + Vector2(6, -18), c + Vector2(15, -11), c + Vector2(21, 2)]), steel, 4.0)
		"wood":
			draw_rect(Rect2(c + Vector2(-18, -9), Vector2(36, 18)), wood)
			draw_circle(c + Vector2(18, 0), 9, Color(0.82, 0.66, 0.42))
			draw_arc(c + Vector2(18, 0), 5, 0, TAU, 16, wood, 1.5)
		"stone", "iron", "copper":
			var pts := PackedVector2Array([c + Vector2(-17, 8), c + Vector2(-12, -10), c + Vector2(3, -16), c + Vector2(17, -6), c + Vector2(15, 11), c + Vector2(-4, 15)])
			draw_colored_polygon(pts, stone if id == "stone" else Color(0.42, 0.4, 0.4))
			if id != "stone":
				var spot := Color(0.85, 0.5, 0.28) if id == "iron" else Color(0.3, 0.78, 0.62)
				for q in [Vector2(-6, -4), Vector2(6, 4), Vector2(5, -8), Vector2(-8, 7)]:
					draw_circle(c + q, 3.5, spot)
		"workbench":
			draw_rect(Rect2(c + Vector2(-22, -10), Vector2(44, 8)), Color(0.72, 0.52, 0.3))
			draw_rect(Rect2(c + Vector2(-19, -2), Vector2(6, 20)), Color(0.5, 0.33, 0.18))
			draw_rect(Rect2(c + Vector2(13, -2), Vector2(6, 20)), Color(0.5, 0.33, 0.18))
			draw_rect(Rect2(c + Vector2(-15, 8), Vector2(30, 4)), Color(0.6, 0.42, 0.24))
			draw_rect(Rect2(c + Vector2(-10, -16), Vector2(12, 6)), Color(0.55, 0.56, 0.6))
		"crystal":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -20), c + Vector2(11, -4), c + Vector2(0, 18), c + Vector2(-11, -4)]), Color(0.7, 0.55, 1.0))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -20), c + Vector2(11, -4), c + Vector2(0, -4)]), Color(0.88, 0.8, 1.0))


func _draw_craft(font: Font) -> void:
	var c := _craft_rect()
	draw_rect(c, Color(0.11, 0.13, 0.16, 0.96))
	draw_rect(c, Color(1, 1, 1, 0.35), false, 2.0)
	draw_string(font, c.position + Vector2(20, 38), "クラフト", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	for i in Inventory.RECIPES.size():
		var rec: Dictionary = Inventory.RECIPES[i]
		var row := _craft_row_rect(i)
		var ok := inventory.can_afford(rec["cost"])
		draw_rect(row, Color(1, 1, 1, 0.06))
		var icon := Rect2(row.position + Vector2(8, (row.size.y - SLOT_SIZE) / 2.0), Vector2(SLOT_SIZE, SLOT_SIZE))
		draw_rect(icon, Color(0.08, 0.1, 0.12, 0.8))
		_draw_item_icon(icon, rec["id"])
		var tx := icon.end.x + 12
		draw_string(font, Vector2(tx, row.position.y + 34), Inventory.item_name(rec["id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		# 必要な素材(持っている数 / 必要な数)。足りない物は赤
		var x := tx
		for k in rec["cost"]:
			var have := inventory.total(k)
			var need: int = rec["cost"][k]
			var txt := "%s %d/%d" % [Inventory.item_name(k), mini(have, 999), need]
			var col := Color(0.75, 0.95, 0.7) if have >= need else Color(1.0, 0.55, 0.5)
			draw_string(font, Vector2(x, row.position.y + 66), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
			x += font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12
		var b := _craft_button_rect(i)
		var pressed := _pressed.values().has("craft%d" % i)
		draw_rect(b, Color(0.3, 0.7, 0.4, 0.95 if pressed else 0.8) if ok else Color(0.35, 0.35, 0.38, 0.6))
		draw_string(font, Vector2(b.position.x, b.position.y + 31), "作る", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 20, Color.WHITE if ok else Color(1, 1, 1, 0.45))
