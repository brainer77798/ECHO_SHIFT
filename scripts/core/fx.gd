class_name Fx
extends RefCounted
## Short-lived visual effects: sparks, explosions, rings, beams, damage numbers.
## Effects are parented to Fx.root (set by the active level) and clean themselves up.

static var root: Node3D
const MAX_EFFECTS := 90
static var _live := 0

static func _parent() -> Node:
	if root != null and is_instance_valid(root):
		return root
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree and tree.current_scene else tree.root

## Node under which gameplay objects (projectiles, echoes, effects) should be spawned.
static func world() -> Node:
	return _parent()

static func _reserve() -> bool:
	if _live >= MAX_EFFECTS:
		return false
	_live += 1
	return true

static func _release() -> void:
	_live = maxi(_live - 1, 0)

## Generic particle burst. Returns null if the effect budget is exhausted.
static func burst(pos: Vector3, color: Color, count := 12, speed := 5.0, life := 0.45, size := 0.16, gravity := -6.0, dir := Vector3.UP, spread := 180.0) -> CPUParticles3D:
	if not _reserve():
		return null
	var p := CPUParticles3D.new()
	p.mesh = Mats.particle_mesh(color, size)
	p.amount = count
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	p.position = pos
	p.emitting = true
	_parent().add_child(p)
	p.global_position = pos
	var tmr := p.get_tree().create_timer(life + 0.3)
	tmr.timeout.connect(func() -> void:
		_release()
		if is_instance_valid(p):
			p.queue_free())
	return p

static func impact(pos: Vector3, normal: Vector3, color: Color) -> void:
	burst(pos + normal * 0.05, color, 7, 4.0, 0.28, 0.12, -4.0, normal, 55.0)

static func explosion(pos: Vector3, color: Color, size := 1.0) -> void:
	burst(pos, color, int(18 * size), 7.0 * size, 0.7, 0.28, -3.0)
	burst(pos, Color(1, 1, 1), 6, 3.0 * size, 0.3, 0.4)
	flash_light(pos, color, 4.0 * size, 7.0 * size, 0.35)
	ring(pos, color, 2.2 * size, 0.4)

## Expanding glowing sphere + light, used for hits and deaths.
static func flash_light(pos: Vector3, color: Color, energy := 3.0, light_range := 6.0, life := 0.25) -> void:
	if not _reserve():
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	_parent().add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life)
	tw.tween_callback(func() -> void:
		_release()
		l.queue_free())

## Flat expanding ring (shock-wave).
static func ring(pos: Vector3, color: Color, max_radius := 2.0, life := 0.4, vertical := false) -> void:
	if not _reserve():
		return
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 28
	t.ring_segments = 4
	mi.mesh = t
	var mat := Mats.energy(color, 1.6)
	mi.material_override = mat
	_parent().add_child(mi)
	mi.global_position = pos
	if vertical:
		mi.rotation_degrees.x = 90.0
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * max_radius, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("strength", v), 1.6, 0.0, life)
	tw.chain().tween_callback(func() -> void:
		_release()
		mi.queue_free())

## Straight beam between two points that fades out.
static func beam(from: Vector3, to: Vector3, color: Color, width := 0.08, life := 0.12) -> void:
	if not _reserve():
		return
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	var len_v := from.distance_to(to)
	b.size = Vector3(width, width, maxf(len_v, 0.01))
	mi.mesh = b
	var mat := Mats.beam(color, 1.0)
	mi.material_override = mat
	_parent().add_child(mi)
	mi.global_position = (from + to) * 0.5
	if len_v > 0.01:
		mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("strength", v), 1.0, 0.0, life)
	tw.tween_callback(func() -> void:
		_release()
		mi.queue_free())

## Floating combat text.
static func damage_number(pos: Vector3, amount: float, color: Color = Color.WHITE) -> void:
	if not _reserve():
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.font_size = 40
	l.pixel_size = 0.008
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	_parent().add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.2, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(func() -> void:
		_release()
		l.queue_free())

static func reset() -> void:
	_live = 0
	root = null
