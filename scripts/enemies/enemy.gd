class_name Enemy
extends CharacterBody3D
## Base class for WARDEN security units.
##
## Targeting: every ~0.25 s an enemy scores every operative and Echo it can see. An Echo looks
## ECHO_LURE_FACTOR times closer than it is (so it draws attention), but only while the enemy's
## `lure_budget` lasts, and an operative who gets close (inside `close_threat_range`) outranks any
## decoy. That keeps Echoes a strong but limited distraction.
## Movement uses the level's NavGrid; subclasses implement _think() and _build_visual().

signal died(enemy: Enemy)

enum State { IDLE, PATROL, CHASE, WINDUP, ATTACK, RECOVER, STUNNED, DEAD }

var kind_name := "Unit"
var max_health := 40.0
var move_speed := 4.0
var detect_range := 24.0
var memory_time := 4.0
var fragment_drop := 3
var flying := false
var radius := 0.5
var body_height := 1.8
var eye_height := 1.2
var hit_radius := 0.6
var close_threat_range := 6.0
var lure_enabled := true
var accel := 14.0
var hover_y := 0.0           # flying units: height of the body's origin above the floor
var hover_bob := 0.06

var level: LevelBase
var uid := ""
var group_id := ""
var health := 0.0
var state: State = State.IDLE
var target: Node3D = null
var last_known := Vector3.ZERO
var memory_left := 0.0
var lure_budget := 7.0
var patrol_points: Array = []
var shield_hp := 0.0
var shield_source: Node = null
var visual: Node3D

var _perceive_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _patrol_i := 0
var _shield_vis: MeshInstance3D
var _shield_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _state_time := 0.0
var _alerted_once := false

func _ready() -> void:
	_rng.randomize()
	add_to_group("enemies")
	collision_layer = Cfg.L_ENEMY
	collision_mask = Cfg.L_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING if flying else CharacterBody3D.MOTION_MODE_GROUNDED
	health = max_health
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(body_height, radius * 2.0 + 0.01)
	cs.shape = shape
	cs.position = Vector3(0, body_height * 0.5, 0)
	add_child(cs)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_build_visual()
	_perceive_t = _rng.randf() * 0.25
	if patrol_points.size() > 1:
		state = State.PATROL

# --- Hooks for subclasses ------------------------------------------------------------------------

func _build_visual() -> void:
	pass

func _think(_delta: float) -> void:
	pass

func _on_spotted() -> void:
	set_state(State.CHASE)

func _damage_modifier(_info: DamageInfo) -> float:
	return 1.0

func _on_death() -> void:
	pass

# --- Main loop -----------------------------------------------------------------------------------

var _net_puppet := false
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0

## Called on clients instead of running AI: the host owns this enemy's simulation, we just lerp to
## its broadcast transform and mirror its health/state for the HUD and visuals.
func apply_net_puppet(pos: Vector3, yaw: float, hp: float, max_hp: float, p_state: int, p_shield: float) -> void:
	_net_puppet = true
	_net_pos = pos
	_net_yaw = yaw
	max_health = max_hp
	if hp < health:
		HitFlash.apply(visual, Color(1, 1, 1), 0.6, 0.1)
	health = hp
	shield_hp = p_shield
	if p_state == State.DEAD and state != State.DEAD:
		die()
	else:
		state = p_state as State

func _physics_process(delta: float) -> void:
	if Net.active and not Net.is_host:
		if _net_puppet and state != State.DEAD:
			global_position = global_position.lerp(_net_pos, 1.0 - exp(-14.0 * delta))
			rotation.y = lerp_angle(rotation.y, _net_yaw, 1.0 - exp(-14.0 * delta))
		return
	if state == State.DEAD:
		return
	_state_time += delta
	memory_left = maxf(memory_left - delta, 0.0)
	if target is Echo:
		lure_budget = maxf(lure_budget - delta, 0.0)
	else:
		lure_budget = minf(lure_budget + delta * 0.35, 7.0)
	_perceive_t -= delta
	if _perceive_t <= 0.0:
		_perceive_t = 0.25
		_perceive()
	if is_instance_valid(target) and target is Player and (target as Player).dead:
		target = null
	_think(delta)

func set_state(s: State) -> void:
	if state == s or state == State.DEAD:
		return
	state = s
	_state_time = 0.0

func eye_pos() -> Vector3:
	return global_position + Vector3(0, eye_height, 0)

