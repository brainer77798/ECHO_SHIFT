class_name ShootTarget
extends StaticBody3D
## Resonance target: a puzzle node activated by blaster fire. An `echo_only` target rejects the
## operative's own shots and only reacts to shots fired by an Echo, so the shot has to be recorded
## and replayed. With `duration` > 0 it deactivates again after that many seconds.

var channel := ""
var echo_only := false
var duration := 6.0
var yaw := 0.0
var level: LevelBase
var active := false

var _time_left := 0.0
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _lbl: Label3D
var _color: Color = Cfg.C_CYAN
var _ring_mats: Array = []

func build() -> void:
	collision_layer = Cfg.L_TRIGGER
	collision_mask = 0
	rotation.y = yaw
	_color = Cfg.C_VIOLET if echo_only else Cfg.C_CYAN
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.75
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	add_child(cs)
	var metal := Mats.plain(Color(0.09, 0.11, 0.15), 0.5, 0.7)
	Shapes.cylinder(self, 0.12, 0.2, 1.2, Vector3(0, 0.6, 0), metal, 10)
	Shapes.cylinder(self, 0.5, 0.5, 0.12, Vector3(0, 0.06, 0), metal, 16)
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.albedo_color = _color * 0.2
	_mat.emission = _color
	_mat.emission_energy_multiplier = 1.4
	var disc := Shapes.cylinder(self, 0.72, 0.72, 0.1, Vector3(0, 1.5, 0), _mat, 24)
	disc.rotation.x = PI * 0.5
	for i in 3:
		var m := Mats.glow(_color if i != 1 else Color.WHITE, 2.5)
		var t := Shapes.torus(self, 0.14 + i * 0.2, 0.18 + i * 0.2, Vector3(0, 1.5, -0.07), m, 24)
		t.rotation.x = PI * 0.5
	_light = Shapes.add_light(self, Vector3(0, 1.5, -0.8), _color, 0.8, 4.0)
	_lbl = Shapes.label3d(self, "ECHO RESONANCE" if echo_only else "TARGET", Vector3(0, 2.6, 0), _color, 20, 0.006)
	_lbl.modulate.a = 0.8

func take_damage(info: DamageInfo) -> void:
	if info.team != Cfg.TEAM_PLAYER:
		return
	if echo_only and not info.from_echo:
		Sfx.play_at("armor_hit", global_position, -6.0, 1.4)
		_lbl.text = "ECHO SHOTS ONLY"
		_lbl.modulate = Cfg.C_RED
		var tw := create_tween()
		tw.tween_interval(1.0)
		tw.tween_callback(func() -> void:
			if is_instance_valid(_lbl):
				_lbl.text = "ECHO RESONANCE"
				_lbl.modulate = Color(_color.r, _color.g, _color.b, 0.8))
		return
	active = true
	_time_left = duration
	Sfx.play_at("switch", global_position, -2.0)
	Fx.burst(global_position + Vector3(0, 1.5, 0), _color, 10, 4.0, 0.35, 0.12)
	if level != null:
		level.set_channel(channel, true)
	_refresh()

func _physics_process(delta: float) -> void:
	if active and duration > 0.0:
		_time_left -= delta
		_lbl.text = "%.1fs" % maxf(_time_left, 0.0)
		if _time_left <= 0.0:
			active = false
			_lbl.text = "ECHO RESONANCE" if echo_only else "TARGET"
			Sfx.play_at("plate_off", global_position, -4.0)
			if level != null:
				level.set_channel(channel, false)
			_refresh()

func _refresh() -> void:
	var c := Cfg.C_GREEN if active else _color
	_mat.emission = c
	_mat.albedo_color = c * 0.2
	_mat.emission_energy_multiplier = 3.0 if active else 1.4
	_light.light_color = c
