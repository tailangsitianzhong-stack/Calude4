class_name Player
extends CharacterBody3D
## 開拓者。一人称視点(最初)と三人称視点を切り替えられる。手に持った道具で木や鉱石を叩く。

signal swung(target: Object, hit_point: Vector3)

const EYE_HEIGHT := 1.62
const REACH := 3.2
const SWING_TIME := 0.42
const HIT_DELAY := 0.17

var move_input := Vector2.ZERO
var look_delta := Vector2.ZERO
var jump_requested := false
var attack_held := false

var walk_speed := 5.0
var jump_speed := 5.2
var gravity := 14.0
var bounds := 118.0

var first_person := true
var current_tool := "axe"   ## "axe" / "pickaxe" / ""(素手)

var head: Node3D            ## 視点の上下(ピッチ)
var camera: Camera3D
var spring: SpringArm3D
var ray: RayCast3D
var viewmodel: Node3D       ## 一人称で画面に映る腕と道具
var vm_tool_holder: Node3D
var body_model: Node3D      ## Blenderで作った全身モデル
var anim: AnimationPlayer
var tp_tool_holder: Node3D

var _tools := {}
var _swing_timer := 0.0
var _hit_pending := false
var _bob := 0.0
var _vm_rest := Vector3(0.3, -0.4, -0.1)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.4

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	_tools["axe"] = load("res://assets/models/axe.glb")
	_tools["pickaxe"] = load("res://assets/models/pickaxe.glb")

	_build_body()

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	spring = SpringArm3D.new()
	spring.collision_mask = 1
	spring.margin = 0.25
	spring.spring_length = 0.0
	spring.add_excluded_object(get_rid())
	head.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 600.0
	spring.add_child(camera)
	camera.current = true

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 4
	ray.add_exception(self)
	head.add_child(ray)

	_build_viewmodel()
	set_first_person(true)
	set_tool(current_tool)


func _build_body() -> void:
	body_model = load("res://assets/models/pioneer.glb").instantiate()
	add_child(body_model)
	var players := body_model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		anim = players[0]
		for n in ["Idle", "Walk"]:
			if anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		anim.play("Idle")
	# 右手に道具を持たせる
	var skels := body_model.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		var skel: Skeleton3D = skels[0]
		var att := BoneAttachment3D.new()
		for i in skel.get_bone_count():
			var bn := skel.get_bone_name(i).to_lower()
			if bn.begins_with("hand") and bn.ends_with("r"):
				att.bone_name = skel.get_bone_name(i)
		skel.add_child(att)
		tp_tool_holder = Node3D.new()
		tp_tool_holder.position = Vector3(0, 0.06, 0.0)
		tp_tool_holder.rotation = Vector3(deg_to_rad(55), 0, 0)
		att.add_child(tp_tool_holder)


func _build_viewmodel() -> void:
	viewmodel = Node3D.new()
	viewmodel.position = _vm_rest
	viewmodel.rotation = Vector3(deg_to_rad(8), deg_to_rad(-8), deg_to_rad(-6))
	camera.add_child(viewmodel)
	# 回転の中心は肘。手はそこから前へ 0.4m
	var grip := Node3D.new()
	grip.position = Vector3(0, 0.03, -0.4)
	viewmodel.add_child(grip)
	var arm: Node3D = load("res://assets/models/fp_arm.glb").instantiate()
	grip.add_child(arm)
	vm_tool_holder = Node3D.new()
	vm_tool_holder.rotation = Vector3(deg_to_rad(-20), deg_to_rad(60), 0)
	grip.add_child(vm_tool_holder)
	_set_no_shadow(viewmodel)


func _set_no_shadow(n: Node) -> void:
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_tool(id: String) -> void:
	current_tool = id
	for holder in [vm_tool_holder, tp_tool_holder]:
		if holder == null:
			continue
		for c in holder.get_children():
			c.queue_free()
		if _tools.has(id):
			var t: Node3D = _tools[id].instantiate()
			holder.add_child(t)
			if holder == vm_tool_holder:
				_set_no_shadow(t)
	# 持ち替えの動き
	if viewmodel:
		viewmodel.position = _vm_rest + Vector3(0, -0.3, 0)
	_apply_body_visibility()