func has_los_to(point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye_pos(), point, Cfg.L_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _perceive() -> void:
	var best: Node3D = null
	var best_score := INF
	var origin := eye_pos()
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.dead:
			continue
		var c := p.hit_center()
		var d := origin.distance_to(c)
		if d > detect_range or not has_los_to(c):
			continue
		var score := d * (0.55 if d < close_threat_range else 1.0)
		if score < best_score:
			best_score = score
			best = p
	if lure_enabled and lure_budget > 0.0:
		for n in get_tree().get_nodes_in_group("echoes"):
			var e := n as Echo
			if e == null or not e.is_lure():
				continue
			var c := e.hit_center()
			var d := origin.distance_to(c)
			if d > detect_range or not has_los_to(c):
				continue
			var score := d * Cfg.ECHO_LURE_FACTOR
			if score < best_score:
				best_score = score
				best = e
	if best != null:
		target = best
		last_known = best.global_position
		memory_left = memory_time
		if state == State.IDLE or state == State.PATROL:
			_on_spotted()
			if not _alerted_once and level != null:
				_alerted_once = true
				level.alert_around(global_position, 18.0, best, self)
	elif memory_left <= 0.0:
		target = null

## Called when another enemy spots something nearby, or when this enemy is shot.
func alert(pos: Vector3, who: Node3D = null) -> void:
	if state == State.DEAD:
		return
	last_known = pos
	memory_left = memory_time
	if who != null and target == null:
		target = who
	if state == State.IDLE or state == State.PATROL:
		_on_spotted()

func has_target() -> bool:
	return is_instance_valid(target)

func target_center() -> Vector3:
	if is_instance_valid(target) and target.has_method("hit_center"):
		return target.hit_center()
	return last_known + Vector3(0, 1.0, 0)

# --- Movement helpers ----------------------------------------------------------------------------

func face_towards(point: Vector3, delta: float, rate := 10.0) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length_squared() < 0.0004:
		return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-rate * delta))

## Walks (or flies) along a smoothed NavGrid path towards `dest`. Returns true when within `stop_dist`.
func nav_move(dest: Vector3, speed: float, delta: float, stop_dist := 0.4) -> bool:
	var flat := Vector3(dest.x - global_position.x, 0.0, dest.z - global_position.z)
	if flat.length() <= stop_dist:
		_apply_velocity(Vector3.ZERO, delta)
		return true
	_repath_t -= delta
	if level != null and level.nav != null:
		if _repath_t <= 0.0 or _path_i >= _path.size():
			_path = level.nav.find_path(global_position, dest, radius * 0.8)
			_path_i = 0
			_repath_t = 0.35 + _rng.randf() * 0.2
		while _path_i < _path.size() and Vector2(_path[_path_i].x - global_position.x, _path[_path_i].z - global_position.z).length() < 0.55:
			_path_i += 1
		var wp := dest
		if _path_i < _path.size():
			wp = _path[_path_i]
		flat = Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
	var dir := flat.normalized() if flat.length() > 0.01 else Vector3.ZERO
	_apply_velocity(dir * speed + _separation(), delta)
	return false

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == self or not (n is Node3D):
			continue
		var off: Vector3 = global_position - (n as Node3D).global_position
		off.y = 0.0
		var d := off.length()
		if d < 1.6 and d > 0.001:
			push += off / d * (1.6 - d) * 2.0
	return push

