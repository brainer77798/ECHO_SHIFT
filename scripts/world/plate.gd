class_name PressurePlate
extends Area3D
## Floor plate that drives a logic channel while something valid stands on it.
##   ANY         (cyan)   - the operative or any Echo
##   ECHO_ONLY   (violet) - only a holographic Echo can press it
##   PLAYER_ONLY (amber)  - only a live operative can press it
## `latch_time` keeps the channel on briefly after release, which is what makes the
## record-an-Echo-and-run-for-the-door puzzles forgiving.

enum Accept { ANY, ECHO_ONLY, PLAYER_ONLY }

var channel := ""
var accept: Accept = Accept.ANY
var size := Vector2(2.0, 2.0)
var latch_time := 0.0
var level: LevelBase
var pressed := false

var _latch_left := 0.0
var _pad: MeshInstance3D
var _ring_mat: ShaderMaterial
var _pad_mat: StandardMaterial3D
var _light: OmniLight3D
var _tag: Label3D
var _color: Color = Cfg.C_CYAN
var _was := false

func build() -> void:
	collision_layer = 0
	collision_mask = Cfg.L_PLAYER | Cfg.L_ECHO
	monitoring = true
	monitorable = false
	match accept:
		Accept.ECHO_ONLY:
			_color = Cfg.C_VIOLET
		Accept.PLAYER_ONLY:
			_color = Cfg.C_AMBER
		_:
			_color = Cfg.C_CYAN
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x - 0.3, 1.6, size.y - 0.3)
	cs.shape = shape
	cs.position = Vector3(0, 0.8, 0)
	add_child(cs)
	var base := Shapes.box(self, Vector3(size.x, 0.1, size.y), Vector3(0, 0.05, 0), Mats.plain(Color(0.07, 0.09, 0.12), 0.5, 0.7))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pad_mat = StandardMaterial3D.new()
	_pad_mat.albedo_color = _color * 0.25
	_pad_mat.emission_enabled = true
	_pad_mat.emission = _color
	_pad_mat.emission_energy_multiplier = 0.6
	_pad = Shapes.box(self, Vector3(size.x - 0.35, 0.08, size.y - 0.35), Vector3(0, 0.12, 0), _pad_mat)
	_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		Shapes.box(self, Vector3(0.12, 0.14, size.y), Vector3(sx * (size.x * 0.5 - 0.06), 0.07, 0), Mats.glow(_color, 2.0))
	for sz in [-1.0, 1.0]:
		Shapes.box(self, Vector3(size.x, 0.14, 0.12), Vector3(0, 0.07, sz * (size.y * 0.5 - 0.06)), Mats.glow(_color, 2.0))
	_ring_mat = Mats.energy(_color, 0.9, false, 3.0)
	var ring := Shapes.torus(self, 0.55, 0.62, Vector3(0, 0.22, 0), _ring_mat, 28)
	ring.scale = Vector3(1, 0.1, 1)
	_light = Shapes.add_light(self, Vector3(0, 0.9, 0), _color, 0.5, 4.5)
	var text := "ANY" if accept == Accept.ANY else ("ECHO ONLY" if accept == Accept.ECHO_ONLY else "OPERATIVE ONLY")
	_tag = Shapes.label3d(self, text, Vector3(0, 1.35, 0), _color, 22, 0.006)
	_tag.modulate.a = 0.75

func _physics_process(delta: float) -> void:
	var occupied := false
	for b in get_overlapping_bodies():
		if b is Echo and accept != Accept.PLAYER_ONLY and (b as Echo).phase != Echo.Phase.DONE:
			occupied = true
			break
		if b is Player and accept != Accept.ECHO_ONLY and not (b as Player).dead:
			occupied = true
			break
	if occupied:
		_latch_left = latch_time
	elif _latch_left > 0.0:
		_latch_left -= delta
		occupied = true
	pressed = occupied
	if pressed != _was:
		_was = pressed
		Sfx.play_at("plate_on" if pressed else "plate_off", global_position, -4.0)
		_pad.position.y = 0.07 if pressed else 0.12
		_pad_mat.emission_energy_multiplier = 3.0 if pressed else 0.6
		_light.light_energy = 1.4 if pressed else 0.5
		_ring_mat.set_shader_parameter("strength", 1.8 if pressed else 0.9)
		if level != null:
			level.set_channel(channel, pressed)
	elif level != null and level.get_channel(channel) != pressed:
		level.set_channel(channel, pressed)
