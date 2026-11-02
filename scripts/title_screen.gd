class_name TitleScreen
extends Control
## タイトル画面。後ろではゲームの世界がゆっくり回って見える。

signal start_pressed
signal restart_pressed

var started := false   ## 一度ゲームを始めたら「つづける」になる
var _pressed := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _buttons() -> Array:
	var c := size / 2.0
	var list := [{"id": "start", "label": "つづける" if started else "はじめる", "rect": Rect2(c + Vector2(-150, 70), Vector2(300, 70))}]
	if started:
		list.append({"id": "restart", "label": "はじめから", "rect": Rect2(c + Vector2(-150, 156), Vector2(300, 56))})
	return list


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		for b in _buttons():
			if (b["rect"] as Rect2).has_point(t.position):
				if t.pressed:
					_pressed = b["id"]
				elif _pressed == b["id"]:
					_pressed = ""
					if b["id"] == "start":
						start_pressed.emit()
					else:
						restart_pressed.emit()
		if not t.pressed:
			_pressed = ""
		get_viewport().set_input_as_handled()
		queue_redraw()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode in [KEY_ENTER, KEY_SPACE]:
		start_pressed.emit()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var font := get_theme_default_font()
	var c := size / 2.0
	# 下に向かって暗くなるグラデーション
	var top := Color(0.02, 0.04, 0.1, 0.2)
	var bottom := Color(0.02, 0.04, 0.1, 0.72)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	draw_string(font, Vector2(0, c.y - 150), "LANDING SITE · GRASSLAND", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.45, 0.85, 1.0))
	draw_string_outline(font, Vector2(0, c.y - 60), "Planet Pioneer", HORIZONTAL_ALIGNMENT_CENTER, size.x, 84, 14, Color(0.03, 0.05, 0.12, 0.8))
	draw_string(font, Vector2(0, c.y - 60), "Planet Pioneer", HORIZONTAL_ALIGNMENT_CENTER, size.x, 84, Color.WHITE)
	draw_string(font, Vector2(0, c.y - 8), "木を切り、鉱石を掘り、家を建て、ロケットで宇宙をめざそう", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, 0.85))
	for b in _buttons():
		var r: Rect2 = b["rect"]
		var main: bool = b["id"] == "start"
		var on: bool = _pressed == b["id"]
		draw_rect(r, Color(0.85, 0.42, 0.2, 1.0 if on else 0.92) if main else Color(1, 1, 1, 0.22 if on else 0.12))
		draw_rect(r, Color(1, 1, 1, 0.8), false, 2.0)
		draw_string(font, Vector2(r.position.x, r.position.y + r.size.y / 2.0 + (11 if main else 9)), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 30 if main else 22, Color.WHITE)
	draw_string(font, Vector2(0, size.y - 24), "スマホは横向きがおすすめ", HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(1, 1, 1, 0.55))
