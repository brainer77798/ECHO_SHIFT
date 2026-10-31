class_name SweepBeam
extends Node3D
## Rotating security laser: a hub with two opposite arms sweeping at a constant, visible rate.
## Time the gap, hug the hub where the sweep is slowest, or dash through (the dash grants brief
## invulnerability). A channel in `disabled_by` stops it.

var beam_length := 8.5
var speed := 0.85
var damage := 18.0
var beam_height := 0.7
var disabled_by := ""
var level: LevelBase

var _arm: Node3D
var _mat: ShaderMaterial
var _angle := 0.0
var _cd: Dictionary = {}
var _light: OmniLight3D
var _was_off := false

func build() -> void:
	var metal := Mats.plain(Color(0.10, 0.12, 0.16), 0.45, 0.8)
	Shapes.cylinder(self, 0.5, 0.6, 0.35, Vector3(0, 0.175, 0), metal, 14)
	Shapes.cylinder(self, 0.3, 0.3, beam_height + 0.35, Vector3(0, (beam_height + 0.35) * 0.5, 0), metal, 12)
	_arm = Node3D.new()
	_arm.position = Vector3(0, beam_height, 0)
	add_child(_arm)
	_mat = Mats.beam(Cfg.C_RED, 1.0)
	for s in [-1.0, 1.0]:
		var b := Shapes.box(_arm, Vector3(beam_length, 0.12, 0.12), Vector3(s * beam_length * 0.5, 0, 0), _mat)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Shapes.sphere(_arm, 0.2, Vector3(s * beam_length, 0, 0), Mats.glow(Cfg.C_RED, 3.0), 10)
	_light = Shapes.add_light(self, Vector3(0, beam_height + 0.3, 0), Cfg.C_RED, 1.0, 6.0)

func _physics_process(delta: float) -> void:
	var off := level != null and disabled_by != "" and level.get_channel(disabled_by)
	if off != _was_off:
		_was_off = off
		_arm.visible = not off
		_light.light_energy = 0.0 if off else 1.0
	if off:
		return
	_angle += speed * delta
	_arm.rotation.y = _angle
	for k in _cd.keys():
		_cd[k] = float(_cd[k]) - delta
		if float(_cd[k]) <= 0.0:
			_cd.erase(k)
	var dir := Vector3(cos(-_angle), 0.0, sin(-_angle))
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead or _cd.has(p.get_instance_id()):
			continue
		var rel := p.global_position - global_position
		rel.y = 0.0
		var along := rel.dot(dir)
		if absf(along) > beam_length:
			continue
		var perp := (rel - dir * along).length()
		if perp < 0.6:
			var info := DamageInfo.make(damage, Cfg.TEAM_ENEMY, self, "hazard")
			info.direction = (rel - dir * along).normalized() if perp > 0.05 else Vector3.RIGHT
			info.knockback = 7.0
			p.take_damage(info)
			_cd[p.get_instance_id()] = 0.8
			Sfx.play_at("zap", p.global_position, -2.0)
			Fx.burst(p.global_position + Vector3(0, 0.8, 0), Cfg.C_RED, 8, 5.0, 0.3)
