class_name TouchControls
extends Control
## スマホ用の操作と画面表示。
## 左側: バーチャルスティックで移動 / 右側: ドラッグで視点 / 右下: 攻撃・ジャンプ / 下中央: アイテム欄
## PC: WASD で移動、マウスドラッグで視点、F か左クリック長押しで攻撃、Space でジャンプ、1〜6 でアイテム、V で視点切替

signal slot_selected(index: int)
signal view_toggled

const JOY_RADIUS := 80.0
const LOOK_SENSITIVITY := 0.005
const SLOT_COUNT := 6
const SLOT_SIZE := 66.0

var player: Player
var slots: Array = []          ## [{id, label}] main.gd が設定
var selected_slot := 0
var target_name := ""
var target_ratio := -1.0       ## 狙っている物の残り体力(0〜1)、なければ -1

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _attack_index := -1
var _pressed := {}             ## タッチ番号 -> ボタンID
var _key_attack := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _buttons() -> Array:
	var s := size
	return [
		{"id": "attack", "label": "攻撃", "pos": Vector2(s.x - 120, s.y - 150), "r": 70.0},
		{"id": "jump", "label": "ジャンプ", "pos": Vector2(s.x - 265, s.y - 80), "r": 48.0},
		{"id": "view", "label": "視点", "pos": Vector2(s.x - 56, 56), "r": 34.0},
	]


func _slot_rect(i: int) -> Rect2:
	var total := SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * 8.0
	var x0 := (size.x - total) / 2.0
	return Rect2(Vector2(x0 + i * (SLOT_SIZE + 8.0), size.y - SLOT_SIZE - 14.0), Vector2(SLOT_SIZE, SLOT_SIZE))


func _hit_test(p: Vector2) -> String:
	for b in _buttons():
		if p.distance_to(b["pos"]) <= b["r"] + 10.0:
			return b["id"]
	for i in SLOT_COUNT:
		if _slot_rect(i).grow(4).has_point(p):
			return "slot%d" % i
	return ""


func _press(id: String, index: int) -> void:
	_pressed[index] = id
	match id:
		"attack":
			_attack_index = index
		"jump":
			player.jump_requested = true
		"view":
			view_toggled.emit()
		_:
			if id.begins_with("slot"):
				slot_selected.emit(int(id.substr(4)))


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
			queue_redraw()
		elif d.index == _look_index or d.index == _attack_index:
			# 攻撃ボタンを押したまま指を動かしても視点を回せる
			if d.index == _attack_index and _look_last == Vector2.ZERO:
				_look_last = d.position
			player.look_delta += (d.position - _look_last) * LOOK_SENSITIVITY
			_look_last = d.position
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_F:
			_key_attack = k.pressed
		elif k.pressed and not k.echo:
			match k.keycode:
				KEY_SPACE:
					player.jump_requested = true
				KEY_V:
					view_toggled.emit()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
					slot_selected.emit(k.keycode - KEY_1)


func _process(_delta: float) -> void:
	if player == null:
		return
	if _attack_index == -1 and _look_index == -1:
		_look_last = Vector2.ZERO
	player.attack_held = _attack_index != -1 or _key_attack
	if _joy_index != -1:
		player.move_input = _joy_vec
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


func _draw() -> void:
	var font := get_theme_default_font()
	var center := size / 2.0

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
		draw_circle(_joy_origin + Vector2(_joy_vec.x, -_joy_vec.y) * JOY_RADIUS, 34, Color(1, 1, 1, 0.5))
	else:
		var hint := Vector2(150, size.y - 170)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
		draw_string(font, hint + Vector2(-60, 8), "移動", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 1, 1, 0.5))

	# ボタン
	var pressed_ids := _pressed.values()
	for b in _buttons():
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var on: bool = pressed_ids.has(b["id"]) or (b["id"] == "attack" and _key_attack)
		draw_circle(pos, r, Color(0.1, 0.12, 0.15, 0.55 if on else 0.35))
		draw_arc(pos, r, 0, TAU, 48, Color(1, 1, 1, 0.85 if on else 0.55), 2.5)
		var fs := 26 if b["id"] == "attack" else 18
		draw_string(font, Vector2(pos.x - r, pos.y + fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)

	# アイテム欄
	for i in SLOT_COUNT:
		var rect := _slot_rect(i)
		var sel := i == selected_slot
		draw_rect(rect, Color(0.08, 0.1, 0.12, 0.6))
		draw_rect(rect, Color(1.0, 0.85, 0.3) if sel else Color(1, 1, 1, 0.35), false, 3.0 if sel else 1.5)
		draw_string(font, rect.position + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
		if i < slots.size():
			var s: Dictionary = slots[i]
			_draw_tool_icon(rect, s["id"])
			draw_string(font, Vector2(rect.position.x, rect.end.y - 6), s["label"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, Color.WHITE)


func _draw_tool_icon(rect: Rect2, id: String) -> void:
	var c := rect.get_center() + Vector2(0, -6)
	var wood := Color(0.62, 0.42, 0.24)
	var steel := Color(0.8, 0.82, 0.86)
	draw_line(c + Vector2(-12, 16), c + Vector2(10, -14), wood, 4.0)
	if id == "axe":
		draw_colored_polygon(PackedVector2Array([c + Vector2(4, -18), c + Vector2(18, -16), c + Vector2(16, -2), c + Vector2(8, -8)]), steel)
	elif id == "pickaxe":
		draw_polyline(PackedVector2Array([c + Vector2(-8, -18), c + Vector2(6, -16), c + Vector2(14, -10), c + Vector2(20, 2)]), steel, 4.0)
