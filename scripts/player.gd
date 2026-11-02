class_name Player
extends CharacterBody3D
## 惑星の中心に向かう重力で、球体の地表を歩く宇宙飛行士。

var planet_center := Vector3.ZERO
var sea_level := 0.0

# 操作(TouchControls から設定される)
var move_input := Vector2.ZERO   ## x: 右, y: 前
var look_delta := Vector2.ZERO   ## 視点の回転量(ラジアン)
var jump_requested := false

var walk_speed := 7.0
var jump_speed := 8.5
var gravity := 18.0
var pitch := -0.35

var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var visual: Node3D
var _walk_time := 0.0
var _spawn_point := Vector3.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	floor_stop_on_slope = true

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	_build_visual()

	pivot = Node3D.new()
	pivot.position.y = 1.5
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 5.5
	spring.collision_mask = 1
	spring.margin = 0.3
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	spring.add_excluded_object(get_rid())
	pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 2500.0
	spring.add_child(camera)
	camera.current = true


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)

	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.92, 0.92, 0.95)
	suit.roughness = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(1.0, 0.55, 0.15)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.25, 0.35)
	glass.emission_enabled = true
	glass.emission = Color(0.2, 0.7, 1.0)
	glass.emission_energy_multiplier = 0.6
	glass.metallic = 0.8
	glass.roughness = 0.1

	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	body.mesh = cap
	body.position.y = 0.9
	body.material_override = suit
	visual.add_child(body)

	var visor := MeshInstance3D.new()
	var vbox := BoxMesh.new()
	vbox.size = Vector3(0.55, 0.28, 0.2)
	visor.mesh = vbox
	visor.position = Vector3(0, 1.45, -0.32)
	visor.material_override = glass
	visual.add_child(visor)

	var pack := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.55, 0.7, 0.3)
	pack.mesh = pbox
	pack.position = Vector3(0, 1.05, 0.42)
	pack.material_override = accent
	visual.add_child(pack)


func spawn_at(pos: Vector3) -> void:
	_spawn_point = pos
	global_position = pos
	velocity = Vector3.ZERO
	var up := (pos - planet_center).normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	global_transform.basis = Basis.looking_at((ref - up * ref.dot(up)).normalized(), up)


func get_up() -> Vector3:
	return (global_position - planet_center).normalized()


func get_forward() -> Vector3:
	return -global_transform.basis.z


func is_underwater() -> bool:
	return global_position.distance_to(planet_center) < sea_level - 0.6


func _physics_process(delta: float) -> void:
	var up := get_up()

	# 体を「惑星の中心から外向き」に立たせ、視点の左右回転を反映する
	var fwd := -global_transform.basis.z
	fwd = fwd - up * fwd.dot(up)
	if fwd.length() < 0.001:
		fwd = up.cross(Vector3.RIGHT)
	fwd = fwd.normalized()
	if look_delta.x != 0.0:
		fwd = fwd.rotated(up, -look_delta.x)
	pitch = clampf(pitch - look_delta.y, -1.25, 0.45)
	look_delta = Vector2.ZERO
	global_transform.basis = Basis.looking_at(fwd, up)
	pivot.rotation.x = pitch

	# 移動
	var right := fwd.cross(up)
	var wish := right * move_input.x + fwd * move_input.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	var water := is_underwater()
	var speed := walk_speed * (0.55 if water else 1.0)

	var v_up := velocity.dot(up)
	var horiz := velocity - up * v_up
	var accel := 10.0 if is_on_floor() else 2.5
	horiz = horiz.lerp(wish * speed, clampf(delta * accel, 0.0, 1.0))

	v_up -= gravity * (0.45 if water else 1.0) * delta
	if water:
		v_up = maxf(v_up, -4.0)
	if jump_requested and (is_on_floor() or water):
		v_up = jump_speed * (0.6 if water else 1.0)
	jump_requested = false

	velocity = horiz + up * v_up
	up_direction = up
	move_and_slide()

	_animate(delta, wish)

	# 万一地面をすり抜けたり宇宙へ飛んだら、最初の地点へ戻す
	var dist := global_position.distance_to(planet_center)
	if dist < sea_level - 25.0 or dist > sea_level + 150.0:
		spawn_at(_spawn_point)


func _animate(delta: float, wish: Vector3) -> void:
	var moving := wish.length() > 0.1
	if moving:
		var local := global_transform.basis.inverse() * wish
		var target := atan2(-local.x, -local.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target, clampf(delta * 10.0, 0.0, 1.0))
		_walk_time += delta * 11.0
	visual.position.y = absf(sin(_walk_time)) * 0.08 if (moving and is_on_floor()) else lerpf(visual.position.y, 0.0, 0.2)
