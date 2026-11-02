class_name TouchControls
extends Control
## スマホ用の操作。左側はバーチャルスティック、右側のドラッグで視点、右下にボタン。
## PCでは WASD/矢印キーで移動、マウスドラッグで視点、Space/E/1/2 でボタン操作。

signal action_pressed(id: String)

const JOY_RADIUS := 80.0
const LOOK_SENSITIVITY := 0.006

var player: Player
var enabled := {"jump": true, "collect": false, "drill": false, "dome": false}

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _pressed := {}  # タッチ番号 -> ボタンID


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _buttons() -> Array:
	var s := size
	return [
		{"id": "jump", "label": "ジャンプ", "pos": Vector2(s.x - 95, s.y - 95), "r": 60.0},
		{"id": "collect", "label": "採取", "pos": Vector2(s.x - 230, s.y - 80), "r": 50.0},
		{"id": "drill", "label": "採掘機\n結晶3", "pos": Vector2(s.x - 95, s.y - 240), "r": 50.0},
		{"id": "dome", "label": "ドーム\n鉱石10 結晶2", "pos": Vector2(s.x - 230, s.y - 210), "r": 50.0},
	]


func _button_at(p: Vector2) -> String:
	for b in _buttons():
		if p.distance_to(b["pos"]) <= b["r"] + 8.0:
			return b["id"]
	return ""


func _fire(id: String) -> void:
	if id == "jump":
		player.jump_requested = true
	action_pressed.emit(id)


func _input(event: InputEvent) -> void:
	if player == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var id := _button_at(t.position)
			if id != "":
				_pressed[t.index] = id
				_fire(id)
			elif t.position.x < size.x * 0.45 and _joy_index == -1:
				_joy_index = t.index
				_joy_origin = t.position
				_joy_pos = t.position
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
			_pressed.erase(t.index)
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			_joy_pos = d.position
			var off := _joy_pos - _joy_origin
			if off.length() > JOY_RADIUS:
				off = off.normalized() * JOY_RADIUS
			_joy_vec = Vector2(off.x, -off.y) / JOY_RADIUS
			queue_redraw()
		elif d.index == _look_index:
			player.look_delta += (d.position - _look_last) * LOOK_SENSITIVITY
			_look_last = d.position
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_SPACE:
					_fire("jump")
				KEY_E:
					_fire("collect")
				KEY_1:
					_fire("drill")
				KEY_2:
					_fire("dome")


func _process(_delta: float) -> void:
	if player == null:
		return
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


func _draw() -> void:
	var font := get_theme_default_font()

	# スティック
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.4), 3.0)
		draw_circle(_joy_origin + Vector2(_joy_vec.x, -_joy_vec.y) * JOY_RADIUS, 34, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(150, size.y - 150)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0)
		draw_string(font, hint + Vector2(-60, 8), "ここで移動", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 1, 1, 0.35))

	# ボタン
	var pressed_ids := _pressed.values()
	for b in _buttons():
		var on: bool = enabled.get(b["id"], true)
		var is_pressed: bool = pressed_ids.has(b["id"])
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var fill := Color(0.3, 0.8, 1.0, 0.45 if is_pressed else 0.22) if on else Color(0.5, 0.5, 0.5, 0.12)
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0, TAU, 48, Color(1, 1, 1, 0.7 if on else 0.25), 2.5)
		var lines: PackedStringArray = String(b["label"]).split("\n")
		var fs := 20 if lines.size() == 1 else 17
		var y0 := pos.y - (lines.size() - 1) * fs * 0.6 + fs * 0.35
		for i in lines.size():
			var size_i := fs if i == 0 else 13
			draw_string(font, Vector2(pos.x - r, y0 + i * fs * 1.15), lines[i], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size_i, Color(1, 1, 1, 0.95 if on else 0.4))
