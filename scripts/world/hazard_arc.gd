class_name ArcHazard
extends Node3D
## Electrical discharge between two pylons on a fixed cycle: idle -> warning (sparks, red flicker and
## a rising tone) -> discharge (damaging arc). The cycle is deterministic so it can be timed or
## dashed through. A channel in `disabled_by` switches it off while that channel is on.

var length := 4.0
var period := 4.2
var warn_time := 1.0
var active_time := 1.2
var phase := 0.0
var damage := 22.0
var disabled_by := ""
var level: LevelBase

var _zone: Area3D
var _arc_mat: ShaderMaterial
var _arc: MeshInstance3D
var _glow_a: StandardMaterial3D
var _light: OmniLight3D
var _strip_mat: StandardMaterial3D
var _t := 0.0
var _mode := 0                # 0 idle, 1 warn, 2 active, 3 disabled
var _cd: Dictionary = {}
var _spark_t := 0.0

func build() -> void:
	var metal := Mats.plain(Color(0.10, 0.12, 0.16), 0.45, 0.8)
	_glow_a = StandardMaterial3D.new()
	_glow_a.emission_enabled = true
	_glow_a.albedo_color = Color(0.1, 0.1, 0.1)
	_glow_a.emission = Cfg.C_BLUE
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * length * 0.5, 0, 0)
		Shapes.cylinder(self, 0.3, 0.38, 0.3, p + Vector3(0, 0.15, 0), metal, 10)
		Shapes.cylinder(self, 0.14, 0.18, 1.3, p + Vector3(0, 0.95, 0), metal, 8)
		Shapes.sphere(self, 0.22, p + Vector3(0, 1.7, 0), _glow_a, 12)
		Shapes.torus(self, 0.25, 0.3, p + Vector3(0, 1.15, 0), Mats.glow(Cfg.C_AMBER, 1.5), 14)
	# floor strip shows the zone (grey -> amber -> red)
	_strip_mat = StandardMaterial3D.new()
	_strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_strip_mat.albedo_color = Color(0.25, 0.3, 0.35)
	var strip := Shapes.box(self, Vector3(length - 0.5, 0.02, 0.8), Vector3(0, 0.02, 0), _strip_mat)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc_mat = Mats.energy(Cfg.C_BLUE, 2.2, false, 14.0)
	_arc = Shapes.box(self, Vector3(length - 0.4, 0.5, 0.5), Vector3(0, 1.4, 0), _arc_mat)
	_arc.visible = false
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = Shapes.add_light(self, Vector3(0, 1.4, 0), Cfg.C_BLUE, 0.0, 6.0)
	_zone = Area3D.new()
	_zone.collision_layer = 0
	_zone.collision_mask = Cfg.L_PLAYER | Cfg.L_ENEMY
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length - 0.2, 2.4, 1.1)
	cs.shape = shape
	cs.position = Vector3(0, 1.2, 0)
	_zone.add_child(cs)
	add_child(_zone)

func _physics_process(delta: float) -> void:
	_t += delta
	var off := level != null and disabled_by != "" and level.get_channel(disabled_by)
	var mode := 3 if off else 0
	if not off:
		var c := fposmod(_t + phase, period)
		if c >= period - active_time:
			mode = 2
		elif c >= period - active_time - warn_time:
			mode = 1
	if mode != _mode:
		_mode = mode
		_on_mode()
	if _mode == 1:
		var flick := 0.5 + 0.5 * sin(_t * 40.0)
		_glow_a.emission = Cfg.C_RED * (0.4 + flick * 1.6)
		_strip_mat.albedo_color = Cfg.C_AMBER.lerp(Cfg.C_RED, flick)
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = 0.12
			Fx.burst(global_position + Vector3(randf_range(-length * 0.5, length * 0.5), 1.0, 0), Cfg.C_AMBER, 2, 2.0, 0.25, 0.1, 0.0, Vector3.UP, 60.0)
	elif _mode == 2:
		_light.light_energy = 2.0 + randf() * 1.5
		_arc.scale.y = randf_range(0.7, 1.3)
		_arc.position.y = 1.4 + randf_range(-0.12, 0.12)
		for b in _zone.get_overlapping_bodies():
			_try_hit(b, delta)
	for k in _cd.keys():
		_cd[k] = float(_cd[k]) - delta
		if float(_cd[k]) <= 0.0:
			_cd.erase(k)

func _try_hit(b: Node, _delta: float) -> void:
	var id := b.get_instance_id()
	if _cd.has(id):
		return
	var info := DamageInfo.make(damage, Cfg.TEAM_ENEMY, self, "hazard")
	var side := global_transform.basis.z
	var away: Vector3 = b.global_position - global_position
	info.direction = side * (1.0 if away.dot(side) >= 0.0 else -1.0)
	info.knockback = 6.0
	info.point = (b as Node3D).global_position + Vector3(0, 1, 0)
	if b is Player:
		if (b as Player).dead:
			return
		(b as Player).take_damage(info)
	elif b is Enemy:
		info.team = Cfg.TEAM_PLAYER   # arcs hurt WARDEN's units too (lure them through!)
		info.amount = damage * 0.8
		(b as Enemy).take_damage(info)
	else:
		return
	_cd[id] = 0.6
	Sfx.play_at("zap", info.point, 0.0)
	Fx.burst(info.point, Cfg.C_BLUE, 8, 5.0, 0.3)

func _on_mode() -> void:
	match _mode:
		0, 3:
			_arc.visible = false
			_light.light_energy = 0.0
			_glow_a.emission = Cfg.C_BLUE * (0.5 if _mode == 0 else 0.1)
			_strip_mat.albedo_color = Color(0.25, 0.3, 0.35)
		1:
			Sfx.play_at("warn", global_position, -4.0, 0.9)
		2:
			_arc.visible = true
			_glow_a.emission = Color(0.7, 0.9, 1.0) * 2.0
			_strip_mat.albedo_color = Cfg.C_RED
			Sfx.play_at("zap", global_position, 2.0, 0.8)
			Bus.screen_shake.emit(0.15)