func set_first_person(on: bool) -> void:
	first_person = on
	spring.spring_length = 0.0 if on else 3.2
	spring.position = Vector3.ZERO if on else Vector3(0.45, 0.15, 0)
	viewmodel.visible = on
	_apply_body_visibility()


## 一人称では全身モデル(手に持った道具も含む)は見せず、影だけ落とす
func _apply_body_visibility() -> void:
	if body_model == null:
		return
	for c in body_model.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


## いま狙っている物(届く範囲)
func get_target() -> Object:
	if ray.is_colliding():
		var c := ray.get_collider()
		if c is Harvestable:
			return c
	return null


func _physics_process(delta: float) -> void:
	# 視点
	rotate_y(-look_delta.x)
	head.rotation.x = clampf(head.rotation.x - look_delta.y, deg_to_rad(-85), deg_to_rad(85))
	look_delta = Vector2.ZERO

	# 移動
	var basis_flat := global_transform.basis
	var wish := (basis_flat.x * move_input.x - basis_flat.z * move_input.y)
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var accel := 12.0 if is_on_floor() else 3.0
	var horiz := Vector3(velocity.x, 0, velocity.z).lerp(wish * walk_speed, clampf(accel * delta, 0.0, 1.0))
	velocity.x = horiz.x
	velocity.z = horiz.z
	if is_on_floor():
		if jump_requested:
			velocity.y = jump_speed
	else:
		velocity.y -= gravity * delta
	jump_requested = false
	move_and_slide()

	# 世界の端から出ないように
	var p := global_position
	var flat := Vector2(p.x, p.z)
	if flat.length() > bounds:
		flat = flat.normalized() * bounds
		global_position = Vector3(flat.x, p.y, flat.y)
	if p.y < -30.0:
		global_position = Vector3(0, 5, 0)
		velocity = Vector3.ZERO

	_update_attack(delta)
	_animate(delta, horiz.length())


func _update_attack(delta: float) -> void:
	if _swing_timer > 0.0:
		_swing_timer -= delta
		if _hit_pending and _swing_timer <= SWING_TIME - HIT_DELAY:
			_hit_pending = false
			var target := get_target()
			swung.emit(target, ray.get_collision_point() if ray.is_colliding() else Vector3.ZERO)
	elif attack_held:
		_swing_timer = SWING_TIME
		_hit_pending = true
		if anim and anim.has_animation("Swing"):
			anim.play("Swing", 0.05, 1.6)


func _animate(delta: float, speed: float) -> void:
	var moving := speed > 0.5 and is_on_floor()
	if moving:
		_bob += delta * speed * 2.2

	# 一人称の腕と道具
	var t := 1.0 - clampf(_swing_timer / SWING_TIME, 0.0, 1.0) if _swing_timer > 0.0 else 0.0
	var swing_rot := 0.0
	if _swing_timer > 0.0:
		# 振り上げ → 振り下ろし → 戻す
		if t < 0.3:
			swing_rot = lerpf(0.0, 0.7, t / 0.3)
		elif t < 0.5:
			swing_rot = lerpf(0.7, -1.2, (t - 0.3) / 0.2)
		else:
			swing_rot = lerpf(-1.2, 0.0, (t - 0.5) / 0.5)
	var bob_off := Vector3(sin(_bob) * 0.015, -absf(cos(_bob)) * 0.02, 0) if moving else Vector3.ZERO
	viewmodel.position = viewmodel.position.lerp(_vm_rest + bob_off, clampf(delta * 10.0, 0.0, 1.0))
	viewmodel.rotation.x = deg_to_rad(8) + swing_rot

	# 三人称の体のアニメーション
	if anim and _swing_timer <= 0.0:
		var want := "Walk" if moving else "Idle"
		if anim.current_animation != want:
			anim.play(want, 0.2)
		if want == "Walk":
			anim.speed_scale = clampf(speed / walk_speed, 0.5, 1.3)
		else:
			anim.speed_scale = 1.0
