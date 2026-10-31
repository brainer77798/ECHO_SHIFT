class_name PlayerModel
extends Node3D
## Procedural operative model (origin at the feet, facing -Z). Used by the Player and, with a
## holographic material, by Echoes. Animation is driven by animate().

var holo := false
var tint := Cfg.C_CYAN
var muzzle: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_r: Node3D
var arm_l: Node3D
var torso_root: Node3D
var head: Node3D
var _phase := 0.0
var _holo_mats: Array[ShaderMaterial] = []

func build(p_holo := false, p_tint: Color = Cfg.C_CYAN) -> void:
	holo = p_holo
	tint = p_tint
	var suit := _mat(Color(0.10, 0.12, 0.16), 0.6, 0.5)
	var armor := _mat(Color(0.20, 0.24, 0.30), 0.5, 0.6)
	var accent := _glow(tint, 2.2)
	var dark := _mat(Color(0.05, 0.06, 0.08), 0.8, 0.2)
	# legs (pivot at hip)
	leg_l = _limb(Vector3(-0.15, 0.95, 0), Vector3(0.17, 0.88, 0.2), suit, armor)
	leg_r = _limb(Vector3(0.15, 0.95, 0), Vector3(0.17, 0.88, 0.2), suit, armor)
	# upper body pivot at the hips so we can lean
	torso_root = Node3D.new()
	torso_root.position = Vector3(0, 0.95, 0)
	add_child(torso_root)
	Shapes.box(torso_root, Vector3(0.5, 0.56, 0.30), Vector3(0, 0.33, 0), armor)
	Shapes.box(torso_root, Vector3(0.36, 0.3, 0.02), Vector3(0, 0.38, -0.16), accent)       # chest light
	Shapes.box(torso_root, Vector3(0.42, 0.14, 0.26), Vector3(0, 0.02, 0), dark)            # belt
	Shapes.box(torso_root, Vector3(0.34, 0.5, 0.16), Vector3(0, 0.36, 0.22), dark)          # backpack
	Shapes.box(torso_root, Vector3(0.06, 0.4, 0.04), Vector3(0, 0.36, 0.31), accent)        # pack core
	Shapes.sphere(torso_root, 0.13, Vector3(-0.31, 0.56, 0), armor, 10)                      # shoulders
	Shapes.sphere(torso_root, 0.13, Vector3(0.31, 0.56, 0), armor, 10)
	head = Node3D.new()
	head.position = Vector3(0, 0.78, 0)
	torso_root.add_child(head)
	Shapes.sphere(head, 0.15, Vector3.ZERO, armor, 12)
	Shapes.box(head, Vector3(0.22, 0.06, 0.06), Vector3(0, 0.0, -0.12), accent)              # visor
	# arms
	arm_r = _arm(Vector3(0.31, 0.56, 0), suit)
	arm_l = _arm(Vector3(-0.31, 0.56, 0), suit)
	# blaster in the right hand
	var gun := Node3D.new()
	gun.position = Vector3(0, -0.46, 0)
	arm_r.add_child(gun)
	gun.rotation_degrees.x = -90.0
	Shapes.box(gun, Vector3(0.09, 0.12, 0.42), Vector3(0, 0, -0.18), dark)
	Shapes.box(gun, Vector3(0.05, 0.05, 0.1), Vector3(0, 0.02, -0.42), accent)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -0.5)
	gun.add_child(muzzle)
	if holo:
		_apply_holo(self)

func _mat(c: Color, rough: float, metal: float) -> Material:
	return Mats.plain(c, rough, metal)

func _glow(c: Color, e: float) -> Material:
	return Mats.glow(c, e)

func _limb(pos: Vector3, size: Vector3, mat: Material, cap_mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	Shapes.box(pivot, size, Vector3(0, -size.y * 0.5, 0), mat)
	Shapes.box(pivot, Vector3(size.x + 0.04, 0.2, size.z + 0.06), Vector3(0, -size.y * 0.72, -0.02), cap_mat)
	return pivot

func _arm(pos: Vector3, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	torso_root.add_child(pivot)
	Shapes.box(pivot, Vector3(0.11, 0.5, 0.11), Vector3(0, -0.25, 0), mat)
	return pivot

func _apply_holo(n: Node) -> void:
	if n is MeshInstance3D:
		var m := Mats.holo(tint, 0.75)
		(n as MeshInstance3D).material_override = m
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holo_mats.append(m)
	for c in n.get_children():
		_apply_holo(c)

## Fade / flicker the hologram (strength 0..1).
func set_holo_strength(s: float) -> void:
	for m in _holo_mats:
		m.set_shader_parameter("strength", 0.75 * s)

func set_holo_glitch(g: float) -> void:
	for m in _holo_mats:
		m.set_shader_parameter("glitch", g)

## move_local: velocity expressed in the body's local frame (x = right, z = back). speed_ratio 0..1.
func animate(delta: float, move_local: Vector3, speed_ratio: float, dashing: bool, aim_pitch: float) -> void:
	var stride := 1.0
	if move_local.z > 0.2 and absf(move_local.x) < 0.5:
		stride = -1.0     # running backwards
	_phase += delta * (4.0 + 9.0 * speed_ratio) * (0.0 if speed_ratio < 0.02 else 1.0)
	var swing := sin(_phase) * 0.75 * speed_ratio * stride
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	var lean := 0.12 * speed_ratio * (-stride) + (0.55 if dashing else 0.0)
	torso_root.rotation.x = lerpf(torso_root.rotation.x, -lean, minf(1.0, delta * 14.0))
	torso_root.rotation.z = lerpf(torso_root.rotation.z, -move_local.x * 0.12 * speed_ratio, minf(1.0, delta * 10.0))
	# arms point along the aim pitch (positive pitch = aiming up)
	var arm_angle := PI * 0.5 + clampf(aim_pitch, -1.2, 1.2) - torso_root.rotation.x
	arm_r.rotation.x = arm_angle
	arm_l.rotation.x = arm_angle - 0.1
	arm_l.rotation.y = 0.35
	head.rotation.x = clampf(aim_pitch, -0.6, 0.6) * 0.6
	position.y = absf(sin(_phase)) * 0.05 * speed_ratio