func _apply_velocity(want: Vector3, delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	h = h.lerp(Vector3(want.x, 0.0, want.z), 1.0 - exp(-accel * delta))
	velocity.x = h.x
	velocity.z = h.z
	if flying:
		var want_y := hover_y + sin(Time.get_ticks_msec() * 0.003 + float(get_instance_id() % 97)) * hover_bob
		velocity.y = (want_y - global_position.y) * 5.0
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= Cfg.GRAVITY * delta
	move_and_slide()

func stop_moving(delta: float) -> void:
	_apply_velocity(Vector3.ZERO, delta)

func patrol_step(delta: float, speed: float) -> void:
	if patrol_points.size() < 2:
		stop_moving(delta)
		return
	var p: Vector3 = patrol_points[_patrol_i]
	if nav_move(p, speed, delta, 0.9):
		_patrol_i = (_patrol_i + 1) % patrol_points.size()
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.3:
		face_towards(global_position + dir, delta, 6.0)

# --- Damage ----------------------------------------------------------------------------------------

func hit_center() -> Vector3:
	return global_position + Vector3(0, body_height * 0.55, 0)

func is_targetable() -> bool:
	return state != State.DEAD

func take_damage(info: DamageInfo) -> void:
	if state == State.DEAD or info.team == Cfg.TEAM_ENEMY:
		return
	if Net.active and not Net.is_host:
		# the host owns this enemy's health; report the hit instead of mutating our puppet copy,
		# with just enough local feedback that the shot doesn't feel like it did nothing.
		if level != null:
			Net.report_hit(level.get_path_to(self), info)
		Fx.impact(info.point if info.point != Vector3.ZERO else hit_center(), Vector3.UP, Cfg.C_CYAN if info.from_echo else Color.WHITE)
		Sfx.play_at("hit", global_position, -8.0)
		return
	var amount := info.amount
	if shield_hp > 0.0:
		shield_hp -= amount
		Sfx.play_at("armor_hit", global_position, -4.0, 1.5)
		Fx.impact(info.point if info.point != Vector3.ZERO else hit_center(), Vector3.UP, Cfg.C_VIOLET)
		if _shield_mat != null:
			_shield_mat.set_shader_parameter("strength", 2.6)
		if shield_hp <= 0.0:
			_break_shield()
		_react_to(info)
		return
	amount *= _damage_modifier(info)
	health -= amount
	HitFlash.apply(visual, Color(1, 1, 1) if not info.from_echo else Cfg.C_CYAN, 0.7, 0.1)
	Fx.damage_number(hit_center() + Vector3(0, 0.6, 0), amount, Cfg.C_CYAN if info.from_echo else Color(1, 0.95, 0.8))
	Sfx.play_at("enemy_hit", global_position, -3.0, randf_range(0.9, 1.15))
	_on_damaged(info, amount)
	_react_to(info)
	if health <= 0.0:
		die(info)

func _on_damaged(_info: DamageInfo, _amount: float) -> void:
	pass

## An unseen attacker still wakes the unit and points it at the shooter (Echo shots draw it to the Echo).
func _react_to(info: DamageInfo) -> void:
	if state == State.DEAD:
		return
	var src: Node3D = null
	if info.from_echo and is_instance_valid(info.source) and info.source is Node3D:
		src = info.source as Node3D
	elif is_instance_valid(info.source_player) and info.source_player is Node3D:
		src = info.source_player as Node3D
	if src != null:
		last_known = src.global_position
		memory_left = memory_time
		if target == null:
			target = src
	if state == State.IDLE or state == State.PATROL:
		_on_spotted()
		if level != null and not _alerted_once:
			_alerted_once = true
			level.alert_around(global_position, 18.0, src, self)

func give_shield(amount: float, source: Node) -> void:
	shield_hp = amount
	shield_source = source
	if _shield_vis == null:
		_shield_vis = MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = maxf(radius, 0.5) * 1.5
		sph.height = sph.radius * 2.0
		sph.radial_segments = 20
		sph.rings = 10
		_shield_vis.mesh = sph
		_shield_mat = Mats.energy(Cfg.C_VIOLET, 1.0, true, 3.0)
		_shield_vis.material_override = _shield_mat
		_shield_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shield_vis.position = Vector3(0, body_height * 0.5, 0)
		add_child(_shield_vis)
	_shield_vis.visible = true
	_shield_mat.set_shader_parameter("strength", 1.0)

func _break_shield() -> void:
	shield_hp = 0.0
	if _shield_vis != null:
		_shield_vis.visible = false
	Sfx.play_at("shield_down", global_position, -2.0)
	Fx.burst(hit_center(), Cfg.C_VIOLET, 14, 6.0, 0.5, 0.18)
	if is_instance_valid(shield_source) and shield_source.has_method("on_shield_broken"):
		shield_source.on_shield_broken(self)
	shield_source = null

func clear_shield() -> void:
	shield_hp = 0.0
	shield_source = null
	if _shield_vis != null:
		_shield_vis.visible = false

func die(info: DamageInfo = null) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	remove_from_group("enemies")
	collision_layer = 0
	clear_shield()
	_on_death()
	GameState.kills += 1
	if level != null and uid != "":
		GameState.set_flag(level.flag_key("dead_" + uid), true)
	Fx.explosion(hit_center(), Cfg.C_ORANGE, 0.8 + body_height * 0.2)
	Sfx.play_at("explosion", global_position, -2.0, randf_range(0.9, 1.1))
	Bus.screen_shake.emit(0.25)
	_drop_loot()
	Bus.enemy_defeated.emit(self)
	died.emit(self)
	queue_free()

func _drop_loot() -> void:
	var parent := Fx.world()
	var pieces := clampi(int(ceil(float(fragment_drop) / 3.0)), 1, 4)
	for i in pieces:
		Pickup.spawn(parent, "frag", hit_center(), maxi(1, fragment_drop / pieces), "", true)
	var lp := GameState.local_player as Player
	var hurt := lp != null and lp.health < lp.max_health * 0.6
	if _rng.randf() < (0.4 if hurt else 0.16):
		Pickup.spawn(parent, "health", hit_center(), 25, "", true)

# --- Projectile helper -------------------------------------------------------------------------------

func fire_bolt(from: Vector3, dir: Vector3, speed: float, dmg: float, opts := {}) -> void:
	var o := {"color": Cfg.C_RED, "size": 0.09, "range": 45.0, "from_point": eye_pos()}
	o.merge(opts, true)
	Projectile.spawn(Fx.world(), from, dir, speed, dmg, Cfg.TEAM_ENEMY, self, o)
