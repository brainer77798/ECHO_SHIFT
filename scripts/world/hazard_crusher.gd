class_name Crusher
extends AnimatableBody3D
## Sliding blast barrier on a timed cycle: dwell open, slam shut, dwell, retract. A hazard-stripe
## wall that is lethal-ish to stand in the way of, with a lit warning bar. A channel in `disabled_by`
## parks it in the open position.

var travel := Vector3(0, 0, 4)       # displacement from the open position to the closed position
var size := Vector3(4, 4, 0.8)
var period := 7.0
var dwell := 2.2                      # seconds held at each end
var phase := 0.0
var damage := 20.0
var disabled_by := ""
var level: LevelBase

var _start := Vector3.ZERO
var _t := 0.0
var _hurt: Area3D
var _bar_mat: StandardMaterial3D
var _cd: Dictionary = {}
var _moving := false

func build() -> void:
	_start = position
	collision_layer = Cfg.L_WORLD
	collision_mask = 0
	sync_to_physics = true
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	Shapes.box(self, size, Vector3(0, size.y * 0.5, 0), Props.stripes_material(Cfg.C_AMBER))
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.emission_enabled = true
	_bar_mat.albedo_color = Color(0.2, 0.05, 0.02)
	_bar_mat.emission = Cfg.C_RED
	Shapes.box(self, Vector3(size.x * 0.9, 0.18, size.z + 0.06), Vector3(0, size.y - 0.4, 0), _bar_mat)
	_hurt = Area3D.new()
	_hurt.collision_layer = 0
	_hurt.collision_mask = Cfg.L_PLAYER
	var hcs := CollisionShape3D.new()
	var hshape := BoxShape3D.new()
	hshape.size = size + Vector3(0.7, 0.0, 0.7)
	hcs.shape = hshape
	hcs.position = Vector3(0, size.y * 0.5, 0)
	_hurt.add_child(hcs)
	add_child(_hurt)

## 0 = open position, 1 = closed position.
func _fraction(t: float) -> float:
	var half := period * 0.5
	var move := maxf(half - dwell, 0.2)
	var c := fposmod(t, period)
	if c < dwell:
		return 0.0
	if c < dwell + move:
		return smoothstep(0.0, 1.0, (c - dwell) / move)
	if c < half + dwell:
		return 1.0
	if c < half + dwell + move:
		return 1.0 - smoothstep(0.0, 1.0, (c - half - dwell) / move)
	return 0.0

func _physics_process(delta: float) -> void:
	_t += delta
	var off := level != null and disabled_by != "" and level.get_channel(disabled_by)
	var f_now := 0.0 if off else _fraction(_t + phase)
	var f_prev := 0.0 if off else _fraction(_t + phase - 0.05)
	var f_soon := 0.0 if off else _fraction(_t + phase + 0.7)
	var moving := absf(f_now - f_prev) > 0.0001
	var about_to_move := not moving and absf(f_soon - f_now) > 0.0001
	if moving != _moving:
		_moving = moving
		if moving:
			Sfx.play_at("door", global_position, -2.0, 0.7)
	position = _start + travel * f_now
	# the warning bar blinks amber just before each movement and burns red while moving
	if moving:
		_bar_mat.emission = Cfg.C_RED * 3.0
	elif about_to_move:
		_bar_mat.emission = Cfg.C_AMBER * (0.5 + 2.5 * (0.5 + 0.5 * sin(_t * 30.0)))
	else:
		_bar_mat.emission = Cfg.C_AMBER * 0.5
	var f_next := f_now + (f_now - f_prev)
	for k in _cd.keys():
		_cd[k] = float(_cd[k]) - delta
		if float(_cd[k]) <= 0.0:
			_cd.erase(k)
	if moving:
		for b in _hurt.get_overlapping_bodies():
			var p := b as Player
			if p == null or p.dead or _cd.has(p.get_instance_id()):
				continue
			var info := DamageInfo.make(damage, Cfg.TEAM_ENEMY, self, "hazard")
			info.direction = travel.normalized() * (1.0 if f_next > f_now else -1.0)
			info.knockback = 9.0
			p.take_damage(info)
			_cd[p.get_instance_id()] = 0.6
			Fx.burst(p.global_position + Vector3(0, 1, 0), Cfg.C_AMBER, 8, 5.0, 0.3)
