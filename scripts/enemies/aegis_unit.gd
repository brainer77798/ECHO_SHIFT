class_name AegisUnit
extends Enemy
## Support drone. It never attacks; it projects a damage-absorbing shield onto the strongest ally in
## sight (shown as a violet bubble plus a tether beam) and keeps its distance from the operative.
## Destroying it drops every shield it maintains, so it is the priority target in a mixed squad.

const SHIELD_HP := 80.0

var _cast_cd := 1.0
var _link: Enemy
var _tether: MeshInstance3D
var _tether_mat: ShaderMaterial
var _rings: Array[Node3D] = []
var _core_mat: StandardMaterial3D
var _shadow: MeshInstance3D
var _evade_t := 0.0

func _init() -> void:
	kind_name = "Aegis Unit"
	max_health = 55.0
	move_speed = 5.2
	flying = true
	radius = 0.45
	body_height = 1.0
	eye_height = 0.5
	hit_radius = 0.7
	fragment_drop = 7
	detect_range = 30.0
	accel = 8.0
	hover_y = 1.35
	lure_enabled = false     # it does not chase decoys; it only tends to its squad

func _build_visual() -> void:
	var dark := Mats.plain(Color(0.10, 0.09, 0.15), 0.4, 0.8)
	_core_mat = StandardMaterial3D.new()
	_core_mat.emission_enabled = true
	_core_mat.albedo_color = Cfg.C_VIOLET * 0.3
	_core_mat.emission = Cfg.C_VIOLET
	_core_mat.emission_energy_multiplier = 3.0
	var c := Vector3(0, 0.5, 0)
	var top := Shapes.cylinder(visual, 0.0, 0.34, 0.5, c + Vector3(0, 0.25, 0), dark, 6)
	var bot := Shapes.cylinder(visual, 0.34, 0.0, 0.5, c + Vector3(0, -0.25, 0), dark, 6)
	top.rotation.y = 0.5
	bot.rotation.y = 0.5
	Shapes.sphere(visual, 0.17, c, _core_mat, 12)
	for i in 2:
		var r := Node3D.new()
		r.position = c
		visual.add_child(r)
		Shapes.torus(r, 0.5 + i * 0.12, 0.54 + i * 0.12, Vector3.ZERO, Mats.glow(Cfg.C_VIOLET, 1.8), 24)
		r.rotation = Vector3(0.6 * i, 0, 0.5 * i)
		_rings.append(r)
	Shapes.add_light(visual, c, Cfg.C_VIOLET, 0.6, 5.0)
	_shadow = Props.blob_shadow(self, 0.6, 0.45)
	_shadow.top_level = true
	_tether_mat = Mats.energy(Cfg.C_VIOLET, 1.6, true, 4.0)
	_tether = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 1.0)
	_tether.mesh = bm
	_tether.material_override = _tether_mat
	_tether.top_level = true
	_tether.visible = false
	_tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tether)

func _process(_delta: float) -> void:
	if _shadow != null and state != State.DEAD:
		_shadow.global_position = Vector3(global_position.x, 0.03, global_position.z)

func _think(delta: float) -> void:
	_cast_cd -= delta
	_rings[0].rotation.y += delta * 2.5
	_rings[1].rotation.x += delta * 3.0
	match state:
		State.IDLE, State.PATROL:
			stop_moving(delta)
		State.CHASE:
			_keep_distance(delta)
	_tend_shield()

## Stay between 9 and 14 m from the threat, drifting away when it gets close.
func _keep_distance(delta: float) -> void:
	if not has_target():
		stop_moving(delta)
		if memory_left <= 0.0:
			set_state(State.IDLE)
		return
	var tp := target.global_position
	var flat := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
	var d := flat.length()
	face_towards(tp, delta, 6.0)
	_evade_t -= delta
	if d < 8.5:
		var away := global_position - flat.normalized() * 6.0
		nav_move(level.nav.nearest_walkable_world(away) if level != null and level.nav != null else away, move_speed, delta, 0.6)
	elif d > 15.0:
		nav_move(tp, move_speed * 0.8, delta, 12.0)
	else:
		# gentle sideways drift so it is not a stationary target
		var side := Vector3(-flat.z, 0.0, flat.x).normalized() * sin(Time.get_ticks_msec() * 0.0012 + float(get_instance_id() % 13))
		_apply_velocity(side * move_speed * 0.4, delta)

func _tend_shield() -> void:
	if is_instance_valid(_link):
		if _link.state == Enemy.State.DEAD or _link.shield_hp <= 0.0 or _link.shield_source != self:
			_link = null
		else:
			_draw_tether(_link.hit_center())
	if _link == null:
		_tether.visible = false
		if _cast_cd <= 0.0 and state == State.CHASE:
			var best: Enemy = null
			var best_score := -1.0
			for n in get_tree().get_nodes_in_group("enemies"):
				var e := n as Enemy
				if e == null or e == self or e is AegisUnit or e.state == Enemy.State.DEAD or e.shield_hp > 0.0:
					continue
				if global_position.distance_to(e.global_position) > 16.0 or not has_los_to(e.hit_center()):
					continue
				var score := e.max_health
				if score > best_score:
					best_score = score
					best = e
			if best != null:
				best.give_shield(SHIELD_HP, self)
				_link = best
				_cast_cd = 1.0
				Sfx.play_at("echo_create", global_position, -6.0, 1.6)
			else:
				_cast_cd = 1.0

func _draw_tether(to: Vector3) -> void:
	var from := global_position + Vector3(0, 0.5, 0)
	var len_v := from.distance_to(to)
	if len_v < 0.1:
		return
	_tether.visible = true
	_tether.global_position = (from + to) * 0.5
	_tether.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.RIGHT)
	_tether.scale = Vector3(1, 1, len_v)

func on_shield_broken(_ally: Enemy) -> void:
	_link = null
	_cast_cd = 5.0

func _on_spotted() -> void:
	set_state(State.CHASE)

func _on_death() -> void:
	_tether.visible = false
	if is_instance_valid(_link):
		_link.clear_shield()
		Fx.burst(_link.hit_center(), Cfg.C_VIOLET, 10, 5.0, 0.4, 0.16)
